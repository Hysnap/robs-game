# res://tests/test_live_spatial_logistics_verbs.gd
extends SceneTree

const VERB_ROUTER = preload("res://systems/verb_router.gd")
const COMPOSER_CTRL = preload("res://systems/directive_composer_controller.gd")
const ENGINE_RESULT = preload("res://systems/engine_result.gd")

func _init() -> void:
	print("\n==========================================================================")
	print("   HEADLESS SUITE: LIVE SPATIAL LOGISTICS VERBS (DELIVER_TO & COLLECT_FROM)")
	print("==========================================================================")

	VERB_ROUTER.initialize()

	var passed: bool = true
	passed = passed and _test_mounting_and_composer_visibility()
	passed = passed and _test_deliver_to_cross_district_and_colocated()
	passed = passed and _test_deliver_to_early_stock_gate()
	passed = passed and _test_collect_from_cross_district_and_gates()

	if passed:
		print("==========================================================================")
		print("   ALL SPATIAL LOGISTICS VERB TESTS PASSED (EXIT 0)                       ")
		print("==========================================================================\n")
		quit(0)
	else:
		printerr("==========================================================================")
		printerr("   SPATIAL LOGISTICS VERB TEST SUITE FAILED (EXIT 1)                      ")
		printerr("==========================================================================\n")
		quit(1)

func _build_fixture_world_state() -> Dictionary:
	return {
		"metadata": {
			"current_sim_day": 29219,
			"current_day_tick": 1
		},
		"districts": {
			"DISTRICT_HQ": {
				"district_id": "DISTRICT_HQ",
				"display_name": "Aston Row"
			},
			"DISTRICT_MARKET": {
				"district_id": "DISTRICT_MARKET",
				"display_name": "High Parade"
			}
		},
		"residents": {
			"op_courier": {
				"resident_id": "op_courier",
				"name": "Arthur Shelby",
				"is_crew": true,
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 100.0,
					"CIGARETTES_UNFILTERED": 10.0
				}
			},
			"contact_buyer": {
				"resident_id": "contact_buyer",
				"name": "Alfie Solomons",
				"is_crew": false,
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 25.0
				}
			}
		},
		"establishments": {
			"estab_depot": {
				"establishment_id": "estab_depot",
				"name": "Aston Lockup",
				"district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 500.0,
					"WHISKY_BOTTLE": 12.0
				}
			},
			"estab_pub": {
				"establishment_id": "estab_pub",
				"name": "The Garrison",
				"district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 50.0
				}
			}
		},
		"caches": {}
	}

func _test_mounting_and_composer_visibility() -> bool:
	var mounted: Array[String] = VERB_ROUTER.get_registered_verbs()
	if not mounted.has("DELIVER_TO") or not mounted.has("COLLECT_FROM"):
		printerr("FAIL [Test 1]: VerbRouter missing DELIVER_TO or COLLECT_FROM. Mounted: ", mounted)
		return false

	var composer_verbs: Array[String] = COMPOSER_CTRL.get_registered_verbs()
	if not composer_verbs.has("DELIVER_TO") or not composer_verbs.has("COLLECT_FROM"):
		printerr("FAIL [Test 1]: DirectiveComposerController did not expose DELIVER_TO / COLLECT_FROM: ", composer_verbs)
		return false

	print("PASS [Test 1]: DELIVER_TO and COLLECT_FROM mounted (%d total verbs) and visible in composer." % mounted.size())
	return true

func _test_deliver_to_cross_district_and_colocated() -> bool:
	var ws := _build_fixture_world_state()

	# 1. Cross-district delivery: op_courier moves DISTRICT_HQ -> DISTRICT_MARKET and hands over 4 packs
	var order_cross := {
		"verb": "DELIVER_TO",
		"assigned_to": "op_courier",
		"target_node_id": "DISTRICT_MARKET",
		"recipient_id": "contact_buyer",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 4.0
	}
	var res1: Dictionary = VERB_ROUTER.dispatch(ws, order_cross)
	if not bool(res1.get("success", false)):
		printerr("FAIL [Test 2]: Cross-district DELIVER_TO failed: ", res1)
		return false

	if str(ws["residents"]["op_courier"]["current_district_id"]) != "DISTRICT_MARKET":
		printerr("FAIL [Test 2]: Courier did not relocate to DISTRICT_MARKET.")
		return false

	var courier_stock: float = float(ws["residents"]["op_courier"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))
	var buyer_stock: float = float(ws["residents"]["contact_buyer"]["inventory"].get("CIGARETTES_UNFILTERED", 0.0))
	if not is_equal_approx(courier_stock, 6.0) or not is_equal_approx(buyer_stock, 4.0):
		printerr("FAIL [Test 2]: Inventory mismatch after cross-district DELIVER_TO (courier=%f, buyer=%f)." % [courier_stock, buyer_stock])
		return false

	# 2. Same-district follow-up delivery (already in DISTRICT_MARKET): transfers £30 CASH to estab_pub
	var order_local := {
		"verb": "DELIVER_TO",
		"assigned_to": "op_courier",
		"target_node_id": "DISTRICT_MARKET",
		"recipient_id": "estab_pub",
		"item_id": "CASH",
		"amount": 30.0
	}
	var res2: Dictionary = VERB_ROUTER.dispatch(ws, order_local)
	if not bool(res2.get("success", false)):
		printerr("FAIL [Test 2]: Same-district follow-up DELIVER_TO failed: ", res2)
		return false

	var courier_cash: float = float(ws["residents"]["op_courier"]["inventory"].get("CASH", 0.0))
	var pub_cash: float = float(ws["establishments"]["estab_pub"]["inventory"].get("CASH", 0.0))
	if not is_equal_approx(courier_cash, 70.0) or not is_equal_approx(pub_cash, 80.0):
		printerr("FAIL [Test 2]: Cash mismatch after co-located DELIVER_TO (courier=%f, pub=%f)." % [courier_cash, pub_cash])
		return false

	print("PASS [Test 2]: DELIVER_TO verified across cross-district transit and co-located follow-up.")
	return true

