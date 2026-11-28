# res://systems/routine_flow_resolver.gd
class_name RoutineFlowResolver
extends RefCounted

const _DBManager = preload("res://systems/db_manager.gd")
const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _ManifestManager = preload("res://systems/scenario_manifest_manager.gd")
const _ObligationLedger = preload("res://systems/economy/obligation_ledger.gd")

static var _nearest_estab_cache: Dictionary = {} # "district_id|CAT1,CAT2" -> { "establishment_id": int, "district_id": String }

## Clears cached spatial catchment lookups (call when resetting or switching databases)
static func reset_cache() -> void:
	_nearest_estab_cache.clear()

## Loads and validates the resident_routines config module
static func get_rules() -> Dictionary:
	assert(_ManifestManager.has_module("resident_routines"),
		"FATAL: [RoutineFlowResolver] Active scenario manifest missing required 'resident_routines' module.")
	var rules: Dictionary = _ManifestManager.load_module("resident_routines")
	for req_key in [
		"schedule_window_hours", "interaction_profiles", "school_routines",
		"weekly_shopping", "pub_routines", "civic_errands",
		"medical_and_dental", "worship_schedules", "ceremony_rules"
	]:
		assert(rules.has(req_key), "FATAL: [RoutineFlowResolver] 'resident_routines' missing required key '%s'." % req_key)
	return rules

## Returns the sorted daily schedule blocks for a resident on sim_day
## Each block: { "routine_id": String, "start_hour": float, "end_hour": float, "establishment_id": int,
##               "district_id": String, "interaction_profile": Dictionary, "event_id": int }
static func resolve_resident_day_schedule(world_state: Dictionary, resident_id: int, sim_day: int) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	if resident_id <= 0 or not _DBManager.is_database_open():
		return blocks

	var res_row: Dictionary = _fetch_resident_context(resident_id)
	if res_row.is_empty():
		return blocks

	var rules: Dictionary = get_rules()
	var job_defs: Dictionary = _ManifestManager.load_module("job_definitions")
	var dow: int = _CalendarHelper.day_of_week(sim_day)
	var age_years: int = maxi(0, floori(float(sim_day - int(res_row["dob"])) / 365.25))
	var home_dist: String = str(res_row["home_district_id"])
	var home_estab: int = int(res_row["home_establishment_id"])
	var role_code: String = str(res_row.get("role_code", "")).to_upper()
	var contract_class: String = str(res_row.get("contract_class_code", "")).to_upper()

	# 1. Work Shift & Commute Legs (driven directly by job_definitions.json)
	if contract_class == "FORMAL_LEGAL" and int(res_row.get("employer_establishment_id", 0)) > 0:
		var work_blocks: Array[Dictionary] = _resolve_work_and_commute_blocks(
			res_row, role_code, sim_day, dow, home_dist, rules, job_defs
		)
		blocks.append_array(work_blocks)

	# 2. School Attendance (Primary escorted vs Secondary independent)
	var school_cfg: Dictionary = rules["school_routines"]
	var school_days: Array = school_cfg["school_days"]
	if _int_array_has(school_days, dow):
		var p_min: int = int(school_cfg["primary_age_min"])
		var p_max: int = int(school_cfg["primary_age_max"])
		var s_min: int = int(school_cfg["secondary_age_min"])
		var s_max: int = int(school_cfg["secondary_age_max"])
		var school_estab: int = int(res_row.get("employer_establishment_id", 0))
		var school_dist: String = str(res_row.get("employer_district_id", home_dist))
		if school_estab <= 0:
			var s_cats: Array = school_cfg["primary_escort"]["categories"] if age_years <= p_max else school_cfg["secondary_independent"]["categories"]
			var nearest_school: Dictionary = find_nearest_establishment(home_dist, s_cats)
			school_estab = int(nearest_school.get("establishment_id", 0))
			school_dist = str(nearest_school.get("district_id", home_dist))

		if age_years >= p_min and age_years <= p_max and school_estab > 0:
			var pe: Dictionary = school_cfg["primary_escort"]
			blocks.append(_make_block("SCHOOL_ATTENDANCE", float(pe["class_start"]), float(pe["class_end"]), school_estab, school_dist, rules))
		elif age_years >= s_min and age_years <= s_max and (contract_class == "ENCLAVE_STUDENT" or role_code in ["CHILD", "STUDENT"]) and school_estab > 0:
			var si: Dictionary = school_cfg["secondary_independent"]
			var commute_id: String = "COMMUTE_BUS" if school_dist != home_dist else "COMMUTE_WALK"
			blocks.append(_make_block(commute_id, float(si["commute_out_start"]), float(si["commute_out_end"]), 0, school_dist, rules))
			blocks.append(_make_block("SCHOOL_ATTENDANCE", float(si["class_start"]), float(si["class_end"]), school_estab, school_dist, rules))
			blocks.append(_make_block(commute_id, float(si["commute_back_start"]), float(si["commute_back_end"]), 0, home_dist, rules))

	# 2b. Primary School Escort Drop-off / Pick-up (adult in household with under-11 child)
	if age_years >= 18 and _int_array_has(school_days, dow):
		var escort_block_pair: Array[Dictionary] = _resolve_school_escort_blocks(
			res_row, sim_day, blocks, rules
		)
		blocks.append_array(escort_block_pair)

	# 3. Civic Errands bound to Layer A calendar_events (Sign-on, Giro, Pension)
	var civic_blocks: Array[Dictionary] = _resolve_civic_errand_blocks(res_row, role_code, sim_day, home_dist, rules)
	blocks.append_array(civic_blocks)

	# 4. Weekly Household Shopping
	if age_years >= 18 and _is_household_shopper(res_row, role_code):
		var shop_cfg: Dictionary = rules["weekly_shopping"]
		var pref_days: Array = shop_cfg["preferred_days"]
		var assigned_shop_day: int = int(pref_days[int(res_row["household_id"]) % pref_days.size()])
		if dow == assigned_shop_day and not _has_overlap(blocks, float(shop_cfg["start_hour"]), float(shop_cfg["end_hour"])):
			var shop_est: Dictionary = find_nearest_establishment(home_dist, shop_cfg["categories"])
			if int(shop_est.get("establishment_id", 0)) > 0:
				blocks.append(_make_block(
					"WEEKLY_SHOPPING",
					float(shop_cfg["start_hour"]),
					float(shop_cfg["end_hour"]),
					int(shop_est["establishment_id"]),
					str(shop_est["district_id"]),
					rules
				))

	# 5. Worship Attendance (OCEAN + life-stressor continuous devotion, mapped by religion_code)
	var worship_block: Dictionary = _resolve_worship_block(world_state, res_row, sim_day, dow, age_years, rules)
	if not worship_block.is_empty():
		blocks.append(worship_block)

	# 6. Local Catchment GP & Semi-Annual Dental Visits
	var med_blocks: Array[Dictionary] = _resolve_medical_and_dental_blocks(res_row, sim_day, dow, age_years, home_dist, blocks, rules)
	blocks.append_array(med_blocks)

	# 7. Pub Attendance
	var pub_block: Dictionary = _resolve_pub_block(res_row, sim_day, dow, age_years, blocks, rules)
	if not pub_block.is_empty():
		blocks.append(pub_block)

	# 8. Materialized Life-Milestone Ceremonies (Funerals, Christenings, Weddings)
	var ceremony_blocks: Array[Dictionary] = _resolve_ceremony_blocks(res_row, sim_day, rules)
	blocks.append_array(ceremony_blocks)

	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["start_hour"]) < float(b["start_hour"])
	)
	return blocks

