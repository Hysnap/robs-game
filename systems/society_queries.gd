# res://systems/society_queries.gd
class_name SocietyQueries
extends RefCounted

## Returns an inspectable dossier for an establishment, applying Fog-of-War masking when player_context is supplied
static func get_establishment_docket(estab_id: int, current_sim_day: int = 0, player_context: Dictionary = {}) -> Dictionary:
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

	if current_sim_day <= 0:
		var meta_rows = DBManager.query_rows("SELECT value FROM world_metadata WHERE key = 'current_sim_day';")
		if not meta_rows.is_empty():
			current_sim_day = int(meta_rows[0].get("value", 29219))
		else:
			current_sim_day = 29219

	var apply_fow: bool = not player_context.is_empty()
	var known_res_lookup: Dictionary = {}
	var known_hh_lookup: Dictionary = {}
	var is_estab_investigated: bool = false

	if apply_fow:
		var intel: Dictionary = _resolve_crew_intel_sets(player_context)
		known_res_lookup = intel["known_residents"]
		known_hh_lookup = intel["known_households"]
		var scouted_estabs: Dictionary = intel["scouted_establishments"]
		is_estab_investigated = scouted_estabs.has(estab_id)

	# 2. Branch: Residential Unit
	if cat_code == "RESIDENTIAL_UNIT":
		var hh_rows: Array = DBManager.query_rows("""
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

		var res_rows: Array = DBManager.query_rows("""
			SELECT 
				r.resident_id,
				r.household_id,
				r.first_name || ' ' || r.current_surname AS full_name,
				l_gen.code AS gender_code,
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

		var any_occupant_known: bool = not apply_fow or is_estab_investigated
		if apply_fow:
			var masked_residents: Array = []
			for row in res_rows:
				var r_id: int = int(row.get("resident_id", 0))
				var hh_id: int = int(row.get("household_id", 0))
				var is_known: bool = is_estab_investigated or known_res_lookup.has(r_id) or known_hh_lookup.has(hh_id)
				if is_known:
					any_occupant_known = true
					var clear_row: Dictionary = row.duplicate()
					clear_row["is_masked"] = false
					masked_residents.append(clear_row)
				else:
					var age_val: int = int(row.get("age", 30))
					var age_decade: int = int(floor(float(age_val) / 10.0)) * 10
					masked_residents.append({
						"resident_id": 0,
						"household_id": 0,
						"full_name": "UI_MASKED_OCCUPANT",
						"gender_code": row.get("gender_code", "U"),
						"gender": row.get("gender", "UI_INTEL_UNKNOWN"),
						"age": -1,
						"age_decade": age_decade,
						"education": "UI_INTEL_UNKNOWN",
						"occupation": "UI_INTEL_UNKNOWN",
						"weekly_wage": null,
						"is_masked": true
					})
			res_rows = masked_residents

		if apply_fow and not any_occupant_known and not hh_rows.is_empty():
			var masked_hh: Array = []
			for h_row in hh_rows:
				var m_h: Dictionary = h_row.duplicate()
				m_h["ethnicity"] = "UI_INTEL_UNKNOWN"
				m_h["religion"] = "UI_INTEL_UNKNOWN"
				m_h["local_pub_name"] = "UI_INTEL_UNKNOWN"
				m_h["is_masked"] = true
				masked_hh.append(m_h)
			hh_rows = masked_hh

		docket["household"] = hh_rows
		docket["residents"] = res_rows

	# 3. Branch: Commercial, Industrial, or Civic Anchor
	else:
		var emp_rows: Array = DBManager.query_rows("""
			SELECT 
				r.resident_id,
				r.household_id,
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

		if apply_fow:
			var masked_emps: Array = []
			for emp in emp_rows:
				var r_id: int = int(emp.get("resident_id", 0))
				var hh_id: int = int(emp.get("household_id", 0))
				var is_known: bool = is_estab_investigated or known_res_lookup.has(r_id) or known_hh_lookup.has(hh_id)
				if is_known:
					var clear_emp: Dictionary = emp.duplicate()
					clear_emp["is_masked"] = false
					masked_emps.append(clear_emp)
				else:
					masked_emps.append({
						"resident_id": 0,
						"household_id": 0,
						"full_name": "UI_MASKED_STAFF",
						"role_title": "UI_INTEL_UNKNOWN",
						"contract_class": "UI_INTEL_UNKNOWN",
						"schedule_window": "UI_INTEL_UNKNOWN",
						"weekly_hours": 0.0,
						"compensation_rate": 0.0,
						"weekly_pay": null,
						"is_masked": true
					})
			emp_rows = masked_emps

		docket["employees"] = emp_rows

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

## Resolves 1st-degree known residents, crew households, and investigated establishments while blocking 2nd-degree leaks
static func _resolve_crew_intel_sets(player_context: Dictionary) -> Dictionary:
	var crew_ids: Array[int] = []
	for raw_id in player_context.get("crew_resident_ids", []):
		var id_int: int = int(raw_id)
		if id_int > 0 and not crew_ids.has(id_int):
			crew_ids.append(id_int)

	var known_residents: Dictionary = {}
	var known_households: Dictionary = {}
	var scouted_establishments: Dictionary = {}

	for raw_known in player_context.get("known_resident_ids", []):
		var k_id: int = int(raw_known)
		if k_id > 0:
			known_residents[k_id] = true

	for raw_est in player_context.get("scouted_establishment_ids", []):
		var e_id: int = int(raw_est)
		if e_id > 0:
			scouted_establishments[e_id] = true

	if crew_ids.is_empty():
		return {
			"known_residents": known_residents,
			"known_households": known_households,
			"scouted_establishments": scouted_establishments
		}

	var id_strings: Array[String] = []
	for c_id in crew_ids:
		known_residents[c_id] = true
		id_strings.append(str(c_id))
	var in_clause: String = ", ".join(id_strings)

	# 1. Crew members' own households and home establishments
	var crew_hh_rows: Array = DBManager.query_rows("""
		SELECT r.household_id, h.establishment_id
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		WHERE r.resident_id IN (%s);
	""" % in_clause)
	for row in crew_hh_rows:
		known_households[int(row["household_id"])] = true
		scouted_establishments[int(row["establishment_id"])] = true

	# 2. Crew members' active workplaces
	var crew_work_rows: Array = DBManager.query_rows("""
		SELECT employer_entity_id
		FROM livelihood_contracts
		WHERE resident_id IN (%s) AND valid_to IS NULL AND employer_entity_id LIKE 'ESTAB_%%';
	""" % in_clause)
	for row in crew_work_rows:
		var emp_str: String = str(row.get("employer_entity_id", ""))
		if emp_str.begins_with("ESTAB_"):
			var work_est_id: int = int(emp_str.trim_prefix("ESTAB_"))
			if work_est_id > 0:
				scouted_establishments[work_est_id] = true

	# 3. Strict 1st-degree social_relationships from crew members (blocks 2nd-degree family acquaintances)
	var direct_edges: Array = DBManager.query_rows("""
		SELECT DISTINCT to_resident_id
		FROM social_relationships
		WHERE from_resident_id IN (%s) AND valid_to IS NULL;
	""" % in_clause)
	for edge in direct_edges:
		var target_id: int = int(edge.get("to_resident_id", 0))
		if target_id > 0:
			known_residents[target_id] = true

	return {
		"known_residents": known_residents,
		"known_households": known_households,
		"scouted_establishments": scouted_establishments
	}

## Returns 1st-degree known contacts (kin, co-residents, introduced acquaintances) for the crew, excluding 2nd-degree contacts
static func get_known_contacts_for_crew(crew_resident_ids: Array, known_resident_ids: Array = [], current_sim_day: int = 29219) -> Array[Dictionary]:
	var crew_set: Dictionary = {}
	var id_strings: Array[String] = []
	for raw_id in crew_resident_ids:
		var c_id: int = int(raw_id)
		if c_id > 0 and not crew_set.has(c_id):
			crew_set[c_id] = true
			id_strings.append(str(c_id))

	if id_strings.is_empty():
		return []

	var in_clause: String = ", ".join(id_strings)
	var candidate_ids: Dictionary = {}

	# A. Co-residents sharing a household with any crew member
	var co_res_rows: Array = DBManager.query_rows("""
		SELECT DISTINCT r2.resident_id
		FROM residents r1
		JOIN residents r2 ON r1.household_id = r2.household_id
		WHERE r1.resident_id IN (%s) AND r2.dod IS NULL;
	""" % in_clause)
	for row in co_res_rows:
		var r_id: int = int(row["resident_id"])
		if not crew_set.has(r_id):
			candidate_ids[r_id] = "HOUSEHOLD"

	# B. Direct 1st-degree social_relationships from crew members (strictly 1 hop)
	var edge_rows: Array = DBManager.query_rows("""
		SELECT DISTINCT sr.to_resident_id, l_rel.code AS rel_code
		FROM social_relationships sr
		JOIN system_labels l_rel ON sr.relationship_type_id = l_rel.label_id
		WHERE sr.from_resident_id IN (%s) AND sr.valid_to IS NULL;
	""" % in_clause)
	for row in edge_rows:
		var t_id: int = int(row["to_resident_id"])
		if not crew_set.has(t_id) and not candidate_ids.has(t_id):
			candidate_ids[t_id] = str(row.get("rel_code", "CONTACT"))

	# C. Explicitly introduced / investigated contacts
	for raw_k in known_resident_ids:
		var k_id: int = int(raw_k)
		if k_id > 0 and not crew_set.has(k_id) and not candidate_ids.has(k_id):
			candidate_ids[k_id] = "INTRODUCED"

	if candidate_ids.is_empty():
		return []

	var contact_id_strs: Array[String] = []
	for c_id in candidate_ids.keys():
		contact_id_strs.append(str(c_id))

	var rows: Array = DBManager.query_rows("""
		SELECT 
			r.resident_id,
			r.household_id,
			h.establishment_id,
			e.name AS home_address,
			e.district_id,
			d.display_name AS district_name,
			r.first_name || ' ' || r.current_surname AS full_name,
			CAST((%d - r.dob) / 365.25 AS INTEGER) AS age,
			l_role.title AS occupation
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		JOIN districts d ON e.district_id = d.district_id
		LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id AND c.valid_to IS NULL
		LEFT JOIN system_labels l_role ON c.role_title_id = l_role.label_id
		WHERE r.resident_id IN (%s) AND r.dod IS NULL
		ORDER BY r.current_surname ASC, r.first_name ASC;
	""" % [current_sim_day, ", ".join(contact_id_strs)])

	var contacts: Array[Dictionary] = []
	for row in rows:
		var r_id: int = int(row["resident_id"])
		var entry: Dictionary = row.duplicate()
		entry["relationship_source"] = candidate_ids.get(r_id, "CONTACT")
		contacts.append(entry)

	return contacts

## Ensures reciprocal FAMILY edges exist in social_relationships for all living members of a household
static func ensure_household_kinship_edges(household_id: int, sim_start_day: int = 29219) -> void:
	assert(household_id > 0, "FATAL: [SocietyQueries] household_id must be positive.")
	var members: Array = DBManager.query_rows("""
		SELECT resident_id
		FROM residents
		WHERE household_id = %d AND dod IS NULL;
	""" % household_id)

	if members.size() <= 1:
		return

	var rel_family_id: int = DBManager.get_label_id("RELATIONSHIP_TYPE", "FAMILY")
	var reason_id: int = DBManager.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var statements: Array[String] = []

	for i in range(members.size()):
		for j in range(members.size()):
			if i == j:
				continue
			var a: int = int(members[i]["resident_id"])
			var b: int = int(members[j]["resident_id"])
			statements.append("""
				INSERT OR IGNORE INTO social_relationships (
					from_resident_id, to_resident_id, relationship_type_id,
					context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
				) VALUES (%d, %d, %d, NULL, 0.90, %d, NULL, %d);
			""" % [a, b, rel_family_id, sim_start_day, reason_id])

	if not statements.is_empty():
		DBManager.execute_batch(statements)

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
			COUNT(DISTINCT r.resident_id) AS active_population,
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
			"active_population": 0,
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