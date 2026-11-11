# res://tests/test_action_primitives_pipeline.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const ActionPrimitivesScript = preload("res://systems/action_pipeline/action_primitives.gd")
const ActionPipelineRunnerScript = preload("res://systems/action_pipeline/action_pipeline_runner.gd")

func _init() -> void:
	print("\n--- [Test] Starting Pure Primitives & Action Pipeline Stress Suite ---")
	var passed: bool = true

	passed = passed and test_primitive_require_commodity()
	passed = passed and test_primitive_require_location()
	passed = passed and test_primitive_require_attribute()
	passed = passed and test_primitive_move_actor()
	passed = passed and test_primitive_transfer_item()
	passed = passed and test_pipeline_pure_buy_success()
	passed = passed and test_pipeline_gate_failures()

	if passed:
		print("--- [Test] ALL PRIMITIVE & PIPELINE STRESS TESTS PASSED ---\n")
		quit(0)
	else:
		printerr("--- [Test] PRIMITIVE & PIPELINE STRESS TESTS FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"staff": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"fatigue": 15.0,
				"inventory": {
					"CASH": 50.0,
					"BEER_KEG": 2.0
				}
			},
			"op_02": {
				"name": "Sarah Connor",
				"current_district_id": "DISTRICT_HQ",
				"fatigue": 0.0,
				"inventory": {
					"CASH": 0.0
				}
			}
		},
		"counterparties": {
			"supplier_01": {
				"name": "Digbeth Wholesalers",
				"inventory": {
					"CASH": 100.0,
					"BEER_KEG": 20.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": {
				"venues": {}
			},
			"DISTRICT_HQ": {
				"venues": {}
			}
		}
	}

# -----------------------------------------------------------------------------
# 1. Micro-Verb Primitives Tests
# -----------------------------------------------------------------------------

func test_primitive_require_commodity() -> bool:
	var ws := _create_fixture_state()
	var directive := {}

	# Pass case
	var p_pass := { "actor": "op_01", "domain": "COMMODITY", "metric": "CASH", "operator": ">=", "value": 50.0 }
	var res_pass: Dictionary = ActionPrimitivesScript.dispatch("REQUIRE", ws, directive, p_pass, "req_1")
	if not res_pass.get("success", false):
		printerr("FAIL: REQUIRE commodity should have passed for op_01 holding 50.0 CASH.")
		return false

	# Insufficient case
	var p_fail := { "actor": "op_01", "domain": "COMMODITY", "metric": "CASH", "operator": ">=", "value": 50.01 }
	var res_fail: Dictionary = ActionPrimitivesScript.dispatch("REQUIRE", ws, directive, p_fail, "req_2")
	if res_fail.get("success", false):
		printerr("FAIL: REQUIRE commodity should have failed for op_01 requiring 50.01 CASH.")
		return false

	# Unheld item case
	var p_unheld := { "actor": "op_01", "domain": "COMMODITY", "metric": "WHISKEY", "operator": ">=", "value": 1.0 }
	var res_unheld: Dictionary = ActionPrimitivesScript.dispatch("REQUIRE", ws, directive, p_unheld, "req_3")
	if res_unheld.get("success", false):
		printerr("FAIL: REQUIRE commodity should have failed for unheld item WHISKEY.")
		return false

	print("PASS: Primitive REQUIRE (COMMODITY domain) gates validated.")
	return true

func test_primitive_require_location() -> bool:
	var ws := _create_fixture_state()
	var directive := { "target_node_id": "DISTRICT_MARKET" }

	# Pass case
	var p_pass := { "actor": "op_01", "domain": "LOCATION", "metric": "current_district_id", "operator": "==", "value": "DISTRICT_MARKET" }
	var res_pass: Dictionary = ActionPrimitivesScript.dispatch("REQUIRE", ws, directive, p_pass, "loc_1")
	if not res_pass.get("success", false):
		printerr("FAIL: REQUIRE location should have passed for op_01 at DISTRICT_MARKET.")
		return false

	# Location mismatch case
	var p_fail := { "actor": "op_02", "domain": "LOCATION", "metric": "current_district_id", "operator": "==", "value": "DISTRICT_MARKET" }
	var res_fail: Dictionary = ActionPrimitivesScript.dispatch("REQUIRE", ws, directive, p_fail, "loc_2")
	if res_fail.get("success", false):
		printerr("FAIL: REQUIRE location should have failed for op_02 located at DISTRICT_HQ.")
		return false

	print("PASS: Primitive REQUIRE (LOCATION domain) gates validated.")
	return true

