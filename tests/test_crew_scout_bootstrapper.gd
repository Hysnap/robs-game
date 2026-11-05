# res://tests/test_crew_scout_bootstrapper.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const TEST_SOCIETY_FACTORY = preload("res://tests/test_society_factory.gd")
const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")

func _init() -> void:
	print("\n========================================================")
	print("🧪 RUNNING HEADLESS TEST: CREW SCOUT BOOTSTRAPPER")
	print("========================================================")

	# 1. Initialize schema and generate standardized test society via factory
	var world_state: Dictionary = TEST_SOCIETY_FACTORY.create_test_world(2, 2, "bootstrapper-test-seed")
	var home_district: String = str(world_state.get("player_knowledge", {}).get("home_district_id", ""))
	assert(not home_district.is_empty(), "FAIL: TestSocietyFactory produced empty home_district_id.")

	print("  ✓ Test society generated. Scouting candidates in: %s" % home_district)

	# 2. Execute crew scouting bootstrapper
	var success: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(world_state, home_district)
	assert(success, "FAIL: CrewScoutBootstrapper failed to scout and bind crew.")
	print("✅ Bootstrapper returned success.")

	# 3. Assert staff entries in world_state
	var staff: Dictionary = world_state.get("staff", {})
	assert(staff.has("crew_0") and staff.has("crew_1") and staff.has("crew_2"), "FAIL: Missing crew slots in staff.")

	for slot in ["crew_0", "crew_1", "crew_2"]:
		var member: Dictionary = staff[slot]
		assert(int(member.get("resident_id", 0)) > 0, "FAIL: %s missing valid resident_id." % slot)
		assert(not str(member.get("name", "")).is_empty(), "FAIL: %s missing procedural name." % slot)
		assert(int(member.get("household_id", 0)) > 0, "FAIL: %s missing household_id." % slot)
		print("   • Slot %s: %s (Resident #%d, Age %d, Pocket: £%.2f)" % [
			slot, member["name"], member["resident_id"], member["age"], member.get("pocket_cash", 0.0)
		])

	# 4. Verify SQLite secondary contracts and is_active_agent
	for slot in ["crew_0", "crew_1", "crew_2"]:
		var r_id: int = int(staff[slot]["resident_id"])
		
		# Check active agent flag
		var r_rows: Array = DB_MANAGER.query_rows("SELECT is_active_agent FROM residents WHERE resident_id = %d;" % r_id)
		assert(not r_rows.is_empty() and int(r_rows[0].get("is_active_agent", 0)) == 1, "FAIL: Resident #%d not marked active agent." % r_id)

		# Check secondary enterprise contract
		var c_rows: Array = DB_MANAGER.query_rows("""
			SELECT employer_entity_id, weekly_hours, compensation_rate 
			FROM livelihood_contracts 
			WHERE resident_id = %d AND employer_entity_id = 'CREW_ENTERPRISE';
		""" % r_id)
		assert(not c_rows.is_empty(), "FAIL: Resident #%d missing CREW_ENTERPRISE secondary contract." % r_id)
		print("   • Verified SQLite CREW_ENTERPRISE contract for %s (Resident #%d)" % [slot, r_id])

	print("\n🎉 ALL CREW SCOUT BOOTSTRAPPER CHECKS PASSED CLEANLY.\n")
	quit(0)