# res://systems/society_queries.gd
class_name SocietyQueries
extends RefCounted

## Fetches all establishments located in a given district for list views
static func get_district_establishments(district_id: String) -> Array:
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

## Returns a complete inspectable dossier for an establishment
static func get_establishment_docket(estab_id: int) -> Dictionary:
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
				(29219 - r.dob) / 365 AS age,
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
		""" % estab_id)

	# 3. Branch: Commercial, Industrial, or Civic Anchor
	else:
		# Employee Roster
		docket["employees"] = DBManager.query_rows("""
			SELECT 
				r.resident_id,
				r.first_name || ' ' || r.current_surname AS full_name,
				l_role.title AS role_title,
				l_class.title AS contract_class,
				l_sch.title as schedule_window,
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