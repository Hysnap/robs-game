# res://tests/test_live_inform_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative INFORM Verb Definition ---")
	var passed: bool = true

	passed = passed and test_inform_mounting()
	passed = passed and test_inform_success()
	passed = passed and test_inform_operative_location_mismatch_gate()
	passed = passed and test_inform_target_recipient_away_gate()

	if passed:
		print("--- [Test] DECLARATIVE INFORM VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE INFORM VERB VERIFICATION FAILED ---\n")
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
				"name": "Arthur Shelby",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 50.0
				}
			},
			"res_contact_01": {
				"name": "Handler Vance",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {}
			},
			"res_away_01": {
				"name": "Inspector Campbell",
				"current_district_id": "DISTRICT_SUBURBS",
				"inventory": {}
			}
		},
		"establishments": {},
		"caches": {},
		"districts": {
			"DISTRICT_MARKET": {},
			"DISTRICT_HQ": {},
			"DISTRICT_SUBURBS": {}
		}
	}

func test_inform_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("INFORM"):
		printerr("FAIL: VerbRouter failed to discover and mount 'INFORM'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'INFORM'.")
	return true

func test_inform_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "INFORM",
		"assigned_to": "op_01",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 1.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: INFORM dispatch failed unexpectedly: ", res.get("message"))
		return false

	# Assert state purity: locations preserved and inventories untouched
	var op_loc: String = str(ws["residents"]["op_01"].get("current_district_id", ""))
	var contact_loc: String = str(ws["residents"]["res_contact_01"].get("current_district_id", ""))
	var op_cash: float = float(ws["residents"]["op_01"]["inventory"].get("CASH", 0.0))

	if op_loc != "DISTRICT_MARKET" or contact_loc != "DISTRICT_MARKET" or not is_equal_approx(op_cash, 100.0):
		printerr("FAIL: INFORM mutated state unexpectedly.")
		return false

	print("PASS: INFORM executed cleanly when both actors were co-present.")
	return true

func test_inform_operative_location_mismatch_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "INFORM",
		"assigned_to": "op_02", # In DISTRICT_HQ
		"target_resident_id": "res_contact_01", # In DISTRICT_MARKET
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 1.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected INFORM to halt when operative is not in target district.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET for operative location mismatch, got: ", err_code)
		return false

	print("PASS: INFORM halted at Step 1 when operative was not at target location.")
	return true

func test_inform_target_recipient_away_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "INFORM",
		"assigned_to": "op_01", # In DISTRICT_MARKET
		"target_resident_id": "res_away_01", # In DISTRICT_SUBURBS
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 1.0
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected INFORM to halt when recipient contact is not in target district.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET when recipient is away, got: ", err_code)
		return false

	print("PASS: INFORM halted at Step 2 when target recipient was away from meeting place.")
	return true