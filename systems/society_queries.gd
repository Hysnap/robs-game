# res://systems/society_queries.gd
class_name SocietyQueries
extends RefCounted

const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

## Returns an inspectable dossier for an establishment, applying continuous 0-100 Fog-of-War masking when player_context is supplied
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
			e.owner_org_id,
			o.display_name AS owner_org_name,
			e.unit_door_number,
			l_cat.code AS category_code,
			l_cat.title AS category_title,
			e.capacity,
			e.is_vacant
		FROM establishments e
		JOIN districts d ON e.district_id = d.district_id
		LEFT JOIN organizations o ON e.owner_org_id = o.org_id
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
	var estab_score: float = 100.0
	var ws_ref = player_context.get("world_state", null)
	var observers_ref = player_context.get("observers", null)

	if apply_fow:
		var intel: Dictionary = _resolve_crew_intel_sets(player_context)
		known_res_lookup = intel["known_residents"]
		known_hh_lookup = intel["known_households"]
		var own_estabs: Dictionary = intel["own_establishments"]

		if own_estabs.has(estab_id):
			estab_score = 100.0
		elif ws_ref is Dictionary and observers_ref is Array:
			estab_score = IntelManagerScript.get_collective_score(ws_ref, observers_ref, "ESTABLISHMENT", str(estab_id))
		else:
			estab_score = 0.0

		if not IntelManagerScript.is_field_exposed(estab_score, "ESTABLISHMENT", "capacity"):
			docket["capacity"] = null
			docket["owner_org_id"] = ""
			docket["owner_org_name"] = "UI_INTEL_UNKNOWN"

	docket["intel_score"] = estab_score
	var all_staff_exposed: bool = not apply_fow or IntelManagerScript.is_field_exposed(estab_score, "ESTABLISHMENT", "employees.all")
	var all_residents_exposed: bool = not apply_fow or IntelManagerScript.is_field_exposed(estab_score, "ESTABLISHMENT", "residents.all")
	var pay_exposed_by_estab: bool = not apply_fow or IntelManagerScript.is_field_exposed(estab_score, "ESTABLISHMENT", "market_catchment")

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

		var any_occupant_known: bool = all_residents_exposed
		if apply_fow:
			var masked_residents: Array = []
			for row in res_rows:
				var r_id: int = int(row.get("resident_id", 0))
				var hh_id: int = int(row.get("household_id", 0))
				var res_score: float = 0.0
				if ws_ref is Dictionary and observers_ref is Array and r_id > 0:
					res_score = IntelManagerScript.get_collective_score(ws_ref, observers_ref, "RESIDENT", str(r_id))
				var is_known: bool = all_residents_exposed or known_res_lookup.has(r_id) or known_hh_lookup.has(hh_id) or IntelManagerScript.is_entity_known(res_score, "RESIDENT")
				if is_known:
					any_occupant_known = true
					var clear_row: Dictionary = row.duplicate()
					clear_row["is_masked"] = false
					if not pay_exposed_by_estab and not known_res_lookup.has(r_id) and not known_hh_lookup.has(hh_id) and not IntelManagerScript.is_field_exposed(res_score, "RESIDENT", "hourly_wage"):
						clear_row["weekly_wage"] = null
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
			WHERE c.employer_establishment_id = %d AND c.valid_to IS NULL AND r.dod IS NULL;
		""" % estab_id)

		if apply_fow:
			var masked_emps: Array = []
			for emp in emp_rows:
				var r_id: int = int(emp.get("resident_id", 0))
				var hh_id: int = int(emp.get("household_id", 0))
				var res_score: float = 0.0
				if ws_ref is Dictionary and observers_ref is Array and r_id > 0:
					res_score = IntelManagerScript.get_collective_score(ws_ref, observers_ref, "RESIDENT", str(r_id))
				var is_known: bool = all_staff_exposed or known_res_lookup.has(r_id) or known_hh_lookup.has(hh_id) or IntelManagerScript.is_entity_known(res_score, "RESIDENT")
				if is_known:
					var clear_emp: Dictionary = emp.duplicate()
					clear_emp["is_masked"] = false
					if not pay_exposed_by_estab and not known_res_lookup.has(r_id) and not known_hh_lookup.has(hh_id) and not IntelManagerScript.is_field_exposed(res_score, "RESIDENT", "hourly_wage"):
						clear_emp["weekly_pay"] = null
						clear_emp["compensation_rate"] = 0.0
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

		# Market Catchment (Surrounding 9 Chebyshev blocks) — gated by ESTABLISHMENT threshold
		if not apply_fow or IntelManagerScript.is_field_exposed(estab_score, "ESTABLISHMENT", "market_catchment"):
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
		else:
			docket["market_catchment"] = {}

	return docket

## Resolves 1st-degree known residents, crew households, and own home/work establishments while blocking 2nd-degree leaks
static func _resolve_crew_intel_sets(player_context: Dictionary) -> Dictionary:
	var crew_ids: Array[int] = []
	for raw_id in player_context.get("crew_resident_ids", []):
		var id_int: int = int(raw_id)
		if id_int > 0 and not crew_ids.has(id_int):
			crew_ids.append(id_int)

	var known_residents: Dictionary = {}
	var known_households: Dictionary = {}
	var own_establishments: Dictionary = {}

	if crew_ids.is_empty():
		return {
			"known_residents": known_residents,
			"known_households": known_households,
			"own_establishments": own_establishments
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
		own_establishments[int(row["establishment_id"])] = true

	# 2. Crew members' active workplaces
	var crew_work_rows: Array = DBManager.query_rows("""
		SELECT employer_establishment_id
		FROM livelihood_contracts
		WHERE resident_id IN (%s) AND valid_to IS NULL AND employer_establishment_id IS NOT NULL;
	""" % in_clause)
	for row in crew_work_rows:
		var work_est_id: int = int(row.get("employer_establishment_id", 0))
		if work_est_id > 0:
			own_establishments[work_est_id] = true

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
		"own_establishments": own_establishments
	}

## Returns 1st-degree known contacts (kin, co-residents, and knowledge_pool acquaintances) for the crew, excluding 2nd-degree leaks
static func get_known_contacts_for_crew(player_context: Dictionary, current_sim_day: int = 29219) -> Array[Dictionary]:
	var crew_set: Dictionary = {}
	var id_strings: Array[String] = []
	for raw_id in player_context.get("crew_resident_ids", []):
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

	# C. Continuous 0-100 knowledge_pools contacts meeting RESIDENT discovery threshold
	var ws_ref = player_context.get("world_state", null)
	var observers_ref = player_context.get("observers", null)
	if ws_ref is Dictionary and observers_ref is Array:
		var res_pools: Dictionary = ws_ref.get("knowledge_pools", {}).get("RESIDENT", {})
		var seen_subjects: Dictionary = {}
		for obs in observers_ref:
			var obs_id: String = str(obs.get("observer_id", ""))
			var dossier = res_pools.get(obs_id, null)
			if not (dossier is Dictionary):
				continue
			for target_key in dossier.keys():
				var tk_str := str(target_key)
				if tk_str.begins_with("RESIDENT:"):
					var subj_id_str := tk_str.trim_prefix("RESIDENT:")
					if subj_id_str.is_valid_int() and not seen_subjects.has(subj_id_str):
						seen_subjects[subj_id_str] = true
						var k_id: int = int(subj_id_str)
						if k_id > 0 and not crew_set.has(k_id) and not candidate_ids.has(k_id):
							var score: float = IntelManagerScript.get_collective_score(ws_ref, observers_ref, "RESIDENT", subj_id_str)
							if IntelManagerScript.is_entity_known(score, "RESIDENT"):
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
		WHERE c.employer_establishment_id = %d
		  AND c.valid_to IS NULL
		  AND r.dod IS NULL;
	""" % estab_id)

	if rows.is_empty():
		return 0
	return int(rows[0].get("staff_count", 0))

