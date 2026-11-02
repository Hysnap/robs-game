# res://tests/test_engine_harness.gd
extends SceneTree

const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const CommodityManagerScript = preload("res://systems/commodity_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING HEADLESS DECISION & RESPONSE ENGINE HARNESS")
	print("=======================================================")

	# 1. INITIALIZE ENGINE SWITCHBOARDS, CATALOGS & CALENDAR
	print("\n[STEP 1] Initializing Routers, Sinks and Calendar...")
	VerbRouterScript.initialize()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")
	CalendarHelperScript.initialize({
    "epoch_date": "1900-01-01",
    "simulation_start_date": "1980-01-01",
    "days_per_tick": 7
})

	# 2. LOAD COMMODITIES AND RECIPES
	print("\n[STEP 2] Testing Hierarchical Commodity Loader...")
	var commodities = CommodityManagerScript.load_hierarchical_commodities("res://data_modules/core/commodities/")
	var recipes = CommodityManagerScript.load_hierarchical_commodities("res://data_modules/core/recipes/")

	assert(commodities.has("BEER_STRONG_LAGER"), "ERROR: BEER_STRONG_LAGER not found in registry!")
	var lager = commodities["BEER_STRONG_LAGER"]
	print("  ✓ Loaded: ", lager.get("display_name", "BEER_STRONG_LAGER"))

	# 3. INSTANTIATE WORLD STATE (Canonical Schema Compliant)
	var world_state = {
		"metadata": {
			"current_day_tick": 1,
			"current_week_tick": 1,
			"time_horizon": "week"
		},
		"finances": {
			"liquid_cash": 100.0
		},
		"operations": {
			"fatigue": 0.0,
			"material_waste_accumulated": 0.0,
			"regulatory_scrutiny": 0.0
		},
		"commodity_registry": commodities,
		"recipe_registry": recipes,
		"pending_orders": {},
		"inventory_batches": {},
		
		# Player Inventory: Each commodity requires a Dictionary containing STOCK and PREPPED
		"inventory_registry": {
			"BEER_STRONG_LAGER": {"STOCK": 0.0, "PREPPED": 0.0},
			"ROLLING_TOBACCO": {"STOCK": 10.0, "PREPPED": 0.0},
			"ROLLING_PAPERS": {"STOCK": 20.0, "PREPPED": 0.0},
			"ROLLUP": {"STOCK": 0.0, "PREPPED": 0.0}
		},
		
		# Explicit Counterparty Entities with Structured Inventories
		"counterparties": {
			"WHOLESALER_01": {
				"display_name": "Midlands Regional Brewery Depot",
				"cash": 50000.0,
				"inventory": {
					"BEER_STRONG_LAGER": {"STOCK": 1000.0, "PREPPED": 0.0}
				}
			},
			"MARKET_CONSUMERS_ASTON": {
				"display_name": "Aston Weekend Pub Demand",
				"cash": 250.0,
				"inventory": {
					"BEER_STRONG_LAGER": {"STOCK": 0.0, "PREPPED": 0.0}
				}
			}
		},
		
		"districts": {
			"DIST_ASTON_01": {
				"display_name": "Aston Central",
				"actual_police_heat": 0.10,
				"zone_health_index": 80.0,
				"regulatory_scrutiny": 0.0
			}
		}
	}

	# STEP 3A: BUY DIRECTIVE
	print("\n[STEP 3A] Executing BUY from 'WHOLESALER_01'...")
	var buy_directive = {
		"verb": "BUY",
		"initiator_id": "PLAYER",
		"counterparty_id": "WHOLESALER_01",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 20.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_cost": 1.20, "exposure_modifier": 1.0}
	}
	var buy_result = SimControllerScript.execute_directive(world_state, buy_directive)
	print("  ✓ Buy Result: ", buy_result.get("message", "OK"))
	print("  ✓ Cash Remaining: £%.2f" % world_state["finances"]["liquid_cash"])
	print("  ✓ Stock In Vault: ", world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"])
	
	assert(buy_result.get("success", false), "ERROR: BUY action failed!")
	assert(world_state["finances"]["liquid_cash"] == 76.0, "ERROR: Vault cash calculation incorrect on BUY!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 20.0, "ERROR: Stock failed to increment on BUY!")

	# STEP 3B: SELL DIRECTIVE
	print("\n[STEP 3B] Executing SELL to 'MARKET_CONSUMERS_ASTON'...")
	var sell_directive = {
		"verb": "SELL",
		"initiator_id": "PLAYER",
		"counterparty_id": "MARKET_CONSUMERS_ASTON",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_price": 3.50, "exposure_modifier": 1.0}
	}
	var sell_result = SimControllerScript.execute_directive(world_state, sell_directive)
	print("  ✓ Sell Result: ", sell_result.get("message", "OK"))
	print("  ✓ Cash After Sale: £%.2f" % world_state["finances"]["liquid_cash"])
	print("  ✓ Stock Remaining: ", world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"])
	
	assert(sell_result.get("success", false), "ERROR: SELL action failed!")
	assert(world_state["finances"]["liquid_cash"] == 111.0, "ERROR: Vault cash did not credit on SELL!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 10.0, "ERROR: Stock failed to decrement on SELL!")

	var aston = world_state["districts"]["DIST_ASTON_01"]
	var heat_post_sale: float = float(aston["actual_police_heat"])
	print("  ✓ Aston Police Heat (Post-Sale): ", heat_post_sale)
	assert(heat_post_sale > 0.10, "ERROR: Heat delta failed to sink into district!")

	# STEP 4: GENUINE IDLE TURN CYCLE
	print("\n[STEP 4] Executing Genuine Idle Turn Cycle (SimController.process_turn_cycle)...")
	var cycle_report: Dictionary = SimControllerScript.process_turn_cycle(world_state, [])
	var slips: Array = cycle_report.get("executed_events", [])
	assert(not slips.is_empty(), "ERROR: process_turn_cycle returned empty executed_events array!")

	var idle_slip: Dictionary = slips[0]
	print("  ✓ Generated Cycle Slip Verb: ", idle_slip.get("verb"))
	print("  ✓ Slip Message: ", idle_slip.get("message", idle_slip.get("text", "")))
	print("  ✓ Advanced Week Tick to: ", world_state["metadata"]["current_week_tick"])

	var heat_post_idle: float = float(aston["actual_police_heat"])
	print("  ✓ Aston Police Heat (Post-Passive Drift): ", heat_post_idle)
	assert(heat_post_idle < heat_post_sale, "ERROR: Passive ambient drift failed to dissipate police heat!")

	# STEP 5: MAKE DIRECTIVE
	print("\n[STEP 5] Testing MAKE: Roll 10 Hand-Rolled Cigarettes...")
	var make_directive = {
		"verb": "MAKE",
		"initiator_id": "PLAYER",
		"target_item": "RECIPE_ROLL_CIGARETTE",
		"amount": 10.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {}
	}
	if not recipes.has("RECIPE_ROLL_CIGARETTE") and recipes.has("ROLL_CIGARETTE"):
		make_directive["target_item"] = "ROLL_CIGARETTE"

	var make_result = SimControllerScript.execute_directive(world_state, make_directive)
	print("  ✓ Make Result: ", make_result.get("message", "OK"))
	print("  ✓ Consumed Tobacco (Remaining): ", world_state["inventory_registry"]["ROLLING_TOBACCO"]["STOCK"], "g")
	print("  ✓ Consumed Papers (Remaining): ", world_state["inventory_registry"]["ROLLING_PAPERS"]["STOCK"])
	print("  ✓ Yielded Rollups in Staging: ", world_state["inventory_registry"]["ROLLUP"]["PREPPED"])
	
	assert(make_result.get("success", false), "ERROR: MAKE directive failed!")
	assert(world_state["inventory_registry"]["ROLLING_TOBACCO"]["STOCK"] == 2.0, "ERROR: Tobacco math incorrect (10 - 8 = 2)!")
	assert(world_state["inventory_registry"]["ROLLING_PAPERS"]["STOCK"] == 10.0, "ERROR: Paper math incorrect (20 - 10 = 10)!")
	assert(world_state["inventory_registry"]["ROLLUP"]["PREPPED"] == 10.0, "ERROR: Output yield did not reach PREPPED lane!")

	print("\n=======================================================")
	print("   ALL SYSTEMS OPERATIONAL: HARNESS COMPLETED")
	print("=======================================================\n")
	quit()
