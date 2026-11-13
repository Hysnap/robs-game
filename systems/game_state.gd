# res://systems/game_state.gd
extends Node

## Signals for reactive UI (Filofax, HUD, Map highlights)
signal district_selected(district_id: String)
signal district_updated(district_id: String)
signal turn_advanced(current_week: int, current_day: int)
signal world_state_reset

## Path to active configuration (can be switched by scenario loaders)
@export var active_rules_path: String = "res://data_modules/core/business_rules.cfg"

## The Canonical World State (Single Source of Truth)
var world_state: Dictionary = {}

## Staged initial establishment inventory awaiting home district / establishment binding
var _pending_starting_inventory: Dictionary = {}

## Active UI Selection Pointer (kept in sync with world_state["selected_district_id"])
var selected_district_id: String = ""

const SystemLoggerScript = preload("res://systems/logger.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const DISTRICT_PERCEPTION_FILTER = preload("res://systems/multilayer_info_loop/district_perception_filter.gd")
const INTEL_MANAGER = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")
const COMMODITY_MANAGER = preload("res://systems/commodity_manager.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize_fresh_state()

## Initializes world_state entirely from external definition files
func initialize_fresh_state() -> void:
	assert(ScenarioManifestManager.has_module("startpoint"),
		"FATAL: [GAME_STATE] Active scenario manifest missing 'startpoint' registration.")

	var scenario: Dictionary = ScenarioManifestManager.load_module("startpoint")
	assert(not scenario.is_empty(), "FATAL: [GAME_STATE] Loaded startpoint definition is empty.")

	# Cache starting inventory to inject into the leader's home establishment once resolved
	_pending_starting_inventory = scenario.get("starting_inventory", {}).duplicate(true)

	# 1. Establish clean baseline structure from startpoint definition
	world_state = {
		"metadata": scenario.get("starting_metadata", {}).duplicate(true),
		"obligations": scenario.get("starting_obligations", []).duplicate(true),
		"operations": scenario.get("starting_operations", {}).duplicate(true),
		"debug_rules": scenario.get("debug_rules", {}).duplicate(true),
		"player_knowledge": {
			"home_district_id": "",
			"known_outlets": [],
			"district_survey_ticks": {}
		},
		"knowledge_pools": {},
		"staff": scenario.get("starting_staff", {}).duplicate(true),
		"inventory": {},
		"commodity_registry": {},
		"recipe_registry": {},
		"pending_orders": {},
		"districts": {},
		"counterparties": {},
		"selected_district_id": ""
	}

	# 2. Ingest starting definitions dynamically from business_rules.cfg
	var config := ConfigFile.new()
	var err := config.load(active_rules_path)
	if err == OK:
		_load_section_into_state(config, "starting_metadata", "metadata")
		_load_section_into_state(config, "starting_operations", "operations")
		SystemLogger.log_info("[GAME_STATE] Successfully loaded baseline state from: %s" % active_rules_path)
	else:
		SystemLogger.log_error("[GAME_STATE] Failed to load starting configuration from: %s (Error: %d)" % [active_rules_path, err])
		push_error("[GAME_STATE] Failed to load starting configuration from: %s (Error: %d)" % [active_rules_path, err])
		world_state["metadata"] = {"calendar_year": 1980, "current_week_tick": 1, "current_day_tick": 1, "active_seed": "default-city"}
		world_state["obligations"] = []
		world_state["operations"] = {"fatigue": 0.0}

	# 3. Dynamic Catalog Ingestion via CommodityManager (Rule 1 & Rule 8)
	var core_commodities := "res://data_modules/core/commodities/"
	world_state["commodity_registry"] = COMMODITY_MANAGER.load_hierarchical_commodities(core_commodities)
	if world_state["commodity_registry"].is_empty():
		push_warning("[GAME_STATE] No commodities loaded from %s" % core_commodities)
	else:
		SystemLogger.log_info("[GAME_STATE] Ingested %d catalog commodities." % world_state["commodity_registry"].size())

	var core_recipes := "res://data_modules/core/recipes/"
	world_state["recipe_registry"] = COMMODITY_MANAGER.load_hierarchical_commodities(core_recipes)
	if world_state["recipe_registry"].is_empty():
		push_warning("[GAME_STATE] No recipes loaded from %s" % core_recipes)
	else:
		SystemLogger.log_info("[GAME_STATE] Ingested %d recipes." % world_state["recipe_registry"].size())

	SystemLogger.log_info("[GAME_STATE] Data-driven world_state initialized via ScenarioManifestManager.")
	world_state_reset.emit()

## Pure State Setter: Records the confirmed home district and seeds initial crew & home establishment intel
func set_home_district(district_id: String) -> void:
	assert(not district_id.is_empty(), "FATAL: [GAME_STATE] Cannot set empty home district.")
	if not world_state.has("player_knowledge"):
		world_state["player_knowledge"] = {"home_district_id": "", "known_outlets": [], "district_survey_ticks": {}}
	if not world_state.has("knowledge_pools"):
		world_state["knowledge_pools"] = {}
	if not world_state.has("operations"):
		world_state["operations"] = {}

	world_state["player_knowledge"]["home_district_id"] = district_id
	world_state["operations"]["home_district_id"] = district_id

	set_selected_district(district_id)

	# Anchor starting crew roster to this district and seed initial local district intel
	var staff_dict: Dictionary = world_state.get("staff", {})
	for staff_id in staff_dict.keys():
		if staff_dict[staff_id] is Dictionary:
			var member: Dictionary = staff_dict[staff_id]
			member["current_district_id"] = district_id
			var obs_id: String = str(member.get("resident_id", staff_id))
			if not obs_id.is_empty():
				INTEL_MANAGER.apply_effort_impulse(
					world_state,
					"RESIDENT",
					obs_id,
					"DISTRICT",
					district_id,
					85.0,
					{"distance": 0.0, "access_permeability": 1.0}
				)

	# Physically anchor pending starting inventory into the leader's residence
	_anchor_starting_inventory_to_home(district_id)

	district_updated.emit(district_id)

## Internal helper: Deposits initial enterprise commodities into the leader's residential establishment
func _anchor_starting_inventory_to_home(district_id: String) -> void:
	if _pending_starting_inventory.is_empty():
		return

	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(district_id):
		return

	var venues: Dictionary = districts[district_id].get("venues", {})
	var target_venue_id: String = ""

	var leader_data: Dictionary = world_state.get("staff", {}).get("crew_0", {})
	var res_est_id: String = str(leader_data.get("establishment_id", leader_data.get("residence_establishment_id", "")))
	
	if not res_est_id.is_empty() and venues.has(res_est_id):
		target_venue_id = res_est_id
	elif not venues.is_empty():
		target_venue_id = str(venues.keys()[0])

	if not target_venue_id.is_empty():
		var target_venue: Dictionary = venues[target_venue_id]
		if not target_venue.has("inventory"):
			target_venue["inventory"] = {}
		for item_k in _pending_starting_inventory.keys():
			var qty: float = float(_pending_starting_inventory[item_k])
			target_venue["inventory"][item_k] = float(target_venue["inventory"].get(item_k, 0.0)) + qty
		SystemLogger.log_info("[GAME_STATE] Anchored starting inventory into establishment '%s' in '%s'." % [target_venue_id, district_id])
		_pending_starting_inventory.clear()

## Helper to dynamically map all keys in a config section without hardcoding property names
func _load_section_into_state(config: ConfigFile, section_name: String, target_dict_key: String) -> void:
	if not config.has_section(section_name):
		return
	if not world_state.has(target_dict_key):
		world_state[target_dict_key] = {}
	for key in config.get_section_keys(section_name):
		world_state[target_dict_key][key] = config.get_value(section_name, key)

## Builds the active crew observer descriptor list for IntelManager collective queries
func get_player_observers() -> Array:
	var observers: Array = []
	var staff_dict: Dictionary = world_state.get("staff", {})
	for staff_id in staff_dict.keys():
		var member = staff_dict[staff_id]
		if not (member is Dictionary):
			continue
		var obs_id: String = str(member.get("resident_id", staff_id))
		if obs_id.is_empty():
			continue
		var affs: Array = []
		var home_est_id: String = str(member.get("home_establishment_id", member.get("residence_establishment_id", "")))
		if not home_est_id.is_empty() and home_est_id != "0":
			affs.append({"org_scope": "ESTABLISHMENT", "org_id": home_est_id, "clearance": 1.0})
		var emp_id: String = str(member.get("employer_entity_id", ""))
		if not emp_id.is_empty() and emp_id != "0":
			affs.append({
				"org_scope": "ESTABLISHMENT",
				"org_id": emp_id,
				"role_code": str(member.get("role_code", member.get("role", "")))
			})
		observers.append({
			"observer_scope": "RESIDENT",
			"observer_id": obs_id,
			"affiliations": affs
		})
	return observers

## Query and mutation helpers
func get_district(district_id: String) -> Dictionary:
	return world_state.get("districts", {}).get(district_id, {})

func set_district(district_id: String, data: Dictionary) -> void:
	if not world_state.has("districts"):
		world_state["districts"] = {}
	world_state["districts"][district_id] = data
	district_updated.emit(district_id)

func get_district_truth(district_id: String) -> Dictionary:
	return get_district(district_id)

func get_selected_district_id() -> String:
	return selected_district_id

## Sets the currently clicked/inspected district and synchronizes world_state
func set_selected_district(district_id: String) -> void:
	selected_district_id = district_id
	world_state["selected_district_id"] = district_id
	district_selected.emit(district_id)

## Returns district telemetry filtered through the player's continuous 0-100 perception and fog-of-war
func get_district_view(district_id: String) -> Dictionary:
	assert(not district_id.is_empty(), "FATAL: [GAME_STATE] district_id cannot be empty.")

	# 1. Base spatial entity state
	var districts: Dictionary = world_state.get("districts", {})
	var raw_data: Dictionary = {}
	if districts.has(district_id):
		raw_data = districts[district_id].duplicate(true)
	else:
		raw_data["district_id"] = district_id
		raw_data["display_name"] = district_id.capitalize().replace("_", " ")

	# 2. Enrich with archetype landmark metadata if available
	if ScenarioManifestManager.has_module("archetypes"):
		var archetypes: Dictionary = ScenarioManifestManager.load_module("archetypes")
		var d_type: String = str(raw_data.get("district_type", ""))
		var arch: Dictionary = archetypes.get(d_type, {})
		raw_data["is_public_landmark"] = bool(arch.get("is_public_landmark", false))
		raw_data["type_title"] = str(arch.get("display_name", d_type.capitalize()))

	# 3. Enrich with unified SQLite census ground truth and establishments
	var census_data: Dictionary = SOCIETY_QUERIES.get_district_census(district_id)
	for k in census_data.keys():
		raw_data[k] = census_data[k]

	raw_data["establishments_summary"] = SOCIETY_QUERIES.get_district_establishments(district_id)

	# 4. Assemble continuous 0-100 player perception context (zero legacy known_districts fallback)
	var pk: Dictionary = world_state.get("player_knowledge", {})
	var player_context: Dictionary = {
		"world_state": world_state,
		"observers": get_player_observers(),
		"home_district_id": str(pk.get("home_district_id", "")),
		"current_sim_day": int(world_state.get("metadata", {}).get("current_sim_day", 1))
	}

	# 5. Apply pure in-memory perception transformation
	return DISTRICT_PERCEPTION_FILTER.filter_district_view(raw_data, player_context)