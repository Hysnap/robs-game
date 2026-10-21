# res://systems/game_state.gd
extends Node

## Signals for reactive UI (Filofax, HUD, Map highlights)
signal district_selected(district_id: String)
signal district_updated(district_id: String)
signal filofax_cache_updated(district_id: String)
signal turn_advanced(current_tick: int)
signal world_state_reset

## Path to active configuration (can be switched by scenario loaders)
@export var active_rules_path: String = "res://data_modules/core/business_rules.cfg"

## The Canonical World State (Single Source of Truth)
var world_state: Dictionary = {}

## Active UI Selection Pointer
var selected_district_id: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize_fresh_state()

## Initializes world_state entirely from external definition files
func initialize_fresh_state() -> void:
	# 1. Establish the clean schema skeleton
	world_state = {
		"metadata": {},
		"finances": {},
		"operations": {},
		"inventory_registry": {},
		"commodity_registry": {},
		"recipe_registry": {},
		"pending_orders": {},
		"districts": {},
		"filofax_cache": {
			"districts": {},
			"pinned_memos": []
		},
		"staff": {},
		"counterparties": {}
	}
	
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

func set_district(district_id: String, data: Dictionary) -> void:
	if not world_state.has("districts"):
		world_state["districts"] = {}
	world_state["districts"][district_id] = data
	district_updated.emit(district_id)

## Sets the currently clicked/inspected district and notifies the Filofax
func set_selected_district(district_id: String) -> void:
	selected_district_id = district_id
	district_selected.emit(district_id)

func get_district_truth(district_id: String) -> Dictionary:
	return world_state.get("districts", {}).get(district_id, {})

func get_district_filofax(district_id: String) -> Dictionary:
	return world_state.get("filofax_cache", {}).get("districts", {}).get(district_id, {})