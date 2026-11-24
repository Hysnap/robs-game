# res://systems/save_manager.gd
class_name SaveManager
extends RefCounted

const SAVES_BASE_DIR := "user://saves"
const COMMODITY_MANAGER = preload("res://systems/commodity_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")
const CORE_COMMODITIES_DIR := "res://data_modules/core/commodities/"
const CORE_RECIPES_DIR := "res://data_modules/core/recipes/"

## Returns the full directory path for a given slot
static func get_slot_dir(slot_id: String) -> String:
	return "%s/%s" % [SAVES_BASE_DIR, slot_id]

## Returns the snapshots directory for a specific slot
static func get_snapshots_dir(slot_id: String) -> String:
	return "%s/%s/snapshots" % [SAVES_BASE_DIR, slot_id]

## Ensures the base saves directory and slot directory exist
static func ensure_slot_dir(slot_id: String) -> bool:
	var base_da := DirAccess.open("user://")
	if base_da == null:
		return false
	if not base_da.dir_exists("saves"):
		base_da.make_dir("saves")
		
	var saves_da := DirAccess.open(SAVES_BASE_DIR)
	if saves_da == null:
		return false
	if not saves_da.dir_exists(slot_id):
		saves_da.make_dir(slot_id)
		
	return true

## Prepares a slot for a new game: ensures folder exists and opens fresh SQLite DB inside it
static func prepare_new_slot(slot_id: String) -> bool:
	if not ensure_slot_dir(slot_id):
		return false
	var slot_db_path := "%s/society.db" % get_slot_dir(slot_id)
	return DBManager.initialize_database(true, slot_db_path)

## Safely resolves world_state dictionary across both runtime and headless test runners
static func _resolve_world_state(explicit_state: Dictionary = {}) -> Dictionary:
	if not explicit_state.is_empty():
		return explicit_state
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root and main_loop.root.has_node("GameState"):
		var gs = main_loop.root.get_node("GameState")
		return gs.world_state
	return {}

## Packages current GameState and SQLite database into the slot directory
static func save_game(slot_id: String, city_crafter_node: Node3D = null, custom_world_state: Dictionary = {}) -> bool:
	if not ensure_slot_dir(slot_id):
		SystemLogger.log_error("[SaveManager] Failed to create slot directory: %s" % slot_id)
		push_error("[SaveManager] Failed to create slot directory: %s" % slot_id)
		return false

	var slot_dir := get_slot_dir(slot_id)
	var state_to_save := _resolve_world_state(custom_world_state)
	SystemLogger.log_info("[SaveManager] Saving registries: commodities=%d recipes=%d." % [
		state_to_save.get("commodity_registry", {}).size(),
		state_to_save.get("recipe_registry", {}).size()
	])

	# 1. Save GameState JSON
	var state_file := FileAccess.open("%s/game_state.json" % slot_dir, FileAccess.WRITE)
	if state_file:
		state_file.store_string(JSON.stringify(state_to_save, "\t"))
		state_file.close()

	# 2. Save metadata header for load menus
	var meta_in: Dictionary = state_to_save.get("metadata", {})
	var current_day: int = CALENDAR_HELPER.get_current_sim_day(state_to_save)
	var population_count: int = int(meta_in.get("total_population", state_to_save.get("residents", {}).size()))
	var meta := {
		"slot_id": slot_id,
		"city_name": str(meta_in.get("city_name", slot_id)),
		"seed_id": str(meta_in.get("active_seed", "default")),
		"active_flavours": meta_in.get("active_flavours", []),
		"current_sim_day": current_day,
		"current_week_tick": int(meta_in.get("current_week_tick", 1)),
		"population": population_count,
		"timestamp": Time.get_datetime_string_from_system(),
		"district_count": state_to_save.get("districts", {}).size()
	}
	var meta_file := FileAccess.open("%s/meta.json" % slot_dir, FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta, "\t"))
		meta_file.close()
	
	# 3. Synchronize current_sim_day into SQLite world_metadata
	DBManager.execute_batch([
		"INSERT OR REPLACE INTO world_metadata (key, value) VALUES ('current_sim_day', '%d');" % current_day
		])

	# 4. Save City Visual Layout
	if city_crafter_node != null and city_crafter_node.has_method("export_visual_layout"):
		var layout = city_crafter_node.export_visual_layout()
		var layout_file := FileAccess.open("%s/city_layout.json" % slot_dir, FileAccess.WRITE)
		if layout_file:
			layout_file.store_string(JSON.stringify(layout, "\t"))
			layout_file.close()

	SystemLogger.log_info("[SaveManager] Game saved successfully to: %s" % slot_dir)
	return true

