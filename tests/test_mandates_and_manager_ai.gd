# res://tests/test_mandates_and_manager_ai.gd
extends SceneTree

const TestSocietyFactoryScript = preload("res://tests/test_society_factory.gd")
const DBManagerScript = preload("res://systems/db_manager.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const OrgMandateManagerScript = preload("res://systems/economy/org_mandate_manager.gd")
const ManagerAIResolverScript = preload("res://systems/economy/manager_ai_resolver.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

var _frame_count: int = 0
var _executed: bool = false

func _init() -> void:
	print("--- [Test] Verifying 4-Axis Mandates, OCEAN Manager AI & Staggered Horizons (TestSocietyFactory) ---")

func _process(_delta: float) -> bool:
	if _executed:
		return false
	_frame_count += 1
	if _frame_count < 2:
		return false
	_executed = true
	_run_tests_async()
	return false

func _run_tests_async() -> void:
	ScenarioManifestManagerScript.reset_cache()
	ManagerAIResolverScript.reset_cache()
	DirAccess.make_dir_recursive_absolute("user://saves/test_mandate_slot")

	var ws: Dictionary = await TestSocietyFactoryScript.create_test_world_with_crew(4, 4, "mandates-factory-seed", "month")
	ws["metadata"]["active_slot_id"] = "test_mandate_slot"

	var start_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var home_dist: String = str(ws.get("operations", {}).get("home_district_id", ""))
	var crew_ids: Array[int] = []
	for r_key in ws.get("residents", {}).keys():
		var rec = ws["residents"][r_key]
		if rec is Dictionary and (not str(rec.get("slot_id", "")).is_empty() or bool(rec.get("is_crew", false))):
			crew_ids.append(int(rec.get("resident_id", r_key)))
	crew_ids.sort()

	if crew_ids.size() < 2:
		_fail("Expected at least 2 starting crew members from TestSocietyFactory.create_test_world_with_crew().")
		return

	var mgr_a_id: int = crew_ids[0]
	var mgr_b_id: int = crew_ids[1]

	# Configure deterministic OCEAN contrast on real scouted crew operatives
	ws["residents"][mgr_a_id]["iq_score"] = 115.0
	ws["residents"][mgr_a_id]["mental_agility"] = 0.70
	ws["residents"][mgr_a_id]["loyalty"] = 0.85
	ws["residents"][mgr_a_id]["ocean"] = {
		"openness": 0.25, "conscientiousness": 0.85, "extraversion": 0.80, "agreeableness": 0.30, "neuroticism": 0.45
	}

	ws["residents"][mgr_b_id]["iq_score"] = 120.0
	ws["residents"][mgr_b_id]["mental_agility"] = 0.78
	ws["residents"][mgr_b_id]["loyalty"] = 0.88
	ws["residents"][mgr_b_id]["ocean"] = {
		"openness": 0.75, "conscientiousness": 0.70, "extraversion": 0.55, "agreeableness": 0.35, "neuroticism": 0.35
	}

	# Persist ARMS_LENGTH laundering front organization into SQLite & world_state
	TestSocietyFactoryScript.ensure_test_organization(
		ws, "ORG:CHICKEN_CHAIN", "Midlands Fried Chicken", "ORG:CREW_ENTERPRISE", "ARMS_LENGTH", 0.55, 0.78
	)

	# 1. Create overlapping 4-axis mandates for mgr_a and mgr_b
	var m1: Dictionary = OrgMandateManagerScript.create_mandate(ws, {
		"org_id": "ORG:CREW_ENTERPRISE",
		"manager_resident_id": mgr_a_id,
		"title": "Home Ward Pubs & Clubs",
		"mandate_mode": "CASHFLOW",
		"planning_horizon": "MONTH",
		"scope_filter": {
			"spatial": [home_dist],
			"premises": ["PUB", "CLUB"],
			"commodities": ["CONSUMABLES / ALCOHOL"],
			"verbs": ["BUY", "COLLECT_OBLIGATION"]
		}
	})
	var m2: Dictionary = OrgMandateManagerScript.create_mandate(ws, {
		"org_id": "ORG:CREW_ENTERPRISE",
		"manager_resident_id": mgr_b_id,
		"title": "Home Ward Vice & Protection",
		"mandate_mode": "CASHFLOW",
		"planning_horizon": "MONTH",
		"scope_filter": {
			"spatial": [home_dist],
			"premises": ["CLUB"],
			"commodities": ["*"],
			"verbs": ["COLLECT_OBLIGATION", "THREATEN"]
		}
	})

	OrgMandateManagerScript.create_mandate(ws, {
		"org_id": "ORG:CREW_ENTERPRISE",
		"issuer_org_id": "ORG:CREW_ENTERPRISE",
		"target_org_id": "ORG:CHICKEN_CHAIN",
		"title": "Fast Food Laundering Front",
		"mandate_mode": "CASHFLOW",
		"planning_horizon": "MONTH",
		"heat_ceiling": 0.60,
		"target_metrics": {"remittance_target": 1000.0}
	})

	# 2. Verify Data-Driven OCEAN Standardization & Dyadic Collision
	var pol_a: Dictionary = ManagerAIResolverScript.evaluate_standardization_policy(ws["residents"][mgr_a_id], m1)
	if pol_a.get("policy_style") != "RIGID_SOP" or not bool(pol_a.get("suppress_billy_tweaks", false)):
		_fail("Expected high-C / low-O manager (%d) to enforce RIGID_SOP." % mgr_a_id)
		return
	print("PASS 1/5: Data-driven OCEAN standardization policy resolved RIGID_SOP on real crew member.")

	var col: Dictionary = ManagerAIResolverScript.resolve_dyadic_mandate_collision(
		ws["residents"][mgr_a_id], m1, ws["residents"][mgr_b_id], m2
	)
	if not bool(col.get("has_collision", false)) or str(col.get("outcome", "")) != "TURF_RIVALRY":
		_fail("Expected TURF_RIVALRY between low-agreeableness managers on overlapping scope. Got: %s" % str(col))
		return
	print("PASS 2/5: Dyadic 4-axis scope overlap resolved to TURF_RIVALRY via ConditionEvaluator.")

	# 3. Verify Unsolicited vs. Solicited Intervention Guard
	var unauth: Dictionary = OrgMandateManagerScript.evaluate_intervention_authorization(m1, start_day + 2, false)
	if bool(unauth.get("authorized", true)) or not bool(unauth.get("excuse_granted", false)):
		_fail("Expected mid-month unsolicited intervention to be unauthorized with accountability excuse.")
		return
	OrgMandateManagerScript.grant_assistance_window(ws, int(m1["mandate_id"]), start_day + 7)
	var auth: Dictionary = OrgMandateManagerScript.evaluate_intervention_authorization(
		ws["org_mandates"][int(m1["mandate_id"])], start_day + 2, false
	)
	if not bool(auth.get("authorized", false)) or str(auth.get("reason", "")) != "SOLICITED_ASSISTANCE":
		_fail("Expected intervention inside assistance window to be authorized.")
		return
	print("PASS 3/5: Commitment lock & solicited assistance window verified.")

	# 4. Verify Staggered 4-Week Monthly Checkpoints & ARMS_LENGTH Macro Exception at Month Close
	for cp in range(1, 4):
		SimControllerScript.process_turn_cycle(ws, [])
		if int(ws["metadata"].get("month_checkpoint", -1)) != cp:
			_fail("Expected month_checkpoint=%d after weekly step %d." % [cp, cp])
			return
	print("PASS 4/5: Staggered monthly horizon stepped through Weeks 1..3 checkpoints cleanly.")

	var rep_close: Dictionary = SimControllerScript.process_turn_cycle(ws, [])
	if int(ws["metadata"].get("month_checkpoint", -1)) != 0:
		_fail("Expected month_checkpoint to reset to 0 on Week 4 close.")
		return
	var found_arms_exc := false
	for ev in rep_close.get("executed_events", []):
		if ev is Dictionary and str(ev.get("trigger_type", "")) == "ARMS_LENGTH_EXCEPTION":
			found_arms_exc = true
			break
	if not found_arms_exc:
		_fail("Expected ARMS_LENGTH_EXCEPTION alert on month close when subsidiary heat breached ceiling.")
		return
	print("PASS 5/5: Week 4 month close reconciled ARMS_LENGTH subsidiary and emitted exception alert.")

	DBManagerScript.close_database()
	print("--- [Test] ALL MANDATE, MANAGER AI & STAGGERED HORIZON CHECKS PASSED ---")
	quit(0)

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	DBManagerScript.close_database()
	quit(1)