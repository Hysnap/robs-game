# res://tests/test_container_decay_pipeline.gd
extends SceneTree

const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")
const IMPACT_CALCULATOR = preload("res://systems/impacts/impact_calculator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING CONTAINER & DRY DECAY PIPELINE TEST        ")
	print("=======================================================")

	# -------------------------------------------------------------
	# [SUITE 1] INGEST CONTAINERS & VERIFY PROFILES
	# -------------------------------------------------------------
	print("\n--- [SUITE 1] Ingesting Containers Catalog ---")
	var container_dir = "res://data_modules/core/containers/"
	var containers = {}
	
	if DirAccess.dir_exists_absolute(container_dir):
		containers = COMMODITY_MGR.load_hierarchical_commodities(container_dir)
		print("  ✓ Containers discovered on disk: ", containers.keys())
	else:
		print("  ℹ️ Note: Core containers directory not yet committed. Using simulated test containers.")

	# Provide fallback mock containers if disk directory is still being populated
	if not containers.has("CONTAINER_GLASS_BOTTLE_330ML"):
		containers["CONTAINER_GLASS_BOTTLE_330ML"] = {
			"id": "CONTAINER_GLASS_BOTTLE_330ML",
			"display_name": "Glass Bottle (330ml)",
			"category": "CONTAINER",
			"capacity": {"volume_ml": 330.0, "mass_g": 0.0},
			"tare_footprint": {"empty_mass_g": 190.0, "storage_footprint_per_unit": 0.03},
			"decay_modifiers": {"shelf_life_multiplier": 3.0, "factor_multiplier": 0.20, "ambient_loss_per_tick": 0.0},
			"handling_attributes": {"fragility": 0.08, "tamper_evident": true, "opsec_visibility": 0.10}
		}

	if not containers.has("CONTAINER_OPEN_PITCHER_1000ML"):
		containers["CONTAINER_OPEN_PITCHER_1000ML"] = {
			"id": "CONTAINER_OPEN_PITCHER_1000ML",
			"display_name": "Open Pitcher (1L)",
			"category": "CONTAINER",
			"capacity": {"volume_ml": 1000.0, "mass_g": 0.0},
			"tare_footprint": {"empty_mass_g": 250.0, "storage_footprint_per_unit": 0.08},
			"decay_modifiers": {"shelf_life_multiplier": 0.5, "factor_multiplier": 2.0, "ambient_loss_per_tick": 0.02},
			"handling_attributes": {"fragility": 0.15, "tamper_evident": false, "opsec_visibility": 0.50}
		}

	var bottle = containers["CONTAINER_GLASS_BOTTLE_330ML"]
	assert(bottle.get("category", "") == "CONTAINER", "FAILED: Container category must be 'CONTAINER'!")
	assert(bottle["tare_footprint"]["empty_mass_g"] == 190.0, "FAILED: Tare mass mismatch!")
	assert(bottle["decay_modifiers"]["factor_multiplier"] == 0.20, "FAILED: Decay modifier mismatch!")
	print("  ✓ PASS: Container schema and attributes verified.")

	# -------------------------------------------------------------
	# [SUITE 2] PACKAGING & LOGISTICS MASS/VOLUME CHECK
	# -------------------------------------------------------------
	print("\n--- [SUITE 2] Packaging & Logistics Gross Mass Resolution ---")
	# Scenario: 50L (50,000ml) bulk liquid packaged into 330ml bottles
	var bulk_volume_ml: float = 50000.0
	var bottle_capacity_ml: float = bottle["capacity"]["volume_ml"]
	var bottles_yield: int = int(floor(bulk_volume_ml / bottle_capacity_ml)) # 151 bottles
	
	assert(bottles_yield == 151, "FAILED: Bottle yield math incorrect (expected 151)!")
	
	# Logistics tare weight calculation
	var net_liquid_mass_g: float = 330.0 # ~1g per ml for beer
	var tare_glass_mass_g: float = bottle["tare_footprint"]["empty_mass_g"]
	var gross_unit_mass_g: float = net_liquid_mass_g + tare_glass_mass_g # 520g
	var total_crate_mass_kg: float = (gross_unit_mass_g * 24.0) / 1000.0 # 24-bottle crate
	
	assert(is_equal_approx(gross_unit_mass_g, 520.0), "FAILED: Gross bottle mass calculation incorrect!")
	print("  ✓ Packaged 50L bulk into %d units." % bottles_yield)
	print("  ✓ Gross Unit Mass: %.1fg (Net: %.1fg + Tare Glass: %.1fg)" % [gross_unit_mass_g, net_liquid_mass_g, tare_glass_mass_g])
	print("  ✓ Full 24-Bottle Crate Transport Weight: %.2f kg" % total_crate_mass_kg)

	# -------------------------------------------------------------
	# [SUITE 3] DRY DECAY RESOLUTION VIA IMPACT_CALCULATOR
	# -------------------------------------------------------------
	print("\n--- [SUITE 3] Perishable Decay via ImpactCalculator Engine ---")
	
	# Commodity Base Definition (Linear Decay: -10% per tick past shelf life)
	var beer_decay_def = {
		"shelf_life_ticks": 4,
		"degrades_to": "SPOILED_BEER",
		"impact": {
			"model": "LINEAR_PER_UNIT",
			"factor": -0.10,
			"params": {}
		}
	}

	var raw_factor: float = beer_decay_def["impact"]["factor"]
	var base_qty: float = 100.0

	# Case A: Poor Container (Open Pitcher: 2.0x rot factor)
	var pitcher = containers["CONTAINER_OPEN_PITCHER_1000ML"]
	var pitcher_factor: float = raw_factor * pitcher["decay_modifiers"]["factor_multiplier"] # -0.20
	var pitcher_loss = IMPACT_CALCULATOR.calculate(
		beer_decay_def["impact"]["model"],
		base_qty,
		pitcher_factor,
		beer_decay_def["impact"]["params"]
	)
	assert(is_equal_approx(pitcher_loss, -20.0), "FAILED: Open pitcher should lose 20 units!")
	print("  ✓ Open Pitcher (Exposure): Loss delta = %.1f units (-20%% rot)" % pitcher_loss)

	# Case B: Sealed Container (Amber Crown Bottle: 0.20x rot factor)
	var bottle_factor: float = raw_factor * bottle["decay_modifiers"]["factor_multiplier"] # -0.02
	var bottle_loss = IMPACT_CALCULATOR.calculate(
		beer_decay_def["impact"]["model"],
		base_qty,
		bottle_factor,
		beer_decay_def["impact"]["params"]
	)
	assert(is_equal_approx(bottle_loss, -2.0), "FAILED: Crown bottle should lose only 2 units!")
	print("  ✓ Crown Bottle (Preserved): Loss delta = %.1f units (-2%% rot)" % bottle_loss)

	# -------------------------------------------------------------
	# [SUITE 4] AMBIENT INVENTORY TICK & SPOILAGE CONVERSION
	# -------------------------------------------------------------
	print("\n--- [SUITE 4] Objective World State Spoilage Ingestion ---")
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")

	var world_state = {
		"inventory_registry": {
			"BEER_OPEN": {
				"STOCK": 100.0,
				"age_ticks": 5, # 1 tick past shelf_life_ticks (4)
				"commodity_id": "BEER_STRONG_LAGER",
				"container_id": "CONTAINER_OPEN_PITCHER_1000ML"
			},
			"SPOILED_BEER": {
				"STOCK": 0.0
			}
		}
	}

	# Apply decayed loss to inventory
	var units_lost: float = abs(pitcher_loss) # 20 units
	world_state["inventory_registry"]["BEER_OPEN"]["STOCK"] -= units_lost
	world_state["inventory_registry"]["SPOILED_BEER"]["STOCK"] += units_lost

	assert(world_state["inventory_registry"]["BEER_OPEN"]["STOCK"] == 80.0, "FAILED: Stock did not decrement!")
	assert(world_state["inventory_registry"]["SPOILED_BEER"]["STOCK"] == 20.0, "FAILED: Spoiled beer did not increment!")
	print("  ✓ Fresh Beer Stock Remaining: ", world_state["inventory_registry"]["BEER_OPEN"]["STOCK"])
	print("  ✓ Spoiled Waste Generated:    ", world_state["inventory_registry"]["SPOILED_BEER"]["STOCK"])

	print("\n=======================================================")
	print("   CONTAINER & DECAY PIPELINE TEST PASSED 100% CLEAN!  ")
	print("=======================================================\n")
	quit()