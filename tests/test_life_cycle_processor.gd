# res://tests/test_life_cycle_processor.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const TEST_SOCIETY_FACTORY = preload("res://tests/test_society_factory.gd")
const SCENARIO_MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const SAVE_MANAGER = preload("res://systems/save_manager.gd")
const OBLIGATION_LEDGER = preload("res://systems/economy/obligation_ledger.gd")
const DIARY_AGENDA_BUILDER = preload("res://systems/economy/diary_agenda_builder.gd")
const LIFE_CYCLE_PROCESSOR = preload("res://systems/life_cycle_processor.gd")

var _frame_count: int = 0
var _executed: bool = false

func _init() -> void:
	print("\n========================================================")
	print("🧪 RUNNING HEADLESS TEST: LIFE CYCLE & MEMORY PRIORITIES")
	print("========================================================")

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
	var test_slot := "slot_lifecycle_proc_test"

	# ------------------------------------------------------------------
	# CHECK 1: Layered business_rules.cfg & [memory_priorities]
	# ------------------------------------------------------------------
	print("\n[CHECK 1] Verifying layered business_rules.cfg [memory_priorities]...")
	SCENARIO_MANIFEST_MANAGER.set_active_flavours([])
	assert(SCENARIO_MANIFEST_MANAGER.get_memory_priority("health_conditions") == "ACTIVE_KEY_ONLY",
		"FAIL: Core health_conditions priority must be ACTIVE_KEY_ONLY.")
	assert(SCENARIO_MANIFEST_MANAGER.get_memory_priority("criminal_activity") == "SQLITE_BACKGROUND",
		"FAIL: Core criminal_activity priority must be SQLITE_BACKGROUND.")

	SCENARIO_MANIFEST_MANAGER.set_active_flavours(["crime"])
	assert(SCENARIO_MANIFEST_MANAGER.get_memory_priority("health_conditions") == "ACTIVE_KEY_ONLY",
		"FAIL: Crime overlay should inherit health_conditions = ACTIVE_KEY_ONLY.")
	assert(SCENARIO_MANIFEST_MANAGER.get_memory_priority("criminal_activity") == "FINE_IN_MEMORY",
		"FAIL: Crime overlay must elevate criminal_activity to FINE_IN_MEMORY.")
	print("  ✓ PASS 1/5: Layered core + crime [memory_priorities] verified.")

	# ------------------------------------------------------------------
	# Setup Radial Test World + Crew via TestSocietyFactory
	# ------------------------------------------------------------------
	var ws: Dictionary = await TEST_SOCIETY_FACTORY.create_test_world_with_crew(4, 4, "life-cycle-proc-seed")
	SAVE_MANAGER.delete_save_slot(test_slot)
	SAVE_MANAGER.ensure_slot_dir(test_slot)
	ws["metadata"]["active_slot_id"] = test_slot

	var crew_ids: Array[int] = []
	for r_key in ws.get("residents", {}).keys():
		if r_key is int and int(r_key) > 0:
			crew_ids.append(int(r_key))
	assert(not crew_ids.is_empty(), "FAIL: Expected hydrated crew residents from TestSocietyFactory.")
	crew_ids.sort()
	var crew_obs_id: int = crew_ids[0]
	var home_dist: String = str(ws.get("operations", {}).get("home_district_id", "")).strip_edges()
	assert(not home_dist.is_empty(), "FAIL: Missing home_district_id.")

	# ------------------------------------------------------------------
	# CHECK 2: Monthly Proactive Scheduling via SimController
	# ------------------------------------------------------------------
	print("\n[CHECK 2] Verifying monthly proactive scheduling in SimController...")
	var turn_res: Dictionary = SIM_CONTROLLER.process_turn_cycle(ws, [])
	var lc_roll: Dictionary = turn_res.get("life_cycle_rollover", {})
	var total_scheduled: int = int(lc_roll.get("scheduled_births", 0)) + int(lc_roll.get("scheduled_deaths", 0)) + int(lc_roll.get("scheduled_illnesses", 0))
	assert(total_scheduled > 0, "FAIL: Expected proactive monthly life-cycle events to be scheduled on first tick.")
	assert(not str(ws.get("metadata", {}).get("lifecycle_last_scheduled_month", "")).is_empty(),
		"FAIL: Expected metadata.lifecycle_last_scheduled_month to be stamped.")
	print("  ✓ PASS 2/5: Proactively scheduled %d births, %d deaths, %d illnesses for month %s." % [
		int(lc_roll.get("scheduled_births", 0)),
		int(lc_roll.get("scheduled_deaths", 0)),
		int(lc_roll.get("scheduled_illnesses", 0)),
		str(ws["metadata"]["lifecycle_last_scheduled_month"])
	])

	# ------------------------------------------------------------------
	# CHECK 3: Knowledge-Gated Diary Visibility (IntelManager EVENT scope)
	# ------------------------------------------------------------------
	print("\n[CHECK 3] Verifying knowledge-gated DiaryAgendaBuilder visibility & venue masking...")
	var current_day: int = CALENDAR_HELPER.get_current_sim_day(ws)
	var target_day: int = current_day + 2
	var test_estab_id: int = 999901
	if not ws.has("establishments") or not (ws["establishments"] is Dictionary):
		ws["establishments"] = {}
	ws["establishments"][test_estab_id] = {
		"establishment_id": test_estab_id,
		"district_id": home_dist,
		"name": "Test Backroom Venue"
	}

	var secret_ev_id: int = OBLIGATION_LEDGER.create_calendar_event({
		"event_type": "ILLNESS_ONSET",
		"title_token": "UI_EVENT_ILLNESS_CASE",
		"location_scope": "ESTABLISHMENT",
		"location_id": "ESTABLISHMENT:%d" % test_estab_id,
		"start_day": target_day,
		"end_day": target_day,
		"visibility_scope": "PRIVATE",
		"created_day": current_day,
		"impacts": []
	})

	# 3a. Score 0.0 -> Hidden
	var cal_0: Dictionary = DIARY_AGENDA_BUILDER.build_calendar_payload(ws, current_day, {"sim_day": target_day})
	assert(_find_diary_event(cal_0, secret_ev_id).is_empty(),
		"FAIL: Unrevealed PRIVATE event should be hidden at score 0.0.")

	# 3b. Score 10.0 (known >= 1.0, but below scheduled_day threshold 20.0) -> Still hidden from calendar date
	_set_crew_event_score(ws, crew_obs_id, secret_ev_id, 10.0, current_day)
	var cal_10: Dictionary = DIARY_AGENDA_BUILDER.build_calendar_payload(ws, current_day, {"sim_day": target_day})
	assert(_find_diary_event(cal_10, secret_ev_id).is_empty(),
		"FAIL: Faint rumour (score 10.0 < 20.0) must not pin exact scheduled_day in Diary.")

	# 3c. Score 25.0 (>= 20.0, < 40.0) -> Visible on date, but venue masked to parent district
	_set_crew_event_score(ws, crew_obs_id, secret_ev_id, 25.0, current_day)
	var cal_25: Dictionary = DIARY_AGENDA_BUILDER.build_calendar_payload(ws, current_day, {"sim_day": target_day})
	var item_25: Dictionary = _find_diary_event(cal_25, secret_ev_id)
	assert(not item_25.is_empty(), "FAIL: Event should appear in Diary at score 25.0.")
	assert(str(item_25.get("location_id", "")) == home_dist,
		"FAIL: Expected venue masked to parent district '%s' at score 25.0, got '%s'." % [home_dist, str(item_25.get("location_id", ""))])

	# 3d. Score 50.0 (>= 40.0) -> Exact venue exposed
	_set_crew_event_score(ws, crew_obs_id, secret_ev_id, 50.0, current_day)
	var cal_50: Dictionary = DIARY_AGENDA_BUILDER.build_calendar_payload(ws, current_day, {"sim_day": target_day})
	var item_50: Dictionary = _find_diary_event(cal_50, secret_ev_id)
	assert(not item_50.is_empty(), "FAIL: Event should appear in Diary at score 50.0.")
	assert(str(item_50.get("location_id", "")) == "ESTABLISHMENT:%d" % test_estab_id,
		"FAIL: Expected exact venue at score 50.0, got '%s'." % str(item_50.get("location_id", "")))
	print("  ✓ PASS 3/5: DiaryAgendaBuilder enforced EVENT score thresholds (0/10 hidden, 25 district-masked, 50 venue-exposed).")

	# ------------------------------------------------------------------
	# CHECK 4: Deterministic Birth & Death Resolution
	# ------------------------------------------------------------------
	print("\n[CHECK 4] Verifying scheduled LIFE_BIRTH and LIFE_DEATH resolution...")
	var female_id: int = DB_MANAGER.get_label_id("GENDER", "F")
	var mother_rows: Array = DB_MANAGER.query_rows("""
		SELECT resident_id, household_id, current_surname
		FROM residents
		WHERE dod IS NULL AND gender_id = %d
		LIMIT 1;
	""" % female_id)
	assert(not mother_rows.is_empty(), "FAIL: No living female resident found for birth test.")
	var mother_id: int = int(mother_rows[0]["resident_id"])
	var mother_hh: int = int(mother_rows[0]["household_id"])

	var before_birth_cnt: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) AS cnt FROM residents WHERE household_id = %d;" % mother_hh)[0]["cnt"])
	var birth_res: Dictionary = LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, current_day, [ {
		"event_type": "LIFE_BIRTH",
		"impacts_json": JSON.stringify([ {
			"lifecycle_action": "BIRTH",
			"mother_id": mother_id,
			"household_id": mother_hh,
			"child_gender_code": "M"
		}])
	}])
	assert(int(birth_res.get("births_resolved", 0)) == 1, "FAIL: Expected 1 resolved birth.")
	var after_birth_cnt: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) AS cnt FROM residents WHERE household_id = %d;" % mother_hh)[0]["cnt"])
	assert(after_birth_cnt == before_birth_cnt + 1, "FAIL: Newborn row was not inserted into mother's household.")
	var newborn_rows: Array = DB_MANAGER.query_rows("""
		SELECT resident_id, first_name, current_surname, dob
		FROM residents
		WHERE household_id = %d AND dob = %d
		ORDER BY resident_id DESC
		LIMIT 1;
	""" % [mother_hh, current_day])
	assert(not newborn_rows.is_empty() and not str(newborn_rows[0]["first_name"]).is_empty(),
		"FAIL: Newborn missing lexicon-resolved first_name.")
	var child_id: int = int(newborn_rows[0]["resident_id"])
	var mother_edge: Array = DB_MANAGER.query_rows("""
		SELECT COUNT(*) AS cnt FROM social_relationships
		WHERE from_resident_id = %d AND to_resident_id = %d;
	""" % [child_id, mother_id])
	assert(int(mother_edge[0]["cnt"]) >= 1, "FAIL: Missing MOTHER social_relationships edge for newborn.")

	# Pick a non-crew employed resident for death cascade verification
	var crew_csv := ", ".join(crew_ids.map(func(x): return str(x)))
	var victim_rows: Array = DB_MANAGER.query_rows("""
		SELECT r.resident_id
		FROM residents r
		JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id
		WHERE r.dod IS NULL AND lc.valid_to IS NULL AND r.resident_id NOT IN (%s)
		LIMIT 1;
	""" % crew_csv)
	assert(not victim_rows.is_empty(), "FAIL: No employed non-crew resident found for death test.")
	var victim_id: int = int(victim_rows[0]["resident_id"])

	var death_res: Dictionary = LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, current_day, [ {
		"event_type": "LIFE_DEATH",
		"impacts_json": JSON.stringify([ {
			"lifecycle_action": "DEATH",
			"resident_id": victim_id,
			"death_reason_code": "CARDIOVASCULAR"
		}])
	}])
	assert(int(death_res.get("deaths_resolved", 0)) == 1, "FAIL: Expected 1 resolved death.")
	var dead_check: Array = DB_MANAGER.query_rows("SELECT dod, death_reason_id FROM residents WHERE resident_id = %d;" % victim_id)
	assert(int(dead_check[0]["dod"]) == current_day and dead_check[0]["death_reason_id"] != null,
		"FAIL: Resident dod / death_reason_id not updated.")
	var open_contracts: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) AS cnt FROM livelihood_contracts WHERE resident_id = %d AND valid_to IS NULL;" % victim_id)[0]["cnt"])
	assert(open_contracts == 0, "FAIL: Deceased resident still has open livelihood_contracts.")
	print("  ✓ PASS 4/5: Birth (%s %s) and Death cascade (Resident #%d) verified." % [
		str(newborn_rows[0]["first_name"]), str(newborn_rows[0]["current_surname"]), victim_id
	])

	# ------------------------------------------------------------------
	# CHECK 5: Illness Storage, View & ACTIVE_KEY_ONLY Memory Sync + Recovery
	# ------------------------------------------------------------------
	print("\n[CHECK 5] Verifying resident_health_conditions persistence, view, ACTIVE_KEY_ONLY sync & recovery...")
	var bg_rows: Array = DB_MANAGER.query_rows("""
		SELECT resident_id FROM residents
		WHERE dod IS NULL AND is_active_agent = 0 AND resident_id NOT IN (%s)
		LIMIT 1;
	""" % crew_csv)
	assert(not bg_rows.is_empty(), "FAIL: No background non-crew resident found.")
	var bg_res_id: int = int(bg_rows[0]["resident_id"])

	var ill_res: Dictionary = LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, current_day, [
		{
			"event_type": "ILLNESS_ONSET",
			"impacts_json": JSON.stringify([ {
				"lifecycle_action": "ILLNESS_ONSET",
				"resident_id": crew_obs_id,
				"condition_code": "SEASONAL_INFLUENZA",
				"severity": 0.5,
				"is_contagious": true,
				"is_chronic": false,
				"duration_days": 5
			}])
		},
		{
			"event_type": "ILLNESS_ONSET",
			"impacts_json": JSON.stringify([ {
				"lifecycle_action": "ILLNESS_ONSET",
				"resident_id": bg_res_id,
				"condition_code": "ACUTE_BRONCHITIS",
				"severity": 0.4,
				"is_contagious": false,
				"is_chronic": false,
				"duration_days": 5
			}])
		}
	])
	assert(int(ill_res.get("illnesses_started", 0)) == 2, "FAIL: Expected 2 started illnesses.")

	var view_rows: Array = DB_MANAGER.query_rows("SELECT resident_id, condition_code FROM v_active_health_conditions WHERE resident_id IN (%d, %d);" % [crew_obs_id, bg_res_id])
	assert(view_rows.size() == 2, "FAIL: Expected both active conditions in v_active_health_conditions SQLite view.")

	var mem_health: Dictionary = ws.get("resident_health_conditions", {})
	assert(mem_health.has(str(crew_obs_id)), "FAIL: Active crew member illness missing from world_state under ACTIVE_KEY_ONLY.")
	assert(not mem_health.has(str(bg_res_id)), "FAIL: Background resident illness leaked into world_state under ACTIVE_KEY_ONLY.")

	var rec_res: Dictionary = LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, current_day + 5, [])
	assert(int(rec_res.get("illnesses_recovered", 0)) >= 2, "FAIL: Expected scheduled illnesses to recover at day + 5.")
	assert(not ws.get("resident_health_conditions", {}).has(str(crew_obs_id)),
		"FAIL: Recovered crew illness was not cleared from world_state.")
	print("  ✓ PASS 5/5: SQLite table/view, ACTIVE_KEY_ONLY memory sync, and recovery verified.")

	# Cleanup
	SCENARIO_MANIFEST_MANAGER.set_active_flavours([])
	DB_MANAGER.close_database()
	SAVE_MANAGER.delete_save_slot(test_slot)
	print("\n🎉 ALL LIFE CYCLE & MEMORY PRIORITY CHECKS PASSED CLEANLY.\n")
	quit(0)

static func _set_crew_event_score(ws: Dictionary, crew_id: int, event_id: int, score: float, sim_day: int) -> void:
	if not ws.has("knowledge_pools") or not (ws["knowledge_pools"] is Dictionary):
		ws["knowledge_pools"] = {}
	var pools: Dictionary = ws["knowledge_pools"]
	if not pools.has("RESIDENT"):
		pools["RESIDENT"] = {}
	var obs_key := str(crew_id)
	if not pools["RESIDENT"].has(obs_key):
		pools["RESIDENT"][obs_key] = {}
	pools["RESIDENT"][obs_key]["EVENT:%d" % event_id] = {
		"score": score,
		"last_updated_day": sim_day
	}

static func _find_diary_event(cal_payload: Dictionary, event_id: int) -> Dictionary:
	for item in cal_payload.get("selected_day_items", []):
		if item is Dictionary and int(item.get("event_id", 0)) == event_id:
			return item
	return {}