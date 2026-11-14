# res://tests/test_live_obligation_verbs.gd
extends SceneTree

const DBManagerScript = preload("res://systems/db_manager.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const ObligationLedgerScript = preload("res://systems/economy/obligation_ledger.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")

func _init() -> void:
	print("=== Starting Live Obligation Verbs & Clearing Rollover Test ===")

	# 1. Initialize scenario manifest & isolated SQLite database
	ScenarioManifestManagerScript.reset_cache()
	var manifest := ScenarioManifestManagerScript.get_manifest()
	assert(not manifest.is_empty(), "FAIL: Could not load active scenario manifest.")

	var test_db_path := "user://test_live_obligation_verbs.db"
	var opened := DBManagerScript.initialize_database(true, test_db_path)
	assert(opened, "FAIL: Could not initialize test SQLite database.")

	var slot_dir := ProjectSettings.globalize_path("user://saves/test_obl_slot")
	DirAccess.make_dir_recursive_absolute(slot_dir)

	var start_day := CalendarHelperScript.get_simulation_start_day()

	# 2. Construct canonical world_state with co-located residents
	var world_state: Dictionary = {
		"metadata": {
			"current_sim_day": start_day,
			"time_horizon": "day",
			"active_slot_id": "test_obl_slot"
		},
		"residents": {
			"101": {
				"resident_id": 101,
				"name": "Arthur Pendelton",
				"current_district_id": "WARD_ASTON",
				"inventory": { "CASH": 250.0, "GRAIN_SACK": 10.0 }
			},
			"102": {
				"resident_id": 102,
				"name": "Billy Kimber",
				"current_district_id": "WARD_ASTON",
				"inventory": { "CASH": 20.0, "GRAIN_SACK": 5.0 }
			}
		},
		"establishments": {},
		"caches": {}
	}

	# 3. Fail-Early gate check when lender is not co-located at target_node_id
	var non_colocated_res := SimControllerScript.execute_directive(world_state, {
		"verb": "CREATE_OBLIGATION",
		"assigned_to": "101",
		"counterparty_id": "102",
		"obligation_type": "TERM_LOAN",
		"amount": 50.0,
		"target_node_id": "WARD_SOHO"
	})
	assert(not non_colocated_res.get("success", true), "FAIL: CREATE_OBLIGATION should fail when actor is not co-located.")
	print("[PASS] CREATE_OBLIGATION rejected non-co-located directive (INVALID_TARGET).")

	# 4. Execute valid CREATE_OBLIGATION (£100 TERM_LOAN from 101 to 102)
	var create_directive := {
		"verb": "CREATE_OBLIGATION",
		"assigned_to": "101",
		"counterparty_id": "102",
		"obligation_type": "TERM_LOAN",
		"amount": 100.0,
		"interest_rate": 0.05,
		"due_in_days": 14,
		"target_node_id": "WARD_ASTON"
	}
	var create_res := SimControllerScript.execute_directive(world_state, create_directive)
	assert(create_res.get("success", false), "FAIL: Valid CREATE_OBLIGATION failed: %s" % str(create_res))
	var obl_id := int(create_directive.get("created_obligation_id", 0))
	assert(obl_id > 0, "FAIL: created_obligation_id was not populated on directive.")
	assert(is_equal_approx(float(world_state["residents"]["101"]["inventory"]["CASH"]), 150.0), "FAIL: Lender cash should be 150.0.")
	assert(is_equal_approx(float(world_state["residents"]["102"]["inventory"]["CASH"]), 120.0), "FAIL: Borrower cash should be 120.0.")
	var obl_row := ObligationLedgerScript.get_obligation(obl_id)
	assert(str(obl_row.get("obligation_type", "")) == "TERM_LOAN", "FAIL: SQLite obligation_type mismatch.")
	assert(is_equal_approx(float(obl_row.get("balance", 0.0)), 100.0), "FAIL: SQLite initial balance should be 100.0.")
	print("[PASS] CREATE_OBLIGATION transferred physical CASH and persisted obligation_id=%d (TERM_LOAN, £100)." % obl_id)

	# 5. Execute partial inbound COLLECT_OBLIGATION (£40 PHYSICAL_CASH from 102 to 101)
	var collect_res := SimControllerScript.execute_directive(world_state, {
		"verb": "COLLECT_OBLIGATION",
		"assigned_to": "101",
		"counterparty_id": "102",
		"obligation_id": obl_id,
		"amount": 40.0,
		"rail_code": "PHYSICAL_CASH",
		"target_node_id": "WARD_ASTON"
	})
	assert(collect_res.get("success", false), "FAIL: COLLECT_OBLIGATION failed: %s" % str(collect_res))
	assert(is_equal_approx(float(world_state["residents"]["101"]["inventory"]["CASH"]), 190.0), "FAIL: Collector cash should be 190.0.")
	assert(is_equal_approx(float(world_state["residents"]["102"]["inventory"]["CASH"]), 80.0), "FAIL: Debtor cash should be 80.0.")
	obl_row = ObligationLedgerScript.get_obligation(obl_id)
	assert(is_equal_approx(float(obl_row.get("balance", 0.0)), 60.0), "FAIL: Remaining obligation balance should be 60.0.")
	assert(str(obl_row.get("status", "")) == "ACTIVE", "FAIL: Partially collected obligation must remain ACTIVE.")
	print("[PASS] COLLECT_OBLIGATION collected £40 cash and reduced SQLite balance to £60.0 (ACTIVE).")

	# 6. Execute outbound SETTLE_OBLIGATION for remaining £60 via multi-day CLEARING_BANK_CHEQUE rail
	var settle_res := SimControllerScript.execute_directive(world_state, {
		"verb": "SETTLE_OBLIGATION",
		"assigned_to": "102",
		"counterparty_id": "101",
		"obligation_id": obl_id,
		"item_id": "CASH",
		"amount": 60.0,
		"rail_code": "CLEARING_BANK_CHEQUE",
		"target_node_id": "WARD_ASTON"
	})
	assert(settle_res.get("success", false), "FAIL: SETTLE_OBLIGATION failed: %s" % str(settle_res))
	var settle_impact: Dictionary = settle_res.get("verb_impacts", {}).get("OBLIGATION", {})
	assert(not bool(settle_impact.get("settled_immediately", true)), "FAIL: CLEARING_BANK_CHEQUE rail should enter PENDING_CLEARANCE float.")
	var clears_on := int(settle_impact.get("settles_on_day", start_day))
	assert(clears_on > start_day, "FAIL: CLEARING_BANK_CHEQUE settles_on_day (%d) must be after start_day (%d)." % [clears_on, start_day])

	while int(world_state["metadata"]["current_sim_day"]) < clears_on:
		var tick_report := SimControllerScript.process_turn_cycle(world_state, [])
		assert(tick_report.has("obligation_rollover"), "FAIL: process_turn_cycle missing obligation_rollover.")

	obl_row = ObligationLedgerScript.get_obligation(obl_id)
	assert(is_equal_approx(float(obl_row.get("balance", -1.0)), 0.0), "FAIL: Cleared obligation balance should be 0.0.")
	assert(str(obl_row.get("status", "")) == "SETTLED", "FAIL: Cleared obligation status should be SETTLED.")
	print("[PASS] CLEARING_BANK_CHEQUE float matured on day %d via SimController.process_turn_cycle() -> SETTLED." % clears_on)

	# 7. Test non-financial obligation settlement (GRAIN_SACK) via SETTLE_OBLIGATION
	var grain_obl_id := ObligationLedgerScript.create_obligation({
		"debtor": "RESIDENT:102",
		"creditor": "RESIDENT:101",
		"obligation_type": "COMMODITY_FORWARD",
		"principal": 4.0,
		"balance": 4.0,
		"created_day": int(world_state["metadata"]["current_sim_day"])
	})
	var grain_settle_res := SimControllerScript.execute_directive(world_state, {
		"verb": "SETTLE_OBLIGATION",
		"assigned_to": "102",
		"counterparty_id": "101",
		"obligation_id": grain_obl_id,
		"item_id": "GRAIN_SACK",
		"amount": 4.0,
		"rail_code": "PHYSICAL_CASH",
		"target_node_id": "WARD_ASTON"
	})
	assert(grain_settle_res.get("success", false), "FAIL: Non-financial SETTLE_OBLIGATION failed.")
	assert(is_equal_approx(float(world_state["residents"]["101"]["inventory"]["GRAIN_SACK"]), 14.0), "FAIL: Creditor GRAIN_SACK should be 14.0.")
	assert(is_equal_approx(float(world_state["residents"]["102"]["inventory"]["GRAIN_SACK"]), 1.0), "FAIL: Debtor GRAIN_SACK should be 1.0.")
	assert(str(ObligationLedgerScript.get_obligation(grain_obl_id).get("status", "")) == "SETTLED", "FAIL: Commodity obligation should be SETTLED.")
	print("[PASS] Non-financial obligation settled cleanly using GRAIN_SACK.")

	# Cleanup
	DBManagerScript.close_database()
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_db_path))

	print("=== ALL LIVE OBLIGATION VERB & ROLLOVER TESTS PASSED ===")
	quit(0)