## Returns where a resident is at a specific hour on sim_day (falls back to home when no routine block is active)
static func get_resident_location_at_hour(world_state: Dictionary, resident_id: int, sim_day: int, hour: float) -> Dictionary:
	var res_row: Dictionary = _fetch_resident_context(resident_id)
	if res_row.is_empty():
		return {}

	var schedule: Array[Dictionary] = resolve_resident_day_schedule(world_state, resident_id, sim_day)
	for blk in schedule:
		var s_hr: float = float(blk["start_hour"])
		var e_hr: float = float(blk["end_hour"])
		var in_span: bool = (hour >= s_hr and hour < e_hr) if s_hr <= e_hr else (hour >= s_hr or hour < e_hr)
		if in_span:
			return {
				"resident_id": resident_id,
				"district_id": str(blk["district_id"]),
				"establishment_id": int(blk["establishment_id"]),
				"routine_id": str(blk["routine_id"]),
				"interaction_profile": blk["interaction_profile"],
				"event_id": int(blk.get("event_id", 0)),
				"is_at_home": false
			}

	return {
		"resident_id": resident_id,
		"district_id": str(res_row["home_district_id"]),
		"establishment_id": int(res_row["home_establishment_id"]),
		"routine_id": "AT_HOME",
		"interaction_profile": {"contact_density": 0.30, "infection_vector_weight": 0.85, "gossip_exchange_weight": 0.65},
		"event_id": 0,
		"is_at_home": true
	}

## Computes exact [start_hour, end_hour] windows during sim_day when ALL living members of a household are out of the house
static func get_household_empty_windows(world_state: Dictionary, household_id: int, sim_day: int) -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	if household_id <= 0 or not _DBManager.is_database_open():
		return windows

	var member_rows: Array = _DBManager.query_rows("""
		SELECT resident_id FROM residents
		WHERE household_id = %d AND dod IS NULL
		ORDER BY resident_id ASC;
	""" % household_id)
	if member_rows.is_empty():
		return windows

	var member_schedules: Array = []
	for m in member_rows:
		member_schedules.append(resolve_resident_day_schedule(world_state, int(m["resident_id"]), sim_day))

	# Evaluate in 0.5-hour slots across the 24-hour day (48 slots)
	var in_empty := false
	var span_start: float = 0.0
	for slot_idx in range(48):
		var hr: float = float(slot_idx) * 0.5
		var all_away := true
		for sched in member_schedules:
			if not _is_away_at_hour(sched, hr):
				all_away = false
				break
		if all_away and not in_empty:
			in_empty = true
			span_start = hr
		elif not all_away and in_empty:
			in_empty = false
			windows.append({"start_hour": span_start, "end_hour": hr})
	if in_empty:
		windows.append({"start_hour": span_start, "end_hour": 24.0})

	return windows

