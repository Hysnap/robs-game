# res://tests/test_crime_routes_and_timeline.gd
extends SceneTree

const DBManagerScript = preload("res://systems/db_manager.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const RouteRoundSeederScript = preload("res://systems/society/route_round_seeder.gd")
const StandingOrderProcessorScript = preload("res://systems/standing_order_processor.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const TestSocietyFactoryScript = preload("res://tests/test_society_factory.gd")

var _started := false

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run_tests_async()
	return false

func _run_tests_async() -> void:
	print("=== RUNNING HEADLESS TEST: CRIME ROUTES, 1-HR TIMELINE & WITNESS SLIPS ===")

	# 1. Verify crime flavour overlay merges route_rounds & building_classes cleanly
	ScenarioManifestManagerScript.reset_cache()
	var prev_flavours: Array[String] = ScenarioManifestManagerScript.get_active_flavours()
	ScenarioManifestManagerScript.set_active_flavours(["crime"])

	var merged_rounds: Dictionary = ScenarioManifestManagerScript.load_module("route_rounds")
	var rounds_map: Dictionary = merged_rounds.get("rounds", {})
	assert(rounds_map.has("MILK_ROUND"), "FAIL: Core MILK_ROUND missing after crime overlay merge.")
	assert(rounds_map.has("SOLO_STREET_VICE_BEAT"), "FAIL: Crime SOLO_STREET_VICE_BEAT missing after overlay merge.")
	assert(str(rounds_map["SOLO_STREET_VICE_BEAT"].get("territory_mode", "")) == "SHARED_MARKETPLACE",
		"FAIL: SOLO_STREET_VICE_BEAT should declare SHARED_MARKETPLACE territory_mode.")
	assert(rounds_map.has("PROTECTION_RACKET_PATCH"), "FAIL: Crime PROTECTION_RACKET_PATCH missing.")
	print("PASS [1/4]: Crime flavour overlay deep-merged route_rounds (cooperative + contested + shared marketplace).")

	# 2. Generate standard radial test society with crew & verify multi-territory route seeding
	var ws: Dictionary = await TestSocietyFactoryScript.create_test_world_with_crew(4, 4, "test-crime-routes-seed", "day", true, ["crime"])
	ScenarioManifestManagerScript.reset_cache()
	ScenarioManifestManagerScript.set_active_flavours(["crime"])
	VerbRouterScript.initialize("crime")
	ImpactRouterScript.reset()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")
	ImpactRouterScript.autoload_sinks("res://data_modules/crime/impacts/")

	var sim_day: int = int(ws.get("metadata", {}).get("current_sim_day", 27393))
	# Ensure day_of_week == 5 (Friday) so MILK_ROUND, PROTECTION_RACKET_PATCH, and SOLO_STREET_VICE_BEAT are due
	while ((sim_day - 1) % 7) + 1 != 5:
		sim_day += 1
	ws["metadata"]["current_sim_day"] = sim_day

	var seeded_count: int = RouteRoundSeederScript.seed_service_routes(ws, sim_day)
	assert(seeded_count > 0, "FAIL: RouteRoundSeeder seeded 0 routes.")

	var solo_vice_rows: Array = DBManagerScript.query_rows("""
		SELECT route_id, establishment_id, worker_resident_id, target_district_id
		FROM service_routes
		WHERE valid_to IS NULL AND service_code = 'SOLO_STREET_VICE_BEAT';
	""")
	assert(not solo_vice_rows.is_empty(), "FAIL: Expected un-premised SOLO_STREET_VICE_BEAT routes to be seeded.")
	assert(solo_vice_rows[0].get("establishment_id") == null,
		"FAIL: SOLO_STREET_VICE_BEAT should be un-premised (establishment_id IS NULL).")
	print("PASS [2/4]: RouteRoundSeeder seeded %d routes including un-premised SOLO_STREET_VICE_BEAT operators." % seeded_count)

	# 3. Verify 1-hour continuous timeline sorting with travel spillover across shift windows
	var districts: Array = ws.get("districts", {}).keys()
	districts.sort()
	assert(districts.size() >= 3, "FAIL: Expected at least 3 districts in test world.")
	var dist_home: String = str(ws.get("operations", {}).get("home_district_id", districts[0]))
	var dist_other: String = str(districts[0]) if str(districts[0]) != dist_home else str(districts[1])
	var dist_remote: String = str(districts[-1])
	if dist_remote == dist_home or dist_remote == dist_other:
		dist_remote = str(districts[1])

	var crew_id: String = ""
	for r_key in ws.get("residents", {}).keys():
		var rec = ws["residents"][r_key]
		if rec is Dictionary and (not str(rec.get("slot_id", "")).is_empty() or bool(rec.get("is_crew", false))):
			crew_id = str(rec.get("resident_id", r_key))
			rec["current_district_id"] = dist_home
			break
	assert(not crew_id.is_empty(), "FAIL: No active crew resident found in test world.")

	var staged: Array = [
		{
			"verb": "REST",
			"assigned_to": crew_id,
			"target_node_id": dist_home,
			"time_window": "MORNING",
			"estimated_hours": 6.0
		},
		{
			"verb": "REST",
			"assigned_to": crew_id,
			"target_node_id": dist_home,
			"time_window": "AFTERNOON",
			"estimated_hours": 1.0
		}
	]
	var built_queue: Array[Dictionary] = SimControllerScript._build_day_execution_queue(ws, staged, sim_day, [])
	assert(built_queue.size() >= 2, "FAIL: Expected at least 2 tasks in 1-hour timeline queue.")
	# Morning task starts at 08:00 and runs 6h -> finishes 14:00, pushing AFTERNOON (anchor 13:00) to 14:00
	var first_hr: float = float(built_queue[0].get("scheduled_hour", 0.0))
	var second_hr: float = float(built_queue[1].get("scheduled_hour", 0.0))
	assert(is_equal_approx(first_hr, 8.0) and second_hr >= 14.0,
		"FAIL: Expected 1-hr timeline spillover from 08:00+6h to >=14:00, got %.2f -> %.2f" % [first_hr, second_hr])
	print("PASS [3/4]: 1-hour continuous timeline ordered tasks chronologically with delay/duration spillover (%.1fh -> %.1fh)." % [first_hr, second_hr])

	# 4. Verify witness, owned-establishment, and calendar event visibility filtering
	ws["establishments"][999001] = {
		"establishment_id": 999001,
		"district_id": dist_remote,
		"owner_org_id": "ORG:CREW_ENTERPRISE",
		"name": "Crew Front Cafe"
	}
	var synthetic_events: Array = [
		# Should PASS: direct crew action
		{
			"trigger_type": "ACTION_RESOLUTION",
			"target_node_id": dist_home,
			"directive_snapshot": {"assigned_to": crew_id, "target_node_id": dist_home}
		},
		# Should PASS: targets player-owned establishment in remote district
		{
			"trigger_type": "ACTION_RESOLUTION",
			"target_node_id": "ESTABLISHMENT:999001",
			"directive_snapshot": {"assigned_to": "999999", "target_node_id": "ESTABLISHMENT:999001"}
		},
		# Should PASS: witnessed co-located event in crew's current district
		{
			"trigger_type": "ACTION_RESOLUTION",
			"target_node_id": dist_home,
			"directive_snapshot": {"assigned_to": "888888", "target_node_id": dist_home}
		},
		# Should BLOCK: un-witnessed background NPC route in remote district with no crew/owned property
		{
			"trigger_type": "STANDING_ORDER_EXECUTION",
			"target_node_id": dist_remote,
			"directive_snapshot": {"assigned_to": "777777", "target_node_id": dist_remote}
		},
		# Should PASS: universal PUBLIC calendar event (Bank Holiday)
		{
			"trigger_type": "CALENDAR_EVENT_STARTED",
			"event_id": 5001,
			"visibility_scope": "PUBLIC",
			"target_node_id": ""
		},
		# Should BLOCK: unrelated cohort calendar event (e.g., Pension Day when no crew/associate is involved)
		{
			"trigger_type": "CALENDAR_EVENT_STARTED",
			"event_id": 5002,
			"visibility_scope": "COHORT",
			"target_node_id": dist_remote
		}
	]

	var filtered_slips: Array = SimControllerScript._filter_witnessed_events(ws, synthetic_events)
	assert(filtered_slips.size() == 4,
		"FAIL: Expected 4 witnessed/relevant slips (crew, owned estab, co-located, PUBLIC holiday), got %d." % filtered_slips.size())
	print("PASS [4/4]: Witness & ownership feedback slip filter passed (%d/6 slips surfaced, un-witnessed remote & unrelated cohort events suppressed)." % filtered_slips.size())

	DBManagerScript.close_database()
	ScenarioManifestManagerScript.set_active_flavours(prev_flavours)
	ScenarioManifestManagerScript.reset_cache()
	print("=== ALL CRIME ROUTES, 1-HR TIMELINE & WITNESS SLIP TESTS PASSED ===")
	quit(0)