func test_primitive_require_attribute() -> bool:
	var ws := _create_fixture_state()
	var directive := {}

	# Pass case: op_01 fatigue <= 20.0
	var p_pass := { "actor": "op_01", "domain": "ATTRIBUTE", "metric": "fatigue", "operator": "<=", "value": 20.0 }
	var res_pass: Dictionary = ActionPrimitivesScript.dispatch("REQUIRE", ws, directive, p_pass, "attr_1")
	if not res_pass.get("success", false):
		printerr("FAIL: REQUIRE attribute should have passed for op_01 fatigue <= 20.0.")
		return false

	# Fail case: op_01 fatigue <= 10.0
	var p_fail := { "actor": "op_01", "domain": "ATTRIBUTE", "metric": "fatigue", "operator": "<=", "value": 10.0 }
	var res_fail: Dictionary = ActionPrimitivesScript.dispatch("REQUIRE", ws, directive, p_fail, "attr_2")
	if res_fail.get("success", false):
		printerr("FAIL: REQUIRE attribute should have failed for op_01 fatigue <= 10.0.")
		return false

	print("PASS: Primitive REQUIRE (ATTRIBUTE domain) gates validated.")
	return true

func test_primitive_move_actor() -> bool:
	var ws := _create_fixture_state()
	var directive := {}

	var p_move := { "actor": "op_02", "destination": "DISTRICT_MARKET" }
	var res_move: Dictionary = ActionPrimitivesScript.dispatch("MOVE_ACTOR", ws, directive, p_move, "move_1")
	if not res_move.get("success", false):
		printerr("FAIL: MOVE_ACTOR failed unexpectedly.")
		return false

	var new_loc: String = ws["staff"]["op_02"]["current_district_id"]
	if new_loc != "DISTRICT_MARKET":
		printerr("FAIL: MOVE_ACTOR failed to migrate op_02 to DISTRICT_MARKET, found: ", new_loc)
		return false

	print("PASS: Primitive MOVE_ACTOR spatial migration validated.")
	return true

func test_primitive_transfer_item() -> bool:
	var ws := _create_fixture_state()
	var directive := {}

	# Transfer 20.0 CASH from op_01 to op_02
	var p_xfer := { "from": "op_01", "to": "op_02", "item_id": "CASH", "quantity": 20.0 }
	var res_xfer: Dictionary = ActionPrimitivesScript.dispatch("TRANSFER_ITEM", ws, directive, p_xfer, "xfer_1")
	if not res_xfer.get("success", false):
		printerr("FAIL: TRANSFER_ITEM failed unexpectedly.")
		return false

	var op1_cash: float = float(ws["staff"]["op_01"]["inventory"].get("CASH", 0.0))
	var op2_cash: float = float(ws["staff"]["op_02"]["inventory"].get("CASH", 0.0))

	if not is_equal_approx(op1_cash, 30.0) or not is_equal_approx(op2_cash, 20.0):
		printerr("FAIL: Balances wrong after TRANSFER_ITEM. op1: %f, op2: %f" % [op1_cash, op2_cash])
		return false

	print("PASS: Primitive TRANSFER_ITEM pure commodity handover validated.")
	return true

# -----------------------------------------------------------------------------
# 2. Sequential ActionPipelineRunner Tests
# -----------------------------------------------------------------------------

func _get_pure_buy_definition() -> Dictionary:
	return {
		"_meta": { "verb_token": "BUY" },
		"steps": [
			{
				"step_id": "gate_solvency",
				"primitive": "REQUIRE",
				"params": {
					"domain": "COMMODITY",
					"actor": "ORDER_ACTOR",
					"metric": "CASH",
					"operator": ">=",
					"value": "CALCULATED_TOTAL_COST"
				},
				"on_failure": { "error_code": "INSUFFICIENT_RESOURCE" }
			},
			{
				"step_id": "gate_co_location",
				"primitive": "REQUIRE",
				"params": {
					"domain": "LOCATION",
					"actor": "ORDER_ACTOR",
					"metric": "current_district_id",
					"operator": "==",
					"value": "TARGET_NODE"
				},
				"on_failure": { "error_code": "INVALID_TARGET" }
			},
			{
				"step_id": "gate_stock",
				"primitive": "REQUIRE",
				"params": {
					"domain": "COMMODITY",
					"actor": "PARAM.supplier_id",
					"metric": "PARAM.item_id",
					"operator": ">=",
					"value": "PARAM.amount"
				},
				"on_failure": { "error_code": "OUT_OF_STOCK" }
			},
			{
				"step_id": "pay_cash",
				"primitive": "TRANSFER_ITEM",
				"params": {
					"from": "ORDER_ACTOR",
					"to": "PARAM.supplier_id",
					"item_id": "CASH",
					"quantity": "CALCULATED_TOTAL_COST"
				}
			},
			{
				"step_id": "receive_commodity",
				"primitive": "TRANSFER_ITEM",
				"params": {
					"from": "PARAM.supplier_id",
					"to": "ORDER_ACTOR",
					"item_id": "PARAM.item_id",
					"quantity": "PARAM.amount"
				}
			}
		]
	}

