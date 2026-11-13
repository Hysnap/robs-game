# res://tests/test_intel_saturation_engine.gd
extends SceneTree

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

func _init() -> void:
	print("=== STARTING INTEL SATURATION & EXPOSURE ENGINE TEST ===")

	ScenarioManifestManagerScript.reset_cache()
	IntelManagerScript.reset_cache()
	ImpactRouterScript.reset()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")

	assert(ImpactRouterScript.has_sink("INTEL_SCORE"), "FAIL: INTEL_SCORE sink was not mounted by ImpactRouter.")

	var world_state: Dictionary = {
		"metadata": {"current_sim_day": 100},
		"knowledge_pools": {}
	}

	_test_hyperbolic_saturation_and_friction(world_state)
	_test_compartmentalization_and_clearance(world_state)
	_test_exposure_thresholds_and_fuzz()
	_test_ambient_decay_floor(world_state)

	print("=== ALL INTEL SATURATION ENGINE CHECKS PASSED ===")
	quit(0)

func _test_hyperbolic_saturation_and_friction(world_state: Dictionary) -> void:
	# 1. Local scout (distance 0, default permeability 0.85, base H = 30.0)
	var s1: float = IntelManagerScript.apply_effort_impulse(
		world_state, "RESIDENT", "101", "DISTRICT", "block_0_0", 20.0, {"distance": 0.0}
	)
	assert(s1 > 30.0 and s1 < 45.0, "FAIL: Expected initial effort impulse to yield ~36.1, got %.2f" % s1)

	# 2. Distant scout (distance 4 -> multiplier 1 / (1 + 0.35*4) = 0.4167) yields strictly less
	var s_far: float = IntelManagerScript.apply_effort_impulse(
		world_state, "RESIDENT", "102", "DISTRICT", "block_0_0", 20.0, {"distance": 4.0}
	)
	assert(s_far < s1, "FAIL: Distant observation (%.2f) should yield less than co-located observation (%.2f)" % [s_far, s1])

	# 3. Massive effort saturates asymptotically below 100.0 (never reaches 100.0)
	var s_heavy: float = IntelManagerScript.apply_effort_impulse(
		world_state, "RESIDENT", "101", "DISTRICT", "block_0_0", 5000.0, {"distance": 0.0}
	)
	assert(s_heavy > 98.0 and s_heavy < 100.0, "FAIL: Heavy effort should saturate asymptotically below 100.0, got %.4f" % s_heavy)

	# 4. Large organization maintenance friction (org_size = 40 increases H by 3x)
	var s_small_org: float = IntelManagerScript.apply_effort_impulse(
		world_state, "ESTABLISHMENT", "10", "ESTABLISHMENT", "99", 25.0, {"observer_org_size": 0.0}
	)
	var s_large_org: float = IntelManagerScript.apply_effort_impulse(
		world_state, "ESTABLISHMENT", "20", "ESTABLISHMENT", "99", 25.0, {"observer_org_size": 40.0}
	)
	assert(s_large_org < s_small_org, "FAIL: Larger organization (%.2f) should require more effort than small org (%.2f)" % [s_large_org, s_small_org])
	print("  [PASS] Hyperbolic saturation, distance decay, and organizational maintenance friction verified.")

