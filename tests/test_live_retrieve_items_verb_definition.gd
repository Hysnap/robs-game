# res://tests/test_live_retrieve_items_verb_definition.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative RETRIEVE_ITEMS Verb Definition ---")
	var passed: bool = true

	passed = passed and test_retrieve_items_mounting()
	passed = passed and test_retrieve_items_success()
	passed = passed and test_retrieve_items_insufficient_stock_gate()
	passed = passed and test_retrieve_items_location_mismatch_gate()

	if passed:
		print("--- [Test] DECLARATIVE RETRIEVE_ITEMS VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE RETRIEVE_ITEMS VERB VERIFICATION FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"residents": {
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
					"CASH": 50.0,
					"CIGARETTES_UNFILTERED": 0.0
				}
			}
		},
		"caches": {
			"cache_canal_01": {
				"name": "Canal Wall Dead Drop",
				"district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 50.0,
					"CIGARETTES_UNFILTERED": 15.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": {},
			"DISTRICT_HQ": {}
		}
	}

func test_retrieve_items_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("RETRIEVE_ITEMS"):
		printerr("FAIL: VerbRouter failed to discover and mount 'RETRIEVE_ITEMS'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'RETRIEVE_ITEMS'.")
	return true

func test_retrieve_items_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "RETRIEVE_ITEMS",
		"assigned_to": "op_01",
		"cache_id": "cache_canal_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 7.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: RETRIEVE_ITEMS dispatch failed unexpectedly: ", res.get("message"))
		return false

	var op_cigs: float = float(ws["residents"]["op_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))
	var cache_cigs: float = float(ws["caches"]["cache_canal_01"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))

	if not is_equal_approx(op_cigs, 7.0) or not is_equal_approx(cache_cigs, 8.0):
		printerr("FAIL: Inventories corrupted after RETRIEVE_ITEMS. Op: %f, Cache: %f" % [op_cigs, cache_cigs])
		return false

	print("PASS: RETRIEVE_ITEMS executed successfully, items retrieved cleanly.")
	return true

func test_retrieve_items_insufficient_stock_gate() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "RETRIEVE_ITEMS",
		"assigned_to": "op_01",
		"cache_id": "cache_canal_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 40.0, # Cache only possesses 15.0
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected RETRIEVE_ITEMS to halt on insufficient cache stock.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE, got: ", err_code)
		return false

	print("PASS: RETRIEVE_ITEMS correctly halted on insufficient cache stock with INSUFFICIENT_RESOURCE.")
	return true

func test_retrieve_items_location_mismatch_gate() -> bool:
	var ws := _create_fixture_state()
	# op_02 is at DISTRICT_HQ, but target_node_id is DISTRICT_MARKET
	var directive := {
		"verb": "RETRIEVE_ITEMS",
		"assigned_to": "op_02",
		"cache_id": "cache_canal_01",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 2.0,
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: Expected RETRIEVE_ITEMS to halt on location mismatch.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL: Expected INVALID_TARGET on location mismatch, got: ", err_code)
		return false

	print("PASS: RETRIEVE_ITEMS correctly halted on location mismatch with INVALID_TARGET.")
	return true