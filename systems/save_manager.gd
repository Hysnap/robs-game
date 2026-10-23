# res://systems/save_manager.gd
class_name SaveManager
extends RefCounted

const SAVES_BASE_DIR := "user://saves"

## Returns the full directory path for a given slot
static func get_slot_dir(slot_id: String) -> String:
	return "%s/%s" % [SAVES_BASE_DIR, slot_id]

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

## Packages current GameState and SQLite database into the slot directory
static func save_game(slot_id: String, city_crafter_node: Node3D = null) -> bool:
	if not ensure_slot_dir(slot_id):
		push_error("[SaveManager] Failed to create slot directory: %s" % slot_id)
		return false

	var slot_dir := get_slot_dir(slot_id)
	
	# 1. Close active DB connection cleanly before file copy
	DBManager.close_database()
	
	# 2. Copy the active SQLite database file to the slot directory
	var active_db_global: String = ProjectSettings.globalize_path(DBManager.DB_PATH)
	var target_db_global: String = ProjectSettings.globalize_path("%s/society.db" % slot_dir)
	
	if FileAccess.file_exists(DBManager.DB_PATH):
		var copy_err := DirAccess.copy_absolute(active_db_global, target_db_global)
		if copy_err != OK:
			push_error("[SaveManager] Failed to copy SQLite database into slot: %d" % copy_err)
			return false
	
	# Re-open active DB
	DBManager.initialize_database(false)

	# 3. Save GameState (districts, finances, inventory, ticks)
	var state_file := FileAccess.open("%s/game_state.json" % slot_dir, FileAccess.WRITE)
	if state_file:
		state_file.store_string(JSON.stringify(GameState.world_state, "\t"))
		state_file.close()

	# 4. Save metadata header for load menus
	var meta := {
		"slot_id": slot_id,
		"seed_id": GameState.world_state.get("metadata", {}).get("active_seed", "default"),
		"timestamp": Time.get_datetime_string_from_system(),
		"district_count": GameState.world_state.get("districts", {}).size()
	}
	var meta_file := FileAccess.open("%s/meta.json" % slot_dir, FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta, "\t"))
		meta_file.close()
	
	# Save City Visual Layout
	if city_crafter_node != null and city_crafter_node.has_method("export_visual_layout"):
		var layout = city_crafter_node.export_visual_layout()
		var layout_file := FileAccess.open("%s/city_layout.json" % slot_dir, FileAccess.WRITE)
		if layout_file:
			layout_file.store_string(JSON.stringify(layout, "\t"))
			layout_file.close()

	print("[SaveManager] Game saved successfully to: %s" % slot_dir)
	return true

## Loads an existing save slot into GameState and SQLite
static func load_game(slot_id: String) -> bool:
	var slot_dir := get_slot_dir(slot_id)
	var state_path := "%s/game_state.json" % slot_dir
	var db_path := "%s/society.db" % slot_dir
	
	if not FileAccess.file_exists(state_path) or not FileAccess.file_exists(db_path):
		push_error("[SaveManager] Save slot incomplete or missing: %s" % slot_id)
		return false

	# 1. Ingest GameState JSON
	var file := FileAccess.open(state_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("[SaveManager] Corrupted game_state.json in slot: %s" % slot_id)
		return false
	GameState.world_state = parsed

	# 2. Swap and mount SQLite DB from slot
	DBManager.close_database()
	var active_db_global: String = ProjectSettings.globalize_path(DBManager.DB_PATH)
	var slot_db_global: String = ProjectSettings.globalize_path(db_path)
	
	var err := DirAccess.copy_absolute(slot_db_global, active_db_global)
	if err != OK:
		push_error("[SaveManager] Failed to restore SQLite database from slot: %d" % err)
		return false

	# Ingest city_layout.json into GameState cache
	var layout_path := "%s/city_layout.json" % slot_dir
	if FileAccess.file_exists(layout_path):
		var l_file := FileAccess.open(layout_path, FileAccess.READ)
		var parsed_layout = JSON.parse_string(l_file.get_as_text())
		l_file.close()
		if parsed_layout is Dictionary:
			GameState.world_state["city_layout"] = parsed_layout

	DBManager.initialize_database(false)
	print("[SaveManager] Loaded game slot: %s" % slot_id)
	return true

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