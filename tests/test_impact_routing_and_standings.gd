# res://tests/test_impact_routing_and_standings.gd
extends SceneTree

const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const UniversalMetricSinkScript = preload("res://systems/impacts/universal_metric_sink.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Impact Routing, STANDINGS Inheritance & INTOXICATION ---")
	var passed: bool = true
	passed = passed and _test_standings_routes_and_inheritance()
	passed = passed and _test_intoxication_resident_route_zero_staff_fallback()
	passed = passed and _test_profile_scale_bounds_and_cycle_reset()
	passed = passed and _test_unmapped_scope_fails_loud()

	if passed:
		print("--- [Test] ALL IMPACT ROUTING & STANDINGS TESTS PASSED ---\n")
		quit(0)
	else:
		printerr("--- [Test] IMPACT ROUTING & STANDINGS TESTS FAILED ---\n")
		quit(1)

func _test_standings_routes_and_inheritance() -> bool:
	ImpactRouterScript.reset()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")

	if not ImpactRouterScript.has_sink("REPUTATION") or not ImpactRouterScript.has_sink("STANDING"):
		printerr("FAIL [Standings]: Expected both REPUTATION and STANDING sinks mounted.")
		return false

	var ws: Dictionary = {
		"metadata": {"current_sim_day": 29219},
		"standings": {}
	}

	# 1. Public baseline toward Police: high reputation (+0.75), middling trust (+0.10)
	ImpactRouterScript.dispatch_delta(ws, "GLOBAL:PUBLIC->ORG:POLICE", "REPUTATION", 0.75)
	ImpactRouterScript.dispatch_delta(ws, "GLOBAL:PUBLIC->ORG:POLICE", "STANDING", 0.10)

	# 2. Police internal trust toward Police: high (+0.80)
	ImpactRouterScript.dispatch_delta(ws, "ORG:POLICE->ORG:POLICE", "STANDING", 0.80)

	# 3. Officer 102 has a personal grudge/distrust (-0.60) toward Police
	ImpactRouterScript.dispatch_delta(ws, "RESIDENT:102->ORG:POLICE", "STANDING", -0.60)

	var police_affs: Array = [ {"org_scope": "ORG", "org_id": "POLICE"}]

	# Civilian 200 (no org affiliation) inherits GLOBAL:PUBLIC for both
	var civ_rep: float = IntelManagerScript.get_cascading_value(ws, "RESIDENT", "200", "ORG", "POLICE", [], "standings", "reputation")
	var civ_trust: float = IntelManagerScript.get_cascading_value(ws, "RESIDENT", "200", "ORG", "POLICE", [], "standings", "standing")
	if not is_equal_approx(civ_rep, 0.75) or not is_equal_approx(civ_trust, 0.10):
		printerr("FAIL [Standings]: Civilian inheritance mismatch (rep=%.2f, trust=%.2f)." % [civ_rep, civ_trust])
		return false

	# Officer 101 (no personal override) inherits ORG:POLICE trust (+0.80) and GLOBAL:PUBLIC reputation (+0.75)
	var off1_rep: float = IntelManagerScript.get_cascading_value(ws, "RESIDENT", "101", "ORG", "POLICE", police_affs, "standings", "reputation")
	var off1_trust: float = IntelManagerScript.get_cascading_value(ws, "RESIDENT", "101", "ORG", "POLICE", police_affs, "standings", "standing")
	if not is_equal_approx(off1_rep, 0.75) or not is_equal_approx(off1_trust, 0.80):
		printerr("FAIL [Standings]: Officer 101 org inheritance mismatch (rep=%.2f, trust=%.2f)." % [off1_rep, off1_trust])
		return false

	# Officer 102 personal negative override (-0.60) supersedes ORG:POLICE (+0.80)
	var off2_trust: float = IntelManagerScript.get_cascading_value(ws, "RESIDENT", "102", "ORG", "POLICE", police_affs, "standings", "standing")
	if not is_equal_approx(off2_trust, -0.60):
		printerr("FAIL [Standings]: Officer 102 personal override failed (expected -0.60, got %.2f)." % off2_trust)
		return false

	print("  PASS [1/4]: REPUTATION & STANDING routes and RESIDENT -> ORG -> GLOBAL inheritance verified.")
	return true

func _test_intoxication_resident_route_zero_staff_fallback() -> bool:
	ImpactRouterScript.reset()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")

	if not ImpactRouterScript.has_sink("INTOXICATION"):
		printerr("FAIL [Intoxication]: INTOXICATION sink not mounted.")
		return false

	var ws: Dictionary = {
		"residents": {
			101: {"intoxication": 10.0}
		},
		"staff": {
			999: {"intoxication": 10.0}
		}
	}

	ImpactRouterScript.dispatch_delta(ws, "101", "INTOXICATION", 25.0)
	ImpactRouterScript.dispatch_delta(ws, "999", "INTOXICATION", 25.0)

	var res_val: float = float(ws["residents"][101]["intoxication"])
	var staff_val: float = float(ws["staff"][999]["intoxication"])
	if not is_equal_approx(res_val, 35.0):
		printerr("FAIL [Intoxication]: Expected residents[101].intoxication == 35.0, got %.2f." % res_val)
		return false
	if not is_equal_approx(staff_val, 10.0):
		printerr("FAIL [Intoxication]: Legacy staff[999] was mutated (%.2f); zero-fallback violated." % staff_val)
		return false

	print("  PASS [2/4]: INTOXICATION RESIDENT route verified (zero legacy staff fallback).")
	return true

