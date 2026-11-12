# res://tests/test_live_receive_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative RECEIVE Verb Definition ---")
	var passed: bool = true

	passed = passed and test_receive_mounting()
	passed = passed and test_receive_commodity_success()
	passed = passed and test_receive_insufficient_stock_gate()
	passed = passed and test_receive_location_mismatch_gate()

	if passed:
		print("--- [Test] DECLARATIVE RECEIVE VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE RECEIVE VERB VERIFICATION FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"staff": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 10.0,
					"CIGARETTES_UNFILTERED": 0.0
				}
			},
			"op_02": {
				"name": "Arthur Shelby",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 0.0
				}
			}
		},
		"counterparties": {
			"source_01": {
				"name": "Digbeth Wholesalers",
				"inventory": {
					"CASH": 100.0,
					"CIGARETTES_UNFILTERED": 10.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": { "venues": {} },
			"DISTRICT_HQ": { "venues": {} }
		}
	}

func test_receive_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("RECEIVE"):
		printerr("FAIL: VerbRouter failed to discover and mount 'RECEIVE'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'RECEIVE'.")
	return true

func test_receive_commodity_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "RECEIVE",
		"assigned_to": "op_01",
		"source_id": "source_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 4.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: RECEIVE dispatch failed unexpectedly: ", res.get("message"))
		return false

	var op_cigs: float = float(ws["staff"]["op_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))
	var src_cigs: float = float(ws["counterparties"]["source_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))

	if not is_equal_approx(op_cigs, 4.0) or not is_equal_approx(src_cigs, 6.0):
		printerr("FAIL: Inventories corrupted after RECEIVE. Receiver: %f, Source: %f" % [op_cigs, src_cigs])
		return false

	print("PASS: RECEIVE executed successfully, commodity transferred cleanly.")
	return true

func test_receive_insufficient_stock_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "RECEIVE",
		"assigned_to": "op_01",
		"source_id": "source_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 50.0, # Source only holds 10.0
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected RECEIVE to halt on source insufficient stock.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE, got: ", err_code)
		return false

	print("PASS: RECEIVE correctly halted on insufficient stock with INSUFFICIENT_RESOURCE.")
	return true

func test_receive_location_mismatch_gate() -> bool:
	var ws := _create_fixture_state()
	# op_02 is at DISTRICT_HQ, but target_node_id is DISTRICT_MARKET
	var directive := {
		"verb": "RECEIVE",
		"assigned_to": "op_02",
		"source_id": "source_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 2.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected RECEIVE to halt on location mismatch.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET on location mismatch, got: ", err_code)
		return false

	print("PASS: RECEIVE correctly halted on location mismatch with INVALID_TARGET.")
	return true