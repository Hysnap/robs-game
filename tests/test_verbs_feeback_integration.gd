# res://tests/test_verbs_feedback_integration.gd
extends SceneTree

const VERB_ROUTER = preload("res://systems/verb_router.gd")
const FEEDBACK_MGR = preload("res://systems/feedback_manager.gd")
const DIALOGUE_RESOLVER = preload("res://systems/dialogue_resolver.gd")

func _init() -> void:
	print("\n=======================================================")
	print("    TESTING REAL ACTIONS + MODULAR FEEDBACK PIPELINE   ")
	print("=======================================================")

	# 1. Initialize Routers and Loaders
	VERB_ROUTER.initialize()
	var feedback_data = FEEDBACK_MGR.load_all_feedback(
		"res://data_modules/shared/feedback/",
		"res://data_modules/core/verbs/"
	)

	# 2. Load Dialect Profile
	var dialect: Dictionary = {}
	var dialect_path = "res://data_modules/core/dialects/brummie_street.json"
	if FileAccess.file_exists(dialect_path):
		var file = FileAccess.open(dialect_path, FileAccess.READ)
		dialect = JSON.parse_string(file.get_as_text())
		file.close()

	var staff = {"name": "Billy", "loyalty": 0.95}

	# 3. Seed Realistic World State (Matching ConditionEvaluator/OrderManager layout)
	var world_state = {
		"finances": {"liquid_cash": 100.0},
		"inventory_registry": {
			"BEER_STRONG_LAGER": {"STOCK": 0.0, "PREPPED": 0.0},
			"RAW_TOBACCO": {"STOCK": 50.0, "PREPPED": 0.0},
			"ROLLING_PAPERS": {"STOCK": 50.0, "PREPPED": 0.0},
			"CIGARETTE_ROLLUP": {"STOCK": 0.0, "PREPPED": 0.0}
		},
		"commodity_registry": {
			"BEER_STRONG_LAGER": {"base_cost": 1.20, "impact_activations": {}},
			"RAW_TOBACCO": {"base_cost": 0.50, "impact_activations": {}},
			"ROLLING_PAPERS": {"base_cost": 0.10, "impact_activations": {}},
			"CIGARETTE_ROLLUP": {"base_cost": 1.00, "impact_activations": {}}
		},
		"recipe_registry": {
			"RECIPE_ROLL_CIGS": {
				"output_item": "CIGARETTE_ROLLUP",
				"output_yield_units": 10.0,
				"inputs": {
					"RAW_TOBACCO": 10.0,
					"ROLLING_PAPERS": 10.0
				},
				"impact_activations": {}
			}
		},
		"counterparties": {
			"WHOLESALER_01": {
				"display_name": "Midlands Brewery Depot",
				"cash": 5000.0,
				"inventory": {"BEER_STRONG_LAGER": {"STOCK": 500.0}}
			},
			"MARKET_CONSUMERS": {
				"display_name": "Aston Street Consumers",
				"cash": 200.0,
				"inventory": {"BEER_STRONG_LAGER": {"STOCK": 0.0}}
			}
		},
		"pending_orders": {},
		"completed_orders": {}
	}

	# -------------------------------------------------------------
	# TEST 1: Composite BUY (Order -> Pay -> Receive -> Archive)
	# -------------------------------------------------------------
	print("\n--- [TEST 1] Composite Action: BUY ---")
	var buy_cmd = {
		"verb": "BUY",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 20.0,
		"initiator_id": "PLAYER",
		"counterparty_id": "WHOLESALER_01",
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_cost": 1.20}
	}
	var res_buy = VERB_ROUTER.dispatch(world_state, buy_cmd)
	print("  Result success: ", res_buy.get("success", false))
	print("  Result message: ", res_buy.get("message", ""))
	
	assert(res_buy.get("success", false) == true, "FAILED: BUY execution failed!")
	assert(world_state["finances"]["liquid_cash"] == 76.0, "FAILED: Cash not reduced by 20 x £1.20 (£24)!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 20.0, "FAILED: Stock not received!")

	var memo_buy = DIALOGUE_RESOLVER.format_feedback(res_buy, staff, dialect, feedback_data)
	print("  Generated Memo -> ", memo_buy)

	# -------------------------------------------------------------
	# TEST 2: Action MAKE (Batch Production)
	# -------------------------------------------------------------
	print("\n--- [TEST 2] Action: MAKE ---")
	var make_cmd = {
		"verb": "MAKE",
		"target_item": "RECIPE_ROLL_CIGS",
		"amount": 1,
		"initiator_id": "PLAYER",
		"target_node_id": "HQ"
	}
	var res_make = VERB_ROUTER.dispatch(world_state, make_cmd)
	print("  Result success: ", res_make.get("success", false))
	print("  Result message: ", res_make.get("message", ""))

	assert(res_make.get("success", false) == true, "FAILED: MAKE execution failed!")
	assert(world_state["inventory_registry"]["RAW_TOBACCO"]["STOCK"] == 40.0, "FAILED: Raw tobacco not deducted!")
	assert(world_state["inventory_registry"]["CIGARETTE_ROLLUP"]["PREPPED"] == 10.0, "FAILED: Yield not placed in PREPPED!")

	var memo_make = DIALOGUE_RESOLVER.format_feedback(res_make, staff, dialect, feedback_data)
	print("  Generated Memo -> ", memo_make)

	# -------------------------------------------------------------
	# TEST 3: Action SELL (Retail Settlement)
	# -------------------------------------------------------------
	print("\n--- [TEST 3] Composite Action: SELL ---")
	var sell_cmd = {
		"verb": "SELL",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"initiator_id": "PLAYER",
		"counterparty_id": "MARKET_CONSUMERS",
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_price": 2.50}
	}
	var res_sell = VERB_ROUTER.dispatch(world_state, sell_cmd)
	print("  Result success: ", res_sell.get("success", false))
	print("  Result message: ", res_sell.get("message", ""))

	assert(res_sell.get("success", false) == true, "FAILED: SELL execution failed!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 10.0, "FAILED: Stock not reduced!")
	assert(world_state["finances"]["liquid_cash"] == 101.0, "FAILED: Revenue not deposited (+£25.00)!")

	var memo_sell = DIALOGUE_RESOLVER.format_feedback(res_sell, staff, dialect, feedback_data)
	print("  Generated Memo -> ", memo_sell)

	# -------------------------------------------------------------
	# TEST 4: Failure Test (Bounced Action due to Solvency)
	# -------------------------------------------------------------
	print("\n--- [TEST 4] Solvency Failure Check (Insufficient Funds) ---")
	var excessive_buy = {
		"verb": "BUY",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 500.0, # £600 needed, but player only has £101
		"initiator_id": "PLAYER",
		"counterparty_id": "WHOLESALER_01",
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_cost": 1.20}
	}
	var res_fail = VERB_ROUTER.dispatch(world_state, excessive_buy)
	print("  Result success (Expected false): ", res_fail.get("success", true))
	print("  Result code: ", res_fail.get("code", ""))

	assert(res_fail.get("success", true) == false, "FAILED: Solvency check did not catch shortage!")
	assert(res_fail.get("code", "") == "INSUFFICIENT_RESOURCE", "FAILED: Did not return INSUFFICIENT_RESOURCE!")

	var memo_fail = DIALOGUE_RESOLVER.format_feedback(res_fail, staff, dialect, feedback_data)
	print("  Generated Memo -> ", memo_fail)

	print("\n=======================================================")
	print("     ALL VERBS & FEEDBACK RESOLUTION TESTS PASSED!     ")
	print("=======================================================\n")
	quit()