## Loads an existing save slot into GameState and mounts SQLite DB directly
static func load_game(slot_id: String) -> bool:
	var slot_dir := get_slot_dir(slot_id)
	var state_path := "%s/game_state.json" % slot_dir
	var db_path := "%s/society.db" % slot_dir
	
	if not FileAccess.file_exists(state_path) or not FileAccess.file_exists(db_path):
		SystemLogger.log_error("[SaveManager] Save slot incomplete or missing: %s" % slot_id)
		push_error("[SaveManager] Save slot incomplete or missing: %s" % slot_id)
		return false

	# 1. Ingest GameState JSON
	var file := FileAccess.open(state_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		SystemLogger.log_error("[SaveManager] Corrupted game_state.json in slot: %s" % slot_id)
		push_error("[SaveManager] Corrupted game_state.json in slot: %s" % slot_id)
		return false
	var catalogs_repaired: Variant = _ensure_catalog_registries(parsed, slot_id)
	if catalogs_repaired == null:
		return false
	_normalize_integer_entity_keys(parsed)

	var module_chain: Array[String] = _resolve_module_chain(parsed)
	VERB_ROUTER.initialize_chain(module_chain)
	IMPACT_ROUTER.reset()
	for mod_slug in module_chain:
		var impacts_dir := "res://data_modules/%s/impacts/" % mod_slug
		if DirAccess.dir_exists_absolute(impacts_dir):
			IMPACT_ROUTER.autoload_sinks(impacts_dir)

	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root and main_loop.root.has_node("GameState"):
		var gs = main_loop.root.get_node("GameState")
		gs.world_state = parsed

	# 2. Ingest visual layout if present
	var layout_path := "%s/city_layout.json" % slot_dir
	if FileAccess.file_exists(layout_path):
		var l_file := FileAccess.open(layout_path, FileAccess.READ)
		var parsed_layout = JSON.parse_string(l_file.get_as_text())
		l_file.close()
		if parsed_layout is Dictionary and main_loop is SceneTree and main_loop.root and main_loop.root.has_node("GameState"):
			var gs = main_loop.root.get_node("GameState")
			gs.world_state["city_layout"] = parsed_layout

	# 3. Mount SQLite database directly in place
	if not DBManager.initialize_database(false, db_path):
		SystemLogger.log_error("[SaveManager] Failed to mount database from: %s" % db_path)
		push_error("[SaveManager] Failed to mount database from: %s" % db_path)
		return false

	# 4. Synchronize temporal clock in SQLite metadata
	var loaded_day: int = CALENDAR_HELPER.get_current_sim_day(parsed)
	DBManager.execute_batch([
		"INSERT OR REPLACE INTO world_metadata (key, value) VALUES ('current_sim_day', '%d');" % loaded_day
	])

	if catalogs_repaired:
		var repaired_file := FileAccess.open(state_path, FileAccess.WRITE)
		if repaired_file == null:
			var repair_error := "[SaveManager] Failed to persist repaired registries for save '%s' (Error: %d)." % [
				slot_id, FileAccess.get_open_error()
			]
			SystemLogger.log_error(repair_error)
			push_error(repair_error)
			return false
		repaired_file.store_string(JSON.stringify(parsed, "\t"))
		repaired_file.close()
		SystemLogger.log_info("[SaveManager] Persisted repaired registries for save '%s'." % slot_id)

	SystemLogger.log_info("[SaveManager] Loaded game slot: %s (day=%d, commodities=%d, recipes=%d)." % [
		slot_id,
		loaded_day,
		parsed.get("commodity_registry", {}).size(),
		parsed.get("recipe_registry", {}).size()
	])
	return true

static func _resolve_module_chain(state: Dictionary) -> Array[String]:
	var chain: Array[String] = ["core"]
	var raw_flavours = state.get("metadata", {}).get("active_flavours", [])
	if raw_flavours is Array:
		for f in raw_flavours:
			var slug := str(f).strip_edges()
			if not slug.is_empty() and slug != "core" and slug != "shared" and not chain.has(slug):
				chain.append(slug)
	return chain

## Repairs legacy or incomplete saves that do not contain runtime catalog data.
static func _ensure_catalog_registries(state: Dictionary, slot_id: String) -> Variant:
	var commodity_registry: Dictionary = state.get("commodity_registry", {})
	var recipe_registry: Dictionary = state.get("recipe_registry", {})
	var repaired := false
	var module_chain: Array[String] = _resolve_module_chain(state)

	if commodity_registry.is_empty():
		SystemLogger.log_warn("[SaveManager] Save '%s' has an empty commodity registry; rehydrating from %s." % [slot_id, str(module_chain)])
		commodity_registry = COMMODITY_MANAGER.load_hierarchical_commodities(CORE_COMMODITIES_DIR)
		for mod_slug in module_chain:
			if mod_slug == "core":
				continue
			var mod_comm_dir := "res://data_modules/%s/commodities/" % mod_slug
			if DirAccess.dir_exists_absolute(mod_comm_dir):
				var extra_comm := COMMODITY_MANAGER.load_hierarchical_commodities(mod_comm_dir)
				for k in extra_comm.keys():
					commodity_registry[k] = extra_comm[k]
		state["commodity_registry"] = commodity_registry
		repaired = true

	if recipe_registry.is_empty():
		SystemLogger.log_warn("[SaveManager] Save '%s' has an empty recipe registry; rehydrating from %s." % [slot_id, str(module_chain)])
		recipe_registry = COMMODITY_MANAGER.load_hierarchical_commodities(CORE_RECIPES_DIR)
		for mod_slug in module_chain:
			if mod_slug == "core":
				continue
			var mod_rec_dir := "res://data_modules/%s/recipes/" % mod_slug
			if DirAccess.dir_exists_absolute(mod_rec_dir):
				var extra_rec := COMMODITY_MANAGER.load_hierarchical_commodities(mod_rec_dir)
				for k in extra_rec.keys():
					recipe_registry[k] = extra_rec[k]
		state["recipe_registry"] = recipe_registry
		repaired = true

	SystemLogger.log_info("[SaveManager] Catalog registries ready: commodities=%d recipes=%d." % [
		commodity_registry.size(),
		recipe_registry.size()
	])

	if commodity_registry.is_empty() or recipe_registry.is_empty():
		var message := "[SaveManager] Could not restore required catalog registries for save '%s'." % slot_id
		SystemLogger.log_error(message)
		push_error(message)
		return null

	return repaired

# ==============================================================================
# NON-IRONMAN PER-TURN SNAPSHOTS (Developer & Debugging State History)
# ==============================================================================

## Serializes the active turn's world state into an indented, human-readable snapshot JSON
static func save_turn_snapshot(slot_id: String, turn_index: int, state: Dictionary) -> String:
	var snap_dir := get_snapshots_dir(slot_id)
	var dir_err := DirAccess.make_dir_recursive_absolute(snap_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		SystemLogger.log_error("[SaveManager] Failed to create snapshots directory: %s" % snap_dir)
		push_error("[SaveManager] Failed to create snapshots directory: %s" % snap_dir)
		return ""

	var file_name := "turn_%03d.json" % turn_index
	var file_path := snap_dir.path_join(file_name)

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		var err := FileAccess.get_open_error()
		push_error("[SaveManager] Failed writing snapshot at: %s (Error: %d)" % [file_path, err])
		return ""

	file.store_string(JSON.stringify(state, "\t"))
	file.close()

	SystemLogger.log_info("[SaveManager] Turn %d snapshot written: %s" % [turn_index, file_path])
	return file_path

## Loads a specific turn snapshot back into GameState memory
static func load_turn_snapshot(slot_id: String, turn_index: int) -> Dictionary:
	var file_path := get_snapshots_dir(slot_id).path_join("turn_%03d.json" % turn_index)
	if not FileAccess.file_exists(file_path):
		SystemLogger.log_error("[SaveManager] Snapshot not found: %s" % file_path)
		push_error("[SaveManager] Snapshot not found: %s" % file_path)
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if not (parsed is Dictionary):
		push_error("[SaveManager] Corrupted snapshot JSON: %s" % file_path)
		return {}
	_normalize_integer_entity_keys(parsed)

	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root and main_loop.root.has_node("GameState"):
		var gs = main_loop.root.get_node("GameState")
		gs.world_state = parsed

	SystemLogger.log_info("[SaveManager] Restored turn %d snapshot from: %s" % [turn_index, file_path])
	return parsed

## Lists all snapshot paths in a given slot in chronological turn order
static func list_turn_snapshots(slot_id: String) -> Array[String]:
	var snapshots: Array[String] = []
	var snap_dir := get_snapshots_dir(slot_id)
	var dir := DirAccess.open(snap_dir)
	if not dir:
		return snapshots

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("turn_") and file_name.ends_with(".json"):
			snapshots.append(snap_dir.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	snapshots.sort()
	return snapshots

# ==============================================================================
# SLOT DISCOVERY UTILITIES
# ==============================================================================

## Helper to find the next available auto-numbered slot (e.g. slot_01, slot_02)
static func get_next_available_slot() -> String:
	var idx := 1
	while DirAccess.dir_exists_absolute("user://saves/slot_%02d" % idx):
		idx += 1
	return "slot_%02d" % idx

## Returns the slot_id of the most recently modified save folder, or "" if none exist
static func get_latest_save_slot() -> String:
	var base_da := DirAccess.open(SAVES_BASE_DIR)
	if base_da == null:
		return ""

	base_da.list_dir_begin()
	var file_name := base_da.get_next()
	var latest_slot := ""
	var latest_time := 0

	while file_name != "":
		if base_da.current_is_dir() and not file_name.begins_with("."):
			var state_path := "%s/%s/game_state.json" % [SAVES_BASE_DIR, file_name]
			if FileAccess.file_exists(state_path):
				var modified_time = FileAccess.get_modified_time(state_path)
				if modified_time > latest_time:
					latest_time = modified_time
					latest_slot = file_name
		file_name = base_da.get_next()
	base_da.list_dir_end()

	return latest_slot

# Returns all valid save slots in user://saves/ sorted newest-first, flagging the nominated latest save
static func list_save_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var base_da := DirAccess.open(SAVES_BASE_DIR)
	if base_da == null:
		return slots
	base_da.list_dir_begin()
	var dir_name := base_da.get_next()
	while dir_name != "":
		if base_da.current_is_dir() and not dir_name.begins_with("."):
			var slot_dir := "%s/%s" % [SAVES_BASE_DIR, dir_name]
			var state_path := "%s/game_state.json" % slot_dir
			var db_path := "%s/society.db" % slot_dir
			if FileAccess.file_exists(state_path) and FileAccess.file_exists(db_path):
				var entry := _read_slot_summary(dir_name, slot_dir, state_path)
				slots.append(entry)
		dir_name = base_da.get_next()
	base_da.list_dir_end()

	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("modified_unix", 0)) > int(b.get("modified_unix", 0))
	)

	if not slots.is_empty():
		slots[0]["is_nominated"] = true

	return slots

static func _read_slot_summary(slot_id: String, slot_dir: String, state_path: String) -> Dictionary:
	var mod_time: int = int(FileAccess.get_modified_time(state_path))
	var meta_path := "%s/meta.json" % slot_dir
	var default_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var info: Dictionary = {
		"slot_id": slot_id,
		"city_name": slot_id,
		"seed_id": "default",
		"current_sim_day": default_start_day,
		"current_week_tick": 1,
		"population": 0,
		"district_count": 0,
		"timestamp": "",
		"modified_unix": mod_time,
		"is_nominated": false
		}
	if FileAccess.file_exists(meta_path):
		var mf := FileAccess.open(meta_path, FileAccess.READ)
		if mf != null:
			var parsed_meta = JSON.parse_string(mf.get_as_text())
			mf.close()
			if parsed_meta is Dictionary:
				for k in parsed_meta.keys():
					info[k] = parsed_meta[k]

	# Hydrate missing population/city_name from game_state.json for older saves
	if int(info.get("population", 0)) <= 0 or str(info.get("city_name", "")) == slot_id:
		var sf := FileAccess.open(state_path, FileAccess.READ)
		if sf != null:
			var parsed_state = JSON.parse_string(sf.get_as_text())
			sf.close()
			if parsed_state is Dictionary:
				var m: Dictionary = parsed_state.get("metadata", {})
				if str(info.get("city_name", "")) == slot_id and m.has("city_name"):
					info["city_name"] = str(m["city_name"])
				if int(info.get("current_sim_day", default_start_day)) == default_start_day and m.has("current_sim_day"):
					info["current_sim_day"] = int(m["current_sim_day"])
				if int(info.get("population", 0)) <= 0:
					info["population"] = int(m.get("total_population", parsed_state.get("residents", {}).size()))

	return info


## Deletes a save slot directory and all files inside it
static func delete_save_slot(slot_id: String) -> bool:
	var clean_id := slot_id.strip_edges()
	if clean_id.is_empty() or clean_id.contains("..") or clean_id.contains("/"):
		return false
	var slot_dir := get_slot_dir(clean_id)
	if not DirAccess.dir_exists_absolute(slot_dir):
		return false
	_remove_dir_recursive(slot_dir)
	SystemLogger.log_info("[SaveManager] Deleted save slot: %s" % clean_id)
	return true

static func _remove_dir_recursive(dir_path: String) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry_name := da.get_next()
	while entry_name != "":
		if not entry_name.begins_with("."):
			var full := dir_path.path_join(entry_name)
			if da.current_is_dir():
				_remove_dir_recursive(full)
			else:
				da.remove(entry_name)
		entry_name = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(dir_path)

## Restores canonical int keys and inner integer IDs after JSON deserialization for multi-thousand-turn save compatibility
static func _normalize_integer_entity_keys(state: Dictionary) -> void:
	if state.has("residents") and state["residents"] is Dictionary:
		var raw_res: Dictionary = state["residents"]
		var norm_res: Dictionary = {}
		for raw_key in raw_res.keys():
			var rec = raw_res[raw_key]
			var key_str := str(raw_key)
			var canonical_id: int = int(key_str) if key_str.is_valid_int() else 0
			if rec is Dictionary:
				for id_field in ["resident_id", "id", "establishment_id", "home_establishment_id"]:
					if rec.has(id_field) and str(rec[id_field]).is_valid_int():
						rec[id_field] = int(rec[id_field])
				if int(rec.get("resident_id", 0)) > 0:
					canonical_id = int(rec["resident_id"])
				elif canonical_id > 0:
					rec["resident_id"] = canonical_id
			if canonical_id > 0:
				norm_res[canonical_id] = rec
			else:
				norm_res[raw_key] = rec
		state["residents"] = norm_res

	if state.has("establishments") and state["establishments"] is Dictionary:
		var raw_est: Dictionary = state["establishments"]
		var norm_est: Dictionary = {}
		for raw_key in raw_est.keys():
			var rec = raw_est[raw_key]
			var key_str := str(raw_key)
			var canonical_id: int = int(key_str) if key_str.is_valid_int() else 0
			if rec is Dictionary:
				for id_field in ["establishment_id", "id"]:
					if rec.has(id_field) and str(rec[id_field]).is_valid_int():
						rec[id_field] = int(rec[id_field])
				if int(rec.get("establishment_id", 0)) > 0:
					canonical_id = int(rec["establishment_id"])
				elif canonical_id > 0:
					rec["establishment_id"] = canonical_id
			if canonical_id > 0:
				norm_est[canonical_id] = rec
			else:
				norm_est[raw_key] = rec
		state["establishments"] = norm_est

	if state.has("todo_backlog") and state["todo_backlog"] is Array:
		for item in state["todo_backlog"]:
			if item is Dictionary:
				for ref_field in ["assigned_to", "initiator_id", "counterparty_id"]:
					if item.has(ref_field) and str(item[ref_field]).is_valid_int():
						item[ref_field] = int(item[ref_field])

	if state.has("pending_orders") and state["pending_orders"] is Dictionary:
		for order_key in state["pending_orders"].keys():
			var ord_rec = state["pending_orders"][order_key]
			if ord_rec is Dictionary:
				for ref_field in ["assigned_to", "initiator_id", "counterparty_id"]:
					if ord_rec.has(ref_field) and str(ord_rec[ref_field]).is_valid_int():
						ord_rec[ref_field] = int(ord_rec[ref_field])