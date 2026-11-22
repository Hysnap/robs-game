# res://tests/test_crew_scout_bootstrapper.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const TEST_SOCIETY_FACTORY = preload("res://tests/test_society_factory.gd")
const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")

var _frame_count: int = 0
var _executed: bool = false

func _init() -> void:
	print("\n========================================================")
	print("🧪 RUNNING HEADLESS TEST: CREW SCOUT BOOTSTRAPPER")
	print("========================================================")

func _process(_delta: float) -> bool:
	if _executed:
		return false
	_frame_count += 1
	if _frame_count < 2:
		return false
	_executed = true
	_run_tests_async()
	return false

func _run_tests_async() -> void:
	# 1. Initialize schema and generate standardized radial test society via factory
	var world_state: Dictionary = await TEST_SOCIETY_FACTORY.create_test_world(4, 4, "bootstrapper-test-seed")
	var home_district: String = str(world_state.get("operations", {}).get("home_district_id", world_state.get("player_knowledge", {}).get("home_district_id", "")))
	assert(not home_district.is_empty(), "FAIL: TestSocietyFactory produced empty home_district_id.")

	print("  ✓ Test society generated. Scouting candidates in: %s" % home_district)

	# 2. Execute crew scouting bootstrapper
	var success: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(world_state, home_district)
	assert(success, "FAIL: CrewScoutBootstrapper failed to scout and bind crew.")
	print("✅ Bootstrapper returned success.")

	# 3. Assert canonical integer-keyed resident entries in world_state
	var residents: Dictionary = world_state.get("residents", {})
	assert(residents.size() == 3, "FAIL: Expected 3 crew operatives in canonical residents registry, got %d." % residents.size())
	assert(not world_state.has("staff"), "FAIL: Legacy 'staff' pool must not exist in canonical world_state.")

	var seen_slots: Array[String] = []
	for res_key in residents.keys():
		assert(res_key is int and int(res_key) > 0, "FAIL: Resident key must be a positive int resident_id, got '%s'." % str(res_key))
		var member: Dictionary = residents[res_key]
		var r_id: int = int(member.get("resident_id", 0))
		var slot_id: String = str(member.get("slot_id", ""))
		assert(r_id == int(res_key), "FAIL: Resident dictionary key (%d) must match member.resident_id (%d)." % [int(res_key), r_id])
		assert(not slot_id.is_empty() and not seen_slots.has(slot_id), "FAIL: Invalid or duplicate slot_id '%s'." % slot_id)
		seen_slots.append(slot_id)
		assert(not str(member.get("name", "")).is_empty(), "FAIL: %s missing procedural name." % slot_id)
		assert(int(member.get("household_id", 0)) > 0, "FAIL: %s missing household_id." % slot_id)
		var cash_balance: float = float(member.get("inventory", {}).get("CASH", 0.0))
		print("   • Slot %s: %s (Resident #%d, Age %d, Cash: £%.2f)" % [
			slot_id, member["name"], r_id, member["age"], cash_balance
		])

	assert(seen_slots.has("crew_0") and seen_slots.has("crew_1") and seen_slots.has("crew_2"), "FAIL: Missing expected crew slot_ids.")

	# 4. Verify SQLite secondary contracts and is_active_agent
	for res_key in residents.keys():
		var r_id: int = int(res_key)
		var slot_id: String = str(residents[res_key].get("slot_id", ""))
		
		# Check active agent flag
		var r_rows: Array = DB_MANAGER.query_rows("SELECT is_active_agent FROM residents WHERE resident_id = %d;" % r_id)
		assert(not r_rows.is_empty() and int(r_rows[0].get("is_active_agent", 0)) == 1, "FAIL: Resident #%d not marked active agent." % r_id)

		# Check secondary enterprise contract
		var c_rows: Array = DB_MANAGER.query_rows("""
			SELECT employer_org_id, weekly_hours, compensation_rate 
			FROM livelihood_contracts 
			WHERE resident_id = %d AND employer_org_id = 'ORG:CREW_ENTERPRISE';
		""" % r_id)
		assert(not c_rows.is_empty(), "FAIL: Resident #%d missing ORG:CREW_ENTERPRISE secondary contract." % r_id)
		print("   • Verified SQLite ORG:CREW_ENTERPRISE contract for %s (Resident #%d)" % [slot_id, r_id])

	DB_MANAGER.close_database()
	print("\n🎉 ALL CREW SCOUT BOOTSTRAPPER CHECKS PASSED CLEANLY.\n")
	quit(0)