# res://systems/society/crew_scout_bootstrapper.gd
class_name CrewScoutBootstrapper
extends RefCounted

const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")
const SCENARIO_MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const INTEL_MANAGER = preload("res://systems/multilayer_info_loop/intel_manager.gd")

## Scouts related young adults in the home district using the configured strategy pipeline,
## binds secondary grey-economy contracts & org memberships in SQLite, projects Layer B crew/kin milestones,
## seeds baseline crew knowledge_pools, and stamps operative profiles into world_state["residents"].
static func scout_and_bind_starting_crew(world_state: Dictionary, home_district_id: String) -> bool:
	assert(not home_district_id.is_empty(), "FATAL: [CrewScoutBootstrapper] home_district_id cannot be empty.")
	assert(SCENARIO_MANIFEST_MANAGER.has_module("startpoint"), "FATAL: [CrewScoutBootstrapper] Missing 'startpoint' module.")

	# 1. Resolve simulation temporal day offset (default to 1980-01-01 start day 29219)
	var current_sim_day: int = int(world_state.get("metadata", {}).get("current_sim_day", 29219))

	# 2. Ingest generation criteria and operative templates from startpoint config
	var startpoint: Dictionary = SCENARIO_MANIFEST_MANAGER.load_module("startpoint")
	var criteria: Dictionary = startpoint.get("crew_generation_criteria", {})
	var starting_staff_configs: Dictionary = startpoint.get("starting_staff", {})

	assert(not starting_staff_configs.is_empty(), "FATAL: [CrewScoutBootstrapper] 'starting_staff' config is empty.")

	var staff_slots: Array = starting_staff_configs.keys()
	var target_count: int = int(criteria.get("target_count", staff_slots.size()))
	var min_age: int = int(criteria.get("age_min", 18))
	var max_age: int = int(criteria.get("age_max", 26))
	var pipeline: Array = criteria.get("pipeline", [])

	# 3. Query raw demographic candidate rows from SQLite via SocietyQueries using epoch bounds
	var candidate_rows: Array = SOCIETY_QUERIES.find_kinship_crew_candidates(home_district_id, min_age, max_age, current_sim_day)
	if candidate_rows.is_empty():
		push_error("[CrewScoutBootstrapper] No eligible candidates found in district: %s" % home_district_id)
		return false

	# 4. Assemble indexed candidate context payload
	var by_household: Dictionary = {}
	var unique_candidates: Dictionary = {}
	var relatives_by_resident: Dictionary = {}

	for row in candidate_rows:
		var r_id: int = int(row.get("resident_id", 0))
		var h_id: int = int(row.get("household_id", 0))
		if not unique_candidates.has(r_id):
			unique_candidates[r_id] = row
		if not relatives_by_resident.has(r_id):
			relatives_by_resident[r_id] = []
		var raw_rel_id = row.get("relative_id", null)
		var rel_id: int = int(raw_rel_id) if raw_rel_id != null else 0
		if rel_id > 0:
			var raw_aff = row.get("affinity_score", null)
			relatives_by_resident[r_id].append({
				"relative_id": rel_id,
				"relationship_code": str(row.get("relationship_code", "")),
				"affinity_score": float(raw_aff) if raw_aff != null else 0.0
			})

		if not by_household.has(h_id):
			by_household[h_id] = []
		if not r_id in by_household[h_id]:
			by_household[h_id].append(r_id)

	var base_context: Dictionary = {
		"candidate_rows": candidate_rows,
		"by_household": by_household,
		"unique_candidates": unique_candidates,
		"relatives_by_resident": relatives_by_resident,
		"target_count": target_count
	}

	# 5. Resolve candidates dynamically through the strategy pipeline
	var selected_resident_ids: Array[int] = _execute_pipeline(pipeline, base_context)
	if selected_resident_ids.size() < target_count:
		push_error("[CrewScoutBootstrapper] Strategy pipeline failed to assemble required cohort of %d operatives." % target_count)
		return false

	# 6. Resolve DB Label IDs dynamically from the secondary contract profile & seed Crew Organization
	var sec_contract_def: Dictionary = criteria.get("secondary_contract", {})
	var class_code: String = str(sec_contract_def.get("contract_class_code", "INFORMAL_GREY"))
	var sched_code: String = str(sec_contract_def.get("schedule_window_code", "EVENING"))
	var sched_fallback: String = str(sec_contract_def.get("fallback_schedule_window_code", "FLEXIBLE"))
	var employer_org_id: String = str(sec_contract_def.get("employer_org_id", "ORG:CREW_ENTERPRISE"))
	if not employer_org_id.begins_with("ORG:"):
		employer_org_id = "ORG:%s" % employer_org_id
	var weekly_hours: float = float(sec_contract_def.get("weekly_hours", 20.0))
	var comp_rate: float = float(sec_contract_def.get("compensation_rate", 0.0))

	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	DB_MANAGER.execute_batch([
		"INSERT OR IGNORE INTO organizations (org_id, display_name, org_type, legal_status, institution_rail_class, valid_from, valid_to, change_reason_id) VALUES ('%s', 'Crew Enterprise', 'GANG', 'INFORMAL_GREY', 'STANDARD', %d, NULL, %d);" % [
			employer_org_id.replace("'", "''"), current_sim_day, reason_world_gen_id
		]
	])

	var contract_class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", class_code)
	var schedule_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", sched_code)
	if schedule_id <= 0:
		schedule_id = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", sched_fallback)

	var bindings: Array[Dictionary] = []
	var crew_org_member_sql: Array[String] = []

	# 7. Build contract bindings & organization memberships dynamically driven by starting_staff definitions
	for i in range(target_count):
		var slot_id: String = staff_slots[i]
		var slot_cfg: Dictionary = starting_staff_configs[slot_id]
		var r_id: int = selected_resident_ids[i]
		var role_str: String = str(slot_cfg.get("role", "RUNNER"))
		var role_title_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", role_str)
		var is_leader: bool = (i == 0 or bool(slot_cfg.get("is_leader", false)))
		var auth_mask: int = 3 if is_leader else 1

		bindings.append({
			"resident_id": r_id,
			"role_title_id": role_title_id,
			"contract_class_id": contract_class_id,
			"schedule_window_id": schedule_id,
			"employer_org_id": employer_org_id,
			"employer_establishment_id": null,
			"weekly_hours": weekly_hours,
			"compensation_rate": comp_rate,
			"start_day": current_sim_day
		})

		crew_org_member_sql.append("""
			INSERT OR IGNORE INTO organization_members (
				org_id, resident_id, role_code, authority_mask, valid_from, valid_to, change_reason_id
			) VALUES ('%s', %d, '%s', %d, %d, NULL, %d);
		""" % [employer_org_id.replace("'", "''"), r_id, role_str.replace("'", "''"), auth_mask, current_sim_day, reason_world_gen_id])

	# 8. Execute batch inserts and agent activation in SQLite
	var db_ok: bool = SOCIETY_QUERIES.bind_crew_contracts_and_activate(bindings)
	if not db_ok:
		push_error("[CrewScoutBootstrapper] Failed to execute database contract binding batch.")
		return false
	if not crew_org_member_sql.is_empty():
		DB_MANAGER.execute_batch(crew_org_member_sql)

	# 9. Hydrate canonical world_state["residents"] directly from database profile and slot config
	if not world_state.has("residents"):
		world_state["residents"] = {}

	var leader_home_estab_id: int = 0

	for i in range(target_count):
		var slot_id: String = staff_slots[i]
		var slot_cfg: Dictionary = starting_staff_configs[slot_id]
		var r_id: int = selected_resident_ids[i]
		var profile: Dictionary = SOCIETY_QUERIES.get_resident_profile(r_id, current_sim_day)

		var hh_id: int = int(profile.get("household_id", 0))
		var home_estab_id: int = int(profile.get("establishment_id", 0))
		assert(hh_id > 0, "FATAL: [CrewScoutBootstrapper] Operative '%s' (resident_id=%d) has no valid household_id!" % [slot_id, r_id])
		assert(home_estab_id > 0, "FATAL: [CrewScoutBootstrapper] Operative '%s' (resident_id=%d) has no physical home establishment_id!" % [slot_id, r_id])

		if i == 0 or bool(slot_cfg.get("is_leader", false)):
			leader_home_estab_id = home_estab_id

		# Guarantee reciprocal household edges exist in social_relationships for all co-residents of this household
		SOCIETY_QUERIES.ensure_household_kinship_edges(hh_id, current_sim_day)

		var resident_entry: Dictionary = slot_cfg.duplicate(true)
		var starting_pocket_cash: float = float(resident_entry.get("pocket_cash", 0.0))
		resident_entry.erase("pocket_cash")

		var res_inv: Dictionary = resident_entry.get("inventory", {})
		res_inv["CASH"] = float(res_inv.get("CASH", 0.0)) + starting_pocket_cash
		resident_entry["inventory"] = res_inv

		resident_entry["id"] = r_id
		resident_entry["slot_id"] = slot_id
		resident_entry["resident_id"] = r_id
		resident_entry["name"] = profile.get("full_name", "")
		resident_entry["age"] = profile.get("age", 0)
		resident_entry["gender_id"] = profile.get("gender_id", 0)
		resident_entry["household_id"] = hh_id
		resident_entry["establishment_id"] = home_estab_id
		resident_entry["home_establishment_id"] = home_estab_id
		resident_entry["current_district_id"] = home_district_id
		resident_entry["church_id"] = profile.get("church_id", null)
		resident_entry["local_pub_id"] = profile.get("local_pub_id", null)
		resident_entry["openness"] = float(profile.get("openness", 0.5))
		resident_entry["conscientiousness"] = float(profile.get("conscientiousness", 0.5))
		resident_entry["extraversion"] = float(profile.get("extraversion", 0.5))
		resident_entry["agreeableness"] = float(profile.get("agreeableness", 0.5))
		resident_entry["neuroticism"] = float(profile.get("neuroticism", 0.5))
		resident_entry["primary_employer_org_id"] = profile.get("employer_org_id", "")
		var raw_emp_est = profile.get("employer_establishment_id", null)
		resident_entry["primary_employer_establishment_id"] = int(raw_emp_est) if raw_emp_est != null else 0
		resident_entry["primary_role_id"] = profile.get("role_title_id", 0)
		resident_entry["primary_contract_class_id"] = profile.get("contract_class_id", 0)

		world_state["residents"][r_id] = resident_entry

	if not world_state.has("operations") or not (world_state["operations"] is Dictionary):
		world_state["operations"] = {}
	world_state["operations"]["crew_org_id"] = employer_org_id
	if leader_home_estab_id > 0:
		world_state["operations"]["hq_establishment_id"] = leader_home_estab_id

	# Seed baseline 0-100 familiarity via flood-down (ORG) and trickle-up (RESIDENT -> ORG)
	_seed_starting_crew_knowledge(world_state, selected_resident_ids, home_district_id, employer_org_id)

	# 11. Project Layer B Personal & Kinship Milestones (Birthdays & Wedding Anniversaries) into calendar_events
	project_personal_milestones_for_agents(selected_resident_ids, current_sim_day)

	# 12. Anchor starting_inventory from startpoint config to the leader's physical home establishment & link HQ
	if leader_home_estab_id > 0:
		DB_MANAGER.execute_batch([
			"UPDATE organizations SET hq_establishment_id = %d WHERE org_id = '%s';" % [
				leader_home_estab_id,
				employer_org_id.replace("'", "''")
			]
		])

	var starting_inv: Dictionary = startpoint.get("starting_inventory", {})
	if not starting_inv.is_empty() and leader_home_estab_id > 0:
		if not world_state.has("establishments"):
			world_state["establishments"] = {}
		if not world_state["establishments"].has(leader_home_estab_id):
			world_state["establishments"][leader_home_estab_id] = {
				"establishment_id": leader_home_estab_id,
				"district_id": home_district_id,
				"inventory": {}
			}
		var inv: Dictionary = world_state["establishments"][leader_home_estab_id].get("inventory", {})
		for comm_id in starting_inv.keys():
			inv[comm_id] = float(inv.get(comm_id, 0.0)) + float(starting_inv[comm_id])
		world_state["establishments"][leader_home_estab_id]["inventory"] = inv

	return true

