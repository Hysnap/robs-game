# res://tests/test_live_rest_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative REST Verb Definition ---")
	var passed: bool = true

	passed = passed and test_rest_mounting()
	passed = passed and test_rest_success()
	passed = passed and test_rest_invalid_actor_gate()

	if passed:
		print("--- [Test] DECLARATIVE REST VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE REST VERB VERIFICATION FAILED ---\n")
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
			},
			"ghost_op": {
				"name": "Unassigned Ghost",
				"current_district_id": "",
				"inventory": {}
			}
		},
		"establishments": {},
		"caches": {},
		"districts": {
			"DISTRICT_MARKET": {}
		}
	}

func test_rest_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("REST"):
		printerr("FAIL: VerbRouter failed to discover and mount 'REST'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'REST'.")
	return true

func test_rest_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "REST",
		"assigned_to": "op_01",
		"duration_ticks": 2.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: REST dispatch failed unexpectedly: ", res.get("message"))
		return false

	# Verify state was untouched
	var loc: String = str(ws["residents"]["op_01"].get("current_district_id", ""))
	var cash: float = float(ws["residents"]["op_01"]["inventory"].get("CASH", 0.0))

	if loc != "DISTRICT_MARKET" or not is_equal_approx(cash, 100.0):
		printerr("FAIL: REST corrupted resident state. loc: %s, cash: %f" % [loc, cash])
		return false

	print("PASS: REST executed cleanly without state side-effects.")
	return true

func test_rest_invalid_actor_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "REST",
		"assigned_to": "ghost_op",
		"duration_ticks": 1.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected REST to halt on unplaced/invalid actor.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET for invalid actor, got: ", err_code)
		return false

	print("PASS: REST correctly halted on invalid/unplaced actor with INVALID_TARGET.")
	return true