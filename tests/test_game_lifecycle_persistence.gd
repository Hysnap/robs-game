# res://tests/test_game_lifecycle_persistence.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const TEST_SOCIETY_FACTORY = preload("res://tests/test_society_factory.gd")
const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const SAVE_MANAGER = preload("res://systems/save_manager.gd")

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

	var home_district: String = str(world_state.get("player_knowledge", {}).get("home_district_id", ""))
	assert(not home_district.is_empty(), "FAIL: TestSocietyFactory failed to resolve home district.")
	print("  ✓ Test society active. Home District: %s" % home_district)

	# 3. Scout Starting Crew and Bind Secondary Contracts
	print("\n[STEP 2] Scouting starting crew via CrewScoutBootstrapper...")
	var scout_ok: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(world_state, home_district)
	assert(scout_ok, "FAIL: CrewScoutBootstrapper failed to assemble starting crew.")

	var staff: Dictionary = world_state.get("staff", {})
	assert(staff.has("crew_0") and staff.has("crew_1") and staff.has("crew_2"), "FAIL: Staff slots missing from world_state.")
	print("  ✓ Recruited 3 procedural operatives:")
	for slot in ["crew_0", "crew_1", "crew_2"]:
		print("     • %s: %s (Resident #%d, Age %d)" % [
			slot, staff[slot]["name"], staff[slot]["resident_id"], staff[slot]["age"]
		])

	# 4. Advance Simulation Turn Cycle
	print("\n[STEP 3] Advancing simulation turn cycle...")
	var day_start: int = int(world_state["metadata"]["current_sim_day"])
	var cycle_result: Dictionary = SIM_CONTROLLER.process_turn_cycle(world_state, [])
	var day_after: int = int(world_state["metadata"]["current_sim_day"])

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
	var load_ok: bool = SAVE_MANAGER.load_game(test_slot)
	assert(load_ok, "FAIL: SaveManager.load_game() returned false.")

	var state_file := FileAccess.open("%s/game_state.json" % SAVE_MANAGER.get_slot_dir(test_slot), FileAccess.READ)
	assert(state_file != null, "FAIL: Could not read persisted game_state.json.")
	var restored_state: Dictionary = JSON.parse_string(state_file.get_as_text())
	state_file.close()

	# 7. Assert Post-Reload Invariants
	print("\n[STEP 6] Asserting post-reload invariants across disk and SQLite...")
	var loaded_day: int = int(restored_state.get("metadata", {}).get("current_sim_day", 0))
	assert(loaded_day == day_after, "FAIL: Loaded current_sim_day (%d) does not match expected (%d)." % [loaded_day, day_after])
	print("  ✓ Persisted temporal day preserved: %d" % loaded_day)

	var loaded_staff: Dictionary = restored_state.get("staff", {})
	for slot in ["crew_0", "crew_1", "crew_2"]:
		assert(loaded_staff.has(slot), "FAIL: Loaded save is missing crew slot '%s'." % slot)
		assert(loaded_staff[slot]["resident_id"] == staff[slot]["resident_id"], "FAIL: Resident ID mismatch for slot %s." % slot)
		assert(loaded_staff[slot]["name"] == staff[slot]["name"], "FAIL: Name mismatch for slot %s." % slot)
		print("  ✓ Restored operative %s: %s (Resident #%d)" % [slot, loaded_staff[slot]["name"], loaded_staff[slot]["resident_id"]])

	# Verify secondary enterprise contracts still exist in the re-mounted database
	for slot in ["crew_0", "crew_1", "crew_2"]:
		var r_id: int = int(loaded_staff[slot]["resident_id"])
		var c_rows: Array = DB_MANAGER.query_rows("""
			SELECT employer_entity_id, weekly_hours, compensation_rate
			FROM livelihood_contracts
			WHERE resident_id = %d AND employer_entity_id = 'CREW_ENTERPRISE';
		""" % r_id)
		assert(not c_rows.is_empty(), "FAIL: Re-mounted database is missing CREW_ENTERPRISE contract for resident #%d." % r_id)
	print("  ✓ SQLite CREW_ENTERPRISE contracts verified across all restored operatives.")

	print("\n🎉 ALL GAME LIFECYCLE & PERSISTENCE CHECKS PASSED CLEANLY.\n")
	quit(0)