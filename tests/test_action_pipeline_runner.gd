# res://tests/test_action_pipeline_runner.gd
extends SceneTree

const ActionPipelineRunnerScript = preload("res://systems/action_pipeline/action_pipeline_runner.gd")
const EngineResultScript = preload("res://systems/engine_result.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   TEST: MODULAR ACTION PIPELINE & PRIMITIVES")
	print("=======================================================")

	var passed: bool = true
	passed = passed and test_nominal_pipeline_execution()
	passed = passed and test_gated_failure_with_penalties()
	passed = passed and test_fail_loud_on_missing_parameter()

	if passed:
		print("\n=======================================================")
		print("   ALL ACTION PIPELINE TESTS PASSED CLEANLY")
		print("=======================================================\n")
		quit(0)
	else:
		printerr("\n[FATAL] Action Pipeline Tests encountered failures!\n")
		quit(1)

func test_nominal_pipeline_execution() -> bool:
	print("\n[STEP 1] Testing nominal multi-step execution...")

	var world_state: Dictionary = _create_mock_world_state()
	var directive: Dictionary = {
		"verb": "PURCHASE_SUPPLIES",
		"assigned_to": "OP_01",
		"target_node_id": "DISTRICT_EAST",
		"supplier_id": "VENUE_WHOLESALER",
		"item_id": "BEER_KEG",
		"amount": 2.0,
		"unit_cost": 25.0
	}

	var verb_def: Dictionary = {
		"_meta": { "verb_token": "PURCHASE_SUPPLIES" },
		"steps": [
			{
				"step_id": "gate_cash",
				"primitive": "REQUIRE",
				"params": {
					"domain": "COMMODITY",
					"actor": "ORDER_ACTOR",
					"metric": "CASH",
					"operator": ">=",
					"value": "CALCULATED_TOTAL_COST"
				},
				"on_failure": { "error_code": "INSUFFICIENT_FUNDS" },
				"next_step": "travel_to_venue"
			},
			{
				"step_id": "travel_to_venue",
				"primitive": "MOVE_ACTOR",
				"params": {
					"actor": "ORDER_ACTOR",
					"destination": "PARAM.target_node_id",
					"travel_time": 20.0,
					"travel_fatigue": 0.04
				},
				"next_step": "pay_supplier"
			},
			{
				"step_id": "pay_supplier",
				"primitive": "TRANSFER_ITEM",
				"params": {
					"from": "ORDER_ACTOR",
					"to": "PARAM.supplier_id",
					"item_id": "CASH",
					"quantity": "CALCULATED_TOTAL_COST",
					"transfer_time": 5.0,
					"transfer_fatigue": 0.01
				},
				"next_step": "receive_goods"
			},
			{
				"step_id": "receive_goods",
				"primitive": "TRANSFER_ITEM",
				"params": {
					"from": "PARAM.supplier_id",
					"to": "ORDER_ACTOR",
					"item_id": "PARAM.item_id",
					"quantity": "PARAM.amount",
					"transfer_time": 10.0,
					"transfer_fatigue": 0.02
				},
				"next_step": null
			}
		]
	}

	var res: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(world_state, directive, verb_def)

	if not res.get("success", false):
		printerr("[DIAGNOSTIC] Step 1 halted at '%s' with error: %s (code %d)" % [
			res.get("context", {}).get("halted_step", "UNKNOWN"),
			res.get("message", "No message"),
			res.get("error_code", -1)
		])

	assert(res.get("success", false) == true, "Expected pipeline to succeed! Halting reason: %s" % res.get("message", ""))
	
	var staff_entry: Dictionary = world_state["staff"]["OP_01"]
	var venue_entry: Dictionary = world_state["districts"]["DISTRICT_EAST"]["venues"]["VENUE_WHOLESALER"]

	assert(staff_entry["current_district_id"] == "DISTRICT_EAST", "Expected operative to be in DISTRICT_EAST")
	assert(staff_entry["inventory"]["CASH"] == 50.0, "Expected cash 100 - 50 = 50 in inventory, got: %f" % staff_entry["inventory"].get("CASH", 0.0))
	assert(staff_entry["inventory"]["BEER_KEG"] == 2.0, "Expected 2.0 BEER_KEG in operative inventory")
	assert(venue_entry["inventory"]["CASH"] == 250.0, "Expected venue cash 200 + 50 = 250, got: %f" % venue_entry["inventory"].get("CASH", 0.0))
	assert(staff_entry["shift_time_spent"] == 35.0, "Expected 20 + 5 + 10 = 35 mins spent, got: %f" % staff_entry["shift_time_spent"])
	assert(is_equal_approx(staff_entry["fatigue"], 0.07), "Expected 0.04 + 0.01 + 0.02 = 0.07 fatigue, got: %f" % staff_entry["fatigue"])

	print("  ✓ Nominal multi-step execution, physical cash/item transfers, and shift time verified.")
	return true

