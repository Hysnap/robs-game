# res://tests/test_commodity_debug_toggle.gd
extends SceneTree

const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING COMMODITY CATALOG DEBUG TOGGLE TEST        ")
	print("=======================================================")

	# 1. Setup Mock Commodity Registry
	var mock_registry: Dictionary = {
		"BEER_STRONG_LAGER": {
			"id": "BEER_STRONG_LAGER",
			"category": "ALCOHOL",
			"display_name": "Super Strength Lager",
			"base_cost": 1.20
		},
		"SPIRITS_GIN": {
			"id": "SPIRITS_GIN",
			"category": "ALCOHOL",
			"display_name": "Dry Gin",
			"base_cost": 4.50
		},
		"ROLLING_TOBACCO": {
			"id": "ROLLING_TOBACCO",
			"category": "TOBACCO",
			"display_name": "Rolling Tobacco",
			"base_cost": 0.80
		},
		"SCRAP_COPPER": {
			"id": "SCRAP_COPPER",
			"category": "RAW_MATERIALS",
			"display_name": "Copper Pipe",
			"base_cost": 3.00
		}
	}

	var test_venue: Dictionary = {
		"id": "OFF_LICENCE_01",
		"archetype": "OFF_LICENCE",
		"trade_categories": ["ALCOHOL"]
	}

	# -------------------------------------------------------------
	# TEST SUITE 1: Standard Mode (Debug Rule Disabled / Missing)
	# -------------------------------------------------------------
	print("\n--- [SUITE 1] Testing Standard Category Filtering ---")
	var world_state_standard: Dictionary = {
		"commodity_registry": mock_registry,
		"debug_rules": {
			"all_items_in_all_stores": false
		}
	}

	var standard_items: Array[Dictionary] = COMMODITY_MGR.get_available_commodities_for_venue(test_venue, world_state_standard)
	print("  Standard items returned: %d (expected 2)" % standard_items.size())
	assert(standard_items.size() == 2, "FAILED: Standard mode should return exactly 2 ALCOHOL items.")

	var standard_ids: Array[String] = []
	for item in standard_items:
		standard_ids.append(str(item.get("id", "")))
	assert(standard_ids.has("BEER_STRONG_LAGER"), "FAILED: Missing BEER_STRONG_LAGER.")
	assert(standard_ids.has("SPIRITS_GIN"), "FAILED: Missing SPIRITS_GIN.")
	assert(not standard_ids.has("ROLLING_TOBACCO"), "FAILED: Filter leaked ROLLING_TOBACCO into off-licence.")
	print("  ✓ PASS: Standard category filtering enforced correctly.")

	# -------------------------------------------------------------
	# TEST SUITE 2: Debug Mode (all_items_in_all_stores = true)
	# -------------------------------------------------------------
	print("\n--- [SUITE 2] Testing Debug Toggle Override ---")
	var world_state_debug: Dictionary = {
		"commodity_registry": mock_registry,
		"debug_rules": {
			"all_items_in_all_stores": true
		}
	}

	var debug_items: Array[Dictionary] = COMMODITY_MGR.get_available_commodities_for_venue(test_venue, world_state_debug)
	print("  Debug items returned: %d (expected 4)" % debug_items.size())
	assert(debug_items.size() == 4, "FAILED: Debug mode should return all 4 registered items.")

	var debug_ids: Array[String] = []
	for item in debug_items:
		debug_ids.append(str(item.get("id", "")))
	assert(debug_ids.has("BEER_STRONG_LAGER"), "FAILED: Missing BEER_STRONG_LAGER in debug mode.")
	assert(debug_ids.has("SPIRITS_GIN"), "FAILED: Missing SPIRITS_GIN in debug mode.")
	assert(debug_ids.has("ROLLING_TOBACCO"), "FAILED: Missing ROLLING_TOBACCO in debug mode.")
	assert(debug_ids.has("SCRAP_COPPER"), "FAILED: Missing SCRAP_COPPER in debug mode.")
	print("  ✓ PASS: Debug toggle correctly surfaced entire catalog.")

	# -------------------------------------------------------------
	# TEST SUITE 3: Missing Rules / Empty Registry Resilience
	# -------------------------------------------------------------
	print("\n--- [SUITE 3] Testing Missing / Default Resilience ---")
	var empty_state: Dictionary = {}
	var empty_res: Array[Dictionary] = COMMODITY_MGR.get_available_commodities_for_venue(test_venue, empty_state)
	assert(empty_res.is_empty(), "FAILED: Empty state should return empty array.")

	var no_debug_state: Dictionary = {
		"commodity_registry": mock_registry
	}
	var no_debug_res: Array[Dictionary] = COMMODITY_MGR.get_available_commodities_for_venue(test_venue, no_debug_state)
	assert(no_debug_res.size() == 2, "FAILED: Missing debug_rules dictionary should default to false.")
	print("  ✓ PASS: Defensive defaults verified.")

	print("\n=======================================================")
	print("   ALL COMMODITY DEBUG TOGGLE TESTS PASSED!            ")
	print("=======================================================\n")
	quit()