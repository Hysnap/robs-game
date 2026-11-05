# res://systems/society/crew_scout_bootstrapper.gd
class_name CrewScoutBootstrapper
extends RefCounted

const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")
const SCENARIO_MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const DB_MANAGER = preload("res://systems/db_manager.gd")

## Scouts related young adults in the home district using the configured strategy pipeline,
## binds secondary grey-economy contracts in SQLite, and stamps operative profiles into world_state["staff"].
static func scout_and_bind_starting_crew(world_state: Dictionary, home_district_id: String) -> bool:
	assert(not home_district_id.is_empty(), "FATAL: [CrewScoutBootstrapper] home_district_id cannot be empty.")
	assert(SCENARIO_MANIFEST_MANAGER.has_module("startpoint"), "FATAL: [CrewScoutBootstrapper] Missing 'startpoint' module.")

	# 1. Resolve simulation temporal day offset (default to 1980-01-01 start day 29219)
	var current_sim_day: int = int(world_state.get("metadata", {}).get("current_sim_day", 29219))

	# 2. Ingest generation criteria and staff templates from startpoint config
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

	for row in candidate_rows:
		var r_id: int = int(row.get("resident_id", 0))
		var h_id: int = int(row.get("household_id", 0))
		unique_candidates[r_id] = row

		if not by_household.has(h_id):
			by_household[h_id] = []
		if not r_id in by_household[h_id]:
			by_household[h_id].append(r_id)

	var base_context: Dictionary = {
		"candidate_rows": candidate_rows,
		"by_household": by_household,
		"unique_candidates": unique_candidates,
		"target_count": target_count
	}

	# 5. Resolve candidates dynamically through the strategy pipeline
	var selected_resident_ids: Array[int] = _execute_pipeline(pipeline, base_context)
	if selected_resident_ids.size() < target_count:
		push_error("[CrewScoutBootstrapper] Strategy pipeline failed to assemble required cohort of %d operatives." % target_count)
		return false

	# 6. Resolve DB Label IDs dynamically from the secondary contract profile
	var sec_contract_def: Dictionary = criteria.get("secondary_contract", {})
	var class_code: String = str(sec_contract_def.get("contract_class_code", "INFORMAL_GREY"))
	var sched_code: String = str(sec_contract_def.get("schedule_window_code", "EVENING"))
	var sched_fallback: String = str(sec_contract_def.get("fallback_schedule_window_code", "FLEXIBLE"))
	var employer_id: String = str(sec_contract_def.get("employer_entity_id", "CREW_ENTERPRISE"))
	var weekly_hours: float = float(sec_contract_def.get("weekly_hours", 20.0))
	var comp_rate: float = float(sec_contract_def.get("compensation_rate", 0.0))

	var contract_class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", class_code)
	var schedule_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", sched_code)
	if schedule_id <= 0:
		schedule_id = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", sched_fallback)

	var bindings: Array[Dictionary] = []

	# 7. Build contract bindings dynamically driven by starting_staff definitions
	for i in range(target_count):
		var slot_id: String = staff_slots[i]
		var slot_cfg: Dictionary = starting_staff_configs[slot_id]
		var r_id: int = selected_resident_ids[i]
		var role_str: String = str(slot_cfg.get("role", "RUNNER"))
		var role_title_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", role_str)

		bindings.append({
			"resident_id": r_id,
			"role_title_id": role_title_id,
			"contract_class_id": contract_class_id,
			"schedule_window_id": schedule_id,
			"employer_entity_id": employer_id,
			"weekly_hours": weekly_hours,
			"compensation_rate": comp_rate,
			"start_day": current_sim_day
		})

	# 8. Execute batch inserts and agent activation in SQLite
	var db_ok: bool = SOCIETY_QUERIES.bind_crew_contracts_and_activate(bindings)
	if not db_ok:
		push_error("[CrewScoutBootstrapper] Failed to execute database contract binding batch.")
		return false

	# 9. Hydrate world_state["staff"] directly from database profile and slot config
	if not world_state.has("staff"):
		world_state["staff"] = {}

	for i in range(target_count):
		var slot_id: String = staff_slots[i]
		var slot_cfg: Dictionary = starting_staff_configs[slot_id]
		var r_id: int = selected_resident_ids[i]
		var profile: Dictionary = SOCIETY_QUERIES.get_resident_profile(r_id, current_sim_day)

		var staff_entry: Dictionary = slot_cfg.duplicate(true)
		staff_entry["id"] = slot_id
		staff_entry["resident_id"] = r_id
		staff_entry["name"] = profile.get("full_name", "")
		staff_entry["age"] = profile.get("age", 0)
		staff_entry["gender_id"] = profile.get("gender_id", 0)
		staff_entry["household_id"] = profile.get("household_id", 0)
		staff_entry["establishment_id"] = profile.get("establishment_id", 0)
		staff_entry["current_district_id"] = home_district_id
		staff_entry["primary_employer_id"] = profile.get("employer_entity_id", "")
		staff_entry["primary_role_id"] = profile.get("role_title_id", 0)
		staff_entry["primary_contract_class_id"] = profile.get("contract_class_id", 0)

		world_state["staff"][slot_id] = staff_entry

	return true

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