## Reusable Layer B Lego Brick: projects annual BIRTHDAY and WEDDING_ANNIVERSARY calendar_events
## for active agents and their 1st/2nd-degree kin (supports pre-1900 negative DOB offsets cleanly).
static func project_personal_milestones_for_agents(agent_ids: Array[int], current_sim_day: int) -> void:
	if agent_ids.is_empty():
		return
	var id_strs: Array[String] = []
	for aid in agent_ids:
		if aid > 0:
			id_strs.append(str(aid))
	if id_strs.is_empty():
		return
	var in_clause := ", ".join(id_strs)

	# Gather crew + co-residents + 1st-degree kin
	var person_rows: Array = DB_MANAGER.query_rows("""
		SELECT DISTINCT r.resident_id, r.dob, h.establishment_id
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		WHERE r.dod IS NULL AND (
			r.resident_id IN (%s)
			OR r.household_id IN (SELECT household_id FROM residents WHERE resident_id IN (%s))
			OR r.resident_id IN (
				SELECT sr.to_resident_id
				FROM social_relationships sr
				JOIN system_labels l ON sr.relationship_type_id = l.label_id
				WHERE sr.from_resident_id IN (%s)
				  AND sr.valid_to IS NULL
				  AND l.code NOT IN ('CIVIC_PEER', 'DRINKING_MATE', 'CONGREGATIONAL')
			)
		);
	""" % [in_clause, in_clause, in_clause])

	var current_year: int = CALENDAR_HELPER.day_to_year(current_sim_day)
	var events_sql: Array[String] = []

	for p in person_rows:
		var r_id: int = int(p.get("resident_id", 0))
		var dob_offset: int = int(p.get("dob", 0))
		var home_est: int = int(p.get("establishment_id", 1))
		if r_id <= 0:
			continue
		var ymd: Array[int] = CALENDAR_HELPER._day_offset_to_ymd(dob_offset)
		var b_month: int = ymd[1]
		var b_day: int = mini(ymd[2], CALENDAR_HELPER._days_in_gregorian_month(current_year, b_month))
		var next_bday: int = CALENDAR_HELPER._ymd_to_day_offset(current_year, b_month, b_day)
		if next_bday < current_sim_day:
			var next_yr := current_year + 1
			var next_d := mini(ymd[2], CALENDAR_HELPER._days_in_gregorian_month(next_yr, b_month))
			next_bday = CALENDAR_HELPER._ymd_to_day_offset(next_yr, b_month, next_d)

		var b_impacts := JSON.stringify([{"resident_id": r_id, "milestone": "BIRTHDAY"}])
		events_sql.append("""
			INSERT INTO calendar_events (
				event_type, title_token, organizer_scope, organizer_id,
				location_scope, location_id, start_day, end_day, recurrence_days,
				visibility_scope, impacts_json, status, created_day
			) VALUES (
				'BIRTHDAY', 'UI_CAL_BIRTHDAY', 'RESIDENT', '%d',
				'ESTABLISHMENT', '%d', %d, %d, 365,
				'HOUSEHOLD', '%s', 'SCHEDULED', %d
			);
		""" % [r_id, home_est, next_bday, next_bday, b_impacts, current_sim_day])

	# Project wedding anniversaries from MARRIED_SPOUSE edges in social_relationships
	var marriage_rows: Array = DB_MANAGER.query_rows("""
		SELECT DISTINCT
			MIN(sr.from_resident_id, sr.to_resident_id) AS spouse_a,
			MAX(sr.from_resident_id, sr.to_resident_id) AS spouse_b,
			sr.valid_from AS marriage_day,
			COALESCE(sr.context_establishment_id, 1) AS home_est
		FROM social_relationships sr
		JOIN system_labels l ON sr.relationship_type_id = l.label_id
		WHERE l.code IN ('HUSBAND', 'WIFE')
		  AND sr.valid_to IS NULL
		  AND (sr.from_resident_id IN (%s) OR sr.to_resident_id IN (%s));
	""" % [in_clause, in_clause])

	for m in marriage_rows:
		var sp_a: int = int(m.get("spouse_a", 0))
		var sp_b: int = int(m.get("spouse_b", 0))
		var m_offset: int = int(m.get("marriage_day", 0))
		var home_est: int = int(m.get("home_est", 1))
		if sp_a <= 0 or sp_b <= 0:
			continue
		var m_ymd: Array[int] = CALENDAR_HELPER._day_offset_to_ymd(m_offset)
		var m_month: int = m_ymd[1]
		var m_day: int = mini(m_ymd[2], CALENDAR_HELPER._days_in_gregorian_month(current_year, m_month))
		var next_anniv: int = CALENDAR_HELPER._ymd_to_day_offset(current_year, m_month, m_day)
		if next_anniv < current_sim_day:
			var next_yr := current_year + 1
			var next_d := mini(m_ymd[2], CALENDAR_HELPER._days_in_gregorian_month(next_yr, m_month))
			next_anniv = CALENDAR_HELPER._ymd_to_day_offset(next_yr, m_month, next_d)

		var a_impacts := JSON.stringify([{"spouse_a": sp_a, "spouse_b": sp_b, "milestone": "WEDDING_ANNIVERSARY"}])
		events_sql.append("""
			INSERT INTO calendar_events (
				event_type, title_token, organizer_scope, organizer_id,
				location_scope, location_id, start_day, end_day, recurrence_days,
				visibility_scope, impacts_json, status, created_day
			) VALUES (
				'WEDDING_ANNIVERSARY', 'UI_CAL_WEDDING_ANNIVERSARY', 'RESIDENT', '%d',
				'ESTABLISHMENT', '%d', %d, %d, 365,
				'HOUSEHOLD', '%s', 'SCHEDULED', %d
			);
		""" % [sp_a, home_est, next_anniv, next_anniv, a_impacts, current_sim_day])

	if not events_sql.is_empty():
		DB_MANAGER.execute_batch(events_sql)

