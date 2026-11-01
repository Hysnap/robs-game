# res://tests/test_filofax_bridge.gd
extends SceneTree

const FILOFAX_MGR = preload("res://systems/filofax_manager.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")
const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING FILOFAX PERCEPTION & VIEW TEST")
	print("=======================================================")

	# 1. Setup Engine & Load State
	VERB_ROUTER.initialize()
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")
	var commodities = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/commodities/")
	
	var world_state = {
		"metadata": {"current_week_tick": 1},
		"finances": {"liquid_cash": 100.0},
		"operations": {"fatigue": 0.0},
		"commodity_registry": commodities,
		"pending_orders": {},
		"inventory_registry": {
			"BEER_STRONG_LAGER": {"STOCK": 20.0, "PREPPED": 0.0}
		},
		"counterparties": {
			"MARKET_CONSUMERS_ASTON": {"cash": 100.0, "inventory": {"BEER_STRONG_LAGER": {"STOCK": 0.0}}}
		},
		"districts": {
			"DIST_ASTON_01": {
				"display_name": "Aston Central",
				"actual_police_heat": 0.10,
				"zone_health_index": 80.0
			}
		}
	}

	# 2. Initialize Perceived Cache
	var cache = FILOFAX_MGR.init_cache(world_state)
	print("  ✓ Filofax Initialized: ", cache["districts"]["DIST_ASTON_01"]["display_name"])
	assert(cache["districts"]["DIST_ASTON_01"]["inked_police_heat"] == 0.10, "Initial cache mismatch!")

	# 3. Execute Directive (Mutate World State)
	var sell_cmd = {
		"verb": "SELL",
		"initiator_id": "PLAYER",
		"counterparty_id": "MARKET_CONSUMERS_ASTON",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_price": 3.50, "exposure_modifier": 1.0}
	}
	SIM_CONTROLLER.execute_directive(world_state, sell_cmd)

	# 4. Sync Filofax Cache
	FILOFAX_MGR.refresh_cache_instant(world_state, cache)
	print("  ✓ Synced Filofax Inked Heat: ", cache["districts"]["DIST_ASTON_01"]["inked_police_heat"])
	print("  ✓ Synced Reported Cash: £%.2f" % cache["finances"]["reported_cash"])
	
	assert(cache["districts"]["DIST_ASTON_01"]["inked_police_heat"] > 0.10, "Cache did not receive new heat!")
	assert(cache["finances"]["reported_cash"] == 135.0, "Cache did not receive updated cash!")

	print("\n=======================================================")
	print("   FILOFAX PERCEPTION TEST PASSED")
	print("=======================================================\n")
	quit()