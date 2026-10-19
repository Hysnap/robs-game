# res://scenes/ui/filofax/test_filofax_scene.gd
extends Node2D

const FILOFAX_MGR = preload("res://systems/filofax_manager.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")
const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")
const CATALOG_VALIDATOR = preload("res://systems/catalog_validator.gd")

@onready var binder_ui: FilofaxUI = $FilofaxBinder

func _ready() -> void:
	# 1. Mount Engine & Load Catalogs
	VERB_ROUTER.initialize()
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")
	var commodities = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/commodities/")
	var recipes = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/recipes/")

	# 2. Build World State
	var world_state = {
		"metadata": {"current_week_tick": 1},
		"finances": {"liquid_cash": 100.0},
		"operations": {"fatigue": 0.0},
		"commodity_registry": commodities,
		"recipe_registry": recipes,
		"pending_orders": {},
		"completed_orders": {},
		"inventory_registry": {
			"BEER_STRONG_LAGER": {"STOCK": 0.0, "PREPPED": 0.0},
			"TOBACCO_ROLLING": {"STOCK": 20.0, "PREPPED": 0.0},
			"ROLLING_PAPERS": {"STOCK": 50.0, "PREPPED": 0.0},
			"CIGARETTE_ROLLUP": {"STOCK": 0.0, "PREPPED": 0.0}
		},
		"counterparties": {
			"WHOLESALER_01": {
				"display_name": "Midlands Regional Brewery Depot",
				"cash": 50000.0,
				"inventory": {"BEER_STRONG_LAGER": {"STOCK": 1000.0}}
			},
			"MARKET_CONSUMERS_ASTON": {
				"display_name": "Aston Pub Demand",
				"cash": 300.0,
				"inventory": {"BEER_STRONG_LAGER": {"STOCK": 0.0}}
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

	# 3. RUN SANITIZER & AUDIT (Inserted here!)
	# Cleanses world_state["commodity_registry"] and world_state["recipe_registry"] in-place,
	# stripping any broken files so the UI dropdowns never see them.
	CATALOG_VALIDATOR.sanitize_and_audit(world_state, true)

	# 4. Initialize Perceived Cache & Mount to UI
	# Uses the sanitized world_state to populate the Filofax display safely.
	var cache = FILOFAX_MGR.init_cache(world_state)
	binder_ui.initialize(world_state, cache)
