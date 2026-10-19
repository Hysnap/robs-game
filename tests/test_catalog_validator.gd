# res://tests/test_catalog_validator.gd
extends SceneTree

const CATALOG_VALIDATOR = preload("res://systems/catalog_validator.gd")
const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       STARTING CATALOG VALIDATOR SYSTEM TEST          ")
	print("=======================================================")

	# -------------------------------------------------------------
	# TEST SUITE 1: AUDIT LIVE ON-DISK CATALOGS
	# -------------------------------------------------------------
	print("\n--- [SUITE 1] Auditing Live Disk Catalogs ---")
	VERB_ROUTER.initialize()
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")
	
	var commodities = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/commodities/")
	var recipes = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/recipes/")

	var live_world_state = {
		"commodity_registry": commodities,
		"recipe_registry": recipes
	}

	var live_report = CATALOG_VALIDATOR.validate_catalogs(live_world_state, true)
	print("  Live Commodities Loaded: ", live_report["commodity_count"])
	print("  Live Recipes Loaded:     ", live_report["recipe_count"])
	print("  Live Catalog Clean:      ", live_report["is_clean"])
	
	assert(live_report["is_clean"] == true, "FAILED: Live catalog has integrity errors!")
	assert(live_report["errors"].is_empty(), "FAILED: Live catalog emitted unexpected errors!")
	print("  ✓ PASS: Live catalog data is 100% valid.")

	# -------------------------------------------------------------
	# TEST SUITE 2: DETECT INVALID COMMODITIES (Injection Test)
	# -------------------------------------------------------------
	print("\n--- [SUITE 2] Stress-Testing Bad Commodity Data ---")
	var bad_commodities = {
		"BAD_ITEM_1": {
			"category": "INVALID_CAT_TYPE", # Invalid category
			"base_cost": 2.50,
			"impact_activations": {}
		},
		"BAD_ITEM_2": {
			"category": "CONSUMABLE",
			"base_cost": 0.0, # Zero cost warning
			"impact_activations": {
				"BUY": [{"metric": "HEAT", "model": "NON_EXISTENT_MODEL", "factor": 1.0}] # Invalid model
			}
		}
	}

	var bad_comm_state = {
		"commodity_registry": bad_commodities,
		"recipe_registry": {}
	}

	var comm_report = CATALOG_VALIDATOR.validate_catalogs(bad_comm_state, false)
	assert(comm_report["is_clean"] == false, "FAILED: Validator failed to catch bad commodity category/model!")
	assert(comm_report["errors"].size() == 2, "FAILED: Expected exactly 2 commodity errors, got: %d" % comm_report["errors"].size())
	assert(comm_report["warnings"].size() == 1, "FAILED: Expected 1 zero-cost warning, got: %d" % comm_report["warnings"].size())
	print("  ✓ PASS: Detected invalid category, unknown impact model, and zero-cost warning.")

	# -------------------------------------------------------------
	# TEST SUITE 3: DETECT BROKEN RECIPES (Injection Test)
	# -------------------------------------------------------------
	print("\n--- [SUITE 3] Stress-Testing Corrupted Recipe Data ---")
	var valid_commodities_pool = {
		"RAW_TOBACCO": {"category": "CONSUMABLE", "base_cost": 1.0, "impact_activations": {}},
		"ROLLING_PAPERS": {"category": "CONSUMABLE", "base_cost": 0.5, "impact_activations": {}}
		# Note: "FINISHED_JOINT" is intentionally missing from this pool!
	}

	var broken_recipes = {
		"RECIPE_GHOST_OUTPUT": {
			"output_item": "FINISHED_JOINT", # Does not exist in commodities
			"output_yield_units": 10,
			"inputs": {"RAW_TOBACCO": 1}
		},
		"RECIPE_ZERO_YIELD": {
			"output_item": "RAW_TOBACCO",
			"output_yield_units": 0, # Zero yield error
			"inputs": {"ROLLING_PAPERS": 1}
		},
		"RECIPE_MISSING_INGREDIENT": {
			"output_item": "RAW_TOBACCO",
			"output_yield_units": 1,
			"inputs": {"SECRET_CHEM_X": 5} # Ingredient not in catalog
		}
	}

	var bad_recipe_state = {
		"commodity_registry": valid_commodities_pool,
		"recipe_registry": broken_recipes
	}

	var recipe_report = CATALOG_VALIDATOR.validate_catalogs(bad_recipe_state, false)
	assert(recipe_report["is_clean"] == false, "FAILED: Validator missed corrupted recipe rules!")
	assert(recipe_report["errors"].size() == 3, "FAILED: Expected exactly 3 recipe errors, got: %d" % recipe_report["errors"].size())
	print("  ✓ PASS: Detected ghost output items, zero yields, and missing recipe ingredients.")

	# -------------------------------------------------------------
	# TEST SUITE 4: VERIFY AUDIT LOG FILE PERSISTENCE
	# -------------------------------------------------------------
	print("\n--- [SUITE 4] Verifying user:// Log File Output ---")
	var log_path = "user://catalog_audit.log"
	assert(FileAccess.file_exists(log_path), "FAILED: Audit log was not written to disk!")
	
	var log_file = FileAccess.open(log_path, FileAccess.READ)
	var log_contents = log_file.get_as_text()
	log_file.close()
	
	assert(log_contents.contains("CATALOG INTEGRITY AUDIT"), "FAILED: Log file missing header!")
	print("  ✓ PASS: Audit log written cleanly to '%s' (%d bytes)" % [log_path, log_contents.length()])

	print("\n=======================================================")
	print("       ALL CATALOG VALIDATOR TESTS PASSED!             ")
	print("=======================================================\n")
	quit()