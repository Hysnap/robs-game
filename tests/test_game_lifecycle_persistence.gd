# res://tests/test_game_lifecycle_persistence.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const TEST_SOCIETY_FACTORY = preload("res://tests/test_society_factory.gd")
const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const SAVE_MANAGER = preload("res://systems/save_manager.gd")
const SCENARIO_MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

func _init() -> void:
	print("\n========================================================")
	print("🧪 RUNNING HEADLESS TEST: GAME LIFECYCLE & PERSISTENCE")
	print("========================================================")

	var test_slot := "slot_lifecycle_test"

	# 1. Prepare Target Save Slot and Mount Slot SQLite DB
	print("\n[STEP 1] Preparing save slot folder & SQLite database...")
	var prep_ok: bool = SAVE_MANAGER.prepare_new_slot(test_slot)
	assert(prep_ok, "FAIL: SaveManager.prepare_new_slot() failed for %s." % test_slot)

	# 2. Generate Schema-Compliant Living World via TestSocietyFactory
	print("  Generating test society in slot '%s'..." % test_slot)
	var world_state: Dictionary = TEST_SOCIETY_FACTORY.create_test_world(2, 2, "lifecycle-persist-seed")
	world_state["metadata"]["active_slot_id"] = test_slot

	var home_district: String = str(world_state.get("operations", {}).get("home_district_id", ""))
	assert(not home_district.is_empty(), "FAIL: TestSocietyFactory failed to resolve home district.")
	print("  ✓ Test society active. Home District: %s" % home_district)

	# 3. Scout Starting Crew and Bind Secondary Contracts
	print("\n[STEP 2] Scouting starting crew via CrewScoutBootstrapper...")
	var scout_ok: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(world_state, home_district)
	assert(scout_ok, "FAIL: CrewScoutBootstrapper failed to assemble starting crew.")

	var residents: Dictionary = world_state.get("residents", {})
	assert(residents.size() == 3, "FAIL: Expected 3 crew residents in world_state, got %d." % residents.size())
	print("  ✓ Recruited 3 procedural operatives:")
	for res_key in residents.keys():
		assert(res_key is int and int(res_key) > 0, "FAIL: Expected int resident_id key, got '%s'." % str(res_key))
		print("     • %s: %s (Resident #%d, Age %d)" % [
			residents[res_key]["slot_id"], residents[res_key]["name"], res_key, residents[res_key]["age"]
		])

	# 4. Advance Simulation Turn Cycle
	print("\n[STEP 3] Advancing simulation turn cycle...")
	var day_start: int = CALENDAR_HELPER.get_current_sim_day(world_state)
	var _cycle_result: Dictionary = SIM_CONTROLLER.process_turn_cycle(world_state, [])
	var day_after: int = CALENDAR_HELPER.get_current_sim_day(world_state)

	assert(day_after == day_start + 1, "FAIL: SimController did not advance sim day by 1 (%d -> %d)." % [day_start, day_after])
	print("  ✓ Sim day advanced cleanly: %d -> %d" % [day_start, day_after])

	# Verify SQLite world_metadata table was synchronized in lockstep
	var meta_rows: Array = DB_MANAGER.query_rows("SELECT value FROM world_metadata WHERE key = 'current_sim_day';")
	assert(not meta_rows.is_empty() and int(meta_rows[0].get("value", 0)) == day_after, "FAIL: SQLite world_metadata desynchronized!")
	print("  ✓ SQLite world_metadata verified in lockstep at day %d." % day_after)

	# 5. Persist State to Disk Slot
	print("\n[STEP 4] Persisting state to disk slot '%s'..." % test_slot)
	var save_ok: bool = SAVE_MANAGER.save_game(test_slot, null, world_state)
	assert(save_ok, "FAIL: SaveManager.save_game() returned false.")
	print("  ✓ Game saved successfully.")

	# 6. Simulate Clean Reload
	print("\n[STEP 5] Simulating clean reload: wiping memory and reloading slot...")
	var gs = SCENARIO_MANIFEST_MANAGER.get_game_state()
	if gs != null and "world_state" in gs:
		gs.world_state = {}

	var load_ok: bool = SAVE_MANAGER.load_game(test_slot)
	assert(load_ok, "FAIL: SaveManager.load_game() returned false.")

	var restored_state: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
	if restored_state.is_empty():
		var state_file := FileAccess.open("%s/game_state.json" % SAVE_MANAGER.get_slot_dir(test_slot), FileAccess.READ)
		assert(state_file != null, "FAIL: Could not read persisted game_state.json.")
		restored_state = JSON.parse_string(state_file.get_as_text())
		state_file.close()
		SAVE_MANAGER._normalize_integer_entity_keys(restored_state)

	# 7. Assert Post-Reload Invariants
	print("\n[STEP 6] Asserting post-reload invariants across disk and SQLite...")
	var loaded_day: int = CALENDAR_HELPER.get_current_sim_day(restored_state)
	assert(loaded_day == day_after, "FAIL: Loaded current_sim_day (%d) does not match expected (%d)." % [loaded_day, day_after])
	print("  ✓ Persisted temporal day preserved: %d" % loaded_day)

	var loaded_residents: Dictionary = restored_state.get("residents", {})
	for res_key in residents.keys():
		assert(loaded_residents.has(res_key), "FAIL: Loaded save is missing integer resident_id key %d." % res_key)
		assert(int(loaded_residents[res_key]["resident_id"]) == int(res_key), "FAIL: Resident ID mismatch for key %d." % res_key)
		assert(loaded_residents[res_key]["name"] == residents[res_key]["name"], "FAIL: Name mismatch for resident #%d." % res_key)
		print("  ✓ Restored operative %s: %s (Resident #%d)" % [
			loaded_residents[res_key]["slot_id"], loaded_residents[res_key]["name"], res_key
		])

	# Verify secondary enterprise contracts still exist in the re-mounted database
	for res_key in loaded_residents.keys():
		var r_id: int = int(res_key)
		var c_rows: Array = DB_MANAGER.query_rows("""
			SELECT employer_org_id, weekly_hours, compensation_rate 
			FROM livelihood_contracts 
			WHERE resident_id = %d AND employer_org_id = 'ORG:CREW_ENTERPRISE';
		""" % r_id)
		assert(not c_rows.is_empty(), "FAIL: Re-mounted database is missing ORG:CREW_ENTERPRISE contract for resident #%d." % r_id)
	print("  ✓ SQLite ORG:CREW_ENTERPRISE contracts verified across all restored operatives.")

	print("\n🎉 ALL GAME LIFECYCLE & PERSISTENCE CHECKS PASSED CLEANLY.\n")
	quit(0)
	