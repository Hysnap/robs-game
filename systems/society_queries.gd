# res://systems/society_queries.gd
class_name SocietyQueries
extends RefCounted

## Returns a complete inspectable dossier for an establishment
static func get_establishment_docket(estab_id: int, current_sim_day: int = 0) -> Dictionary:
	assert(estab_id > 0, "FATAL: [SocietyQueries] estab_id must be a positive integer.")

	# 1. Base metadata
	var base_rows = DBManager.query_rows("""
		SELECT 
			e.establishment_id,
			e.name,
			e.district_id,
			d.display_name AS district_name,
			d.grid_x,
			d.grid_z,
			e.owning_entity,
			e.unit_door_number,
			l_cat.code AS category_code,
			l_cat.title AS category_title,
			e.capacity,
			e.is_vacant
		FROM establishments e
		JOIN districts d ON e.district_id = d.district_id
		JOIN system_labels l_cat ON e.category_id = l_cat.label_id
		WHERE e.establishment_id = %d;
	""" % estab_id)

	if base_rows.is_empty():
		return {}

	var docket: Dictionary = base_rows[0]
	var cat_code: String = docket["category_code"]

	# Safe fallback for simulation day without bare autoload coupling
	if current_sim_day <= 0:
		var meta_rows = DBManager.query_rows("SELECT value FROM world_metadata WHERE key = 'current_sim_day';")
		if not meta_rows.is_empty():
			current_sim_day = int(meta_rows[0].get("value", 29219))
		else:
			current_sim_day = 29219


	# 2. Branch: Residential Unit
	if cat_code == "RESIDENTIAL_UNIT":
		docket["household"] = DBManager.query_rows("""
			SELECT 
				h.household_id,
				l_res.title AS residence_type,
				h.wealth_bracket_id,
				l_eth.title AS ethnicity,
				l_rel.title AS religion,
				e_pub.name AS local_pub_name
			FROM households h
			JOIN system_labels l_res ON h.residence_type_id = l_res.label_id
			JOIN system_labels l_eth ON h.ethnicity_id = l_eth.label_id
			JOIN system_labels l_rel ON h.religion_id = l_rel.label_id
			LEFT JOIN establishments e_pub ON h.local_pub_id = e_pub.establishment_id
			WHERE h.establishment_id = %d AND h.valid_to IS NULL;
		""" % estab_id)

		docket["residents"] = DBManager.query_rows("""
			SELECT 
				r.resident_id,
				r.first_name || ' ' || r.current_surname AS full_name,
				l_gen.title AS gender,
				CAST((%d - r.dob) / 365.25 AS INTEGER) AS age,
				l_edu.title AS education,
				l_role.title AS occupation,
				c.compensation_rate * c.weekly_hours AS weekly_wage
			FROM residents r
			JOIN households h ON r.household_id = h.household_id
			JOIN system_labels l_gen ON r.gender_id = l_gen.label_id
			JOIN system_labels l_edu ON r.education_level_id = l_edu.label_id
			LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id AND c.valid_to IS NULL
			LEFT JOIN system_labels l_role ON c.role_title_id = l_role.label_id
			WHERE h.establishment_id = %d AND r.dod IS NULL;
		""" % [current_sim_day, estab_id])

	# 3. Branch: Commercial, Industrial, or Civic Anchor
	else:
		# Employee Roster
		docket["employees"] = DBManager.query_rows("""
			SELECT 
				r.resident_id,
				r.first_name || ' ' || r.current_surname AS full_name,
				l_role.title AS role_title,
				l_class.title AS contract_class,
				l_sch.title AS schedule_window,
				c.weekly_hours,
				c.compensation_rate,
				(c.weekly_hours * c.compensation_rate) AS weekly_pay
			FROM livelihood_contracts c
			JOIN residents r ON c.resident_id = r.resident_id
			JOIN system_labels l_role ON c.role_title_id = l_role.label_id
			JOIN system_labels l_class ON c.contract_class_id = l_class.label_id
			JOIN system_labels l_sch ON c.schedule_window_id = l_sch.label_id
			WHERE c.employer_entity_id = 'ESTAB_%d' AND c.valid_to IS NULL AND r.dod IS NULL;
		""" % estab_id)

		# Market Catchment (Surrounding 9 Chebyshev blocks)
		var gx: int = int(docket["grid_x"])
		var gz: int = int(docket["grid_z"])
		var catchment = DBManager.query_rows("""
			SELECT 
				COUNT(DISTINCT r.resident_id) AS total_catchment_population,
				COUNT(DISTINCT h.household_id) AS total_catchment_households,
				ROUND(AVG(d.base_disposable_income), 2) AS avg_neighbor_disposable_income
			FROM districts d
			JOIN establishments e ON d.district_id = e.district_id
			JOIN households h ON e.establishment_id = h.establishment_id
			JOIN residents r ON h.household_id = r.household_id
			WHERE r.dod IS NULL
			  AND d.grid_x BETWEEN %d AND %d
			  AND d.grid_z BETWEEN %d AND %d;
		""" % [gx - 1, gx + 1, gz - 1, gz + 1])

		docket["market_catchment"] = catchment[0] if not catchment.is_empty() else {}

	return docket