## Queries the database for eligible young adult kinship clusters within a district using temporal DOB bounds
static func find_kinship_crew_candidates(district_id: String, min_age: int = 18, max_age: int = 26, current_sim_day: int = 29219) -> Array:
	assert(not district_id.is_empty(), "FATAL: [SocietyQueries] district_id cannot be empty.")
	
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
			c.employer_org_id,
			c.employer_establishment_id
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
		var employer_org_id: String = str(b.get("employer_org_id", "ORG:CREW_ENTERPRISE"))
		if not employer_org_id.is_empty() and not employer_org_id.begins_with("ORG:"):
			employer_org_id = "ORG:%s" % employer_org_id
		var employer_org_sql: String = "'%s'" % employer_org_id.replace("'", "''") if not employer_org_id.is_empty() else "NULL"
		var raw_estab = b.get("employer_establishment_id", null)
		var employer_estab_sql: String = str(int(raw_estab)) if (raw_estab != null and int(raw_estab) > 0) else "NULL"
		var class_id: int = int(b.get("contract_class_id", 1))
		var role_id: int = int(b.get("role_title_id", 1))
		var sched_id: int = int(b.get("schedule_window_id", 1))
		var hours: float = float(b.get("weekly_hours", 20.0))
		var rate: float = float(b.get("compensation_rate", 0.0))
		var start_day: int = int(b.get("start_day", 29219))
		var c_type_id: int = int(b.get("contract_type_id", type_secondary_id))

		statements.append("""
			INSERT INTO livelihood_contracts (
				resident_id, employer_org_id, employer_establishment_id, contract_class_id, contract_type_id,
				role_title_id, schedule_window_id, weekly_hours, 
				compensation_rate, valid_from
			) VALUES (
				%d, %s, %s, %d, %d, %d, %d, %.2f, %.2f, %d
			);
		""" % [r_id, employer_org_sql, employer_estab_sql, class_id, c_type_id, role_id, sched_id, hours, rate, start_day])

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
			 WHERE c.employer_establishment_id = e.establishment_id 
			   AND c.valid_to IS NULL) AS worker_count
		FROM establishments e
		JOIN system_labels l_cat ON e.category_id = l_cat.label_id
		WHERE e.district_id = '%s'
		ORDER BY e.category_id ASC, e.establishment_id ASC;
	""" % district_id)

# ==============================================================================
# CONSOLIDATED READ-ONLY CITY AUDIT QUERIES (Merged from city_auditor_queries.sql)
# ==============================================================================

static func get_audit_entity_counts(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT 'boroughs' AS entity, COUNT(*) AS count FROM boroughs
		UNION ALL SELECT 'districts', COUNT(*) FROM districts
		UNION ALL SELECT 'establishments', COUNT(*) FROM establishments
		UNION ALL SELECT 'households', COUNT(*) FROM households
		UNION ALL SELECT 'residents', COUNT(*) FROM residents
		UNION ALL SELECT 'workplace_job_slots', COUNT(*) FROM workplace_job_slots
		UNION ALL SELECT 'contracts', COUNT(*) FROM livelihood_contracts
		UNION ALL SELECT 'relationships', COUNT(*) FROM social_relationships;
	""")

