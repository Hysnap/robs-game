# res://systems/game_state.gd
extends Node

## Signals for reactive UI (Filofax, HUD, Map highlights)
signal district_selected(district_id: String)
signal district_updated(district_id: String)
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
const VERB_ROUTER = preload("res://systems/verb_router.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize_fresh_state()

## Discovers all installed flavour directories under res://data_modules/ (excluding core and shared)
static func discover_installed_flavours() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open("res://data_modules/")
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and dir.current_is_dir():
			var slug := entry.strip_edges()
			if slug != "core" and slug != "shared" and not found.has(slug):
				found.append(slug)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found

## Returns the ordered module chain ["core", ...active_flavours] for the live world_state
func get_active_module_chain() -> Array[String]:
	var chain: Array[String] = ["core"]
	var raw_flavours = world_state.get("metadata", {}).get("active_flavours", [])
	if raw_flavours is Array:
		for f in raw_flavours:
			var slug := str(f).strip_edges()
			if not slug.is_empty() and slug != "core" and slug != "shared" and not chain.has(slug):
				chain.append(slug)
	return chain

## Initializes world_state entirely from external definition files and selected flavour packs
func initialize_fresh_state(custom_flavours: Array = []) -> void:
	# 1. Load business_rules.cfg first so scenario flavour stack can mount before manifest modules load
	var config := ConfigFile.new()
	var err := config.load(active_rules_path)
	assert(err == OK, "FATAL: [GAME_STATE] Failed to load active_rules_path '%s' (Error: %d)" % [active_rules_path, err])

	var raw_flavour_list: Array = custom_flavours.duplicate()
	if raw_flavour_list.is_empty() and config.has_section_key("scenario", "active_flavours"):
		var cfg_flavours = config.get_value("scenario", "active_flavours", [])
		if cfg_flavours is Array:
			raw_flavour_list = cfg_flavours.duplicate()

	var normalized_flavours: Array[String] = []
	for raw_f in raw_flavour_list:
		var slug := str(raw_f).strip_edges()
		if slug.is_empty() or slug == "core" or slug == "shared":
			continue
		var mod_dir := "res://data_modules/%s" % slug
		assert(DirAccess.dir_exists_absolute(mod_dir),
			"FATAL: [GAME_STATE] Selected flavour pack '%s' does not exist at '%s'." % [slug, mod_dir])
		if not normalized_flavours.has(slug):
			normalized_flavours.append(slug)

	ScenarioManifestManager.set_active_flavours(normalized_flavours)

	assert(ScenarioManifestManager.has_module("startpoint"),
		"FATAL: [GAME_STATE] Active scenario manifest missing 'startpoint' registration.")

	var scenario: Dictionary = ScenarioManifestManager.load_module("startpoint")
	assert(not scenario.is_empty(), "FATAL: [GAME_STATE] Loaded startpoint definition is empty.")

	# Cache starting inventory to inject into the leader's home establishment once resolved
	_pending_starting_inventory = scenario.get("starting_inventory", {}).duplicate(true)

	# 2. Establish clean baseline structure from startpoint definition
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
		"transport_registry": {},
		"pending_orders": {},
		"districts": {},
		"counterparties": {},
		"selected_district_id": ""
	}

	# 3. Overlay starting metadata & operations from business_rules.cfg and persist active_flavours
	_load_section_into_state(config, "starting_metadata", "metadata")
	_load_section_into_state(config, "starting_operations", "operations")
	SystemLogger.log_info("[GAME_STATE] Successfully loaded baseline state from: %s" % active_rules_path)

	# Include any additional flavours declared inside startpoint.starting_metadata.active_flavours
	var sp_flavours = world_state.get("metadata", {}).get("active_flavours", [])
	if sp_flavours is Array:
		var added_from_sp := false
		for raw_spf in sp_flavours:
			var sp_slug := str(raw_spf).strip_edges()
			if sp_slug.is_empty() or sp_slug == "core" or sp_slug == "shared":
				continue
			var sp_dir := "res://data_modules/%s" % sp_slug
			assert(DirAccess.dir_exists_absolute(sp_dir),
				"FATAL: [GAME_STATE] Startpoint flavour pack '%s' does not exist at '%s'." % [sp_slug, sp_dir])
			if not normalized_flavours.has(sp_slug):
				normalized_flavours.append(sp_slug)
				added_from_sp = true
		if added_from_sp:
			ScenarioManifestManager.set_active_flavours(normalized_flavours)

	world_state["metadata"]["active_flavours"] = normalized_flavours
	var module_chain: Array[String] = get_active_module_chain()

	# 4. Dynamic Catalog Ingestion across ["core", ...active_flavours]
	var commodities_root: String = str(config.get_value("catalogs", "commodities_root", "")).strip_edges()
	var recipes_root: String = str(config.get_value("catalogs", "recipes_root", "")).strip_edges()
	var transports_root: String = str(config.get_value("catalogs", "transports_root", "")).strip_edges()

	assert(not commodities_root.is_empty(), "FATAL: [GAME_STATE] [catalogs] commodities_root missing in %s" % active_rules_path)
	assert(not recipes_root.is_empty(), "FATAL: [GAME_STATE] [catalogs] recipes_root missing in %s" % active_rules_path)
	assert(not transports_root.is_empty(), "FATAL: [GAME_STATE] [catalogs] transports_root missing in %s" % active_rules_path)

	var merged_commodities: Dictionary = COMMODITY_MANAGER.load_hierarchical_commodities(commodities_root)
	var merged_recipes: Dictionary = COMMODITY_MANAGER.load_hierarchical_commodities(recipes_root)
	var merged_transports: Dictionary = COMMODITY_MANAGER.load_hierarchical_transports(transports_root)

	for mod_slug in normalized_flavours:
		var mod_comm_dir := "res://data_modules/%s/commodities/" % mod_slug
		if DirAccess.dir_exists_absolute(mod_comm_dir):
			var extra_comm := COMMODITY_MANAGER.load_hierarchical_commodities(mod_comm_dir)
			for k in extra_comm.keys():
				merged_commodities[k] = extra_comm[k]

		var mod_rec_dir := "res://data_modules/%s/recipes/" % mod_slug
		if DirAccess.dir_exists_absolute(mod_rec_dir):
			var extra_rec := COMMODITY_MANAGER.load_hierarchical_commodities(mod_rec_dir)
			for k in extra_rec.keys():
				merged_recipes[k] = extra_rec[k]

		var mod_trans_dir := "res://data_modules/%s/transports/" % mod_slug
		if DirAccess.dir_exists_absolute(mod_trans_dir):
			var extra_trans := COMMODITY_MANAGER.load_hierarchical_transports(mod_trans_dir)
			for k in extra_trans.keys():
				merged_transports[k] = extra_trans[k]

	world_state["commodity_registry"] = merged_commodities
	if world_state["commodity_registry"].is_empty():
		push_warning("[GAME_STATE] No commodities loaded across %s" % str(module_chain))
	else:
		SystemLogger.log_info("[GAME_STATE] Ingested %d catalog commodities across %s." % [world_state["commodity_registry"].size(), str(module_chain)])

	world_state["recipe_registry"] = merged_recipes
	if world_state["recipe_registry"].is_empty():
		push_warning("[GAME_STATE] No recipes loaded across %s" % str(module_chain))
	else:
		SystemLogger.log_info("[GAME_STATE] Ingested %d recipes across %s." % [world_state["recipe_registry"].size(), str(module_chain)])

	world_state["transport_registry"] = merged_transports
	if world_state["transport_registry"].is_empty():
		push_warning("[GAME_STATE] No transport service profiles loaded across %s" % str(module_chain))
	else:
		SystemLogger.log_info("[GAME_STATE] Ingested %d transport services across %s." % [world_state["transport_registry"].size(), str(module_chain)])

	# 5. Mount VerbRouter & ImpactRouter across the active module chain
	var secondary_flavours: Array[String] = []
	for mod_slug in module_chain:
		if mod_slug != "core":
			secondary_flavours.append(mod_slug)
	if secondary_flavours.is_empty():
		VERB_ROUTER.initialize()
	else:
		for mod_slug in secondary_flavours:
			VERB_ROUTER.initialize(mod_slug)

	IMPACT_ROUTER.reset()
	for mod_slug in module_chain:
		var impacts_dir := "res://data_modules/%s/impacts/" % mod_slug
		if DirAccess.dir_exists_absolute(impacts_dir):
			IMPACT_ROUTER.autoload_sinks(impacts_dir)

	SystemLogger.log_info("[GAME_STATE] Data-driven world_state initialized via ScenarioManifestManager (flavours=%s)." % str(normalized_flavours))
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

	var residents_dict: Dictionary = world_state.get("residents", {})
	for res_key in residents_dict.keys():
		var rec = residents_dict[res_key]
		if rec is Dictionary and bool(rec.get("is_crew", true)):
			rec["current_district_id"] = district_id
			var r_id: int = int(rec.get("resident_id", 0))
			var obs_id: String = str(r_id) if r_id > 0 else str(res_key)
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

	_anchor_starting_inventory_to_home(district_id)

	district_updated.emit(district_id)