## Queries the active living contracted workforce headcount for an establishment
static func get_establishment_headcount(estab_id: int) -> int:
	assert(estab_id > 0, "FATAL: [SocietyQueries] estab_id must be a positive integer.")

	var rows = DBManager.query_rows("""
		SELECT COUNT(*) AS staff_count
		FROM livelihood_contracts c
		JOIN residents r ON c.resident_id = r.resident_id
		WHERE c.employer_entity_id = 'ESTAB_%d'
		  AND c.valid_to IS NULL
		  AND r.dod IS NULL;
	""" % estab_id)

	if rows.is_empty():
		return 0
	return int(rows[0].get("staff_count", 0))

## Queries the database for eligible young adult kinship clusters within a district using temporal DOB bounds
## Queries the database for eligible young adult kinship clusters within a district using temporal DOB bounds
static func find_kinship_crew_candidates(district_id: String, min_age: int = 18, max_age: int = 26, current_sim_day: int = 29219) -> Array:
	assert(not district_id.is_empty(), "FATAL: [SocietyQueries] district_id cannot be empty.")
	
	# Calculate DOB day bounds from epoch
	var dob_max: int = current_sim_day - int(round(float(min_age) * 365.25))
	var dob_min: int = current_sim_day - int(round(float(max_age + 1) * 365.25))

	var sql := """
		SELECT 
			r.resident_id,
			r.household_id,
			h.establishment_id,
			r.first_name,
			r.current_surname,
			CAST((%d - r.dob) / 365.25 AS INTEGER) AS age,
			sr.to_resident_id AS relative_id,
			sr.affinity_score
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		LEFT JOIN social_relationships sr ON r.resident_id = sr.from_resident_id
		LEFT JOIN system_labels l_rel ON sr.relationship_type_id = l_rel.label_id AND l_rel.code = 'FAMILY'
		WHERE e.district_id = '%s'
		  AND r.dod IS NULL
		  AND r.dob <= %d AND r.dob >= %d
		ORDER BY r.household_id, r.resident_id;
	""" % [current_sim_day, district_id, dob_max, dob_min]
	
	return DBManager.query_rows(sql)

## Returns core profile and primary livelihood for an operative
static func get_resident_profile(resident_id: int, current_sim_day: int = 29219) -> Dictionary:
	var sql := """
		SELECT 
			r.resident_id,
			r.household_id,
			h.establishment_id,
			e.district_id,
			r.first_name || ' ' || r.current_surname AS full_name,
			CAST((%d - r.dob) / 365.25 AS INTEGER) AS age,
			r.gender_id,
			c.role_title_id,
			c.contract_class_id,
			c.employer_entity_id
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id AND c.valid_to IS NULL
		WHERE r.resident_id = %d;
	""" % [current_sim_day, resident_id]
	
	var rows: Array = DBManager.query_rows(sql)
	return rows[0] if not rows.is_empty() else {}

