# res://tests/test_live_store_items_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative STORE_ITEMS Verb Definition ---")
	var passed: bool = true

	passed = passed and test_store_items_mounting()
	passed = passed and test_store_items_success()
	passed = passed and test_store_items_insufficient_stock_gate()
	passed = passed and test_store_items_location_mismatch_gate()

	if passed:
		print("--- [Test] DECLARATIVE STORE_ITEMS VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE STORE_ITEMS VERB VERIFICATION FAILED ---\n")
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
					"CASH": 50.0,
					"CIGARETTES_UNFILTERED": 5.0
				}
			}
		},
		"establishments": {
			"venue_vault_01": {
				"name": "Market Stash Vault",
				"district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 50.0,
					"CIGARETTES_UNFILTERED": 0.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": {},
			"DISTRICT_HQ": {}
		}
	}

func test_store_items_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("STORE_ITEMS"):
		printerr("FAIL: VerbRouter failed to discover and mount 'STORE_ITEMS'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'STORE_ITEMS'.")
	return true

func test_store_items_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "STORE_ITEMS",
		"assigned_to": "op_01",
		"venue_id": "venue_vault_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 6.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: STORE_ITEMS dispatch failed unexpectedly: ", res.get("message"))
		return false

	var op_cigs: float = float(ws["residents"]["op_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))
	var vault_cigs: float = float(ws["establishments"]["venue_vault_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))

	if not is_equal_approx(op_cigs, 4.0) or not is_equal_approx(vault_cigs, 6.0):
		printerr("FAIL: Inventories corrupted after STORE_ITEMS. Op: %f, Vault: %f" % [op_cigs, vault_cigs])
		return false

	print("PASS: STORE_ITEMS executed successfully, items deposited cleanly.")
	return true

func test_store_items_insufficient_stock_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "STORE_ITEMS",
		"assigned_to": "op_01",
		"venue_id": "venue_vault_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 25.0, # op_01 only possesses 10.0
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected STORE_ITEMS to halt on insufficient operative stock.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE, got: ", err_code)
		return false

	print("PASS: STORE_ITEMS correctly halted on insufficient stock with INSUFFICIENT_RESOURCE.")
	return true

func test_store_items_location_mismatch_gate() -> bool:
	var ws := _create_fixture_state()
	# op_02 is located at DISTRICT_HQ, but target_node_id is DISTRICT_MARKET
	var directive := {
		"verb": "STORE_ITEMS",
		"assigned_to": "op_02",
		"venue_id": "venue_vault_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 2.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected STORE_ITEMS to halt on location mismatch.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET on location mismatch, got: ", err_code)
		return false

	print("PASS: STORE_ITEMS correctly halted on location mismatch with INVALID_TARGET.")
	return true