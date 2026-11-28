# res://tests/test_routine_flow_resolver.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const TEST_SOCIETY_FACTORY = preload("res://tests/test_society_factory.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const OBLIGATION_LEDGER = preload("res://systems/economy/obligation_ledger.gd")
const LIFE_CYCLE_PROCESSOR = preload("res://systems/life_cycle_processor.gd")
const ROUTINE_FLOW_RESOLVER = preload("res://systems/routine_flow_resolver.gd")

var _frame_count: int = 0
var _executed: bool = false

func _init() -> void:
	print("\n========================================================")
	print("🧪 RUNNING HEADLESS TEST: RESIDENT ROUTINES & FLOWS")
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
	ROUTINE_FLOW_RESOLVER.reset_cache()
	var ws: Dictionary = await TEST_SOCIETY_FACTORY.create_test_world_with_crew(4, 4, "routine-flow-seed")
	var current_day: int = CALENDAR_HELPER.get_current_sim_day(ws)
	var home_dist: String = str(ws.get("operations", {}).get("home_district_id", "")).strip_edges()
	assert(not home_dist.is_empty(), "FAIL: Missing home_district_id.")

	# Find next Monday (dow == 1) for deterministic weekday testing
	var weekday_sim_day: int = current_day
	while CALENDAR_HELPER.day_of_week(weekday_sim_day) != 1:
		weekday_sim_day += 1

	# ------------------------------------------------------------------
	# CHECK 1: Work Shifts, Commutes & Dynamic Rotations (job_definitions)
	# ------------------------------------------------------------------
	print("\n[CHECK 1] Verifying work shifts, commutes, and dynamic shift rotations...")
	var day_worker_rows: Array = DB_MANAGER.query_rows("""
		SELECT r.resident_id
		FROM residents r
		JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id AND lc.valid_to IS NULL
		JOIN system_labels l_cc ON lc.contract_class_id = l_cc.label_id
		JOIN system_labels l_sw ON lc.schedule_window_id = l_sw.label_id
		WHERE r.dod IS NULL AND l_cc.code = 'FORMAL_LEGAL' AND l_sw.code IN ('DAYTIME', 'DAYTIME_OFFICE')
		LIMIT 1;
	""")
	assert(not day_worker_rows.is_empty(), "FAIL: No daytime formal worker found.")
	var day_worker_id: int = int(day_worker_rows[0]["resident_id"])
	var day_sched: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, day_worker_id, weekday_sim_day)
	assert(_has_routine(day_sched, "WORK_SHIFT"), "FAIL: Daytime worker missing WORK_SHIFT on Monday.")
	assert(_has_routine(day_sched, "COMMUTE_WALK") or _has_routine(day_sched, "COMMUTE_BUS"),
		"FAIL: Daytime worker missing commute leg.")

	var rot_rows: Array = DB_MANAGER.query_rows("""
		SELECT r.resident_id
		FROM residents r
		JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id AND lc.valid_to IS NULL
		JOIN system_labels l_sw ON lc.schedule_window_id = l_sw.label_id
		WHERE r.dod IS NULL AND l_sw.code = 'SHIFTS_ROTATING'
		LIMIT 1;
	""")
	assert(not rot_rows.is_empty(), "FAIL: No SHIFTS_ROTATING worker found.")
	var rot_worker_id: int = int(rot_rows[0]["resident_id"])
	var worked_days := 0
	var rest_days := 0
	for offset in range(14):
		var s: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, rot_worker_id, weekday_sim_day + offset)
		if _has_routine(s, "WORK_SHIFT"):
			worked_days += 1
		else:
			rest_days += 1
	assert(worked_days > 0 and rest_days > 0,
		"FAIL: Rotating shift worker should have both working shifts (%d) and rest days (%d) over 14 days." % [worked_days, rest_days])
	print("  ✓ PASS 1/6: Daytime shifts, commutes, and rotating shift cycles (%d on / %d off) verified." % [worked_days, rest_days])

	# ------------------------------------------------------------------
	# CHECK 2: School Run (Under-11 Escort) vs. Independent Secondary (11-18)
	# ------------------------------------------------------------------
	print("\n[CHECK 2] Verifying primary school escort vs. secondary independent commute...")
	var p_dob_max: int = weekday_sim_day - (5 * 365)
	var p_dob_min: int = weekday_sim_day - (11 * 365) + 1
	var primary_pair: Array = DB_MANAGER.query_rows("""
		SELECT c.resident_id AS child_id, a.resident_id AS adult_id
		FROM residents c
		JOIN residents a ON a.household_id = c.household_id AND a.resident_id != c.resident_id
		JOIN livelihood_contracts lc ON lc.resident_id = a.resident_id AND lc.valid_to IS NULL
		JOIN system_labels l_role ON lc.role_title_id = l_role.label_id
		WHERE c.dod IS NULL AND a.dod IS NULL
		  AND c.dob >= %d AND c.dob <= %d
		  AND (%d - a.dob) >= 6570
		  AND l_role.code IN ('HOME_MAKER', 'UNEMPLOYED')
		LIMIT 1;
	""" % [p_dob_min, p_dob_max, weekday_sim_day])
	assert(not primary_pair.is_empty(), "FAIL: No primary-age child + available household adult pair found.")
	var child_sched: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, int(primary_pair[0]["child_id"]), weekday_sim_day)
	var escort_sched: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, int(primary_pair[0]["adult_id"]), weekday_sim_day)
	assert(_has_routine(child_sched, "SCHOOL_ATTENDANCE"), "FAIL: Primary child missing SCHOOL_ATTENDANCE.")
	assert(_has_routine(escort_sched, "SCHOOL_DROP_OFF"), "FAIL: Available household adult missing SCHOOL_DROP_OFF escort routine.")

	var s_dob_max: int = weekday_sim_day - (11 * 365)
	var s_dob_min: int = weekday_sim_day - (18 * 365) + 1
	var sec_rows: Array = DB_MANAGER.query_rows("""
		SELECT r.resident_id
		FROM residents r
		JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id AND lc.valid_to IS NULL
		JOIN system_labels l_cc ON lc.contract_class_id = l_cc.label_id
		WHERE r.dod IS NULL AND r.dob >= %d AND r.dob <= %d AND l_cc.code = 'ENCLAVE_STUDENT'
		LIMIT 1;
	""" % [s_dob_min, s_dob_max])
	assert(not sec_rows.is_empty(), "FAIL: No secondary school student found.")
	var sec_sched: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, int(sec_rows[0]["resident_id"]), weekday_sim_day)
	assert(_has_routine(sec_sched, "SCHOOL_ATTENDANCE"), "FAIL: Secondary student missing SCHOOL_ATTENDANCE.")
	assert(_has_routine(sec_sched, "COMMUTE_WALK") or _has_routine(sec_sched, "COMMUTE_BUS"),
		"FAIL: Secondary student missing independent commute leg.")
	print("  ✓ PASS 2/6: Primary school escort drop-off/pick-up and secondary independent commute verified.")

	# ------------------------------------------------------------------
	# CHECK 3: Local Catchment GP & Semi-Annual Dental Visits
	# ------------------------------------------------------------------
	print("\n[CHECK 3] Verifying dynamic local catchment GP & Dental visits...")
	_ensure_test_clinic(home_dist, "GP_SURGERY", "Local Catchment GP Surgery", current_day)
	_ensure_test_clinic(home_dist, "DENTAL_PRACTICE", "Local Catchment Dental Surgery", current_day)
	ROUTINE_FLOW_RESOLVER.reset_cache()

	var gp_near: Dictionary = ROUTINE_FLOW_RESOLVER.find_nearest_establishment(home_dist, ["GP_SURGERY", "GP_PRACTICE"])
	var dent_near: Dictionary = ROUTINE_FLOW_RESOLVER.find_nearest_establishment(home_dist, ["DENTAL_PRACTICE"])
	assert(int(gp_near.get("establishment_id", 0)) > 0 and int(dent_near.get("establishment_id", 0)) > 0,
		"FAIL: Nearest GP/Dental catchment resolution failed.")

	# Give an unemployed adult an acute illness and confirm GP_WAITING_ROOM appears on weekday
	var patient_rows: Array = DB_MANAGER.query_rows("""
		SELECT r.resident_id FROM residents r
		JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id AND lc.valid_to IS NULL
		JOIN system_labels l_role ON lc.role_title_id = l_role.label_id
		WHERE r.dod IS NULL AND l_role.code = 'HOME_MAKER'
		LIMIT 1;
	""")
	assert(not patient_rows.is_empty(), "FAIL: No adult resident found for GP/Dental check.")
	var patient_id: int = int(patient_rows[0]["resident_id"])

	LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, weekday_sim_day, [ {
		"event_type": "ILLNESS_ONSET",
		"impacts_json": JSON.stringify([ {
			"lifecycle_action": "ILLNESS_ONSET",
			"resident_id": patient_id,
			"condition_code": "SEASONAL_INFLUENZA",
			"severity": 0.70,
			"is_contagious": true,
			"is_chronic": false,
			"duration_days": 7
		}])
	}])
	var gp_sched: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, patient_id, weekday_sim_day)
	assert(_has_routine(gp_sched, "GP_WAITING_ROOM"), "FAIL: Acutely ill resident missing GP_WAITING_ROOM visit.")

	# Find the exact semi-annual dental checkup day for patient_id within next 180 days (must be weekday)
	var found_dental := false
	for d_off in range(180):
		var cand_day: int = weekday_sim_day + d_off
		if CALENDAR_HELPER.day_of_week(cand_day) <= 5 and posmod(cand_day + (patient_id * 7), 180) == 0:
			var d_sched: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, patient_id, cand_day)
			if _has_routine(d_sched, "DENTAL_VISIT"):
				found_dental = true
				break
	assert(found_dental, "FAIL: Semi-annual DENTAL_VISIT did not trigger within 180-day cycle.")
	print("  ✓ PASS 3/6: Nearest local catchment GP & Dental visits verified.")

	# ------------------------------------------------------------------
	# CHECK 4: Continuous OCEAN + Life-Stressor Devotion Model
	# ------------------------------------------------------------------
	print("\n[CHECK 4] Verifying OCEAN + life-stressor continuous worship devotion...")
	var rules: Dictionary = ROUTINE_FLOW_RESOLVER.get_rules()
	var rel_rows: Array = DB_MANAGER.query_rows("""
		SELECT r.resident_id, r.household_id, r.dob, r.church_id,
		       r.openness, r.conscientiousness, r.extraversion, r.agreeableness, r.neuroticism,
		       l_rel.code AS religion_code
		FROM residents r
		JOIN system_labels l_rel ON r.religion_id = l_rel.label_id
		WHERE r.dod IS NULL AND r.church_id IS NOT NULL AND l_rel.code != 'SECULAR_NONE'
		  AND r.resident_id != %d
		LIMIT 1;
	""" % patient_id)
	assert(not rel_rows.is_empty(), "FAIL: No church-affiliated resident found.")
	var rel_row: Dictionary = rel_rows[0]
	var rel_res_id: int = int(rel_row["resident_id"])
	var rel_age: int = maxi(0, floori(float(weekday_sim_day - int(rel_row["dob"])) / 365.25))
	var base_prob: float = ROUTINE_FLOW_RESOLVER.compute_worship_probability(ws, rel_row, weekday_sim_day, rel_age, rules)
	assert(base_prob > 0.0 and base_prob <= 0.95, "FAIL: Invalid baseline worship probability: %f" % base_prob)

	# Apply severe illness stressor -> probability must increase
	LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, weekday_sim_day, [ {
		"event_type": "ILLNESS_ONSET",
		"impacts_json": JSON.stringify([ {
			"lifecycle_action": "ILLNESS_ONSET",
			"resident_id": rel_res_id,
			"condition_code": "LEGIONNAIRES_DISEASE",
			"severity": 0.85,
			"is_contagious": false,
			"is_chronic": false,
			"duration_days": 14
		}])
	}])
	var stressed_prob: float = ROUTINE_FLOW_RESOLVER.compute_worship_probability(ws, rel_row, weekday_sim_day, rel_age, rules)
	assert(stressed_prob > base_prob or base_prob >= 0.95,
		"FAIL: Expected severe illness stressor to increase worship probability (%f -> %f)." % [base_prob, stressed_prob])

	var secular_row: Dictionary = rel_row.duplicate()
	secular_row["religion_code"] = "SECULAR_NONE"
	assert(ROUTINE_FLOW_RESOLVER.compute_worship_probability(ws, secular_row, weekday_sim_day, rel_age, rules) == 0.0,
		"FAIL: SECULAR_NONE must evaluate to 0.0 weekly worship probability.")
	print("  ✓ PASS 4/6: OCEAN + stressor devotion verified (base=%.3f -> stressed=%.3f, secular=0.0)." % [base_prob, stressed_prob])

	# ------------------------------------------------------------------
	# CHECK 5: Conditional Ceremonies (Funeral Cancel & Wedding Proceed)
	# ------------------------------------------------------------------
	print("\n[CHECK 5] Verifying conditional Funeral cancellation and Wedding resolution...")
	var funeral_ev_id: int = OBLIGATION_LEDGER.create_calendar_event({
		"event_type": "CEREMONY_FUNERAL",
		"title_token": "UI_EVENT_CEREMONY_FUNERAL",
		"organizer": OBLIGATION_LEDGER.format_scoped_entity("RESIDENT", str(day_worker_id)),
		"location_scope": "DISTRICT",
		"location_id": home_dist,
		"start_day": weekday_sim_day + 1,
		"end_day": weekday_sim_day + 1,
		"visibility_scope": "PRIVATE",
		"created_day": weekday_sim_day,
		"impacts": [ {
			"lifecycle_action": "CEREMONY_FUNERAL",
			"resident_id": day_worker_id
		}]
	})
	var fun_ev: Dictionary = OBLIGATION_LEDGER.get_calendar_event(funeral_ev_id)
	var fun_res: Dictionary = LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, weekday_sim_day + 1, [fun_ev])
	assert(int(fun_res.get("ceremonies_cancelled", 0)) == 1,
		"FAIL: Funeral for living resident should have cancelled.")
	assert(str(OBLIGATION_LEDGER.get_calendar_event(funeral_ev_id).get("status", "")) == "CANCELLED",
		"FAIL: Cancelled funeral status not persisted to calendar_events.")

	# Schedule a deterministic Wedding between two living adults
	var wed_day: int = weekday_sim_day + 5 # Saturday
	var couple_rows: Array = DB_MANAGER.query_rows("""
		SELECT resident_id FROM residents
		WHERE dod IS NULL AND (%d - dob) >= 6570
		ORDER BY resident_id DESC
		LIMIT 2;
	""" % wed_day)
	assert(couple_rows.size() == 2, "FAIL: Could not find two adults for wedding test.")
	var partner_a: int = int(couple_rows[0]["resident_id"])
	var partner_b: int = int(couple_rows[1]["resident_id"])

	var wed_ev_id: int = OBLIGATION_LEDGER.create_calendar_event({
		"event_type": "CEREMONY_WEDDING",
		"title_token": "UI_EVENT_CEREMONY_WEDDING",
		"organizer": OBLIGATION_LEDGER.format_scoped_entity("RESIDENT", str(partner_a)),
		"location_scope": "DISTRICT",
		"location_id": home_dist,
		"start_day": wed_day,
		"end_day": wed_day,
		"visibility_scope": "PRIVATE",
		"created_day": weekday_sim_day,
		"impacts": [ {
			"lifecycle_action": "CEREMONY_WEDDING",
			"resident_a_id": partner_a,
			"resident_b_id": partner_b,
			"occurrence_probability": 1.0
		}]
	})
	var wed_ev: Dictionary = OBLIGATION_LEDGER.get_calendar_event(wed_ev_id)
	var wed_res: Dictionary = LIFE_CYCLE_PROCESSOR.process_daily_resolution(ws, wed_day, [wed_ev])
	assert(int(wed_res.get("ceremonies_resolved", 0)) == 1, "FAIL: Deterministic wedding failed to resolve.")
	var spouse_edges: Array = DB_MANAGER.query_rows("""
		SELECT COUNT(*) AS cnt FROM social_relationships sr
		JOIN system_labels l ON sr.relationship_type_id = l.label_id
		WHERE l.code = 'SPOUSE'
		  AND ((sr.from_resident_id = %d AND sr.to_resident_id = %d)
		    OR (sr.from_resident_id = %d AND sr.to_resident_id = %d));
	""" % [partner_a, partner_b, partner_b, partner_a])
	assert(int(spouse_edges[0]["cnt"]) >= 2, "FAIL: Wedding did not create reciprocal SPOUSE edges.")
	var wed_sched_a: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.resolve_resident_day_schedule(ws, partner_a, wed_day)
	assert(_has_routine(wed_sched_a, "CEREMONY_WEDDING"), "FAIL: Wedding ceremony missing from organizer's daily schedule.")
	print("  ✓ PASS 5/6: Conditional Funeral cancellation and Wedding resolution + attendee schedule verified.")

	# ------------------------------------------------------------------
	# CHECK 6: Empty-House Windows & District Hourly Population Flow
	# ------------------------------------------------------------------
	print("\n[CHECK 6] Verifying empty-house windows and district hourly population flows...")
	var solo_worker_hh: Array = DB_MANAGER.query_rows("""
		SELECT r.household_id
		FROM residents r
		JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id AND lc.valid_to IS NULL
		JOIN system_labels l_cc ON lc.contract_class_id = l_cc.label_id
		JOIN system_labels l_sw ON lc.schedule_window_id = l_sw.label_id
		WHERE r.dod IS NULL AND l_cc.code = 'FORMAL_LEGAL' AND l_sw.code IN ('DAYTIME', 'DAYTIME_OFFICE')
		  AND (SELECT COUNT(*) FROM residents r2 WHERE r2.household_id = r.household_id AND r2.dod IS NULL) = 1
		LIMIT 1;
	""")
	assert(not solo_worker_hh.is_empty(), "FAIL: No solo daytime-worker household found.")
	var empty_windows: Array[Dictionary] = ROUTINE_FLOW_RESOLVER.get_household_empty_windows(
		ws, int(solo_worker_hh[0]["household_id"]), weekday_sim_day
	)
	assert(not empty_windows.is_empty(), "FAIL: Expected daytime empty-house window for solo daytime worker.")

	var flow: Dictionary = ROUTINE_FLOW_RESOLVER.compute_district_hourly_flow(ws, home_dist, weekday_sim_day, 10.0, 100)
	assert(int(flow.get("sampled_residents", 0)) > 0, "FAIL: District hourly flow sampled 0 residents.")
	assert(float(flow.get("mean_contact_density", 0.0)) > 0.0, "FAIL: Expected positive mean_contact_density.")
	print("  ✓ PASS 6/6: Empty-house windows (%d) and district 10:00 flow (sampled=%d, local=%d, in=%d, out=%d) verified." % [
		empty_windows.size(),
		int(flow["sampled_residents"]),
		int(flow["local_active_count"]),
		int(flow["inbound_count"]),
		int(flow["outbound_count"])
	])

	ROUTINE_FLOW_RESOLVER.reset_cache()
	DB_MANAGER.close_database()
	print("\n🎉 ALL ROUTINE FLOW & CEREMONY CHECKS PASSED CLEANLY.\n")
	quit(0)

static func _has_routine(schedule: Array[Dictionary], routine_id: String) -> bool:
	for blk in schedule:
		if str(blk.get("routine_id", "")) == routine_id:
			return true
	return false

static func _ensure_test_clinic(district_id: String, cat_code: String, title: String, sim_day: int) -> void:
	var existing: Array = DB_MANAGER.query_rows("""
		SELECT e.establishment_id FROM establishments e
		JOIN system_labels l ON e.category_id = l.label_id
		WHERE e.valid_to IS NULL AND e.is_vacant = 0 AND l.code = '%s'
		LIMIT 1;
	""" % cat_code)
	if not existing.is_empty():
		return
	var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_code)
	var chg_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	DB_MANAGER.execute_batch([
		"""
		INSERT INTO establishments (
			district_id, building_index, unit_door_number, name, category_id,
			capacity, is_vacant, valid_from, valid_to, change_reason_id
		) VALUES ('%s', 0, 'CLINIC', '%s', %d, 20, 0, %d, NULL, %d);
		""" % [district_id.replace("'", "''"), title.replace("'", "''"), cat_id, sim_day, chg_id]
	])