func _test_deliver_to_early_stock_gate() -> bool:
	var ws := _build_fixture_world_state()

	# Attempt to deliver 50 packs when courier only has 10 — must fail BEFORE moving from DISTRICT_HQ
	var bad_order := {
		"verb": "DELIVER_TO",
		"assigned_to": "op_courier",
		"target_node_id": "DISTRICT_MARKET",
		"recipient_id": "contact_buyer",
		"item_id": "CIGARETTES_UNFILTERED",
		"amount": 50.0
	}
	var res: Dictionary = VERB_ROUTER.dispatch(ws, bad_order)
	if bool(res.get("success", false)):
		printerr("FAIL [Test 3]: DELIVER_TO succeeded despite insufficient stock.")
		return false

	if int(res.get("error_code", -1)) != ENGINE_RESULT.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL [Test 3]: Expected INSUFFICIENT_RESOURCE, got: ", res)
		return false

	if str(ws["residents"]["op_courier"]["current_district_id"]) != "DISTRICT_HQ":
		printerr("FAIL [Test 3]: Courier moved despite failing pre-transit stock gate!")
		return false

	print("PASS [Test 3]: DELIVER_TO halted at gate_sender_stock (INSUFFICIENT_RESOURCE) before transit.")
	return true

func _test_collect_from_cross_district_and_gates() -> bool:
	var ws := _build_fixture_world_state()
	# Start courier in DISTRICT_MARKET so COLLECT_FROM must travel back to DISTRICT_HQ
	ws["residents"]["op_courier"]["current_district_id"] = "DISTRICT_MARKET"

	var collect_order := {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_courier",
		"target_node_id": "DISTRICT_HQ",
		"source_id": "estab_depot",
		"item_id": "WHISKY_BOTTLE",
		"amount": 5.0
	}
	var res1: Dictionary = VERB_ROUTER.dispatch(ws, collect_order)
	if not bool(res1.get("success", false)):
		printerr("FAIL [Test 4]: Cross-district COLLECT_FROM failed: ", res1)
		return false

	if str(ws["residents"]["op_courier"]["current_district_id"]) != "DISTRICT_HQ":
		printerr("FAIL [Test 4]: Courier did not relocate to DISTRICT_HQ on COLLECT_FROM.")
		return false

	var courier_whisky: float = float(ws["residents"]["op_courier"]["inventory"].get("WHISKY_BOTTLE", 0.0))
	var depot_whisky: float = float(ws["establishments"]["estab_depot"]["inventory"].get("WHISKY_BOTTLE", 0.0))
	if not is_equal_approx(courier_whisky, 5.0) or not is_equal_approx(depot_whisky, 7.0):
		printerr("FAIL [Test 4]: Inventory mismatch after COLLECT_FROM (courier=%f, depot=%f)." % [courier_whisky, depot_whisky])
		return false

	# Same-district follow-up collection of £150 CASH from estab_depot
	var collect_cash := {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_courier",
		"target_node_id": "DISTRICT_HQ",
		"source_id": "estab_depot",
		"item_id": "CASH",
		"amount": 150.0
	}
	var res2: Dictionary = VERB_ROUTER.dispatch(ws, collect_cash)
	if not bool(res2.get("success", false)):
		printerr("FAIL [Test 4]: Co-located COLLECT_FROM failed: ", res2)
		return false

	# Early stock gate when source lacks requested quantity
	ws["residents"]["op_courier"]["current_district_id"] = "DISTRICT_MARKET"
	var bad_collect := {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_courier",
		"target_node_id": "DISTRICT_HQ",
		"source_id": "estab_depot",
		"item_id": "WHISKY_BOTTLE",
		"amount": 99.0
	}
	var res3: Dictionary = VERB_ROUTER.dispatch(ws, bad_collect)
	if bool(res3.get("success", false)) or int(res3.get("error_code", -1)) != ENGINE_RESULT.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL [Test 4]: Expected INSUFFICIENT_RESOURCE on over-collection, got: ", res3)
		return false

	if str(ws["residents"]["op_courier"]["current_district_id"]) != "DISTRICT_MARKET":
		printerr("FAIL [Test 4]: Courier moved despite failing gate_source_stock!")
		return false

	print("PASS [Test 4]: COLLECT_FROM verified across cross-district transit, co-located pickup, and stock gates.")
	return true