## Computes sampled district population flow and aggregate interaction weights at (sim_day, hour)
static func compute_district_hourly_flow(
	world_state: Dictionary,
	district_id: String,
	sim_day: int,
	hour: float,
	sample_limit: int = 250
) -> Dictionary:
	var report := {
		"district_id": district_id,
		"sim_day": sim_day,
		"hour": hour,
		"sampled_residents": 0,
		"at_home_count": 0,
		"local_active_count": 0,
		"outbound_count": 0,
		"inbound_count": 0,
		"routine_counts": {},
		"mean_contact_density": 0.0,
		"mean_infection_weight": 0.0,
		"mean_gossip_weight": 0.0
	}
	if district_id.is_empty() or not _DBManager.is_database_open():
		return report

	var d_esc: String = district_id.replace("'", "''")
	var local_rows: Array = _DBManager.query_rows("""
		SELECT r.resident_id
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		WHERE e.district_id = '%s' AND r.dod IS NULL
		ORDER BY r.resident_id ASC
		LIMIT %d;
	""" % [d_esc, maxi(1, sample_limit)])

	var inbound_rows: Array = _DBManager.query_rows("""
		SELECT DISTINCT lc.resident_id
		FROM livelihood_contracts lc
		JOIN establishments ew ON lc.employer_establishment_id = ew.establishment_id
		JOIN residents r ON lc.resident_id = r.resident_id
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments eh ON h.establishment_id = eh.establishment_id
		WHERE ew.district_id = '%s' AND eh.district_id != '%s'
		  AND lc.valid_to IS NULL AND r.dod IS NULL
		ORDER BY lc.resident_id ASC
		LIMIT %d;
	""" % [d_esc, d_esc, maxi(1, sample_limit)])

	var contact_sum: float = 0.0
	var inf_sum: float = 0.0
	var gossip_sum: float = 0.0
	var present_count: int = 0
	var routine_counts: Dictionary = {}

	for row in local_rows:
		var loc: Dictionary = get_resident_location_at_hour(world_state, int(row["resident_id"]), sim_day, hour)
		if loc.is_empty():
			continue
		report["sampled_residents"] += 1
		if str(loc["district_id"]) != district_id:
			report["outbound_count"] += 1
			continue
		present_count += 1
		if bool(loc["is_at_home"]):
			report["at_home_count"] += 1
		else:
			report["local_active_count"] += 1
		var r_id: String = str(loc["routine_id"])
		routine_counts[r_id] = int(routine_counts.get(r_id, 0)) + 1
		var prof: Dictionary = loc["interaction_profile"]
		contact_sum += float(prof.get("contact_density", 0.0))
		inf_sum += float(prof.get("infection_vector_weight", 0.0))
		gossip_sum += float(prof.get("gossip_exchange_weight", 0.0))

	for row in inbound_rows:
		var loc: Dictionary = get_resident_location_at_hour(world_state, int(row["resident_id"]), sim_day, hour)
		if loc.is_empty() or str(loc["district_id"]) != district_id:
			continue
		report["inbound_count"] += 1
		present_count += 1
		var r_id: String = str(loc["routine_id"])
		routine_counts[r_id] = int(routine_counts.get(r_id, 0)) + 1
		var prof: Dictionary = loc["interaction_profile"]
		contact_sum += float(prof.get("contact_density", 0.0))
		inf_sum += float(prof.get("infection_vector_weight", 0.0))
		gossip_sum += float(prof.get("gossip_exchange_weight", 0.0))

	report["routine_counts"] = routine_counts
	if present_count > 0:
		report["mean_contact_density"] = snappedf(contact_sum / float(present_count), 0.001)
		report["mean_infection_weight"] = snappedf(inf_sum / float(present_count), 0.001)
		report["mean_gossip_weight"] = snappedf(gossip_sum / float(present_count), 0.001)

	return report

