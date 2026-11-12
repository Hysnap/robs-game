# res://tests/test_live_consume_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative CONSUME Verb Definition ---")
	var passed: bool = true

	passed = passed and test_consume_mounting()
	passed = passed and test_consume_success()
	passed = passed and test_consume_insufficient_stock_gate()

	if passed:
		print("--- [Test] DECLARATIVE CONSUME VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE CONSUME VERB VERIFICATION FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"residents": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 100.0,
					"BEER_BOTTLE": 5.0
				}
			}
		},
		"establishments": {},
		"caches": {},
		"districts": {
			"DISTRICT_MARKET": {}
		}
	}

func test_consume_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("CONSUME"):
		printerr("FAIL: VerbRouter failed to discover and mount 'CONSUME'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'CONSUME'.")
	return true

func test_consume_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "CONSUME",
		"assigned_to": "op_01",
		"item_id": "BEER_BOTTLE",
		"amount": 2.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: CONSUME dispatch failed unexpectedly: ", res.get("message"))
		return false

	var op_beer: float = float(ws["residents"]["op_01"]["inventory"].get("BEER_BOTTLE", 0.0))
	if not is_equal_approx(op_beer, 3.0):
		printerr("FAIL: Expected 3.0 remaining after CONSUME, got: %f" % op_beer)
		return false

	print("PASS: CONSUME executed successfully, items consumed and deducted cleanly.")
	return true

func test_consume_insufficient_stock_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "CONSUME",
		"assigned_to": "op_01",
		"item_id": "BEER_BOTTLE",
		"amount": 10.0 # op_01 only possesses 5.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected CONSUME to halt on insufficient stock.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE, got: ", err_code)
		return false

	print("PASS: CONSUME correctly halted on insufficient stock with INSUFFICIENT_RESOURCE.")
	return true