func _test_compartmentalization_and_clearance(world_state: Dictionary) -> void:
	# Precinct (ESTABLISHMENT:50) holds an official case file on RESIDENT:889 at score 60.0
	IntelManagerScript.apply_effort_impulse(
		world_state, "ESTABLISHMENT", "50", "RESIDENT", "889", 30.0, {"access_permeability": 1.0}
	)
	var precinct_score: float = IntelManagerScript.get_direct_score(world_state, "ESTABLISHMENT", "50", "RESIDENT", "889")
	assert(precinct_score == 60.0, "FAIL: Expected precinct score 60.0, got %.2f" % precinct_score)

	# PC Bob (RESIDENT:412, POLICE_CONSTABLE clearance = 0.40) inherits 60.0 * 0.40 = 24.0
	var bob_affs := [{"org_scope": "ESTABLISHMENT", "org_id": "50", "role_code": "POLICE_CONSTABLE"}]
	var bob_inherited: float = IntelManagerScript.get_effective_score(world_state, "RESIDENT", "412", "RESIDENT", "889", bob_affs)
	assert(is_equal_approx(bob_inherited, 24.0), "FAIL: Expected PC Bob inherited score 24.0, got %.2f" % bob_inherited)

	# Superintendent (RESIDENT:105, CIVIC_OFFICIAL clearance = 1.00) inherits 60.0 * 1.00 = 60.0
	var super_affs := [{"org_scope": "ESTABLISHMENT", "org_id": "50", "role_code": "CIVIC_OFFICIAL"}]
	var super_inherited: float = IntelManagerScript.get_effective_score(world_state, "RESIDENT", "105", "RESIDENT", "889", super_affs)
	assert(is_equal_approx(super_inherited, 60.0), "FAIL: Expected Superintendent inherited score 60.0, got %.2f" % super_inherited)

	# PC Bob personally drinks with Suspect 777 (score ~75.0) — Superintendent must NOT see it automatically!
	IntelManagerScript.apply_effort_impulse(
		world_state, "RESIDENT", "412", "RESIDENT", "777", 60.0, {"access_permeability": 1.0}
	)
	var super_on_777: float = IntelManagerScript.get_effective_score(world_state, "RESIDENT", "105", "RESIDENT", "777", super_affs)
	assert(super_on_777 == 0.0, "FAIL: Personal knowledge leaked upward to Superintendent without transfer! Got %.2f" % super_on_777)

	# Bob explicitly files a report (transfer_intel) into Precinct 50 -> now Superintendent sees it
	IntelManagerScript.transfer_intel(world_state, "RESIDENT", "412", "ESTABLISHMENT", "50", "RESIDENT", "777", 0.8)
	var super_after_report: float = IntelManagerScript.get_effective_score(world_state, "RESIDENT", "105", "RESIDENT", "777", super_affs)
	assert(super_after_report > 40.0, "FAIL: Superintendent should see reported intel after transfer, got %.2f" % super_after_report)
	print("  [PASS] Role clearance inheritance and upward compartmentalization verified.")

func _test_exposure_thresholds_and_fuzz() -> void:
	var raw_estab := {
		"establishment_id": 37,
		"name": "The Crown & Anchor",
		"category_code": "PUBLIC_HOUSE",
		"district_id": "block_0_0",
		"street_address": "14 High Street",
		"capacity": 85,
		"market_catchment": {"total": 1200}
	}

	assert(IntelManagerScript.project_record(raw_estab, 0.0, "ESTABLISHMENT").is_empty(), "FAIL: Score 0.0 must hide entity completely.")

	var tier_15 := IntelManagerScript.project_record(raw_estab, 15.0, "ESTABLISHMENT")
	assert(tier_15.has("name") and not tier_15.has("capacity"), "FAIL: Score 15.0 should expose name but not capacity.")

	var tier_85 := IntelManagerScript.project_record(raw_estab, 85.0, "ESTABLISHMENT")
	assert(tier_85.has("market_catchment"), "FAIL: Score 85.0 should expose market_catchment.")

	var fuzz_low: float = IntelManagerScript.attenuate_fuzz(0.20, 0.02, 10.0)
	var fuzz_high: float = IntelManagerScript.attenuate_fuzz(0.20, 0.02, 90.0)
	assert(fuzz_high < fuzz_low and fuzz_high >= 0.02, "FAIL: Fuzz must shrink toward error_floor as score rises.")
	print("  [PASS] Evenly-spaced threshold exposure and fuzz attenuation verified.")

func _test_ambient_decay_floor(world_state: Dictionary) -> void:
	# Tick ambient weekly cooling several times; score on block_0_0 for RESIDENT:102 should cool to discovery_floor (15.0) and stop
	for _i in range(20):
		ImpactRouterScript.dispatch_ambient_tick(world_state)
	var cooled: float = IntelManagerScript.get_direct_score(world_state, "RESIDENT", "102", "DISTRICT", "block_0_0")
	assert(is_equal_approx(cooled, 15.0), "FAIL: Expected score to cool to discovery_floor 15.0, got %.2f" % cooled)
	print("  [PASS] Weekly ambient decay to discovery_floor verified.")