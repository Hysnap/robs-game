# res://tests/test_verb_router_declarative.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying VerbRouter Declarative Pipeline Integration ---")
	var passed: bool = true

	passed = passed and test_verb_router_mounting()
	passed = passed and test_verb_router_dispatch_buy()
	passed = passed and test_verb_router_dispatch_sell()
	passed = passed and test_verb_router_early_fail_loud()

	if passed:
		print("--- [Test] ALL VERB ROUTER DECLARATIVE INTEGRATION TESTS PASSED ---\n")
		quit(0)
	else:
		printerr("--- [Test] VERB ROUTER DECLARATIVE INTEGRATION TESTS FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"staff": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 100.0,
					"BEER_KEG": 4.0
				}
			},
			"op_02": {
				"name": "Sarah Connor",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 0.0
				}
			}
		},
		"counterparties": {
			"supplier_01": {
				"name": "Digbeth Wholesalers",
				"inventory": {
					"CASH": 200.0,
					"BEER_KEG": 20.0
				}
			},
			"buyer_01": {
				"name": "The Crown Pub",
				"inventory": {
					"CASH": 150.0,
					"BEER_KEG": 0.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": { "venues": {} },
			"DISTRICT_HQ": { "venues": {} }
		}
	}

func test_verb_router_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("BUY"):
		printerr("FAIL: VerbRouter failed to mount 'BUY'.")
		return false
	if not registered.has("SELL"):
		printerr("FAIL: VerbRouter failed to mount 'SELL'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'BUY' and 'SELL'.")
	return true

func test_verb_router_dispatch_buy() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "BUY",
		"assigned_to": "op_01",
		"supplier_id": "supplier_01",
		"item_id": "BEER_KEG",
		"amount": 2.0,
		"unit_cost": 20.0, # Total cost: 40.0 CASH
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: VerbRouter BUY dispatch failed: ", res.get("message"))
		return false

	var op_cash: float = float(ws["staff"]["op_01"]["inventory"].get("CASH", 0.0))
	var op_beer: float = float(ws["staff"]["op_01"]["inventory"].get("BEER_KEG", 0.0))
	var sup_cash: float = float(ws["counterparties"]["supplier_01"]["inventory"].get("CASH", 0.0))
	var sup_beer: float = float(ws["counterparties"]["supplier_01"]["inventory"].get("BEER_KEG", 0.0))

	# op_01 started with 100 CASH, 4 BEER -> 60 CASH, 6 BEER
	# supplier_01 started with 200 CASH, 20 BEER -> 240 CASH, 18 BEER
	if not is_equal_approx(op_cash, 60.0) or not is_equal_approx(op_beer, 6.0):
		printerr("FAIL: Buyer state incorrect after BUY dispatch. Cash: %f, Beer: %f" % [op_cash, op_beer])
		return false
	if not is_equal_approx(sup_cash, 240.0) or not is_equal_approx(sup_beer, 18.0):
		printerr("FAIL: Supplier state incorrect after BUY dispatch. Cash: %f, Beer: %f" % [sup_cash, sup_beer])
		return false

	print("PASS: VerbRouter successfully executed declarative BUY order.")
	return true

func test_verb_router_dispatch_sell() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "SELL",
		"assigned_to": "op_01",
		"buyer_id": "buyer_01",
		"item_id": "BEER_KEG",
		"amount": 2.0,
		"unit_cost": 35.0, # Total cost: 70.0 CASH
		"target_node_id": "DISTRICT_MARKET"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: VerbRouter SELL dispatch failed: ", res.get("message"))
		return false

	var op_cash: float = float(ws["staff"]["op_01"]["inventory"].get("CASH", 0.0))
	var op_beer: float = float(ws["staff"]["op_01"]["inventory"].get("BEER_KEG", 0.0))
	var buyer_cash: float = float(ws["counterparties"]["buyer_01"]["inventory"].get("CASH", 0.0))
	var buyer_beer: float = float(ws["counterparties"]["buyer_01"]["inventory"].get("BEER_KEG", 0.0))

	# op_01 started with 100 CASH, 4 BEER -> 170 CASH, 2 BEER
	# buyer_01 started with 150 CASH, 0 BEER -> 80 CASH, 2 BEER
	if not is_equal_approx(op_cash, 170.0) or not is_equal_approx(op_beer, 2.0):
		printerr("FAIL: Seller state incorrect after SELL dispatch. Cash: %f, Beer: %f" % [op_cash, op_beer])
		return false
	if not is_equal_approx(buyer_cash, 80.0) or not is_equal_approx(buyer_beer, 2.0):
		printerr("FAIL: Buyer state incorrect after SELL dispatch. Cash: %f, Beer: %f" % [buyer_cash, buyer_beer])
		return false

	print("PASS: VerbRouter successfully executed declarative SELL order.")
	return true

func test_verb_router_early_fail_loud() -> bool:
	var ws := _create_fixture_state()

	# 1. Unknown Verb Fail Loud
	var dir_unknown := { "verb": "NON_EXISTENT_VERB", "target_node_id": "DISTRICT_MARKET" }
	var res_unknown: Dictionary = VerbRouterScript.dispatch(ws, dir_unknown)
	if res_unknown.get("success", true):
		printerr("FAIL: VerbRouter should reject unmapped verb.")
		return false
	if int(res_unknown.get("error_code", -1)) != EngineResultScript.ErrorCode.ROUTER_UNMAPPED_VERB:
		printerr("FAIL: Expected ROUTER_UNMAPPED_VERB, got: ", res_unknown.get("error_code"))
		return false

	# 2. Insolvent SELL Gate Fail Loud (buyer lacks cash)
	var dir_broke_buyer := {
		"verb": "SELL",
		"assigned_to": "op_01",
		"buyer_id": "buyer_01",
		"item_id": "BEER_KEG",
		"amount": 2.0,
		"unit_cost": 500.0, # Total: 1000.0 CASH (buyer only has 150.0)
		"target_node_id": "DISTRICT_MARKET"
	}
	var res_broke: Dictionary = VerbRouterScript.dispatch(ws, dir_broke_buyer)
	if res_broke.get("success", true):
		printerr("FAIL: VerbRouter should halt SELL when buyer is insolvent.")
		return false
	if int(res_broke.get("error_code", -1)) != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE on insolvent buyer, got: ", res_broke.get("error_code"))
		return false

	print("PASS: VerbRouter early fail-loud rejections validated.")
	return true