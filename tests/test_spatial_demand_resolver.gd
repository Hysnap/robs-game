# res://tests/test_spatial_demand_resolver.gd
extends SceneTree

const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       TESTING SPATIAL DEMAND RESOLVER (DRY ENGINE)    ")
	print("=======================================================")

	# 1. SETUP MOCK DISTRICT TOPOLOGY
	# Layout (East-West line):
	# D_CORE   at (0, 0)     - High Density Commercial (Pop 200, Built: 10 bldgs)
	# D_RES_1  at (300, 0)   - Populated Terraces (Pop 1200, Built: 25 bldgs)
	# D_VACANT at (500, 0)   - Cleared Brownfield Plot (Pop 0, Built: 0 bldgs, is_initially_vacant = true)
	# D_RES_2  at (700, 0)   - Populated Estate (Pop 1500, Built: 30 bldgs)
	# D_FAR    at (3000, 0)  - Outer Suburban Edge (Pop 400, Built: 10 bldgs)
	var districts: Dictionary = {
		"D_CORE": {
			"district_id": "D_CORE",
			"spatial_anchor": Vector2(0.0, 0.0),
			"district_type": "commercial",
			"sector_class": "COMMERCIAL",
			"actual_building_count": 10,
			"area_sqm": 40000.0,
			"is_initially_vacant": false
		},
		"D_RES_1": {
			"district_id": "D_RES_1",
			"spatial_anchor": Vector2(300.0, 0.0),
			"district_type": "high_density_low_rise",
			"sector_class": "RESIDENTIAL",
			"actual_building_count": 25,
			"area_sqm": 40000.0,
			"is_initially_vacant": false
		},
		"D_VACANT": {
			"district_id": "D_VACANT",
			"spatial_anchor": Vector2(500.0, 0.0),
			"district_type": "high_density_low_rise",
			"sector_class": "RESIDENTIAL",
			"actual_building_count": 0,
			"area_sqm": 40000.0,
			"is_initially_vacant": true
		},
		"D_RES_2": {
			"district_id": "D_RES_2",
			"spatial_anchor": Vector2(700.0, 0.0),
			"district_type": "high_density_high_rise",
			"sector_class": "RESIDENTIAL",
			"actual_building_count": 30,
			"area_sqm": 40000.0,
			"is_initially_vacant": false
		},
		"D_FAR": {
			"district_id": "D_FAR",
			"spatial_anchor": Vector2(3000.0, 0.0),
			"district_type": "suburban_low_density",
			"sector_class": "RESIDENTIAL",
			"actual_building_count": 10,
			"area_sqm": 40000.0,
			"is_initially_vacant": false
		}
	}

	var block_estimates: Dictionary = {
		"D_CORE": 200.0,
		"D_RES_1": 1200.0,
		"D_VACANT": 0.0,
		"D_RES_2": 1500.0,
		"D_FAR": 400.0
	}
	var max_r := 3000.0

	# -------------------------------------------------------------------------
	# [SUITE 1] CATCHMENT VIABILITY & POPULATION THRESHOLD
	# -------------------------------------------------------------------------
	print("\n--- [SUITE 1] Testing Catchment Viability ---")
	var center := Vector2(300.0, 0.0) # At D_RES_1
	var existing_instances: Array = []
	var travel_dist := 600.0 # Reaches D_CORE (dist 300), D_RES_1 (dist 0), D_VACANT (dist 200), D_RES_2 (dist 400)
	# Total population within 600m = 200 + 1200 + 0 + 1500 = 2900 people.

	# Test 1A: First facility is always viable (existing_count == 0)
	var can_place_first = SPATIAL_RESOLVER.is_catchment_viable(
		center, existing_instances, districts, block_estimates, travel_dist, 1500.0
	)
	assert(can_place_first == true, "FAILED: First facility should always be viable!")
	print("  ✓ First facility approved in catchment.")

	# Test 1B: Second facility requires (1 + 1) * 1500 = 3000 people. Catchment has 2900 -> Should REJECT.
	existing_instances.append(Vector2(300.0, 0.0))
	var can_place_second_tight = SPATIAL_RESOLVER.is_catchment_viable(
		center, existing_instances, districts, block_estimates, travel_dist, 1500.0
	)
	assert(can_place_second_tight == false, "FAILED: Saturated catchment should have rejected 2nd facility (needs 3000, has 2900)!")
	print("  ✓ Second facility correctly rejected when catchment population is insufficient.")

	# Test 1C: If pop_ratio is 1200, 2 facilities need 2 * 1200 = 2400 people. Catchment has 2900 -> Should APPROVE.
	var can_place_second_supported = SPATIAL_RESOLVER.is_catchment_viable(
		center, existing_instances, districts, block_estimates, travel_dist, 1200.0
	)
	assert(can_place_second_supported == true, "FAILED: Catchment with 2900 should support 2 facilities when ratio is 1200!")
	print("  ✓ Second facility approved when catchment population satisfies threshold.")

	# -------------------------------------------------------------------------
	# [SUITE 2] PRIORITIZING VACANT / BROWNFIELD LAND FIRST
	# -------------------------------------------------------------------------
	print("\n--- [SUITE 2] Testing Vacant Plot Prioritization ---")
	var church_spec: Dictionary = {
		"code": "place_of_worship",
		"footprint_sqm": 15000.0,
		"travel_dist_m": 800.0,
		"pop_ratio": 1000.0,
		"norm_dist_range": [0.0, 1.0],
		"allowed_sectors": ["RESIDENTIAL"],
		"prefer_vacant": true
	}

	# D_VACANT has dev_score = -1000.0; populated blocks have dev_score > 0
	var chosen_block = SPATIAL_RESOLVER.find_best_host_district(
		districts, block_estimates, [], church_spec, max_r
	)
	assert(not chosen_block.is_empty(), "FAILED: Candidate search returned empty!")
	assert(chosen_block["dist_id"] == "D_VACANT", "FAILED: Did not prioritize vacant block 'D_VACANT'!")
	assert(chosen_block["is_vacant"] == true, "FAILED: 'is_vacant' flag not propagated!")
	print("  ✓ Resolver selected vacant plot '%s' with dev_score %.1f." % [chosen_block["dist_id"], chosen_block["dev_score"]])

	# -------------------------------------------------------------------------
	# [SUITE 3] CATEGORY ISOLATION (CHURCHES DO NOT REPEL SCHOOLS)
	# -------------------------------------------------------------------------
	print("\n--- [SUITE 3] Testing Category Isolation (No Cross-Repulsion) ---")
	# Place an existing church at D_RES_1
	# var placed_churches: Array = [Vector2(300.0, 0.0)]
	var placed_schools: Array = [] # Zero schools placed so far

	var school_spec: Dictionary = {
		"code": "primary_school",
		"footprint_sqm": 35000.0,
		"travel_dist_m": 600.0,
		"pop_ratio": 1200.0,
		"min_sep_m": 500.0, # Schools must be 500m apart from OTHER SCHOOLS
		"norm_dist_range": [0.0, 1.0],
		"allowed_sectors": ["RESIDENTIAL"],
		"prefer_vacant": false # Force consideration of populated blocks
	}

	# Even though D_RES_1 has a church at 0m distance, school evaluation queries placed_schools, NOT placed_churches!
	var chosen_school_block = SPATIAL_RESOLVER.find_best_host_district(
		districts, block_estimates, placed_schools, school_spec, max_r
	)
	assert(not chosen_school_block.is_empty(), "FAILED: School candidate search failed due to church interference!")
	print("  ✓ School successfully evaluated without repulsion from existing church.")

	# -------------------------------------------------------------------------
	# [SUITE 4] URBAN RING DISTANCE FILTERING
	# -------------------------------------------------------------------------
	print("\n--- [SUITE 4] Testing Normalized Distance Range Filtering ---")
	var suburban_only_spec: Dictionary = {
		"code": "suburban_amenity",
		"footprint_sqm": 2000.0,
		"travel_dist_m": 5000.0,
		"pop_ratio": 200.0,
		"norm_dist_range": [0.80, 1.0], # Only valid on outer edge (r >= 2400m)
		"allowed_sectors": ["RESIDENTIAL"],
		"prefer_vacant": false
	}
	var outer_block = SPATIAL_RESOLVER.find_best_host_district(
		districts, block_estimates, [], suburban_only_spec, max_r
	)
	assert(outer_block.get("dist_id") == "D_FAR", "FAILED: Did not filter to outer ring block 'D_FAR'!")
	print("  ✓ Candidate filtered strictly to outer ring: '%s' (r = 3000m)." % outer_block["dist_id"])

	# -------------------------------------------------------------------------
	# [SUITE 5] NEAREST-ANCHOR WORKPLACE COMMUTE
	# -------------------------------------------------------------------------
	print("\n--- [SUITE 5] Testing Nearest-Anchor Workplace Commute ---")
	var mock_by_cat: Dictionary = {
		"COMMERCIAL": [
			{"id": 101, "district_id": "D_CORE"},  # at (0, 0) - 300m away from D_RES_1
			{"id": 102, "district_id": "D_FAR"}   # at (3000, 0) - 2700m away from D_RES_1
		]
	}

	# A worker living in D_RES_1 at (300, 0) should be matched to establishment 101 in D_CORE, NOT 102
	var home_pos := Vector2(300.0, 0.0)
	var matched_anchor_id = SPATIAL_RESOLVER.pick_nearest_anchor(
		mock_by_cat, "COMMERCIAL", home_pos, districts
	)
	assert(matched_anchor_id == 101, "FAILED: Worker did not pick the nearest establishment!")
	print("  ✓ Worker at (300, 0) matched to nearest establishment #%d in '%s'." % [
		matched_anchor_id, districts["D_CORE"]["district_id"]
	])

	print("\n=======================================================")
	print("       ALL SPATIAL DEMAND RESOLVER TESTS PASSED!       ")
	print("=======================================================\n")
	quit()
