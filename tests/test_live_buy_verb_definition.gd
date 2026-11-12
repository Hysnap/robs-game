# res://tests/test_live_buy_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const ActionPipelineRunnerScript = preload("res://systems/action_pipeline/action_pipeline_runner.gd")

const BUY_DEF_PATH := "res://data_modules/core/verbs/buy/verb_definition.json"

func _init() -> void:
	print("\n--- [Test] Verifying Live Disk Definition: verb_definition.json ---")
	var passed: bool = true

	passed = passed and test_file_exists_and_parses()
	passed = passed and test_live_buy_execution_success()
	passed = passed and test_live_buy_insolvency_gate()
	passed = passed and test_live_buy_location_gate()
	passed = passed and test_live_buy_out_of_stock_gate()

	if passed:
		print("--- [Test] LIVE BUY VERB DEFINITION FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] LIVE BUY VERB DEFINITION VERIFICATION FAILED ---\n")
		quit(1)

func _load_live_verb_def() -> Dictionary:
	assert(FileAccess.file_exists(BUY_DEF_PATH), "FATAL: Missing live verb definition at: %s" % BUY_DEF_PATH)
	var file := FileAccess.open(BUY_DEF_PATH, FileAccess.READ)
	assert(file != null, "FATAL: Could not read file at: %s" % BUY_DEF_PATH)
	var content := file.get_as_text()
	var parsed = JSON.parse_string(content)
	assert(parsed is Dictionary, "FATAL: Failed to parse JSON from: %s" % BUY_DEF_PATH)
	return parsed

func _create_fixture_state() -> Dictionary:
	return {
		"staff": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 100.0,
					"BEER_KEG": 0.0
				}
			},
			"op_02": {
				"name": "Sarah Connor",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 100.0,
					"BEER_KEG": 0.0
				}
			}
		},
		"counterparties": {
			"supplier_01": {
				"name": "Digbeth Wholesalers",
				"inventory": {
					"CASH": 50.0,
					"BEER_KEG": 10.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": { "venues": {} },
			"DISTRICT_HQ": { "venues": {} }
		}
	}

func test_file_exists_and_parses() -> bool:
	var def := _load_live_verb_def()
	if str(def.get("_meta", {}).get("verb_token", "")) != "BUY":
		printerr("FAIL: Live definition _meta.verb_token is not 'BUY'.")
		return false

	var steps: Array = def.get("steps", [])
	if steps.size() != 5:
		printerr("FAIL: Expected exactly 5 declarative steps in pure BUY definition, found: ", steps.size())
		return false

	print("PASS: Live verb_definition.json exists, parsed, and has 5 pure steps.")
	return true

func test_live_buy_execution_success() -> bool:
	var ws := _create_fixture_state()
	var verb_def := _load_live_verb_def()
	var directive := {
		"verb": "BUY",
		"assigned_to": "op_01",
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 2.0,
		"unit_cost": 25.0, # Total: 50.0 CASH
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws, directive, verb_def)
	if not res.get("success", false):
		printerr("FAIL: Live BUY pipeline failed: ", res.get("message"))
		return false

	var buyer_cash: float = float(ws["staff"]["op_01"]["inventory"].get("CASH", 0.0))
	var buyer_beer: float = float(ws["staff"]["op_01"]["inventory"].get("BEER_KEG", 0.0))
	var sup_cash: float = float(ws["counterparties"]["supplier_01"]["inventory"].get("CASH", 0.0))
	var sup_beer: float = float(ws["counterparties"]["supplier_01"]["inventory"].get("BEER_KEG", 0.0))

	if not is_equal_approx(buyer_cash, 50.0) or not is_equal_approx(buyer_beer, 2.0):
		printerr("FAIL: Buyer post-BUY balances incorrect. Cash: %f, Beer: %f" % [buyer_cash, buyer_beer])
		return false
	if not is_equal_approx(sup_cash, 100.0) or not is_equal_approx(sup_beer, 8.0):
		printerr("FAIL: Supplier post-BUY balances incorrect. Cash: %f, Beer: %f" % [sup_cash, sup_beer])
		return false

	print("PASS: Live BUY execution succeeded with physical cash & commodity balances verified.")
	return true

func test_live_buy_insolvency_gate() -> bool:
	var ws := _create_fixture_state()
	var verb_def := _load_live_verb_def()
	var directive := {
		"verb": "BUY",
		"assigned_to": "op_01",
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 10.0,
		"unit_cost": 25.0, # Total: 250.0 CASH (buyer only has 100.0)
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws, directive, verb_def)
	if res.get("success", true):
		printerr("FAIL: Insolvent buyer should have been rejected at gate_cash.")
		return false
	if int(res.get("error_code", -1)) != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE error code, got: ", res.get("error_code"))
		return false

	print("PASS: Live gate_cash correctly halted insolvent order with INSUFFICIENT_RESOURCE.")
	return true

func test_live_buy_location_gate() -> bool:
	var ws := _create_fixture_state()
	var verb_def := _load_live_verb_def()
	var directive := {
		"verb": "BUY",
		"assigned_to": "op_02", # Operative is at DISTRICT_HQ
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 1.0,
		"unit_cost": 10.0,
		"target_node_id": "DISTRICT_MARKET" # Buyer is not co-located here
	}

	var res: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws, directive, verb_def)
	if res.get("success", true):
		printerr("FAIL: Co-location gate should have rejected operative outside market.")
		return false
	if int(res.get("error_code", -1)) != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET error code on location mismatch, got: ", res.get("error_code"))
		return false

	print("PASS: Live gate_co_location correctly halted order with INVALID_TARGET.")
	return true

func test_live_buy_out_of_stock_gate() -> bool:
	var ws := _create_fixture_state()
	var verb_def := _load_live_verb_def()
	var directive := {
		"verb": "BUY",
		"assigned_to": "op_01",
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 50.0, # Supplier only has 10.0
		"unit_cost": 1.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = ActionPipelineRunnerScript.run_action_pipeline(ws, directive, verb_def)
	if res.get("success", true):
		printerr("FAIL: Out-of-stock gate should have rejected order exceeding supplier stock.")
		return false
	if int(res.get("error_code", -1)) != EngineResultScript.ErrorCode.OUT_OF_STOCK:
		printerr("FAIL: Expected OUT_OF_STOCK error code, got: ", res.get("error_code"))
		return false

	print("PASS: Live verify_stock correctly halted order with OUT_OF_STOCK.")
	return true