func test_pipeline_pure_buy_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "BUY",
		"assigned_to": "op_01",
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 5.0,
		"unit_cost": 4.0, # Total cost: 20.0
		"target_node_id": "DISTRICT_MARKET"
	}
	var verb_def := _get_pure_buy_definition()

	var result: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws, directive, verb_def)
	if not result.get("success", false):
		printerr("FAIL: Pure BUY pipeline failed: ", result.get("message"))
		return false

	var op_cash: float = float(ws["staff"]["op_01"]["inventory"].get("CASH", 0.0))
	var op_beer: float = float(ws["staff"]["op_01"]["inventory"].get("BEER_KEG", 0.0))
	var sup_cash: float = float(ws["counterparties"]["supplier_01"]["inventory"].get("CASH", 0.0))
	var sup_beer: float = float(ws["counterparties"]["supplier_01"]["inventory"].get("BEER_KEG", 0.0))

	# op_01 started with 50 CASH, 2 BEER. Paid 20 CASH, received 5 BEER -> 30 CASH, 7 BEER
	# supplier started with 100 CASH, 20 BEER -> 120 CASH, 15 BEER
	if not is_equal_approx(op_cash, 30.0) or not is_equal_approx(op_beer, 7.0):
		printerr("FAIL: Buyer post-BUY state corrupted. Cash: %f, Beer: %f" % [op_cash, op_beer])
		return false
	if not is_equal_approx(sup_cash, 120.0) or not is_equal_approx(sup_beer, 15.0):
		printerr("FAIL: Supplier post-BUY state corrupted. Cash: %f, Beer: %f" % [sup_cash, sup_beer])
		return false

	print("PASS: Pure BUY declarative pipeline execution succeeded completely.")
	return true

func test_pipeline_gate_failures() -> bool:
	var verb_def := _get_pure_buy_definition()

	# 1. Insolvency Failure Gate
	var ws1 := _create_fixture_state()
	var dir_insolvent := {
		"verb": "BUY",
		"assigned_to": "op_01",
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 100.0,
		"unit_cost": 4.0, # Total cost: 400.0 (op_01 has 50.0)
		"target_node_id": "DISTRICT_MARKET"
	}
	var res1: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws1, dir_insolvent, verb_def)
	if res1.get("success", true):
		printerr("FAIL: Pipeline should have rejected insolvent BUY.")
		return false
	if int(res1.get("error_code", -1)) != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE on solvency bounce, got: ", res1.get("error_code"))
		return false

	# 2. Location Mismatch Failure Gate
	var ws2 := _create_fixture_state()
	var dir_wrong_loc := {
		"verb": "BUY",
		"assigned_to": "op_02", # Located at DISTRICT_HQ
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 1.0,
		"unit_cost": 0.0,
		"target_node_id": "DISTRICT_MARKET" # Buyer is not here
	}
	var res2: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws2, dir_wrong_loc, verb_def)
	if res2.get("success", true):
		printerr("FAIL: Pipeline should have rejected un-colocated BUY.")
		return false
	if int(res2.get("error_code", -1)) != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET on co-location bounce, got: ", res2.get("error_code"))
		return false

	# 3. Out of Stock Failure Gate
	var ws3 := _create_fixture_state()
	var dir_out_of_stock := {
		"verb": "BUY",
		"assigned_to": "op_01",
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 500.0, # Supplier only has 20.0
		"unit_cost": 0.0,
		"target_node_id": "DISTRICT_MARKET"
	}
	var res3: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws3, dir_out_of_stock, verb_def)
	if res3.get("success", true):
		printerr("FAIL: Pipeline should have rejected out-of-stock BUY.")
		return false
	if int(res3.get("error_code", -1)) != EngineResultScript.ErrorCode.OUT_OF_STOCK:
		printerr("FAIL: Expected OUT_OF_STOCK on inventory bounce, got: ", res3.get("error_code"))
		return false

	print("PASS: Pipeline early-halt gates and ErrorCode mappings verified loud and clear.")
	return true