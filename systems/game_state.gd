# res://systems/game_state.gd
extends Node

## Signals for reactive UI (Filofax, HUD, Map highlights)
signal district_selected(district_id: String)
signal world_state_reset

## Path to active configuration (can be switched by scenario loaders)
@export var active_rules_path: String = "res://data_modules/core/business_rules.cfg"

## The Canonical World State (Single Source of Truth)
var world_state: Dictionary = {}

## Active UI Selection Pointer
var selected_district_id: String = ""

const DB_MGR = preload("res://systems/db_manager.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize_fresh_state()

## Initializes world_state entirely from external definition files
func initialize_fresh_state() -> void:
	assert(ScenarioManifestManager.has_module("startpoint"),
		"FATAL: [GAME_STATE] Active scenario manifest missing 'startpoint' registration.")

	var scenario: Dictionary = ScenarioManifestManager.load_module("startpoint")
	assert(not scenario.is_empty(), "FATAL: [GAME_STATE] Loaded startpoint definition is empty.")

	# 1. Establish clean baseline structure from startpoint definition
	world_state = {
		"metadata": scenario.get("starting_metadata", {}).duplicate(true),
		"finances": scenario.get("starting_finances", {}).duplicate(true),
		"operations": scenario.get("starting_operations", {}).duplicate(true),
		"debug_rules": scenario.get("debug_rules", {}).duplicate(true),
		"player_knowledge": {
			"home_district_id": "",
			"known_districts": [],
			"known_outlets": []
		},
		"staff": scenario.get("starting_staff", {}).duplicate(true),
		"inventory_registry": {},
		"commodity_registry": {},
		"recipe_registry": {},
		"pending_orders": {},
		"districts": {},
		"counterparties": {}
	}

	# 2. Store scenario constraints for dynamic spatial resolution
	var starting_knowledge: Dictionary = scenario.get("starting_knowledge", {})
	world_state["_startpoint_rules"] = {
		"eligible_home_archetypes": starting_knowledge.get("eligible_home_archetypes", [
			"high_density_low_rise",
			"high_density_high_rise",
			"residential",
			"suburban_low_density"
		])
	}

	# If districts are already populated in world_state, resolve immediately;
	# otherwise resolve_starting_home_district() is called after map generation completes.
	if not world_state["districts"].is_empty():
		resolve_starting_home_district()

	print("[GAME_STATE] Data-driven world_state initialized via ScenarioManifestManager.")
	world_state_reset.emit()
	
	# 2. Ingest starting definitions dynamically from business_rules.cfg
	var config := ConfigFile.new()
	var err := config.load(active_rules_path)
	if err == OK:
		_load_section_into_state(config, "starting_metadata", "metadata")
		_load_section_into_state(config, "starting_finances", "finances")
		_load_section_into_state(config, "starting_operations", "operations")
		print("[GAME_STATE] Successfully loaded baseline state from: %s" % active_rules_path)
	else:
		push_error("[GAME_STATE] Failed to load starting configuration from: %s (Error: %d)" % [active_rules_path, err])
		# Minimal fallback to prevent crash if file is missing
		world_state["metadata"] = {"calendar_year": 1984, "current_week_tick": 1, "active_seed": "default-city"}
		world_state["finances"] = {"liquid_cash": 0.0, "clean_bank_balance": 0.0}
		world_state["operations"] = {"fatigue": 0.0}

	world_state_reset.emit()

## Dynamically resolves an anchor district based on eligible archetypes and places crew
func resolve_starting_home_district() -> String:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return ""

	var eligible_archetypes: Array = world_state.get("_startpoint_rules", {}).get("eligible_home_archetypes", [])
	var candidate_district_ids: Array[String] = []

	# Find all districts matching eligible housing/urban archetypes
	for d_id in districts.keys():
		var district_data: Dictionary = districts[d_id]
		var arch: String = str(district_data.get("archetype", district_data.get("district_type", "")))
		if eligible_archetypes.has(arch):
			candidate_district_ids.append(str(d_id))

	# Fallback: take any district with an active population
	if candidate_district_ids.is_empty():
		for d_id in districts.keys():
			if int(districts[d_id].get("active_population", 0)) > 0:
				candidate_district_ids.append(str(d_id))

	# Absolute fallback: first available district key
	if candidate_district_ids.is_empty():
		candidate_district_ids.append(str(districts.keys()[0]))

	candidate_district_ids.sort()
	var selected_home := candidate_district_ids[0]

	# Stamp home district into operations & player knowledge
	world_state["operations"]["home_district_id"] = selected_home
	world_state["player_knowledge"]["home_district_id"] = selected_home
	if not world_state["player_knowledge"]["known_districts"].has(selected_home):
		world_state["player_knowledge"]["known_districts"].append(selected_home)

	# Anchor starting crew to the resolved district
	var staff_dict: Dictionary = world_state.get("staff", {})
	for staff_id in staff_dict.keys():
		staff_dict[staff_id]["current_district_id"] = selected_home

	print("[GAME_STATE] Anchored home district to: %s (Staff placed: %s)" % [selected_home, str(staff_dict.keys())])
	return selected_home

## Helper to dynamically map all keys in a config section without hardcoding property names
func _load_section_into_state(config: ConfigFile, section_name: String, target_dict_key: String) -> void:
	if not config.has_section(section_name):
		return
	for key in config.get_section_keys(section_name):
		var val = config.get_value(section_name, key)
		world_state[target_dict_key][key] = val

## Query and mutation helpers
func get_district(district_id: String) -> Dictionary:
	return world_state.get("districts", {}).get(district_id, {})

## Sets the currently clicked/inspected district and notifies the Filofax
func set_selected_district(district_id: String) -> void:
	selected_district_id = district_id
	district_selected.emit(district_id)

func get_district_view(block_id: String) -> Dictionary:
	var view_data: Dictionary = {}
	
	# 1. Base spatial/macro state from memory
	var districts: Dictionary = world_state.get("districts", {})
	if districts.has(block_id):
		view_data = districts[block_id].duplicate(true)
	else:
		view_data["district_id"] = block_id
		view_data["display_name"] = block_id.capitalize().replace("_", " ")

	# 2. Augment with SQLite census ground truth (if society database is initialized)
	var census_rows = DB_MGR.query_rows("""
		SELECT total_households, total_residents, active_living_population, 
				formally_employed_count, street_informal_count, incarcerated_count 
		FROM v_district_census 
		WHERE district_id = '%s';
	""" % block_id)

	if not census_rows.is_empty():
		var row: Dictionary = census_rows[0]
		view_data["active_population"] = int(row.get("active_living_population", 0))
		view_data["total_households"] = int(row.get("total_households", 0))
		view_data["formally_employed_count"] = int(row.get("formally_employed_count", 0))
		view_data["street_informal_count"] = int(row.get("street_informal_count", 0))
		view_data["incarcerated_count"] = int(row.get("incarcerated_count", 0))
	else:
		view_data["active_population"] = view_data.get("population", 0)
		view_data["total_households"] = int(round(float(view_data["active_population"]) / 2.6))
		view_data["formally_employed_count"] = 0
		view_data["street_informal_count"] = 0
		view_data["incarcerated_count"] = 0

	# 3. Augment with normalized establishments in this district
	var estab_rows = DB_MGR.query_rows("""
		SELECT name, category_title, capacity 
		FROM v_establishments_overview 
		WHERE district_id = '%s'
		ORDER BY category_title ASC, name ASC;
	""" % block_id)

	view_data["establishments_summary"] = estab_rows
	return view_data