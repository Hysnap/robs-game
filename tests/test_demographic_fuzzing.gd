# res://tests/test_demographic_fuzzing.gd
extends SceneTree

const FILTER = preload("res://systems/multilayer_info_loop/district_perception_filter.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING DEMOGRAPHIC FUZZING & PERCEPTION TEST      ")
	print("=======================================================")

	# 1. Setup Ground-Truth Raw District Data
	var raw_ward: Dictionary = {
		"district_id": "DISTRICT_NECHELLS_01",
		"display_name": "Nechells Green",
		"district_type": "RESIDENTIAL_TERRACES",
		"is_public_landmark": false,
		"active_population": 2847,
		"total_households": 1095,
		"formally_employed_count": 920,
		"street_informal_count": 180,
		"incarcerated_count": 12,
		"establishments_summary": [
			{"name": "Aston Scrap Yard", "worker_count": 42},
			{"name": "The Dog & Partridge", "worker_count": 4},
			{"name": "Midlands General Foundry", "worker_count": 312}
		]
	}

	# -------------------------------------------------------------
	# TEST SUITE 1: Unexplored Ward (Full Fog of War Masking)
	# -------------------------------------------------------------
	print("\n--- [SUITE 1] Testing Unexplored Ward Masking ---")
	var unk_context: Dictionary = {
		"known_districts": [],
		"home_district_id": "DISTRICT_DIGBETH_01",
		"current_sim_day": 10
	}

	var masked_view: Dictionary = FILTER.filter_district_view(raw_ward, unk_context)
	
	# Verify spatial identity survives
	assert(masked_view.get("district_id") == "DISTRICT_NECHELLS_01", "FAILED: district_id must survive.")
	assert(masked_view.get("display_name") == "Nechells Green", "FAILED: display_name must survive.")
	assert(masked_view.get("is_known") == false, "FAILED: is_known must be false.")
	assert(masked_view.get("intel_status") == "INTEL_STATUS_UNEXPLORED", "FAILED: Status must be UNEXPLORED.")

	# Verify sensitive census metrics are completely suppressed
	assert(masked_view.get("active_population") == null, "FAILED: active_population leaked in unexplored ward.")
	assert(masked_view.get("total_households") == null, "FAILED: total_households leaked in unexplored ward.")
	assert(masked_view.get("establishments_summary").is_empty(), "FAILED: establishments_summary leaked in unexplored ward.")
	print("  ✓ PASS: Unexplored ward correctly masked all private census and business telemetry.")

	# -------------------------------------------------------------
	# TEST SUITE 2: Surveyed Remote Ward (General Perception)
	# -------------------------------------------------------------
	print("\n--- [SUITE 2] Testing Surveyed Ward Transformation ---")
	var known_context: Dictionary = {
		"known_districts": ["DISTRICT_NECHELLS_01"],
		"home_district_id": "DISTRICT_DIGBETH_01",
		"current_sim_day": 15,
		"district_survey_ticks": {"DISTRICT_NECHELLS_01": 15}
	}

	var surveyed_view: Dictionary = FILTER.filter_district_view(raw_ward, known_context)
	assert(surveyed_view.get("is_known") == true, "FAILED: is_known must be true.")
	assert(surveyed_view.get("is_home_turf") == false, "FAILED: is_home_turf must be false.")
	assert(surveyed_view.get("intel_status") == "INTEL_STATUS_VERIFIED", "FAILED: Status must be VERIFIED.")

	# Verify establishments are hydrated and workforce headcounts processed
	var estabs: Array = surveyed_view.get("establishments_summary", [])
	assert(estabs.size() == 3, "FAILED: Establishments summary must be hydrated for known ward.")
	print("  Surveyed establishments count: %d" % estabs.size())
	for e in estabs:
		print("    - %s: workforce=%s" % [e.get("name"), str(e.get("worker_count"))])
	print("  ✓ PASS: Surveyed ward transformed telemetry and hydrated establishments.")

	# -------------------------------------------------------------
	# TEST SUITE 3: Home Turf Ward (Sharpened Perception)
	# -------------------------------------------------------------
	print("\n--- [SUITE 3] Testing Home Turf Perception ---")
	var home_context: Dictionary = {
		"known_districts": ["DISTRICT_NECHELLS_01"],
		"home_district_id": "DISTRICT_NECHELLS_01",
		"current_sim_day": 15,
		"district_survey_ticks": {"DISTRICT_NECHELLS_01": 15}
	}

	var home_view: Dictionary = FILTER.filter_district_view(raw_ward, home_context)
	assert(home_view.get("is_home_turf") == true, "FAILED: is_home_turf must be true.")
	print("  ✓ PASS: Home turf flag cleanly propagated.")

	# -------------------------------------------------------------
	# TEST SUITE 4: Stale Intel Temporal Decay
	# -------------------------------------------------------------
	print("\n--- [SUITE 4] Testing Stale Intel Decay ---")
	var stale_context: Dictionary = {
		"known_districts": ["DISTRICT_NECHELLS_01"],
		"home_district_id": "DISTRICT_DIGBETH_01",
		"current_sim_day": 100, # 85 days elapsed (> 28-day threshold)
		"district_survey_ticks": {"DISTRICT_NECHELLS_01": 15}
	}

	var stale_view: Dictionary = FILTER.filter_district_view(raw_ward, stale_context)
	print("  Elapsed days: 85 -> Intel status: %s" % stale_view.get("intel_status"))
	assert(stale_view.get("intel_status") == "INTEL_STATUS_STALE", "FAILED: Expected INTEL_STATUS_STALE.")
	print("  ✓ PASS: Temporal decay accurately flagged stale intelligence.")

	print("\n=======================================================")
	print("   ALL DEMOGRAPHIC FUZZING TESTS PASSED CLEANLY!       ")
	print("=======================================================\n")
	quit()