## Computes continuous weekly worship attendance probability [min_prob, max_prob] from OCEAN traits, age, and life stressors
static func compute_worship_probability(
	world_state: Dictionary,
	res_row: Dictionary,
	sim_day: int,
	age_years: int,
	rules: Dictionary
) -> float:
	var religion_code: String = str(res_row.get("religion_code", "SECULAR_NONE")).to_upper()
	if religion_code == "SECULAR_NONE" or res_row.get("church_id", null) == null:
		return 0.0

	var dev_cfg: Dictionary = rules["worship_schedules"]["devotion_model"]
	var prob: float = float(dev_cfg["base_probability"])
	var weights: Dictionary = dev_cfg["ocean_weights"]
	for trait_key in weights.keys():
		var trait_val: float = float(res_row.get(str(trait_key), 0.5))
		prob += (trait_val - 0.5) * float(weights[trait_key])

	var age_start: int = int(dev_cfg["age_bonus_start"])
	if age_years > age_start:
		var age_bonus: float = float(age_years - age_start) * float(dev_cfg["age_bonus_per_year"])
		prob += minf(age_bonus, float(dev_cfg["age_bonus_cap"]))

	var stress: Dictionary = dev_cfg["stressor_modifiers"]
	var hh_id: int = int(res_row.get("household_id", 0))
	if hh_id > 0:
		var bereave_days: int = int(stress["recent_bereavement_days"])
		var b_rows: Array = _DBManager.query_rows("""
			SELECT COUNT(*) AS cnt FROM residents
			WHERE household_id = %d AND dod IS NOT NULL AND dod >= %d AND dod <= %d;
		""" % [hh_id, sim_day - bereave_days, sim_day])
		if not b_rows.is_empty() and int(b_rows[0]["cnt"]) > 0:
			prob += float(stress["recent_bereavement_bonus"])

	var res_id: int = int(res_row["resident_id"])
	if _has_table("resident_health_conditions"):
		var ill_rows: Array = _DBManager.query_rows("""
			SELECT MAX(severity) AS max_sev FROM resident_health_conditions
			WHERE resident_id = %d AND valid_to IS NULL;
		""" % res_id)
		if not ill_rows.is_empty() and ill_rows[0]["max_sev"] != null and float(ill_rows[0]["max_sev"]) >= 0.55:
			prob += float(stress["severe_illness_bonus"])

	var ws_res: Dictionary = world_state.get("residents", {})
	var mem_rec = ws_res.get(res_id, ws_res.get(str(res_id), {}))
	if mem_rec is Dictionary and mem_rec.has("desperation"):
		prob += float(mem_rec["desperation"]) * float(stress["desperation_weight"])

	return clampf(prob, float(dev_cfg["min_probability"]), float(dev_cfg["max_probability"]))

## Dynamically resolves the nearest non-vacant establishment matching category_codes to origin_district_id
static func find_nearest_establishment(origin_district_id: String, category_codes: Array) -> Dictionary:
	if origin_district_id.is_empty() or category_codes.is_empty() or not _DBManager.is_database_open():
		return {}

	var sorted_cats: Array[String] = []
	for c in category_codes:
		sorted_cats.append(str(c).strip_edges().to_upper())
	sorted_cats.sort()
	var cache_key := "%s|%s" % [origin_district_id, ",".join(sorted_cats)]
	if _nearest_estab_cache.has(cache_key):
		return _nearest_estab_cache[cache_key]

	var cat_tokens: Array[String] = []
	for c in sorted_cats:
		cat_tokens.append("'%s'" % c.replace("'", "''"))
	var cat_csv := ", ".join(cat_tokens)

	var origin_rows: Array = _DBManager.query_rows("""
		SELECT grid_x, grid_z FROM districts WHERE district_id = '%s' LIMIT 1;
	""" % origin_district_id.replace("'", "''"))
	if origin_rows.is_empty():
		return {}

	var ox: float = float(origin_rows[0]["grid_x"])
	var oz: float = float(origin_rows[0]["grid_z"])

	var candidates: Array = _DBManager.query_rows("""
		SELECT e.establishment_id, e.district_id, d.grid_x, d.grid_z
		FROM establishments e
		JOIN districts d ON e.district_id = d.district_id
		JOIN system_labels l ON e.category_id = l.label_id
		WHERE e.valid_to IS NULL AND e.is_vacant = 0 AND l.code IN (%s);
	""" % cat_csv)

	var best: Dictionary = {}
	var best_dist_sq: float = INF
	for cand in candidates:
		var dx: float = float(cand["grid_x"]) - ox
		var dz: float = float(cand["grid_z"]) - oz
		var d_sq: float = (dx * dx) + (dz * dz)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = {
				"establishment_id": int(cand["establishment_id"]),
				"district_id": str(cand["district_id"])
			}

	_nearest_estab_cache[cache_key] = best
	return best

# ==============================================================================
# INTERNAL ROUTINE RESOLVERS
# ==============================================================================

