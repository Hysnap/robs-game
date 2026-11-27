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

	print("  PASS [1/3]: REPUTATION & STANDING routes and RESIDENT -> ORG -> GLOBAL inheritance verified.")
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

	print("  PASS [2/3]: INTOXICATION RESIDENT route verified (zero legacy staff fallback).")
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

	print("  PASS [3/3]: Unmapped target_scope fails loud with empty route_path.")
	return true