## Seeds starting 0-100 familiarity into world_state["knowledge_pools"] using SocietyQueries
## and shares personal/street/kin/workplace knowledge upward via IntelManager.share_actor_intel_with_org().
static func _seed_starting_crew_knowledge(
	world_state: Dictionary,
	crew_ids: Array[int],
	home_district_id: String,
	crew_org_id: String
) -> void:
	if crew_ids.is_empty():
		return

	var residents_map: Dictionary = world_state.get("residents", {})

	# A. All active street addresses in the home district (residential & commercial)
	var home_all_estab_ids: Array[int] = SOCIETY_QUERIES.get_district_establishment_ids(home_district_id, true)
	# B. Everyday non-residential venues in the home district (shops, pubs, post office, jobcentre)
	var home_commercial_ids: Array[int] = SOCIETY_QUERIES.get_district_establishment_ids(home_district_id, false)

	# C. City-wide public civic landmarks & city-centre commercial venues
	var public_estab_rows: Array = DB_MANAGER.query_rows("""
		SELECT e.establishment_id, d.district_id, d.district_type
		FROM establishments e
		JOIN districts d ON e.district_id = d.district_id
		JOIN system_labels l ON e.category_id = l.label_id
		WHERE e.is_vacant = 0
		  AND l.code != 'RESIDENTIAL_UNIT'
		  AND (
			e.owner_org_id IN ('ORG:CIVIC', 'ORG:NHS', 'ORG:POST_OFFICE')
			OR l.code IN (
				'JOBCENTRE', 'POST_OFFICE', 'HOSPITAL', 'POLICE_STATION', 'FIRE_STATION',
				'TOWN_HALL', 'LOCAL_GOVERNMENT', 'MAGISTRATES_COURT', 'CROWN_COURT',
				'CENTRAL_LIBRARY', 'RAILWAY_STATION', 'BUS_STATION', 'BANK_BRANCH'
			)
			OR d.district_type IN ('city_centre', 'city_center', 'commercial_core', 'central_business_district')
		  );
	""")

	# 1. Seed each operative's personal knowledge pool
	for r_id in crew_ids:
		var obs_id := str(r_id)
		var rec: Dictionary = residents_map.get(r_id, {})

		# Home District baseline familiarity (~74.0)
		INTEL_MANAGER.apply_effort_impulse(
			world_state, "RESIDENT", obs_id, "DISTRICT", home_district_id, 85.0,
			{"distance": 0.0, "access_permeability": 1.0, "max_cap": 75.0}
		)

		# Personal Establishment Anchors (Home, Workplace/Jobcentre, Local Pub, Church)
		var home_est: int = int(rec.get("home_establishment_id", 0))
		if home_est > 0:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(home_est), 9999.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 99.95}
			)

		var work_est: int = int(rec.get("primary_employer_establishment_id", 0))
		if work_est > 0:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(work_est), 120.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 75.0}
			)

		var pub_val = rec.get("local_pub_id", null)
		if pub_val != null and int(pub_val) > 0:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(int(pub_val)), 80.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 65.0}
			)

		var church_val = rec.get("church_id", null)
		if church_val != null and int(church_val) > 0:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(int(church_val)), 60.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 55.0}
			)

		# 1st-Degree Direct Family & Friends: person, home address, and workplace (strictly 1 hop)
		var direct_contacts: Array[Dictionary] = SOCIETY_QUERIES.get_resident_direct_contacts_and_anchors(r_id)
		for contact in direct_contacts:
			var c_id: int = int(contact.get("contact_id", 0))
			if c_id > 0:
				INTEL_MANAGER.apply_effort_impulse(
					world_state, "RESIDENT", obs_id, "RESIDENT", str(c_id), 65.0,
					{"distance": 0.0, "access_permeability": 1.0, "max_cap": 65.0}
				)
			var c_home_est: int = int(contact.get("home_establishment_id", 0))
			if c_home_est > 0:
				INTEL_MANAGER.apply_effort_impulse(
					world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(c_home_est), 65.0,
					{"distance": 0.0, "access_permeability": 1.0, "max_cap": 60.0}
				)
			var raw_c_work = contact.get("work_establishment_id", null)
			var c_work_est: int = int(raw_c_work) if raw_c_work != null else 0
			if c_work_est > 0:
				INTEL_MANAGER.apply_effort_impulse(
					world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(c_work_est), 55.0,
					{"distance": 0.0, "access_permeability": 1.0, "max_cap": 55.0}
				)

		# Home District residential street addresses (~10.7 — street & door known, occupants masked)
		for he_id in home_all_estab_ids:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(he_id), 6.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 15.0}
			)

		# Home District local shops, pubs, and services (~40.0 — venue & known staff visible)
		for hc_id in home_commercial_ids:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "RESIDENT", obs_id, "ESTABLISHMENT", str(hc_id), 30.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 40.0}
			)

		# 2. Share all non-personal operative knowledge upward into ORG:CREW_ENTERPRISE via IntelManager
		INTEL_MANAGER.share_actor_intel_with_org(world_state, obs_id, crew_org_id, "ALL")

	# 2b. HQ Proximity Orbit: Commercial establishments within configured radius (e.g. 1.5km) of HQ
	var rules_cfg := ConfigFile.new()
	var cfg_err := rules_cfg.load("res://data_modules/core/business_rules.cfg")
	assert(cfg_err == OK, "FATAL: [CrewScoutBootstrapper] Failed to load res://data_modules/core/business_rules.cfg.")
	assert(
		rules_cfg.has_section_key("spatial_influence", "org_hq_commercial_radius_m"),
		"FATAL: [CrewScoutBootstrapper] Missing [spatial_influence] org_hq_commercial_radius_m in business_rules.cfg."
	)
	var hq_commercial_radius_m: float = float(rules_cfg.get_value("spatial_influence", "org_hq_commercial_radius_m"))

	var nearby_commercials: Array[Dictionary] = SOCIETY_QUERIES.get_commercial_establishments_within_radius(
		world_state, home_district_id, hq_commercial_radius_m
	)
	var seeded_orbit_districts: Dictionary = {home_district_id: true}
	for nc in nearby_commercials:
		var nc_est_id: int = int(nc.get("establishment_id", 0))
		var nc_dist_id: String = str(nc.get("district_id", ""))
		if nc_est_id > 0:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "ORG", crew_org_id, "ESTABLISHMENT", str(nc_est_id), 15.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 25.0}
			)
		if not nc_dist_id.is_empty() and not seeded_orbit_districts.has(nc_dist_id):
			seeded_orbit_districts[nc_dist_id] = true
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "ORG", crew_org_id, "DISTRICT", nc_dist_id, 15.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 25.0}
			)

	# 3. Flood-Down: Seed city-wide public directory & city-centre commercials directly into ORG:CREW_ENTERPRISE
	var seeded_public_districts: Dictionary = {}
	for pe in public_estab_rows:
		var pe_id: int = int(pe.get("establishment_id", 0))
		var pe_dist: String = str(pe.get("district_id", ""))
		var pe_dtype: String = str(pe.get("district_type", ""))
		if pe_id > 0:
			INTEL_MANAGER.apply_effort_impulse(
				world_state, "ORG", crew_org_id, "ESTABLISHMENT", str(pe_id), 15.0,
				{"distance": 0.0, "access_permeability": 1.0, "max_cap": 25.0}
			)
		if not pe_dist.is_empty() and pe_dist != home_district_id and not seeded_public_districts.has(pe_dist):
			if pe_dtype in ["city_centre", "city_center", "commercial_core", "central_business_district"]:
				seeded_public_districts[pe_dist] = true
				INTEL_MANAGER.apply_effort_impulse(
					world_state, "ORG", crew_org_id, "DISTRICT", pe_dist, 15.0,
					{"distance": 0.0, "access_permeability": 1.0, "max_cap": 25.0}
				)

## Iterates through the strategy pipeline, instantiating each strategy file dynamically
static func _execute_pipeline(pipeline: Array, base_context: Dictionary) -> Array[int]:
	for step in pipeline:
		var strat_token: String = ""
		var params: Dictionary = {}

		if step is Dictionary:
			strat_token = str(step.get("strategy", ""))
			params = step
		elif step is String:
			strat_token = step

		if strat_token.is_empty():
			continue

		var script_path: String = "res://systems/society/crew_selection/strategy_%s.gd" % strat_token.to_lower()
		if not ResourceLoader.exists(script_path):
			push_warning("[CrewScoutBootstrapper] Strategy script not found: %s" % script_path)
			continue

		var strat_script = load(script_path)
		if not strat_script:
			continue

		var strat_instance = strat_script.new()
		if not (strat_instance is CrewSelectionStrategy):
			push_error("[CrewScoutBootstrapper] Strategy class does not extend CrewSelectionStrategy: %s" % script_path)
			continue

		var step_context: Dictionary = base_context.duplicate(false)
		step_context["params"] = params

		var candidate_ids: Array[int] = strat_instance.resolve_candidates(step_context)
		if candidate_ids.size() == int(base_context.get("target_count", 0)):
			return candidate_ids

	return []