func _test_profile_scale_bounds_and_cycle_reset() -> bool:
	ImpactRouterScript.reset()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")

	var ws: Dictionary = {
		"districts": {"D1": {"zone_health_index": 80.0, "actual_police_heat": 0.0}},
		"residents": {
			"101": {"shift_time_spent": 167.0, "fatigue": 95.0, "actual_skim": 90.0}
		},
		"staff": {
			"101": {"shift_time_spent": 10.0, "fatigue": 10.0, "actual_skim": 10.0}
		},
		"inventory": {"ITEM_A": {"STOCK": 3.0}}
	}

	ImpactRouterScript.dispatch_delta(ws, "D1", "ZONE_HEALTH", -10.0)
	if not is_equal_approx(float(ws["districts"]["D1"]["zone_health_index"]), 70.0):
		printerr("FAIL [Profile Scales]: ZONE_HEALTH must start at its profile baseline and apply the delta.")
		return false
	ImpactRouterScript.dispatch_delta(ws, "D1", "ZONE_HEALTH", -100.0)
	if not is_equal_approx(float(ws["districts"]["D1"]["zone_health_index"]), 0.0):
		printerr("FAIL [Profile Scales]: ZONE_HEALTH must respect its 0-point floor.")
		return false

	ImpactRouterScript.dispatch_delta(ws, "D1", "POLICE_HEAT", 14.0)
	if not is_equal_approx(float(ws["districts"]["D1"]["actual_police_heat"]), 14.0):
		printerr("FAIL [Profile Scales]: POLICE_HEAT must retain deltas on its 0-100 profile scale.")
		return false

	ImpactRouterScript.dispatch_delta(ws, "101", "OPERATIONAL_TIME", 10.0)
	if not is_equal_approx(float(ws["residents"]["101"]["shift_time_spent"]), 168.0):
		printerr("FAIL [Profile Scales]: OPERATIONAL_TIME must respect its declared 168-hour ceiling.")
		return false

	ImpactRouterScript.dispatch_delta(ws, "101", "WORKER_FATIGUE", 10.0)
	ImpactRouterScript.dispatch_delta(ws, "101", "STAFF_SKIM", 20.0)
	if not (
		is_equal_approx(float(ws["residents"]["101"]["fatigue"]), 100.0)
		and is_equal_approx(float(ws["residents"]["101"]["actual_skim"]), 100.0)
	):
		printerr("FAIL [Profile Routes]: Actor fallback metrics must write to RESIDENT records and honor their ceilings.")
		return false
	if not (
		is_equal_approx(float(ws["staff"]["101"]["fatigue"]), 10.0)
		and is_equal_approx(float(ws["staff"]["101"]["actual_skim"]), 10.0)
		and is_equal_approx(float(ws["staff"]["101"]["shift_time_spent"]), 10.0)
	):
		printerr("FAIL [Profile Routes]: Actor fallback metrics must not mutate the staff container.")
		return false

	ImpactRouterScript.dispatch_delta(ws, "ITEM_A", "INVENTORY", -10.0)
	if not is_equal_approx(float(ws["inventory"]["ITEM_A"]["STOCK"]), 0.0):
		printerr("FAIL [Profile Scales]: INVENTORY must route to STOCK and clamp at zero.")
		return false

	var baseline_sink = UniversalMetricSinkScript.new({
		"metric_id": "TEST_BASELINE",
		"metric_class": "FACTUAL_COUNTER",
		"target_scope": "INVENTORY",
		"tuning": {"default_baseline_test": 10.0}
	})
	baseline_sink.apply_delta(ws, "ITEM_BASELINE", 1.0)
	if not is_equal_approx(float(ws["inventory"]["ITEM_BASELINE"]["STOCK"]), 11.0):
		printerr("FAIL [Profile Scales]: Profile-specific default baselines must initialize new routed values.")
		return false

	ImpactRouterScript.dispatch_cycle_start(ws)
	if not is_equal_approx(float(ws["residents"]["101"]["shift_time_spent"]), 0.0):
		printerr("FAIL [Profile Scales]: OPERATIONAL_TIME must reset at cycle start.")
		return false

	print("  PASS [3/4]: Profile bounds, baseline, inventory route and cycle reset verified.")
	return true

func _test_unmapped_scope_fails_loud() -> bool:
	var bad_sink := UniversalMetricSinkScript.new({
		"metric_id": "TEST_UNMAPPED",
		"target_scope": "NONEXISTENT_SCOPE",
		"state_container": "operations",
		"state_field": "phantom"
	})
	if not bad_sink.route_path.is_empty():
		printerr("FAIL [Unmapped]: Expected empty route_path for unmapped scope, got '%s'." % bad_sink.route_path)
		return false

	print("  PASS [4/4]: Unmapped target_scope fails loud with empty route_path.")
	return true