func test_gated_failure_with_penalties() -> bool:
	print("\n[STEP 2] Testing planning on margin & asymmetric failure penalties...")

	var world_state: Dictionary = _create_mock_world_state()
	# Operative only has £100 in physical inventory, but action requires £200
	var directive: Dictionary = {
		"verb": "BUY_LUXURY",
		"assigned_to": "OP_01",
		"target_node_id": "DISTRICT_NORTH",
		"item_id": "GOLD_WATCH",
		"amount": 1.0,
		"unit_cost": 200.0
	}

	var verb_def: Dictionary = {
		"_meta": { "verb_token": "BUY_LUXURY" },
		"steps": [
			{
				"step_id": "travel_to_shop",
				"primitive": "MOVE_ACTOR",
				"params": {
					"actor": "ORDER_ACTOR",
					"destination": "PARAM.target_node_id",
					"travel_time": 30.0,
					"travel_fatigue": 0.05
				},
				"next_step": "check_wallet"
			},
			{
				"step_id": "check_wallet",
				"primitive": "REQUIRE",
				"params": {
					"domain": "COMMODITY",
					"actor": "ORDER_ACTOR",
					"metric": "CASH",
					"operator": ">=",
					"value": "CALCULATED_TOTAL_COST"
				},
				"on_failure": {
					"error_code": "INSUFFICIENT_FUNDS",
					"penalties": {
						"extra_time_spent": 15.0, # Wasted 15 mins checking pockets/haggling
						"extra_fatigue": 0.03
					}
				},
				"next_step": "pay_shop"
			},
			{
				"step_id": "pay_shop",
				"primitive": "TRANSFER_ITEM",
				"params": {
					"from": "ORDER_ACTOR",
					"to": "PLAYER",
					"item_id": "CASH",
					"quantity": 200.0,
					"transfer_time": 5.0,
					"transfer_fatigue": 0.01
				},
				"next_step": null
			}
		]
	}

	var res: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(world_state, directive, verb_def)

	assert(res.get("success", false) == false, "Expected pipeline to fail at gate!")
	assert(res.get("error_code") == EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE, "Expected INSUFFICIENT_RESOURCE error code")

	var staff_entry: Dictionary = world_state["staff"]["OP_01"]
	# Operative must stay where they traveled to (DISTRICT_NORTH)
	assert(staff_entry["current_district_id"] == "DISTRICT_NORTH", "Expected operative to remain in DISTRICT_NORTH after bounce")
	# Cash was NOT deducted from physical inventory
	assert(staff_entry["inventory"]["CASH"] == 100.0, "Expected cash to remain £100 in inventory")
	# Travel time (30) + penalty delay (15) = 45 mins spent
	assert(staff_entry["shift_time_spent"] == 45.0, "Expected 30 + 15 = 45 mins, got: %f" % staff_entry["shift_time_spent"])
	# Travel fatigue (0.05) + penalty fatigue (0.03) = 0.08
	assert(is_equal_approx(staff_entry["fatigue"], 0.08), "Expected 0.08 fatigue, got: %f" % staff_entry["fatigue"])

	print("  ✓ Planning on margin verified: travel committed, penalty delays applied, downstream aborted.")
	return true

func test_fail_loud_on_missing_parameter() -> bool:
	print("\n[STEP 3] Testing fail-loud when step definition misses mandatory parameter...")

	var world_state: Dictionary = _create_mock_world_state()
	var directive: Dictionary = {
		"verb": "BAD_TRANSFER",
		"assigned_to": "OP_01",
		"target_node_id": "DISTRICT_WEST"
	}

	# Step misses 'transfer_time' and 'transfer_fatigue'
	var verb_def: Dictionary = {
		"_meta": { "verb_token": "BAD_TRANSFER" },
		"steps": [
			{
				"step_id": "bad_step",
				"primitive": "TRANSFER_ITEM",
				"params": {
					"from": "ORDER_ACTOR",
					"to": "PLAYER",
					"item_id": "CASH",
					"quantity": 10.0
				}
			}
		]
	}

	var res: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(world_state, directive, verb_def)

	assert(res.get("success", false) == false, "Expected bad step definition to fail loud!")
	assert("FAIL_LOUD" in str(res.get("message", "")), "Expected message to contain 'FAIL_LOUD'")

	print("  ✓ Strict fail-loud parameter enforcement verified.")
	return true

func _create_mock_world_state() -> Dictionary:
	return {
		"inventory": {
			"CASH": 1000.0
		},
		"staff": {
			"OP_01": {
				"resident_id": "RES_OP_01",
				"current_district_id": "DISTRICT_CENTRAL",
				"fatigue": 0.0,
				"shift_time_spent": 0.0,
				"inventory": {
					"CASH": 100.0
				}
			}
		},
		"districts": {
			"DISTRICT_EAST": {
				"venues": {
					"VENUE_WHOLESALER": {
						"inventory": {
							"CASH": 200.0,
							"BEER_KEG": 10.0
						}
					}
				}
			},
			"DISTRICT_NORTH": {
				"venues": {}
			}
		}
	}