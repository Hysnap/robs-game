# res://tests/test_live_give_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative GIVE Verb Definition ---")
	var passed: bool = true

	passed = passed and test_give_mounting()
	passed = passed and test_give_commodity_success()
	passed = passed and test_give_insufficient_stock_gate()
	passed = passed and test_give_location_mismatch_gate()

	if passed:
		print("--- [Test] DECLARATIVE GIVE VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE GIVE VERB VERIFICATION FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"staff": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 50.0,
					"BEER_KEG": 5.0
				}
			},
			"op_02": {
				"name": "Sarah Connor",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 10.0,
					"BEER_KEG": 0.0
				}
			},
			"op_03": {
				"name": "Arthur Shelby",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 50.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": { "venues": {} },
			"DISTRICT_HQ": { "venues": {} }
		}
	}

func test_give_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("GIVE"):
		printerr("FAIL: VerbRouter failed to discover and mount 'GIVE'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'GIVE'.")
	return true

func test_give_commodity_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "GIVE",
		"assigned_to": "op_01",
		"recipient_id": "op_02",
		"item_id": "BEER_KEG",
		"amount": 2.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: GIVE dispatch failed unexpectedly: ", res.get("message"))
		return false

	var sender_beer: float = float(ws["staff"]["op_01"]["inventory"].get("BEER_KEG", 0.0))
	var recipient_beer: float = float(ws["staff"]["op_02"]["inventory"].get("BEER_KEG", 0.0))

	if not is_equal_approx(sender_beer, 3.0) or not is_equal_approx(recipient_beer, 2.0):
		printerr("FAIL: Inventories corrupted after GIVE. Sender: %f, Recipient: %f" % [sender_beer, recipient_beer])
		return false

	print("PASS: GIVE executed successfully, commodity transferred cleanly.")
	return true

func test_give_insufficient_stock_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "GIVE",
		"assigned_to": "op_01",
		"recipient_id": "op_02",
		"item_id": "BEER_KEG",
		"amount": 10.0, # op_01 only holds 5.0
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected GIVE to halt on insufficient stock.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE, got: ", err_code)
		return false

	print("PASS: GIVE correctly halted on insufficient stock with INSUFFICIENT_RESOURCE.")
	return true

func test_give_location_mismatch_gate() -> bool:
	var ws := _create_fixture_state()
	# op_03 has 50.0 CASH and is at DISTRICT_HQ, but target_node_id is DISTRICT_MARKET
	var directive := {
		"verb": "GIVE",
		"assigned_to": "op_03",
		"recipient_id": "op_02",
		"item_id": "CASH",
		"amount": 10.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected GIVE to halt on location mismatch.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET on location mismatch, got: ", err_code)
		return false

	print("PASS: GIVE correctly halted on location mismatch with INVALID_TARGET.")
	return true