static func get_audit_district_distribution(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT
			district_id,
			district_name,
			total_households,
			active_population AS active_population,
			formally_employed_count,
			street_informal_count,
			incarcerated_count
		FROM v_district_census
		ORDER BY active_population DESC, district_id ASC;
	""")

static func get_audit_borough_distribution(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT
			borough_id,
			borough_name,
			total_districts,
			total_households,
			active_population AS active_population,
			formally_employed_count,
			street_informal_count,
			incarcerated_count
		FROM v_borough_census
		ORDER BY active_population DESC, borough_id ASC;
	""")

static func get_audit_establishment_categories(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT
			l.code AS category,
			COUNT(*) AS establishment_count,
			SUM(e.capacity) AS total_capacity,
			SUM(CASE WHEN e.is_vacant = 1 THEN 1 ELSE 0 END) AS vacant_count
		FROM establishments e
		JOIN system_labels l ON e.category_id = l.label_id
		GROUP BY l.code
		ORDER BY establishment_count DESC, category ASC;
	""")

static func get_audit_employment_classes(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT
			l.code AS contract_class,
			COUNT(*) AS contract_count,
			ROUND(AVG(c.weekly_hours), 2) AS average_weekly_hours,
			ROUND(AVG(c.compensation_rate), 2) AS average_compensation_rate
		FROM livelihood_contracts c
		JOIN system_labels l ON c.contract_class_id = l.label_id
		WHERE c.valid_to IS NULL
		GROUP BY l.code
		ORDER BY contract_count DESC, contract_class ASC;
	""")

