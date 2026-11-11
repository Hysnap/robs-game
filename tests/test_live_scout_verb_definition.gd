# res://tests/test_live_scout_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative SCOUT Verb Definition ---")
	var passed: bool = true

	passed = passed and test_scout_mounting()
	passed = passed and test_scout_success()
	passed = passed and test_scout_location_mismatch_gate()

	if passed:
		print("--- [Test] DECLARATIVE SCOUT VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE SCOUT VERB VERIFICATION FAILED ---\n")
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
			"op_02": {
				"name": "Tommy Shelby",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 50.0
				}
			}
		},
		"establishments": {},
		"caches": {},
		"districts": {
			"DISTRICT_MARKET": {},
			"DISTRICT_HQ": {}
		}
	}

func test_scout_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("SCOUT"):
		printerr("FAIL: VerbRouter failed to discover and mount 'SCOUT'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'SCOUT'.")
	return true

func test_scout_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "SCOUT",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 2.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: SCOUT dispatch failed unexpectedly: ", res.get("message"))
		return false

	# Assert state purity: location preserved, no inventory or cash deducted
	var loc: String = str(ws["residents"]["op_01"].get("current_district_id", ""))
	var cash: float = float(ws["residents"]["op_01"]["inventory"].get("CASH", 0.0))
	var cigs: float = float(ws["residents"]["op_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))

	if loc != "DISTRICT_MARKET" or not is_equal_approx(cash, 100.0) or not is_equal_approx(cigs, 10.0):
		printerr("FAIL: SCOUT mutated resident state unexpectedly.")
		return false

	print("PASS: SCOUT executed cleanly with zero side-effects.")
	return true

func test_scout_location_mismatch_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "SCOUT",
		"assigned_to": "op_02", # In DISTRICT_HQ
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 1.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected SCOUT to halt on location mismatch.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET for location mismatch, got: ", err_code)
		return false

	print("PASS: SCOUT correctly halted on location mismatch with INVALID_TARGET.")
	return true