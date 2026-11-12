# res://tests/test_live_travel_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative TRAVEL Verb Definition ---")
	var passed: bool = true

	passed = passed and test_travel_mounting()
	passed = passed and test_travel_success()
	passed = passed and test_travel_redundant_gate_fail()

	if passed:
		print("--- [Test] DECLARATIVE TRAVEL VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE TRAVEL VERB VERIFICATION FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"staff": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {}
			}
		},
		"districts": {
			"DISTRICT_HQ": { "venues": {} },
			"DISTRICT_MARKET": { "venues": {} }
		}
	}

func test_travel_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("TRAVEL"):
		printerr("FAIL: VerbRouter failed to discover and mount 'TRAVEL'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'TRAVEL'.")
	return true

func test_travel_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "TRAVEL",
		"assigned_to": "op_01",
		"destination_district_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: TRAVEL dispatch failed unexpectedly: ", res.get("message"))
		return false

	var new_loc: String = ws["staff"]["op_01"].get("current_district_id", "")
	if new_loc != "DISTRICT_MARKET":
		printerr("FAIL: Operative failed to move to DISTRICT_MARKET. Current: ", new_loc)
		return false

	print("PASS: TRAVEL executed successfully, operative relocated to destination.")
	return true

func test_travel_redundant_gate_fail() -> bool:
	var ws := _create_fixture_state()
	# Mick Jenkins starts at DISTRICT_HQ; attempt to travel to DISTRICT_HQ
	var directive := {
		"verb": "TRAVEL",
		"assigned_to": "op_01",
		"destination_district_id": "DISTRICT_HQ"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Redundant TRAVEL should have halted at gate_not_already_at_dest.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_PARAMETER:
		printerr("FAIL: Expected INVALID_PARAMETER, got: ", err_code)
		return false

	print("PASS: Redundant TRAVEL halted at gate_not_already_at_dest with INVALID_PARAMETER.")
	return true