static func get_audit_social_degree(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT
			degree_bucket,
			COUNT(*) AS resident_count
		FROM (
			SELECT
				r.resident_id,
				CASE
					WHEN COUNT(sr.relationship_id) = 0 THEN '0'
					WHEN COUNT(sr.relationship_id) BETWEEN 1 AND 2 THEN '1-2'
					WHEN COUNT(sr.relationship_id) BETWEEN 3 AND 5 THEN '3-5'
					WHEN COUNT(sr.relationship_id) BETWEEN 6 AND 10 THEN '6-10'
					ELSE '11+'
				END AS degree_bucket
			FROM residents r
			LEFT JOIN social_relationships sr
				ON sr.from_resident_id = r.resident_id
				OR sr.to_resident_id = r.resident_id
			WHERE r.dod IS NULL
			GROUP BY r.resident_id
		)
		GROUP BY degree_bucket
		ORDER BY CASE degree_bucket
			WHEN '0' THEN 0
			WHEN '1-2' THEN 1
			WHEN '3-5' THEN 2
			WHEN '6-10' THEN 3
			ELSE 4
		END;
	""")

static func get_audit_integrity_checks(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT
			'orphan_establishments' AS check_name,
			COUNT(*) AS failures
		FROM establishments e
		LEFT JOIN districts d ON d.district_id = e.district_id
		WHERE d.district_id IS NULL
		UNION ALL
		SELECT
			'orphan_households',
			COUNT(*)
		FROM households h
		LEFT JOIN establishments e ON e.establishment_id = h.establishment_id
		WHERE e.establishment_id IS NULL
		UNION ALL
		SELECT
			'orphan_residents',
			COUNT(*)
		FROM residents r
		LEFT JOIN households h ON h.household_id = r.household_id
		WHERE h.household_id IS NULL
		UNION ALL
		SELECT
			'orphan_relationships',
			COUNT(*)
		FROM social_relationships sr
		LEFT JOIN residents rf ON rf.resident_id = sr.from_resident_id
		LEFT JOIN residents rt ON rt.resident_id = sr.to_resident_id
		WHERE rf.resident_id IS NULL OR rt.resident_id IS NULL
		UNION ALL
		SELECT
			'orphan_contracts',
			COUNT(*)
		FROM livelihood_contracts c
		LEFT JOIN residents r ON r.resident_id = c.resident_id
		WHERE r.resident_id IS NULL;
	""")

static func get_audit_district_capacity(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT
			d.district_id,
			d.display_name AS district_name,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL THEN r.resident_id END) AS active_population,
			COALESCE(SUM(
				CASE
					WHEN l.code IN ('RESIDENTIAL_UNIT', 'RESIDENTIAL') THEN e.capacity
					ELSE 0
				END
			), 0) AS residential_capacity
		FROM districts d
		LEFT JOIN establishments e ON e.district_id = d.district_id
		LEFT JOIN system_labels l ON l.label_id = e.category_id
		LEFT JOIN households h ON h.establishment_id = e.establishment_id
		LEFT JOIN residents r ON r.household_id = h.household_id
		GROUP BY d.district_id, d.display_name
		ORDER BY d.district_id ASC;
	""")

static func get_audit_labor_vacancies(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT 
			role.code AS role_title,
			edu.code AS required_education,
			COUNT(w.slot_id) AS budgeted_slots,
			SUM(CASE WHEN w.is_filled = 1 THEN 1 ELSE 0 END) AS filled_slots,
			SUM(CASE WHEN w.is_filled = 0 THEN 1 ELSE 0 END) AS vacant_slots,
			ROUND(AVG(w.hourly_rate), 2) AS avg_hourly_wage
		FROM workplace_job_slots w
		JOIN system_labels role ON w.role_title_id = role.label_id
		JOIN system_labels edu ON w.min_education_level_id = edu.label_id
		GROUP BY role.code, edu.code
		ORDER BY vacant_slots DESC, budgeted_slots DESC;
	""")

static func get_audit_labor_by_sector(db = DBManager) -> Array:
	return db.query_rows("""
		SELECT 
			sec.code AS sector,
			COUNT(w.slot_id) AS budgeted_slots,
			SUM(CASE WHEN w.is_filled = 1 THEN 1 ELSE 0 END) AS filled_slots,
			SUM(CASE WHEN w.is_filled = 0 THEN 1 ELSE 0 END) AS vacant_slots
		FROM workplace_job_slots w
		JOIN system_labels sec ON w.sector_category_id = sec.label_id
		GROUP BY sec.code
		ORDER BY budgeted_slots DESC;
	""")