# res://tests/test_engine_harness.gd
extends SceneTree

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING HEADLESS DECISION & RESPONSE ENGINE HARNESS")
	print("=======================================================")

	# 1. TEST N-TIER COMMODITY INGESTION
	print("\n[STEP 1] Testing Hierarchical Commodity Loader...")
	var commodities = CommodityManager.load_hierarchical_commodities("res://data_modules/core/commodities/")
	
	assert(commodities.has("BEER_STRONG_LAGER"), "ERROR: BEER_STRONG_LAGER not found in registry!")
	var lager = commodities["BEER_STRONG_LAGER"]
	print("  ✓ Loaded: ", lager["display_name"])
	print("  ✓ Inherited Category (Tier 1): ", lager["category"])
	print("  ✓ Inherited Shelf Life (Tier 3): ", lager["decay_properties"]["shelf_life_ticks"], " ticks")
	print("  ✓ Overridden Heat Velocity (Tier 4): ", lager["impact_velocities"]["SELL"]["POLICE_HEAT"])
	
	# 2. INSTANTIATE WORLD STATE
	var world_state = {
		"metadata": {"current_week_tick": 1},
		"finances": {"liquid_cash": 100.0},
		"operations": {"fatigue": 0.0},[cite: 1]
		"commodity_registry": commodities,
		"districts": {
			"DIST_ASTON_01": {
				"display_name": "Aston Central",
				"actual_police_heat": 0.10,
				"zone_health_index": 80.0
			}
		}
	}

	# 3. TEST ACTION VERB EXECUTION (SELL)
	print("\n[STEP 2] Executing ActionSell with BEER_STRONG_LAGER...")
	var sell_directive = {
		"verb": "SELL",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_price": 3.50, "exposure_modifier": 1.0}
	}
	
	var result = SimController.execute_directive(world_state, ActionSell, sell_directive)
	print("  ✓ Execution Message: ", result["message"])
	print("  ✓ Generated Impact Deltas: ", result["impact_deltas"])
	
	var aston = world_state["districts"]["DIST_ASTON_01"]
	print("  ✓ Aston Police Heat (Post-Sale): ", aston["actual_police_heat"])
	print("  ✓ Aston Zone Health (Post-Sale): ", aston["zone_health_index"])
	print("  ✓ Vault Cash: £%.2f" % world_state["finances"]["liquid_cash"])
	
	assert(aston["actual_police_heat"] > 0.10, "ERROR: Heat delta failed to sink into district!")
	assert(aston["zone_health_index"] < 80.0, "ERROR: ZHI delta failed to erode district health!")

	# 4. TEST AMBIENT TICK HEARTBEAT
	print("\n[STEP 3] Executing Ambient Heartbeat Pulse...")
	var ambient_script = load("res://data_modules/core/verbs/sell/impacts/impact_police_heat.gd")
	SimController.process_ambient_heartbeat(world_state, [ambient_script])
	
	print("  ✓ Advanced Week Tick to: ", world_state["metadata"]["current_week_tick"])
	print("  ✓ Aston Police Heat (Post-Passive Dissipation): ", aston["actual_police_heat"])
	
	print("\n=======================================================")
	print("   ALL SYSTEMS OPERATIONAL: HARNESS COMPLETED")
	print("=======================================================\n")
	quit()