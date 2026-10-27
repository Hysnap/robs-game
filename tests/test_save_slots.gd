# res://tests/test_save_slots.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SAVE_MANAGER = preload("res://systems/save_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       TESTING MULTI-SLOT DB ISOLATION & MOUNTING      ")
	print("=======================================================")

	var test_slot := "test_slot_99"
	var test_slot_dir := SAVE_MANAGER.get_slot_dir(test_slot)
	var test_db_path := "%s/society.db" % test_slot_dir

	# 1. Clean up any previous test artifacts
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	# 2. Test prepare_new_slot directly mounts target path
	print("[TEST 1] Preparing and mounting %s..." % test_slot)
	var ok: bool = SAVE_MANAGER.prepare_new_slot(test_slot)
	assert(ok, "FAILED: prepare_new_slot returned false!")
	assert(DB_MANAGER.active_db_path == test_db_path, "FAILED: active_db_path was not set to slot path!")
	assert(FileAccess.file_exists(test_db_path), "FAILED: society.db was not created in slot folder!")

	# 3. Insert test row into mounted database
	DB_MANAGER.set_metadata("test_slot_key", "slot_99_isolated_value")
	assert(DB_MANAGER.get_metadata("test_slot_key") == "slot_99_isolated_value", "FAILED: Could not read metadata from slot DB!")

	# 4. Save metadata and game state JSON with mock dictionary (no Autoload needed)
	var mock_state := {
		"metadata": { "active_seed": "test-seed-99" },
		"districts": {}
	}
	assert(SAVE_MANAGER.save_game(test_slot, null, mock_state), "FAILED: save_game returned false!")
	assert(FileAccess.file_exists("%s/game_state.json" % test_slot_dir), "FAILED: game_state.json missing!")
	assert(FileAccess.file_exists("%s/meta.json" % test_slot_dir), "FAILED: meta.json missing!")

	# 5. Switch to a second slot and verify isolation
	var second_slot := "test_slot_98"
	var second_slot_dir := SAVE_MANAGER.get_slot_dir(second_slot)
	var second_db_path := "%s/society.db" % second_slot_dir
	print("[TEST 2] Preparing and mounting %s..." % second_slot)
	assert(SAVE_MANAGER.prepare_new_slot(second_slot), "FAILED: prepare_new_slot failed for second slot!")
	assert(DB_MANAGER.active_db_path == second_db_path, "FAILED: active_db_path did not switch to second slot!")
	assert(DB_MANAGER.get_metadata("test_slot_key") == "", "FAILED: test_slot_98 inherited state from test_slot_99!")

	# 6. Load back first slot without disk-copying
	print("[TEST 3] Loading back %s..." % test_slot)
	assert(SAVE_MANAGER.load_game(test_slot), "FAILED: load_game failed for test_slot_99!")
	assert(DB_MANAGER.active_db_path == test_db_path, "FAILED: DB was not re-mounted to test_slot_99!")
	assert(DB_MANAGER.get_metadata("test_slot_key") == "slot_99_isolated_value", "FAILED: Failed to read isolated slot data!")

	# Cleanup test slots
	DB_MANAGER.close_database()
	DirAccess.remove_absolute(test_db_path)
	DirAccess.remove_absolute("%s/game_state.json" % test_slot_dir)
	DirAccess.remove_absolute("%s/meta.json" % test_slot_dir)
	
	if FileAccess.file_exists(second_db_path):
		DirAccess.remove_absolute(second_db_path)

	var da := DirAccess.open("user://saves")
	if da != null:
		da.remove(test_slot)
		da.remove(second_slot)

	print("\n=======================================================")
	print("    SAVE SLOT MOUNTING & ISOLATION PASSED 100% CLEAN   ")
	print("=======================================================\n")
	quit()