## Binds secondary crew enterprise contracts and activates agent flags in batch
static func bind_crew_contracts_and_activate(bindings: Array) -> bool:
	if bindings.is_empty():
		return false

	var type_secondary_id: int = DBManager.get_label_id("CONTRACT_TYPE", "SECONDARY")
	if type_secondary_id <= 0:
		type_secondary_id = 1

	var statements: Array[String] = []

	for b in bindings:
		var r_id: int = int(b.get("resident_id", 0))
		var employer_id: String = str(b.get("employer_entity_id", "CREW_ENTERPRISE"))
		var class_id: int = int(b.get("contract_class_id", 1))
		var role_id: int = int(b.get("role_title_id", 1))
		var sched_id: int = int(b.get("schedule_window_id", 1))
		var hours: float = float(b.get("weekly_hours", 20.0))
		var rate: float = float(b.get("compensation_rate", 0.0))
		var start_day: int = int(b.get("start_day", 29219))
		var c_type_id: int = int(b.get("contract_type_id", type_secondary_id))

		# 1. Insert secondary enterprise contract
		statements.append("""
			INSERT INTO livelihood_contracts (
				resident_id, employer_entity_id, contract_class_id, contract_type_id,
				role_title_id, schedule_window_id, weekly_hours, 
				compensation_rate, valid_from
			) VALUES (
				%d, '%s', %d, %d, %d, %d, %.2f, %.2f, %d
			);
		""" % [r_id, employer_id, class_id, c_type_id, role_id, sched_id, hours, rate, start_day])

		# 2. Mark citizen as active player-controlled/observed agent
		statements.append("UPDATE residents SET is_active_agent = 1 WHERE resident_id = %d;" % r_id)

	return DBManager.execute_batch(statements)

## Aggregates total population, active households, and average metrics for a district
static func get_district_census(district_id: String) -> Dictionary:
	assert(not district_id.is_empty(), "FATAL: [SocietyQueries] district_id cannot be empty.")
	
	var sql := """
		SELECT 
			COUNT(DISTINCT r.resident_id) AS total_population,
			COUNT(DISTINCT h.household_id) AS total_households,
			COUNT(DISTINCT e.establishment_id) AS total_establishments
		FROM establishments e
		LEFT JOIN households h ON e.establishment_id = h.establishment_id
		LEFT JOIN residents r ON h.household_id = r.household_id AND r.dod IS NULL
		WHERE e.district_id = '%s';
	""" % district_id
	
	var rows: Array = DBManager.query_rows(sql)
	if rows.is_empty():
		return {
			"total_population": 0,
			"total_households": 0,
			"total_establishments": 0
		}
	return rows[0]

## Fetches all establishments located in a given district for list views
static func get_district_establishments(district_id: String) -> Array:
	assert(not district_id.is_empty(), "FATAL: [SocietyQueries] district_id cannot be empty.")
	
	return DBManager.query_rows("""
		SELECT 
			e.establishment_id,
			e.name,
			e.unit_door_number,
			l_cat.code AS category_code,
			l_cat.title AS category_title,
			e.capacity,
			(SELECT COUNT(*) 
			 FROM livelihood_contracts c 
			 WHERE c.employer_entity_id = 'ESTAB_' || e.establishment_id 
			   AND c.valid_to IS NULL) AS worker_count
		FROM establishments e
		JOIN system_labels l_cat ON e.category_id = l_cat.label_id
		WHERE e.district_id = '%s'
		ORDER BY e.category_id ASC, e.establishment_id ASC;
	""" % district_id)