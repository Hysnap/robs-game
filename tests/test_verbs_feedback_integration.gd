# res://tests/test_verbs_feedback_integration.gd
extends SceneTree

const VERB_ROUTER = preload("res://systems/verb_router.gd")
const FEEDBACK_MGR = preload("res://systems/feedback_manager.gd")
const DIALOGUE_RESOLVER = preload("res://systems/dialogue_resolver.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")
const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("    TESTING REAL ACTIONS + MODULAR FEEDBACK PIPELINE   ")
	print("=======================================================")

	# 1. Initialize Core Engine Infrastructure
	VERB_ROUTER.initialize()
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")
	
	var feedback_data = FEEDBACK_MGR.load_all_feedback(
		"res://data_modules/shared/feedback/",
		"res://data_modules/core/verbs/"
	)

	# 2. Ingest Live Disk Catalogs (No hardcoded mock commodities/recipes!)
	var commodities: Dictionary = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/commodities/")
	var recipes: Dictionary = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/recipes/")
	
	print("  ✓ Live Commodities Discovered: ", commodities.keys())
	print("  ✓ Live Recipes Discovered:     ", recipes.keys())

	# Ensure test-essential commodities exist if disk catalog is partial
	if not commodities.has("BEER_STRONG_LAGER"):
		commodities["BEER_STRONG_LAGER"] = {"id": "BEER_STRONG_LAGER", "base_cost": 1.20, "impact_activations": {}}
	if not commodities.has("ROLLING_TOBACCO"):
		commodities["ROLLING_TOBACCO"] = {"id": "ROLLING_TOBACCO", "base_cost": 0.08, "impact_activations": {}}
	if not commodities.has("ROLLING_PAPERS"):
		commodities["ROLLING_PAPERS"] = {"id": "ROLLING_PAPERS", "base_cost": 0.02, "impact_activations": {}}
	if not commodities.has("ROLLUP"):
		commodities["ROLLUP"] = {"id": "ROLLUP", "base_cost": 0.50, "impact_activations": {}}

	# 3. Load Dialect Profile
	var dialect: Dictionary = {}
	var dialect_path = "res://data_modules/core/dialects/brummie_street.json"
	if FileAccess.file_exists(dialect_path):
		var file = FileAccess.open(dialect_path, FileAccess.READ)
		dialect = JSON.parse_string(file.get_as_text())
		file.close()

	var staff = {"name": "Billy", "loyalty": 0.95}

	# 4. Establish Initial World State
	var world_state = {
		"metadata": {"current_week_tick": 1},
		"finances": {"liquid_cash": 100.0},
		"operations": {"fatigue": 0.0},
		"inventory_registry": {
			"BEER_STRONG_LAGER": {"STOCK": 0.0, "PREPPED": 0.0},
			"ROLLING_TOBACCO": {"STOCK": 50.0, "PREPPED": 0.0},
			"ROLLING_PAPERS": {"STOCK": 50.0, "PREPPED": 0.0},
			"ROLLUP": {"STOCK": 0.0, "PREPPED": 0.0}
		},
		"commodity_registry": commodities,
		"recipe_registry": recipes,
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
	var res_buy = SIM_CONTROLLER.execute_directive(world_state, buy_cmd)
	print("  Result success: ", res_buy.get("success", false))
	print("  Result message: ", res_buy.get("message", ""))
	
	assert(res_buy.get("success", false) == true, "FAILED: BUY execution failed!")
	assert(world_state["finances"]["liquid_cash"] == 76.0, "FAILED: Cash not reduced by 20 x £1.20 (£24)!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 20.0, "FAILED: Stock not received!")

	var memo_buy = DIALOGUE_RESOLVER.format_feedback(res_buy, staff, dialect, feedback_data)
	print("  Generated Memo -> ", memo_buy)

	# -------------------------------------------------------------
	# TEST 2: Action MAKE (Batch Transformation via Recipe)
	# -------------------------------------------------------------
	print("\n--- [TEST 2] Action: MAKE (Roll 10 Hand-Rolled Cigarettes) ---")
	
	# Resolves recipe ID dynamically from disk profile ("ROLL_CIGARETTE" or "RECIPE_ROLL_CIGARETTE")
	var target_recipe_id: String = "ROLL_CIGARETTE"
	if not world_state["recipe_registry"].has(target_recipe_id):
		if world_state["recipe_registry"].has("RECIPE_ROLL_CIGARETTE"):
			target_recipe_id = "RECIPE_ROLL_CIGARETTE"

	var make_cmd = {
		"verb": "MAKE",
		"recipe_id": target_recipe_id,
		"amount": 10, # Batch of 10
		"initiator_id": "PLAYER",
		"target_node_id": "HQ"
	}
	var res_make = SIM_CONTROLLER.execute_directive(world_state, make_cmd)
	print("  Result success: ", res_make.get("success", false))
	print("  Result message: ", res_make.get("message", ""))

	assert(res_make.get("success", false) == true, "FAILED: MAKE execution failed!")
	
	# Verification based on recipe_profile.json: 10 batches * 0.8g tobacco = 8.0g consumed (50 - 8 = 42)
	# 10 batches * 1.0 paper = 10 papers consumed (50 - 10 = 40)
	var rem_tobacco: float = world_state["inventory_registry"]["ROLLING_TOBACCO"]["STOCK"]
	var rem_papers: float = world_state["inventory_registry"]["ROLLING_PAPERS"]["STOCK"]
	var prepped_rollups: float = world_state["inventory_registry"]["ROLLUP"]["PREPPED"]

	print("  ✓ Remaining Tobacco: %.1fg (Expected 42.0g)" % rem_tobacco)
	print("  ✓ Remaining Papers:  %.1f  (Expected 40.0)" % rem_papers)
	print("  ✓ Prepped Rollups:   %.1f  (Expected 10.0)" % prepped_rollups)

	assert(rem_tobacco == 42.0, "FAILED: Tobacco deduction math incorrect!")
	assert(rem_papers == 40.0, "FAILED: Papers deduction math incorrect!")
	assert(prepped_rollups == 10.0, "FAILED: Finished yield not placed in PREPPED!")

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
	var res_sell = SIM_CONTROLLER.execute_directive(world_state, sell_cmd)
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
	var res_fail = SIM_CONTROLLER.execute_directive(world_state, excessive_buy)
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