## Internal helper: Deposits initial enterprise commodities into the leader's residential establishment
func _anchor_starting_inventory_to_home(district_id: String) -> void:
	if _pending_starting_inventory.is_empty():
		return

	var estabs: Dictionary = world_state.get("establishments", {})
	if estabs.is_empty():
		return

	var target_estab_key: Variant = null
	var residents_dict: Dictionary = world_state.get("residents", {})
	for res_key in residents_dict.keys():
		var rec = residents_dict[res_key]
		if rec is Dictionary and bool(rec.get("is_crew", true)) and bool(rec.get("is_leader", false)):
			var home_est_id: int = int(rec.get("home_establishment_id", rec.get("establishment_id", 0)))
			if home_est_id > 0 and estabs.has(home_est_id):
				target_estab_key = home_est_id
			elif home_est_id > 0 and estabs.has(str(home_est_id)):
				target_estab_key = str(home_est_id)
			break

	if target_estab_key == null:
		for e_key in estabs.keys():
			var e_rec = estabs[e_key]
			if e_rec is Dictionary and str(e_rec.get("district_id", "")) == district_id:
				target_estab_key = e_key
				break

	if target_estab_key != null:
		var target_est: Dictionary = estabs[target_estab_key]
		if not target_est.has("inventory") or not (target_est["inventory"] is Dictionary):
			target_est["inventory"] = {}
		for item_k in _pending_starting_inventory.keys():
			var qty: float = float(_pending_starting_inventory[item_k])
			target_est["inventory"][item_k] = float(target_est["inventory"].get(item_k, 0.0)) + qty
		SystemLogger.log_info("[GAME_STATE] Anchored starting inventory into establishment '%s' in '%s'." % [str(target_estab_key), district_id])
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
	var residents_dict: Dictionary = world_state.get("residents", {})
	var ops_cfg: Dictionary = world_state.get("operations", {})
	var crew_org_id: String = str(ops_cfg.get("crew_org_id", "ORG:CREW_ENTERPRISE")).strip_edges()
	var hq_estab_id: int = int(ops_cfg.get("hq_establishment_id", 0))
	var seen_ids: Array[int] = []

	for res_key in residents_dict.keys():
		var rec = residents_dict[res_key]
		if not (rec is Dictionary) or not bool(rec.get("is_crew", true)):
			continue
		var r_id: int = int(rec.get("resident_id", 0))
		if r_id > 0 and seen_ids.has(r_id):
			continue
		if r_id > 0:
			seen_ids.append(r_id)

		var obs_id: String = str(r_id) if r_id > 0 else str(res_key)
		if obs_id.is_empty():
			continue

		var affs: Array = []
		if not crew_org_id.is_empty():
			var crew_clearance: float = 1.0 if bool(rec.get("is_leader", false)) else float(rec.get("crew_clearance", 0.85))
			affs.append({"org_scope": "ORG", "org_id": crew_org_id, "clearance": crew_clearance})
		if hq_estab_id > 0:
			affs.append({"org_scope": "ESTABLISHMENT", "org_id": str(hq_estab_id), "clearance": 1.0})

		var home_est_id: int = int(rec.get("home_establishment_id", rec.get("establishment_id", 0)))
		if home_est_id > 0:
			affs.append({"org_scope": "ESTABLISHMENT", "org_id": str(home_est_id), "clearance": 1.0})

		var work_est_id: int = int(rec.get("primary_employer_establishment_id", 0))
		if work_est_id > 0:
			affs.append({
				"org_scope": "ESTABLISHMENT",
				"org_id": str(work_est_id),
				"role_code": str(rec.get("primary_role_code", rec.get("role_title", rec.get("role", "")))).strip_edges()
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