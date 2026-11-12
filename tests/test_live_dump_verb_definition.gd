# res://tests/test_live_dump_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative DUMP Verb Definition ---")
	var passed: bool = true

	passed = passed and test_dump_mounting()
	passed = passed and test_dump_success()
	passed = passed and test_dump_insufficient_stock_gate()

	if passed:
		print("--- [Test] DECLARATIVE DUMP VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE DUMP VERB VERIFICATION FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"residents": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 100.0,
					"CIGARETTES_UNFILTERED": 10.0
				}
			}
		},
		"establishments": {},
		"caches": {},
		"districts": {
			"DISTRICT_MARKET": {}
		}
	}

func test_dump_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("DUMP"):
		printerr("FAIL: VerbRouter failed to discover and mount 'DUMP'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'DUMP'.")
	return true

func test_dump_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "DUMP",
		"assigned_to": "op_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 4.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: DUMP dispatch failed unexpectedly: ", res.get("message"))
		return false

	var op_cigs: float = float(ws["residents"]["op_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))
	if not is_equal_approx(op_cigs, 6.0):
		printerr("FAIL: Expected 6.0 remaining after DUMP, got: %f" % op_cigs)
		return false

	print("PASS: DUMP executed successfully, items deducted cleanly.")
	return true

func test_dump_insufficient_stock_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "DUMP",
		"assigned_to": "op_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 20.0 # op_01 only possesses 10.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected DUMP to halt on insufficient stock.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE, got: ", err_code)
		return false

	print("PASS: DUMP correctly halted on insufficient stock with INSUFFICIENT_RESOURCE.")
	return true