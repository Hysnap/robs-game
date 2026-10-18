# res://tests/test_engine_harness.gd
extends SceneTree

const VERB_ROUTER = preload("res://systems/verb_router.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const COMMODITY_MANAGER = preload("res://systems/commodity_manager.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING HEADLESS DECISION & RESPONSE ENGINE HARNESS")
	print("=======================================================")

	# 1. MOUNT ENGINE
	print("\n[STEP 1] Initializing Routers and Sinks...")
	VERB_ROUTER.initialize()
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")

	# 2. INGEST COMMODITIES
	print("\n[STEP 2] Testing Hierarchical Commodity Loader...")
	var commodities = COMMODITY_MANAGER.load_hierarchical_commodities("res://data_modules/core/commodities/")
	assert(commodities.has("BEER_STRONG_LAGER"), "ERROR: BEER_STRONG_LAGER missing from catalog!")

	# 3. EXPLICIT ENTITY INITIALIZATION (No Ghost Fallbacks)
	var world_state = {
		"metadata": {"current_week_tick": 1},
		"finances": {"liquid_cash": 100.0},
		"operations": {"fatigue": 0.0},
		"commodity_registry": commodities,
		"pending_orders": {},
		
		# The Player's Warehouse Stock
		"inventory_registry": {
			"BEER_STRONG_LAGER": {"STOCK": 0.0, "PREPPED": 0.0}
		},
		
		# Explicit Counterparty Entities
		"counterparties": {
			"WHOLESALER_01": {
				"display_name": "Midlands Regional Brewery Depot",
				"cash": 50000.0,
				"inventory": {
					"BEER_STRONG_LAGER": {"STOCK": 1000.0} # Wholesaler has physical stock!
				}
			},
			"MARKET_CONSUMERS_ASTON": {
				"display_name": "Aston Weekend Pub Demand",
				"cash": 250.0, # Market has liquid cash to buy products!
				"inventory": {
					"BEER_STRONG_LAGER": {"STOCK": 0.0}
				}
			}
		},
		
		"districts": {
			"DIST_ASTON_01": {
				"display_name": "Aston Central",
				"actual_police_heat": 0.10,
				"zone_health_index": 80.0
			}
		}
	}

	# 4. STEP 3A: COMPOSITE BUY (From Explicit Wholesaler)
	print("\n[STEP 3A] Executing BUY from 'WHOLESALER_01'...")
	var buy_cmd = {
		"verb": "BUY",
		"initiator_id": "PLAYER",
		"counterparty_id": "WHOLESALER_01",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 20.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_cost": 1.20}
	}
	var buy_res = SIM_CONTROLLER.execute_directive(world_state, buy_cmd)
	print("  ✓ Buy Result: ", buy_res["message"])
	print("  ✓ Cash Remaining: £%.2f" % world_state["finances"]["liquid_cash"])
	print("  ✓ Stock In Vault: ", world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"])
	print("  ✓ Wholesaler Stock Remaining: ", world_state["counterparties"]["WHOLESALER_01"]["inventory"]["BEER_STRONG_LAGER"]["STOCK"])
	
	assert(buy_res["success"], "BUY action failed!")
	assert(world_state["finances"]["liquid_cash"] == 76.0, "Cash calculation incorrect!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 20.0, "Player stock failed to increment!")

	# 5. STEP 3B: COMPOSITE SELL (To Explicit Market Consumers)
	print("\n[STEP 3B] Executing SELL to 'MARKET_CONSUMERS_ASTON'...")
	var sell_cmd = {
		"verb": "SELL",
		"initiator_id": "PLAYER",
		"counterparty_id": "MARKET_CONSUMERS_ASTON",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_price": 3.50, "exposure_modifier": 1.0}
	}
	var sell_res = SIM_CONTROLLER.execute_directive(world_state, sell_cmd)
	print("  ✓ Sell Result: ", sell_res["message"])
	print("  ✓ Cash After Sale: £%.2f" % world_state["finances"]["liquid_cash"])
	print("  ✓ Stock Remaining: ", world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"])
	print("  ✓ Consumer Cohort Cash Remaining: £%.2f" % world_state["counterparties"]["MARKET_CONSUMERS_ASTON"]["cash"])
	
	var aston = world_state["districts"]["DIST_ASTON_01"]
	print("  ✓ Aston Police Heat: ", aston["actual_police_heat"])
	
	assert(sell_res["success"], "SELL action failed!")
	assert(world_state["finances"]["liquid_cash"] == 111.0, "Vault cash did not credit!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 10.0, "Stock failed to decrement!")
	assert(aston["actual_police_heat"] > 0.10, "Police heat failed to increase!")

	# 6. STEP 4: AMBIENT DRIFT
	print("\n[STEP 4] Executing Ambient Heartbeat Pulse...")
	SIM_CONTROLLER.process_ambient_heartbeat(world_state)
	print("  ✓ Advanced Week Tick to: ", world_state["metadata"]["current_week_tick"])
	print("  ✓ Aston Police Heat (Post-Passive Drift): ", aston["actual_police_heat"])


	
	# -------------------------------------------------------------
	# STEP 5: TEST RECIPE TRANSFORMATION (MAKE)
	# -------------------------------------------------------------
	print("\n[STEP 5] Testing MAKE: Roll 10 Hand-Rolled Cigarettes...")

	# Seed raw materials into inventory
	world_state["inventory_registry"]["TOBACCO_ROLLING"] = {"STOCK": 10.0, "PREPPED": 0.0}
	world_state["inventory_registry"]["ROLLING_PAPERS"] = {"STOCK": 20.0, "PREPPED": 0.0}
	world_state["inventory_registry"]["CIGARETTE_ROLLUP"] = {"STOCK": 0.0, "PREPPED": 0.0}

	# Ingest recipes
	var recipes = COMMODITY_MANAGER.load_hierarchical_commodities("res://data_modules/core/recipes/")
	print("  ✓ Recipes mounted: ", recipes.keys())
	world_state["recipe_registry"] = recipes

	var make_cmd = {
		"verb": "MAKE",
		"target_item": "RECIPE_ROLL_CIGARETTE",
		"amount": 10, # 10 Batches = 10 Cigarettes
		"target_node_id": "DIST_ASTON_01"
	}

	var make_res = SIM_CONTROLLER.execute_directive(world_state, make_cmd)
	print("  ✓ Make Result: ", make_res["message"])
	print("  ✓ Consumed Tobacco (Remaining): ", world_state["inventory_registry"]["TOBACCO_ROLLING"]["STOCK"], "g")
	print("  ✓ Consumed Papers (Remaining): ", world_state["inventory_registry"]["ROLLING_PAPERS"]["STOCK"])
	print("  ✓ Yielded Rollups in Staging: ", world_state["inventory_registry"]["CIGARETTE_ROLLUP"]["PREPPED"])
	print("  ✓ Accumulated Worker Fatigue: ", world_state["operations"]["fatigue"])

	assert(make_res["success"], "MAKE directive failed!")
	assert(world_state["inventory_registry"]["TOBACCO_ROLLING"]["STOCK"] == 2.0, "Tobacco math incorrect! (10 - 8.0 = 2.0)")
	assert(world_state["inventory_registry"]["ROLLING_PAPERS"]["STOCK"] == 10.0, "Paper math incorrect! (20 - 10 = 10)")
	assert(world_state["inventory_registry"]["CIGARETTE_ROLLUP"]["PREPPED"] == 10.0, "Output yield did not reach PREPPED lane!")
	assert(world_state["operations"]["fatigue"] > 0.0, "Worker fatigue failed to sink!")
	
	print("\n=======================================================")
	print("   ALL SYSTEMS OPERATIONAL: HARNESS COMPLETED")
	print("=======================================================\n")

	quit()