static func _resolve_work_and_commute_blocks(
	res_row: Dictionary,
	role_code: String,
	sim_day: int,
	dow: int,
	home_dist: String,
	rules: Dictionary,
	job_defs: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var work_estab: int = int(res_row.get("employer_establishment_id", 0))
	var work_dist: String = str(res_row.get("employer_district_id", home_dist))
	var res_id: int = int(res_row["resident_id"])

	# Resolve work_schedule & shift_rotation dynamically from job_definitions.json (DRY)
	var roles_map: Dictionary = job_defs.get("roles", {})
	var schedules_map: Dictionary = job_defs.get("work_schedules", {})
	var rotations_map: Dictionary = job_defs.get("shift_rotations", {})

	var contract_window: String = str(res_row.get("schedule_window_code", "DAYTIME")).to_upper()
	var resolved_window: String = contract_window
	var is_rotating: bool = (contract_window == "SHIFTS_ROTATING")
	var is_working_today: bool = true

	if is_rotating:
		var rot_key: String = ""
		if roles_map.has(role_code):
			var sched_key: String = str(roles_map[role_code].get("work_schedule", ""))
			if schedules_map.has(sched_key):
				rot_key = str(schedules_map[sched_key].get("rotation_pattern", ""))
		assert(not rot_key.is_empty() and rotations_map.has(rot_key),
			"FATAL: [RoutineFlowResolver] Rotating role '%s' missing valid rotation_pattern '%s' in job_definitions." % [role_code, rot_key])
		var rot_def: Dictionary = rotations_map[rot_key]
		var cycle_days: int = maxi(1, int(rot_def["cycle_days"]))
		var days_on: int = int(rot_def["days_on"])
		var phase_day: int = posmod(sim_day + res_id, cycle_days)
		if phase_day >= days_on:
			is_working_today = false
		else:
			var cycle_index: int = floori(float(sim_day + res_id) / float(cycle_days))
			resolved_window = _pick_rotation_shift_window(rot_def["shift_splits"], cycle_index)

	if not is_working_today:
		return out

	var win_hours_map: Dictionary = rules["schedule_window_hours"]
	assert(win_hours_map.has(resolved_window),
		"FATAL: [RoutineFlowResolver] Unconfigured schedule_window '%s' in resident_routines.json." % resolved_window)
	var win_cfg: Dictionary = win_hours_map[resolved_window]

	# Non-rotating schedules respect their default_days
	if not is_rotating:
		var default_days: Array = win_cfg["default_days"]
		if not _int_array_has(default_days, dow):
			return out

	var start_hr: float = float(win_cfg["start_hour"])
	var end_hr: float = float(win_cfg["end_hour"])
	var commute_hrs: float = float(win_cfg["commute_hours"])
	var commute_id: String = "COMMUTE_BUS" if work_dist != home_dist else "COMMUTE_WALK"

	if commute_hrs > 0.0:
		var out_start: float = maxf(0.0, start_hr - commute_hrs)
		out.append(_make_block(commute_id, out_start, start_hr, 0, work_dist, rules))
	out.append(_make_block("WORK_SHIFT", start_hr, end_hr, work_estab, work_dist, rules))
	if commute_hrs > 0.0 and end_hr >= start_hr:
		var back_end: float = minf(24.0, end_hr + commute_hrs)
		out.append(_make_block(commute_id, end_hr, back_end, 0, home_dist, rules))

	return out

static func _pick_rotation_shift_window(shift_splits: Dictionary, cycle_index: int) -> String:
	var keys: Array = shift_splits.keys()
	keys.sort()
	assert(not keys.is_empty(), "FATAL: [RoutineFlowResolver] Empty shift_splits in shift_rotations.")
	var total_w: float = 0.0
	for k in keys:
		total_w += maxf(0.0, float(shift_splits[k]))
	var slot_pos: float = fposmod(float(cycle_index) * 0.61803398875, 1.0) * total_w
	var running: float = 0.0
	for k in keys:
		running += maxf(0.0, float(shift_splits[k]))
		if slot_pos <= running:
			return str(k).to_upper()
	return str(keys[0]).to_upper()

static func _resolve_school_escort_blocks(
	res_row: Dictionary,
	sim_day: int,
	existing_blocks: Array[Dictionary],
	rules: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var school_cfg: Dictionary = rules["school_routines"]
	var p_min: int = int(school_cfg["primary_age_min"])
	var p_max: int = int(school_cfg["primary_age_max"])
	var hh_id: int = int(res_row["household_id"])
	var dob_max: int = sim_day - (p_min * 365)
	var dob_min: int = sim_day - ((p_max + 1) * 365) + 1

	var child_rows: Array = _DBManager.query_rows("""
		SELECT r.resident_id, lc.employer_establishment_id AS school_estab_id, e.district_id AS school_dist
		FROM residents r
		LEFT JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id AND lc.valid_to IS NULL
		LEFT JOIN establishments e ON lc.employer_establishment_id = e.establishment_id
		WHERE r.household_id = %d AND r.dod IS NULL AND r.dob >= %d AND r.dob <= %d
		LIMIT 1;
	""" % [hh_id, dob_min, dob_max])
	if child_rows.is_empty():
		return out

	var pe: Dictionary = school_cfg["primary_escort"]
	var school_estab: int = int(child_rows[0].get("school_estab_id", 0)) if child_rows[0]["school_estab_id"] != null else 0
	var school_dist: String = str(child_rows[0].get("school_dist", "")) if child_rows[0]["school_dist"] != null else ""
	if school_estab <= 0:
		var nearest: Dictionary = find_nearest_establishment(str(res_row["home_district_id"]), pe["categories"])
		school_estab = int(nearest.get("establishment_id", 0))
		school_dist = str(nearest.get("district_id", res_row["home_district_id"]))
	if school_estab <= 0:
		return out

	if not _has_overlap(existing_blocks, float(pe["drop_off_start"]), float(pe["drop_off_end"])):
		out.append(_make_block("SCHOOL_DROP_OFF", float(pe["drop_off_start"]), float(pe["drop_off_end"]), school_estab, school_dist, rules))
	if not _has_overlap(existing_blocks, float(pe["pick_up_start"]), float(pe["pick_up_end"])):
		out.append(_make_block("SCHOOL_DROP_OFF", float(pe["pick_up_start"]), float(pe["pick_up_end"]), school_estab, school_dist, rules))
	return out

static func _resolve_civic_errand_blocks(
	res_row: Dictionary,
	role_code: String,
	sim_day: int,
	home_dist: String,
	rules: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (role_code in ["UNEMPLOYED", "PENSIONER"]):
		return out

	var errands_cfg: Dictionary = rules["civic_errands"]
	var events: Array = _ObligationLedger.get_calendar_events_in_window(sim_day, sim_day)
	var res_id: int = int(res_row["resident_id"])

	for ev in events:
		if not (ev is Dictionary):
			continue
		var ev_type: String = str(ev.get("event_type", "")).to_upper()
		if not errands_cfg.has(ev_type):
			continue
		var e_cfg: Dictionary = errands_cfg[ev_type]

		if ev_type == "PENSION_DAY" and role_code != "PENSIONER":
			continue
		if ev_type in ["SIGN_ON_DAY", "GIRO_DAY"]:
			if role_code != "UNEMPLOYED":
				continue
			var cohort_num: int = (res_id % int(e_cfg.get("cohort_mod", 5))) + 1
			var expected_cohort: String = "CLAIMANT_COHORT_%d" % cohort_num
			if not str(ev.get("impacts_json", "")).contains(expected_cohort):
				continue

		var venue: Dictionary = find_nearest_establishment(home_dist, e_cfg["categories"])
		if int(venue.get("establishment_id", 0)) > 0:
			out.append(_make_block(
				str(e_cfg["routine_id"]),
				float(e_cfg["start_hour"]),
				float(e_cfg["end_hour"]),
				int(venue["establishment_id"]),
				str(venue["district_id"]),
				rules,
				int(ev.get("event_id", 0))
			))
	return out

static func _resolve_worship_block(
	world_state: Dictionary,
	res_row: Dictionary,
	sim_day: int,
	dow: int,
	age_years: int,
	rules: Dictionary
) -> Dictionary:
	var religion_code: String = str(res_row.get("religion_code", "SECULAR_NONE")).to_upper()
	var by_rel: Dictionary = rules["worship_schedules"]["by_religion"]
	if not by_rel.has(religion_code):
		return {}
	var rel_sched: Dictionary = by_rel[religion_code]
	var days: Array = rel_sched["days_of_week"]
	if days.is_empty() or not _int_array_has(days, dow):
		return {}

	var prob: float = compute_worship_probability(world_state, res_row, sim_day, age_years, rules)
	if prob <= 0.0:
		return {}

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("WORSHIP:%d:%d" % [int(res_row["resident_id"]), _CalendarHelper.day_to_week(sim_day)])
	if rng.randf() > prob:
		return {}

	var church_id: int = int(res_row["church_id"])
	var church_dist: String = str(res_row.get("church_district_id", res_row["home_district_id"]))
	return _make_block("WORSHIP_SERVICE", float(rel_sched["start_hour"]), float(rel_sched["end_hour"]), church_id, church_dist, rules)

static func _resolve_medical_and_dental_blocks(
	res_row: Dictionary,
	sim_day: int,
	dow: int,
	age_years: int,
	home_dist: String,
	existing_blocks: Array[Dictionary],
	rules: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var med_cfg: Dictionary = rules["medical_and_dental"]
	var res_id: int = int(res_row["resident_id"])

	# GP Visit (active acute illness, chronic review, or elderly checkup)
	var gp_cfg: Dictionary = med_cfg["gp_visit"]
	if _int_array_has(gp_cfg["visit_days"], dow):
		var needs_gp := false
		if _has_table("resident_health_conditions"):
			var cond_rows: Array = _DBManager.query_rows("""
				SELECT severity, is_chronic, contracted_day
				FROM resident_health_conditions
				WHERE resident_id = %d AND valid_to IS NULL;
			""" % res_id)
			var acute_thresh: float = float(gp_cfg["acute_severity_threshold"])
			var chronic_int: int = int(gp_cfg["chronic_review_interval_days"])
			for c in cond_rows:
				var elapsed: int = sim_day - int(c["contracted_day"])
				if int(c["is_chronic"]) == 0 and float(c["severity"]) >= acute_thresh and elapsed >= 0 and elapsed <= 2:
					needs_gp = true
					break
				if int(c["is_chronic"]) == 1 and elapsed > 0 and (elapsed % chronic_int) == 0:
					needs_gp = true
					break
		if not needs_gp and age_years >= int(gp_cfg["elderly_checkup_age"]):
			var eld_int: int = int(gp_cfg["elderly_checkup_interval_days"])
			if posmod(sim_day + res_id, eld_int) == 0:
				needs_gp = true

		if needs_gp:
			var gp_est: Dictionary = find_nearest_establishment(home_dist, gp_cfg["categories"])
			if int(gp_est.get("establishment_id", 0)) > 0:
				var s_hr: float = float(gp_cfg["start_hour"])
				var e_hr: float = float(gp_cfg["end_hour"])
				if _has_overlap(existing_blocks, s_hr, e_hr):
					s_hr = float(gp_cfg["afternoon_start_hour"])
					e_hr = float(gp_cfg["afternoon_end_hour"])
				out.append(_make_block("GP_WAITING_ROOM", s_hr, e_hr, int(gp_est["establishment_id"]), str(gp_est["district_id"]), rules))

	# Regular Semi-Annual Dental Checkup (nearest DENTAL_PRACTICE)
	var dent_cfg: Dictionary = med_cfg["dental_checkup"]
	if age_years >= int(dent_cfg["min_age"]) and _int_array_has(dent_cfg["visit_days"], dow):
		var dent_int: int = int(dent_cfg["interval_days"])
		if posmod(sim_day + (res_id * 7), dent_int) == 0:
			var dent_est: Dictionary = find_nearest_establishment(home_dist, dent_cfg["categories"])
			if int(dent_est.get("establishment_id", 0)) > 0:
				var d_start: float = float(dent_cfg["start_hour"]) + float(posmod(res_id, 6))
				var d_end: float = minf(float(dent_cfg["end_hour"]), d_start + float(dent_cfg["slot_duration_hours"]))
				if not _has_overlap(existing_blocks, d_start, d_end):
					out.append(_make_block("DENTAL_VISIT", d_start, d_end, int(dent_est["establishment_id"]), str(dent_est["district_id"]), rules))

	return out

static func _resolve_pub_block(
	res_row: Dictionary,
	sim_day: int,
	dow: int,
	age_years: int,
	existing_blocks: Array[Dictionary],
	rules: Dictionary
) -> Dictionary:
	var pub_cfg: Dictionary = rules["pub_routines"]
	if age_years < int(pub_cfg["min_age"]) or res_row.get("local_pub_id", null) == null:
		return {}

	var is_weekend: bool = (dow == 5 or dow == 6)
	var s_hr: float = float(pub_cfg["weekend_start_hour"]) if is_weekend else float(pub_cfg["weekday_start_hour"])
	var e_hr: float = float(pub_cfg["weekend_end_hour"]) if is_weekend else float(pub_cfg["weekday_end_hour"])
	if _has_overlap(existing_blocks, s_hr, e_hr):
		return {}

	var visits_per_week: float = float(pub_cfg["base_weekly_visits"]) + ((float(res_row["extraversion"]) - 0.5) * float(pub_cfg["extraversion_weight"]))
	if _resident_has_tag(int(res_row["resident_id"]), "ADDICTION_ALCOHOL"):
		visits_per_week += float(pub_cfg["alcohol_tag_bonus_visits"])
	var daily_prob: float = clampf((visits_per_week / 7.0) * (1.6 if is_weekend else 0.75), 0.0, 0.95)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("PUB:%d:%d" % [int(res_row["resident_id"]), sim_day])
	if rng.randf() > daily_prob:
		return {}

	var pub_id: int = int(res_row["local_pub_id"])
	var pub_dist: String = str(res_row.get("pub_district_id", res_row["home_district_id"]))
	return _make_block("PUB_SOCIAL", s_hr, e_hr, pub_id, pub_dist, rules)

static func _resolve_ceremony_blocks(res_row: Dictionary, sim_day: int, rules: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var res_id: int = int(res_row["resident_id"])
	var hh_id: int = int(res_row["household_id"])
	var events: Array = _ObligationLedger.get_calendar_events_in_window(sim_day, sim_day)
	var ceremony_cfg: Dictionary = rules["ceremony_rules"]

	for ev in events:
		if not (ev is Dictionary):
			continue
		var ev_status: String = str(ev.get("status", "SCHEDULED")).to_upper()
		if ev_status == "CANCELLED":
			continue
		var ev_type: String = str(ev.get("event_type", "")).to_upper()
		if not (ev_type in ["CEREMONY_FUNERAL", "CEREMONY_CHRISTENING", "CEREMONY_WEDDING"]):
			continue

		var org_id: int = int(ev.get("organizer_id", 0)) if str(ev.get("organizer_scope", "")) == "RESIDENT" else 0
		if org_id <= 0:
			continue

		var is_attendee: bool = (org_id == res_id)
		if not is_attendee:
			var same_hh: Array = _DBManager.query_rows("SELECT 1 FROM residents WHERE resident_id = %d AND household_id = %d LIMIT 1;" % [org_id, hh_id])
			if not same_hh.is_empty():
				is_attendee = true
		if not is_attendee and _has_table("social_relationships"):
			var rel_rows: Array = _DBManager.query_rows("""
				SELECT 1 FROM social_relationships
				WHERE valid_to IS NULL
				  AND ((from_resident_id = %d AND to_resident_id = %d)
				    OR (from_resident_id = %d AND to_resident_id = %d))
				LIMIT 1;
			""" % [res_id, org_id, org_id, res_id])
			if not rel_rows.is_empty():
				is_attendee = true
		if not is_attendee:
			continue

		var cfg_key: String = ev_type.trim_prefix("CEREMONY_")
		var c_cfg: Dictionary = ceremony_cfg.get(cfg_key, {})
		var s_hr: float = float(c_cfg.get("start_hour", 11.0))
		var e_hr: float = float(c_cfg.get("end_hour", 14.0))
		var loc_raw: String = str(ev.get("location_id", ""))
		var est_id: int = 0
		var dist_id: String = str(res_row["home_district_id"])
		if loc_raw.begins_with("ESTABLISHMENT:"):
			est_id = int(loc_raw.trim_prefix("ESTABLISHMENT:"))
			var e_rows: Array = _DBManager.query_rows("SELECT district_id FROM establishments WHERE establishment_id = %d LIMIT 1;" % est_id)
			if not e_rows.is_empty():
				dist_id = str(e_rows[0]["district_id"])
		elif not loc_raw.is_empty():
			dist_id = loc_raw

		out.append(_make_block(ev_type, s_hr, e_hr, est_id, dist_id, rules, int(ev.get("event_id", 0))))
	return out

# ==============================================================================
# DATA FETCH & HELPER UTILITIES
# ==============================================================================

static func _fetch_resident_context(resident_id: int) -> Dictionary:
	var rows: Array = _DBManager.query_rows("""
		SELECT r.resident_id, r.household_id, r.dob, r.church_id, r.local_pub_id,
		       r.openness, r.conscientiousness, r.extraversion, r.agreeableness, r.neuroticism,
		       h.establishment_id AS home_establishment_id, h.head_resident_id,
		       eh.district_id AS home_district_id,
		       l_rel.code AS religion_code,
		       ec.district_id AS church_district_id,
		       ep.district_id AS pub_district_id,
		       lc.employer_establishment_id,
		       ew.district_id AS employer_district_id,
		       l_role.code AS role_code,
		       l_cc.code AS contract_class_code,
		       l_sw.code AS schedule_window_code
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments eh ON h.establishment_id = eh.establishment_id
		JOIN system_labels l_rel ON r.religion_id = l_rel.label_id
		LEFT JOIN establishments ec ON r.church_id = ec.establishment_id
		LEFT JOIN establishments ep ON r.local_pub_id = ep.establishment_id
		LEFT JOIN livelihood_contracts lc ON lc.resident_id = r.resident_id AND lc.valid_to IS NULL
		LEFT JOIN establishments ew ON lc.employer_establishment_id = ew.establishment_id
		LEFT JOIN system_labels l_role ON lc.role_title_id = l_role.label_id
		LEFT JOIN system_labels l_cc ON lc.contract_class_id = l_cc.label_id
		LEFT JOIN system_labels l_sw ON lc.schedule_window_id = l_sw.label_id
		WHERE r.resident_id = %d AND r.dod IS NULL
		ORDER BY CASE WHEN lc.employer_establishment_id IS NOT NULL THEN 0 ELSE 1 END, lc.contract_id ASC
		LIMIT 1;
	""" % resident_id)
	return rows[0] if not rows.is_empty() else {}

static func _make_block(
	routine_id: String,
	start_hour: float,
	end_hour: float,
	establishment_id: int,
	district_id: String,
	rules: Dictionary,
	event_id: int = 0
) -> Dictionary:
	var profiles: Dictionary = rules["interaction_profiles"]
	assert(profiles.has(routine_id),
		"FATAL: [RoutineFlowResolver] Missing interaction_profile for routine_id '%s'." % routine_id)
	return {
		"routine_id": routine_id,
		"start_hour": start_hour,
		"end_hour": end_hour,
		"establishment_id": establishment_id,
		"district_id": district_id,
		"interaction_profile": profiles[routine_id],
		"event_id": event_id
	}

static func _is_household_shopper(res_row: Dictionary, role_code: String) -> bool:
	if role_code == "HOME_MAKER":
		return true
	return int(res_row["resident_id"]) == int(res_row.get("head_resident_id", 0))

static func _has_overlap(blocks: Array[Dictionary], start_hr: float, end_hr: float) -> bool:
	for b in blocks:
		var bs: float = float(b["start_hour"])
		var be: float = float(b["end_hour"])
		if bs <= be and start_hr < be and end_hr > bs:
			return true
	return false

static func _is_away_at_hour(schedule: Array, hour: float) -> bool:
	for blk in schedule:
		var s_hr: float = float(blk["start_hour"])
		var e_hr: float = float(blk["end_hour"])
		var in_span: bool = (hour >= s_hr and hour < e_hr) if s_hr <= e_hr else (hour >= s_hr or hour < e_hr)
		if in_span:
			return true
	return false

static func _resident_has_tag(resident_id: int, tag_code: String) -> bool:
	if not _has_table("resident_behavioral_tags"):
		return false
	var rows: Array = _DBManager.query_rows("""
		SELECT 1 FROM resident_behavioral_tags t
		JOIN system_labels l ON t.tag_label_id = l.label_id
		WHERE t.resident_id = %d AND t.valid_to IS NULL AND l.code = '%s'
		LIMIT 1;
	""" % [resident_id, tag_code.replace("'", "''")])
	return not rows.is_empty()

static func _int_array_has(arr: Array, target: int) -> bool:
	for item in arr:
		if int(item) == target:
			return true
	return false

static func _has_table(table_name: String) -> bool:
	var rows: Array = _DBManager.query_rows(
		"SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='%s';" % table_name.replace("'", "''")
	)
	return not rows.is_empty() and int(rows[0].get("cnt", 0)) > 0