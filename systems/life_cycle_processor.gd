# res://systems/life_cycle_processor.gd
class_name LifeCycleProcessor
extends RefCounted

const _DBManager = preload("res://systems/db_manager.gd")
const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _ManifestManager = preload("res://systems/scenario_manifest_manager.gd")
const _ObligationLedger = preload("res://systems/economy/obligation_ledger.gd")
const _IntelManager = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const _HouseholdComposer = preload("res://systems/society/household_composition_generator.gd")
const _PersonalityHydrator = preload("res://systems/society/citizen_personality_hydrator.gd")

const LIFE_EVENT_TYPES: Array[String] = ["LIFE_BIRTH", "LIFE_DEATH", "ILLNESS_ONSET", "ILLNESS_OUTBREAK"]

## Loads and validates the active life_cycle_rules JSON module
static func get_rules() -> Dictionary:
	assert(_ManifestManager.has_module("life_cycle_rules"),
		"FATAL: [LifeCycleProcessor] Active scenario manifest missing required 'life_cycle_rules' module.")
	var rules: Dictionary = _ManifestManager.load_module("life_cycle_rules")
	for req_key in ["event_tokens", "proactive_event_leakage", "month_seasonality_multipliers", "mortality_age_bands", "fertility_rules", "health_conditions"]:
		assert(rules.has(req_key), "FATAL: [LifeCycleProcessor] 'life_cycle_rules' missing required key '%s'." % req_key)
	return rules

## Returns true when advancing from prev_day to curr_day crosses a Gregorian calendar month boundary
static func crosses_month_boundary(prev_day: int, curr_day: int) -> bool:
	var prev_meta: Dictionary = _CalendarHelper.get_month_grid_meta(prev_day, 0)
	var curr_meta: Dictionary = _CalendarHelper.get_month_grid_meta(curr_day, 0)
	return int(prev_meta["year"]) != int(curr_meta["year"]) or int(prev_meta["month"]) != int(curr_meta["month"])

## Proactively schedules upcoming births, deaths, and illness onsets into calendar_events for the upcoming month window
static func schedule_upcoming_month_events(world_state: Dictionary, anchor_day: int) -> Dictionary:
	var summary := {
		"window_start": anchor_day,
		"window_end": anchor_day,
		"scheduled_births": 0,
		"scheduled_deaths": 0,
		"scheduled_illnesses": 0,
		"scheduled_outbreaks": 0
	}
	if not _DBManager.is_database_open() or not _has_table("residents") or not _has_table("calendar_events"):
		return summary

	var rules: Dictionary = get_rules()
	var month_meta: Dictionary = _CalendarHelper.get_month_grid_meta(anchor_day, 0)
	var sim_year: int = int(month_meta["year"])
	var sim_month: int = int(month_meta["month"]) # 1..12
	var month_idx: int = clampi(sim_month - 1, 0, 11)
	var window_start: int = maxi(anchor_day, int(month_meta["start_day"]))
	var window_end: int = int(month_meta["end_day"])
	if window_end < window_start:
		return summary

	summary["window_start"] = window_start
	summary["window_end"] = window_end

	var rng := RandomNumberGenerator.new()
	var seed_str: String = str(world_state.get("metadata", {}).get("seed_id", "0"))
	rng.seed = hash("%s:%d:%d" % [seed_str, sim_year, sim_month])

	var tokens: Dictionary = rules["event_tokens"]
	var leak_cfg: Dictionary = rules["proactive_event_leakage"]
	var intel_ctx: Dictionary = _IntelManager.build_player_intel_context(world_state)
	var crew_by_district: Dictionary = _index_crew_observers_by_district(world_state)

	# 1. Proactively schedule monthly deaths by age band & month seasonality
	summary["scheduled_deaths"] = _schedule_monthly_deaths(
		world_state, rules, tokens, leak_cfg, crew_by_district, intel_ctx,
		anchor_day, window_start, window_end, month_idx, rng
	)

	# 2. Proactively schedule monthly births for eligible mothers
	summary["scheduled_births"] = _schedule_monthly_births(
		world_state, rules, tokens, leak_cfg, crew_by_district, intel_ctx,
		anchor_day, window_start, window_end, month_idx, rng
	)

	# 3. Proactively schedule monthly illness onsets & public outbreak alerts
	var ill_counts: Dictionary = _schedule_monthly_illnesses(
		world_state, rules, tokens, leak_cfg, crew_by_district, intel_ctx,
		anchor_day, window_start, window_end, sim_year, month_idx, rng
	)
	summary["scheduled_illnesses"] = int(ill_counts.get("cases", 0))
	summary["scheduled_outbreaks"] = int(ill_counts.get("outbreaks", 0))

	return summary

## Resolves scheduled life-cycle events activating on current_sim_day, advances recoveries, and syncs memory-prioritized health state
static func process_daily_resolution(world_state: Dictionary, current_sim_day: int, activated_events: Array) -> Dictionary:
	var report := {
		"sim_day": current_sim_day,
		"births_resolved": 0,
		"deaths_resolved": 0,
		"illnesses_started": 0,
		"illnesses_recovered": 0,
		"health_records_in_memory": 0
	}
	if not _DBManager.is_database_open():
		return report

	for ev in activated_events:
		if not (ev is Dictionary):
			continue
		var ev_type: String = str(ev.get("event_type", "")).strip_edges().to_upper()
		if not LIFE_EVENT_TYPES.has(ev_type):
			continue
		var parsed = JSON.parse_string(str(ev.get("impacts_json", "[]")))
		if not (parsed is Array):
			continue
		for item in parsed:
			if not (item is Dictionary) or not item.has("lifecycle_action"):
				continue
			var action_type: String = str(item["lifecycle_action"]).strip_edges().to_upper()
			match action_type:
				"BIRTH":
					if _resolve_birth(current_sim_day, item):
						report["births_resolved"] += 1
				"DEATH":
					if _resolve_death(world_state, current_sim_day, item):
						report["deaths_resolved"] += 1
				"ILLNESS_ONSET":
					if _resolve_illness_onset(current_sim_day, item):
						report["illnesses_started"] += 1

	report["illnesses_recovered"] = _resolve_due_recoveries(current_sim_day)
	report["health_records_in_memory"] = sync_health_conditions_to_memory(world_state, current_sim_day)
	return report

## Hydrates active resident_health_conditions into world_state according to [memory_priorities] health_conditions
static func sync_health_conditions_to_memory(world_state: Dictionary, _current_sim_day: int) -> int:
	if not _DBManager.is_database_open() or not _has_table("resident_health_conditions"):
		world_state["resident_health_conditions"] = {}
		return 0

	var tier: String = _ManifestManager.get_memory_priority("health_conditions")
	if tier == "SQLITE_BACKGROUND":
		world_state["resident_health_conditions"] = {}
		return 0

	var sql: String = ""
	if tier == "FINE_IN_MEMORY":
		sql = """
			SELECT rhc.condition_id, rhc.resident_id, l.code AS condition_code,
			       rhc.severity, rhc.is_contagious, rhc.is_chronic,
			       rhc.is_diagnosed, rhc.is_treated, rhc.contracted_day, rhc.expected_recovery_day
			FROM resident_health_conditions rhc
			JOIN residents r ON rhc.resident_id = r.resident_id
			JOIN system_labels l ON rhc.condition_label_id = l.label_id
			WHERE rhc.valid_to IS NULL AND r.dod IS NULL
			ORDER BY rhc.resident_id ASC, rhc.condition_id ASC;
		"""
	else:
		# ACTIVE_KEY_ONLY: hydrate only crew/residents already in world_state["residents"] or flagged is_active_agent = 1
		var key_ids: Array[String] = []
		var residents_dict: Dictionary = world_state.get("residents", {})
		for r_key in residents_dict.keys():
			var rec = residents_dict[r_key]
			if rec is Dictionary:
				var rid: int = int(rec.get("resident_id", int(r_key) if str(r_key).is_valid_int() else 0))
				if rid > 0 and not key_ids.has(str(rid)):
					key_ids.append(str(rid))
		var where_clause: String = "r.is_active_agent = 1"
		if not key_ids.is_empty():
			where_clause = "(r.is_active_agent = 1 OR rhc.resident_id IN (%s))" % ", ".join(key_ids)
		sql = """
			SELECT rhc.condition_id, rhc.resident_id, l.code AS condition_code,
			       rhc.severity, rhc.is_contagious, rhc.is_chronic,
			       rhc.is_diagnosed, rhc.is_treated, rhc.contracted_day, rhc.expected_recovery_day
			FROM resident_health_conditions rhc
			JOIN residents r ON rhc.resident_id = r.resident_id
			JOIN system_labels l ON rhc.condition_label_id = l.label_id
			WHERE rhc.valid_to IS NULL AND r.dod IS NULL AND %s
			ORDER BY rhc.resident_id ASC, rhc.condition_id ASC;
		""" % where_clause

	var rows: Array = _DBManager.query_rows(sql)
	var by_resident: Dictionary = {}
	for row in rows:
		var rid_str: String = str(int(row["resident_id"]))
		if not by_resident.has(rid_str):
			by_resident[rid_str] = []
		by_resident[rid_str].append({
			"condition_id": int(row["condition_id"]),
			"condition_code": str(row["condition_code"]),
			"severity": float(row["severity"]),
			"is_contagious": int(row["is_contagious"]) == 1,
			"is_chronic": int(row["is_chronic"]) == 1,
			"is_diagnosed": int(row["is_diagnosed"]) == 1,
			"is_treated": int(row["is_treated"]) == 1,
			"contracted_day": int(row["contracted_day"]),
			"expected_recovery_day": row["expected_recovery_day"]
		})

	world_state["resident_health_conditions"] = by_resident
	return rows.size()

# ==============================================================================
# PROACTIVE MONTHLY SCHEDULING HELPERS
# ==============================================================================

static func _schedule_monthly_deaths(
	world_state: Dictionary,
	rules: Dictionary,
	tokens: Dictionary,
	leak_cfg: Dictionary,
	crew_by_district: Dictionary,
	_intel_ctx: Dictionary,
	anchor_day: int,
	window_start: int,
	window_end: int,
	month_idx: int,
	rng: RandomNumberGenerator
) -> int:
	var scheduled_count: int = 0
	var seasonality_map: Dictionary = rules["month_seasonality_multipliers"]
	var bands: Array = rules["mortality_age_bands"]

	for band in bands:
		if not (band is Dictionary):
			continue
		var age_min: int = int(band["age_min"])
		var age_max: int = int(band["age_max"])
		var annual_rate: float = float(band["annual_mortality_rate"])
		var cause_weights: Dictionary = band["cause_weights"]

		var dob_max: int = anchor_day - (age_min * 365)
		var dob_min: int = anchor_day - ((age_max + 1) * 365) + 1
		var cnt_rows: Array = _DBManager.query_rows("""
			SELECT COUNT(*) AS cnt FROM residents
			WHERE dod IS NULL AND dob >= %d AND dob <= %d;
		""" % [dob_min, dob_max])
		if cnt_rows.is_empty():
			continue
		var cohort_pop: int = int(cnt_rows[0]["cnt"])
		if cohort_pop <= 0:
			continue

		var weighted_causes: Dictionary = {}
		var season_factor_sum: float = 0.0
		var base_weight_sum: float = 0.0
		for c_code in cause_weights.keys():
			var w: float = float(cause_weights[c_code])
			var s_arr: Array = seasonality_map.get(c_code, [])
			var s_mult: float = float(s_arr[month_idx]) if s_arr.size() > month_idx else 1.0
			weighted_causes[str(c_code)] = w * s_mult
			season_factor_sum += w * s_mult
			base_weight_sum += w

		var avg_season_mult: float = (season_factor_sum / base_weight_sum) if base_weight_sum > 0.0 else 1.0
		var expected: float = float(cohort_pop) * (annual_rate / 12.0) * avg_season_mult
		var target_count: int = _stochastic_round(expected, rng)
		if target_count <= 0:
			continue

		var candidates: Array = _DBManager.query_rows("""
			SELECT r.resident_id, r.household_id, e.district_id
			FROM residents r
			JOIN households h ON r.household_id = h.household_id
			JOIN establishments e ON h.establishment_id = e.establishment_id
			WHERE r.dod IS NULL AND r.dob >= %d AND r.dob <= %d
			ORDER BY RANDOM()
			LIMIT %d;
		""" % [dob_min, dob_max, target_count])

		for cand in candidates:
			var res_id: int = int(cand["resident_id"])
			var dist_id: String = str(cand["district_id"]).strip_edges()
			if dist_id.is_empty():
				continue
			var chosen_cause: String = _pick_weighted_key(weighted_causes, rng)
			var ev_day: int = rng.randi_range(window_start, window_end)
			var participant_count: int = _count_household_members(int(cand["household_id"])) + 1
			var ev_id: int = _ObligationLedger.create_calendar_event({
				"event_type": "LIFE_DEATH",
				"title_token": str(tokens["death_title_token"]),
				"organizer": _ObligationLedger.format_scoped_entity("RESIDENT", str(res_id)),
				"location_scope": "DISTRICT",
				"location_id": dist_id,
				"start_day": ev_day,
				"end_day": ev_day,
				"visibility_scope": "PRIVATE",
				"created_day": anchor_day,
				"impacts": [ {
					"lifecycle_action": "DEATH",
					"resident_id": res_id,
					"death_reason_code": chosen_cause,
					"participant_count": participant_count
				}]
			})
			_apply_participant_rumour_leakage(world_state, ev_id, dist_id, participant_count, leak_cfg, crew_by_district)
			scheduled_count += 1

	return scheduled_count

static func _schedule_monthly_births(
	world_state: Dictionary,
	rules: Dictionary,
	tokens: Dictionary,
	leak_cfg: Dictionary,
	crew_by_district: Dictionary,
	_intel_ctx: Dictionary,
	anchor_day: int,
	window_start: int,
	window_end: int,
	month_idx: int,
	rng: RandomNumberGenerator
) -> int:
	var fert: Dictionary = rules["fertility_rules"]
	var female_id: int = _DBManager.get_label_id("GENDER", str(fert["female_gender_code"]))
	var month_mults: Array = fert["month_multipliers"]
	var month_mult: float = float(month_mults[month_idx]) if month_mults.size() > month_idx else 1.0
	var male_prob: float = float(fert["male_birth_probability"])
	var male_code: String = str(fert["male_gender_code"])
	var female_code: String = str(fert["female_gender_code"])
	var min_spacing: int = int(fert["min_birth_spacing_days"])
	var scheduled_count: int = 0

	for band in fert["age_band_annual_rates"]:
		if not (band is Dictionary):
			continue
		var age_min: int = int(band["age_min"])
		var age_max: int = int(band["age_max"])
		var annual_rate: float = float(band["annual_birth_rate"])
		var dob_max: int = anchor_day - (age_min * 365)
		var dob_min: int = anchor_day - ((age_max + 1) * 365) + 1

		var cnt_rows: Array = _DBManager.query_rows("""
			SELECT COUNT(*) AS cnt FROM residents
			WHERE dod IS NULL AND gender_id = %d AND dob >= %d AND dob <= %d;
		""" % [female_id, dob_min, dob_max])
		if cnt_rows.is_empty():
			continue
		var cohort_pop: int = int(cnt_rows[0]["cnt"])
		if cohort_pop <= 0:
			continue

		var expected: float = float(cohort_pop) * (annual_rate / 12.0) * month_mult
		var target_count: int = _stochastic_round(expected, rng)
		if target_count <= 0:
			continue

		var candidates: Array = _DBManager.query_rows("""
			SELECT r.resident_id, r.household_id, e.district_id
			FROM residents r
			JOIN households h ON r.household_id = h.household_id
			JOIN establishments e ON h.establishment_id = e.establishment_id
			WHERE r.dod IS NULL AND r.gender_id = %d AND r.dob >= %d AND r.dob <= %d
			  AND NOT EXISTS (
				SELECT 1 FROM residents c
				WHERE c.household_id = r.household_id AND c.dob > %d
			  )
			ORDER BY RANDOM()
			LIMIT %d;
		""" % [female_id, dob_min, dob_max, anchor_day - min_spacing, target_count])

		for cand in candidates:
			var mother_id: int = int(cand["resident_id"])
			var hh_id: int = int(cand["household_id"])
			var dist_id: String = str(cand["district_id"]).strip_edges()
			if dist_id.is_empty():
				continue
			var ev_day: int = rng.randi_range(window_start, window_end)
			var child_gender: String = male_code if rng.randf() < male_prob else female_code
			var participant_count: int = _count_household_members(hh_id) + 2
			var ev_id: int = _ObligationLedger.create_calendar_event({
				"event_type": "LIFE_BIRTH",
				"title_token": str(tokens["birth_title_token"]),
				"organizer": _ObligationLedger.format_scoped_entity("RESIDENT", str(mother_id)),
				"location_scope": "DISTRICT",
				"location_id": dist_id,
				"start_day": ev_day,
				"end_day": ev_day,
				"visibility_scope": "PRIVATE",
				"created_day": anchor_day,
				"impacts": [ {
					"lifecycle_action": "BIRTH",
					"mother_id": mother_id,
					"household_id": hh_id,
					"child_gender_code": child_gender,
					"participant_count": participant_count
				}]
			})
			_apply_participant_rumour_leakage(world_state, ev_id, dist_id, participant_count, leak_cfg, crew_by_district)
			scheduled_count += 1

	return scheduled_count

static func _schedule_monthly_illnesses(
	world_state: Dictionary,
	rules: Dictionary,
	tokens: Dictionary,
	leak_cfg: Dictionary,
	crew_by_district: Dictionary,
	_intel_ctx: Dictionary,
	anchor_day: int,
	window_start: int,
	window_end: int,
	sim_year: int,
	month_idx: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var total_cases: int = 0
	var total_outbreaks: int = 0
	var conditions_map: Dictionary = rules["health_conditions"]
	var outbreak_threshold: int = int(leak_cfg["public_outbreak_case_threshold"])

	var living_rows: Array = _DBManager.query_rows("SELECT COUNT(*) AS cnt FROM residents WHERE dod IS NULL;")
	if living_rows.is_empty():
		return {"cases": 0, "outbreaks": 0}
	var total_living: int = int(living_rows[0]["cnt"])
	if total_living <= 0:
		return {"cases": 0, "outbreaks": 0}

	for cond_code in conditions_map.keys():
		var cfg: Dictionary = conditions_map[cond_code]
		if sim_year < int(cfg["min_year"]) or sim_year > int(cfg["max_year"]):
			continue
		var annual_rate: float = float(cfg["annual_incidence_rate"])
		var m_mults: Array = cfg["month_multipliers"]
		var m_mult: float = float(m_mults[month_idx]) if m_mults.size() > month_idx else 1.0
		var ep_years: Array = cfg.get("epidemic_years", [])
		var ep_mult: float = float(cfg.get("epidemic_multiplier", 1.0)) if ep_years.has(sim_year) else 1.0

		var expected: float = float(total_living) * (annual_rate / 12.0) * m_mult * ep_mult
		var target_count: int = _stochastic_round(expected, rng)
		if target_count <= 0:
			continue

		var candidates: Array = _DBManager.query_rows("""
			SELECT r.resident_id, r.household_id, e.district_id
			FROM residents r
			JOIN households h ON r.household_id = h.household_id
			JOIN establishments e ON h.establishment_id = e.establishment_id
			WHERE r.dod IS NULL
			ORDER BY RANDOM()
			LIMIT %d;
		""" % target_count)

		var dur_range: Array = cfg["duration_days"]
		var dur_min: int = int(dur_range[0])
		var dur_max: int = int(dur_range[1]) if dur_range.size() > 1 else dur_min
		var is_contagious: bool = bool(cfg["is_contagious"])
		var is_chronic: bool = bool(cfg["is_chronic"])
		var base_sev: float = float(cfg["base_severity"])
		var district_case_counts: Dictionary = {}

		for cand in candidates:
			var res_id: int = int(cand["resident_id"])
			var dist_id: String = str(cand["district_id"]).strip_edges()
			if dist_id.is_empty():
				continue
			var ev_day: int = rng.randi_range(window_start, window_end)
			var dur: int = rng.randi_range(dur_min, dur_max)
			var participant_count: int = _count_household_members(int(cand["household_id"]))
			var ev_id: int = _ObligationLedger.create_calendar_event({
				"event_type": "ILLNESS_ONSET",
				"title_token": str(tokens["illness_case_title_token"]),
				"organizer": _ObligationLedger.format_scoped_entity("RESIDENT", str(res_id)),
				"location_scope": "DISTRICT",
				"location_id": dist_id,
				"start_day": ev_day,
				"end_day": ev_day,
				"visibility_scope": "PRIVATE",
				"created_day": anchor_day,
				"impacts": [ {
					"lifecycle_action": "ILLNESS_ONSET",
					"resident_id": res_id,
					"condition_code": str(cond_code),
					"severity": clampf(base_sev + rng.randf_range(-0.15, 0.15), 0.1, 1.0),
					"is_contagious": is_contagious,
					"is_chronic": is_chronic,
					"duration_days": dur,
					"participant_count": participant_count
				}]
			})
			_apply_participant_rumour_leakage(world_state, ev_id, dist_id, participant_count, leak_cfg, crew_by_district)
			total_cases += 1
			if is_contagious:
				district_case_counts[dist_id] = int(district_case_counts.get(dist_id, 0)) + 1

		if is_contagious:
			for d_id in district_case_counts.keys():
				if int(district_case_counts[d_id]) >= outbreak_threshold:
					_ObligationLedger.create_calendar_event({
						"event_type": "ILLNESS_OUTBREAK",
						"title_token": str(tokens["outbreak_public_title_token"]),
						"location_scope": "DISTRICT",
						"location_id": str(d_id),
						"start_day": window_start,
						"end_day": window_end,
						"visibility_scope": "PUBLIC",
						"created_day": anchor_day,
						"impacts": []
					})
					total_outbreaks += 1

	return {"cases": total_cases, "outbreaks": total_outbreaks}

## Applies participant-scaled rumour impulse to co-located crew observers when a non-public event is scheduled
static func _apply_participant_rumour_leakage(
	world_state: Dictionary,
	event_id: int,
	district_id: String,
	participant_count: int,
	leak_cfg: Dictionary,
	crew_by_district: Dictionary
) -> void:
	if event_id <= 0 or not crew_by_district.has(district_id):
		return
	var base_perm: float = float(leak_cfg["base_permeability"])
	var per_part: float = float(leak_cfg["per_participant_increment"])
	var max_perm: float = float(leak_cfg["max_permeability"])
	var base_effort: float = float(leak_cfg["rumour_base_effort"])
	var permeability: float = clampf(base_perm + (float(maxi(1, participant_count)) * per_part), 0.05, max_perm)

	for obs_id in crew_by_district[district_id]:
		_IntelManager.apply_effort_impulse(
			world_state,
			"RESIDENT",
			str(obs_id),
			"EVENT",
			str(event_id),
			base_effort,
			{"distance": 0.0, "access_permeability": permeability}
		)

# ==============================================================================
# SCHEDULED DAILY RESOLUTION MUTATORS
# ==============================================================================

static func _resolve_birth(current_sim_day: int, payload: Dictionary) -> bool:
	var mother_id: int = int(payload.get("mother_id", 0))
	var hh_id: int = int(payload.get("household_id", 0))
	if mother_id <= 0 or hh_id <= 0:
		return false

	var mother_rows: Array = _DBManager.query_rows("""
		SELECT r.resident_id, r.household_id, r.current_surname, r.ethnicity_id, r.religion_id,
		       r.openness, r.conscientiousness, r.extraversion, r.agreeableness, r.neuroticism,
		       l_eth.code AS ethnicity_code, l_rel.code AS religion_code,
		       d.district_type, d.base_unemployment_rate
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		JOIN districts d ON e.district_id = d.district_id
		JOIN system_labels l_eth ON r.ethnicity_id = l_eth.label_id
		JOIN system_labels l_rel ON r.religion_id = l_rel.label_id
		WHERE r.resident_id = %d AND r.dod IS NULL
		LIMIT 1;
	""" % mother_id)
	if mother_rows.is_empty():
		return false

	var mother: Dictionary = mother_rows[0]
	var gender_code: String = str(payload.get("child_gender_code", "F")).strip_edges().to_upper()
	var is_male: bool = (gender_code == "M")
	var gender_id: int = _DBManager.get_label_id("GENDER", gender_code)
	var edu_id: int = _DBManager.get_label_id("EDUCATION_LEVEL", "NO_FORMAL")
	var birth_reason_id: int = _DBManager.get_label_id("CHANGE_REASON", "BIRTH")
	var eth_id: int = int(mother["ethnicity_id"])
	var rel_id: int = int(mother["religion_id"])
	var eth_code: String = str(mother["ethnicity_code"]).strip_edges()
	var rel_code: String = str(mother["religion_code"]).strip_edges()
	var surname: String = str(mother["current_surname"]).replace("'", "''")

	var cultural_cfg: Dictionary = _ManifestManager.load_module("cultural_demographics")
	var lexicon_cfg: Dictionary = _ManifestManager.load_module("lexicon")
	var ethnicities_map: Dictionary = cultural_cfg.get("ethnicities", {})
	assert(ethnicities_map.has(eth_code),
		"FATAL: [LifeCycleProcessor] Ethnicity code '%s' not found in cultural_demographics." % eth_code)
	var surnames_pool: String = str(ethnicities_map[eth_code].get("surnames_pool", "surnames"))

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("BIRTH:%d:%d" % [current_sim_day, mother_id])
	var first_name: String = _HouseholdComposer.pick_first_name(lexicon_cfg, is_male, surnames_pool, rel_code, rng)

	var mother_traits: Dictionary = {
		"openness": float(mother["openness"]),
		"conscientiousness": float(mother["conscientiousness"]),
		"extraversion": float(mother["extraversion"]),
		"agreeableness": float(mother["agreeableness"]),
		"neuroticism": float(mother["neuroticism"])
	}
	var spouse_traits: Dictionary = {}
	var spouse_rows: Array = _DBManager.query_rows("""
		SELECT openness, conscientiousness, extraversion, agreeableness, neuroticism
		FROM residents
		WHERE household_id = %d AND resident_id != %d AND dod IS NULL AND (%d - dob) >= 5840
		ORDER BY dob ASC
		LIMIT 1;
	""" % [hh_id, mother_id, current_sim_day])
	if not spouse_rows.is_empty():
		var sp: Dictionary = spouse_rows[0]
		spouse_traits = {
			"openness": float(sp["openness"]),
			"conscientiousness": float(sp["conscientiousness"]),
			"extraversion": float(sp["extraversion"]),
			"agreeableness": float(sp["agreeableness"]),
			"neuroticism": float(sp["neuroticism"])
		}

	var archetypes_cfg: Dictionary = _ManifestManager.load_module("archetypes")
	var demographics_cfg: Dictionary = _ManifestManager.load_module("demographics")
	var ocean_rules: Dictionary = _ManifestManager.load_module("ocean_personality")
	var arch_nudges: Dictionary = _PersonalityHydrator.get_archetype_nudges(archetypes_cfg, str(mother["district_type"]))
	var edu_nudges: Dictionary = _PersonalityHydrator.get_education_nudges(demographics_cfg, "NO_FORMAL")
	var deprivation_ratio: float = clampf(float(mother["base_unemployment_rate"]) * 2.5, 0.0, 1.0)

	var child_traits: Dictionary = _PersonalityHydrator.roll_child_traits(
		mother_traits, spouse_traits, ocean_rules, arch_nudges, edu_nudges, rng
	)
	_PersonalityHydrator.populate_cognitive_and_clinical_profile(
		child_traits, ocean_rules, 0.0, "NO_FORMAL", deprivation_ratio, rng
	)

	var ok: bool = _DBManager.execute_batch([
		"""
		INSERT INTO residents (
			household_id, first_name, birth_surname, current_surname,
			dob, gender_id, education_level_id, ethnicity_id, religion_id,
			openness, conscientiousness, extraversion, agreeableness, neuroticism,
			iq_score, mental_agility, machiavellianism, empathy_affective, power_entitlement,
			valid_from, change_reason_id
		) VALUES (
			%d, '%s', '%s', '%s',
			%d, %d, %d, %d, %d,
			%.3f, %.3f, %.3f, %.3f, %.3f,
			%.1f, %.3f, %.3f, %.3f, %.3f,
			%d, %d
		);
		""" % [
			hh_id, first_name, surname, surname,
			current_sim_day, gender_id, edu_id, eth_id, rel_id,
			float(child_traits["openness"]), float(child_traits["conscientiousness"]),
			float(child_traits["extraversion"]), float(child_traits["agreeableness"]),
			float(child_traits["neuroticism"]),
			float(child_traits["iq_score"]), float(child_traits["mental_agility"]),
			float(child_traits["machiavellianism"]), float(child_traits["empathy_affective"]),
			float(child_traits["power_entitlement"]),
			current_sim_day, birth_reason_id
		]
	])
	if not ok:
		return false

	var id_rows: Array = _DBManager.query_rows("SELECT last_insert_rowid() AS id;")
	if not id_rows.is_empty():
		var child_id: int = int(id_rows[0]["id"])
		var post_stmts: Array[String] = []
		if _has_table("social_relationships"):
			var mother_rel_id: int = _DBManager.get_label_id("RELATIONSHIP_TYPE", "MOTHER")
			post_stmts.append("""
				INSERT INTO social_relationships (
					from_resident_id, to_resident_id, relationship_type_id,
					affinity_score, valid_from, change_reason_id
				) VALUES (%d, %d, %d, 0.95, %d, %d);
			""" % [child_id, mother_id, mother_rel_id, current_sim_day, birth_reason_id])
		if _has_table("resident_behavioral_tags"):
			for tag_entry in child_traits.get("behavioral_tags", []):
				var t_label_id: int = _DBManager.get_label_id("BEHAVIORAL_TAG", str(tag_entry["code"]))
				post_stmts.append("""
					INSERT INTO resident_behavioral_tags (
						resident_id, tag_label_id, severity, is_diagnosed, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %.2f, 0, %d, NULL, %d);
				""" % [child_id, t_label_id, float(tag_entry["severity"]), current_sim_day, birth_reason_id])
		if not post_stmts.is_empty():
			_DBManager.execute_batch(post_stmts)
	return true

static func _resolve_death(world_state: Dictionary, current_sim_day: int, payload: Dictionary) -> bool:
	var res_id: int = int(payload.get("resident_id", 0))
	if res_id <= 0:
		return false

	var res_rows: Array = _DBManager.query_rows("""
		SELECT resident_id, household_id FROM residents
		WHERE resident_id = %d AND dod IS NULL
		LIMIT 1;
	""" % res_id)
	if res_rows.is_empty():
		return false

	var hh_id: int = int(res_rows[0]["household_id"])
	var death_code: String = str(payload.get("death_reason_code", "NATURAL_CAUSES")).strip_edges().to_upper()
	var death_reason_id: int = _DBManager.get_label_id("DEATH_REASON", death_code)
	var change_reason_id: int = _DBManager.get_label_id("CHANGE_REASON", "DEATH")

	var stmts: Array[String] = [
		"""
		UPDATE residents
		SET dod = %d, death_reason_id = %d, valid_to = %d, change_reason_id = %d
		WHERE resident_id = %d;
		""" % [current_sim_day, death_reason_id, current_sim_day, change_reason_id, res_id]
	]

	if _has_table("livelihood_contracts"):
		stmts.append("""
			UPDATE livelihood_contracts
			SET valid_to = %d, change_reason_id = %d
			WHERE resident_id = %d AND valid_to IS NULL;
		""" % [current_sim_day, change_reason_id, res_id])

	if _has_table("workplace_job_slots"):
		stmts.append("""
			UPDATE workplace_job_slots
			SET is_filled = 0, active_resident_id = NULL
			WHERE active_resident_id = %d;
		""" % res_id)

	if _has_table("resident_health_conditions"):
		stmts.append("""
			UPDATE resident_health_conditions
			SET valid_to = %d, change_reason_id = %d
			WHERE resident_id = %d AND valid_to IS NULL;
		""" % [current_sim_day, change_reason_id, res_id])

	_DBManager.execute_batch(stmts)

	# Household succession or residential vacancy
	if hh_id > 0 and _has_table("households"):
		var survivors: Array = _DBManager.query_rows("""
			SELECT resident_id FROM residents
			WHERE household_id = %d AND dod IS NULL
			ORDER BY dob ASC
			LIMIT 1;
		""" % hh_id)
		if not survivors.is_empty():
			var next_head: int = int(survivors[0]["resident_id"])
			_DBManager.execute_batch([
				"UPDATE households SET head_resident_id = %d WHERE household_id = %d AND head_resident_id = %d;" % [next_head, hh_id, res_id]
			])
		else:
			_DBManager.execute_batch([
				"UPDATE households SET valid_to = %d, change_reason_id = %d WHERE household_id = %d;" % [current_sim_day, change_reason_id, hh_id],
				"""
				UPDATE establishments SET is_vacant = 1
				WHERE establishment_id = (SELECT establishment_id FROM households WHERE household_id = %d);
				""" % hh_id
			])

	# Mirror dod onto in-memory resident if hydrated
	var residents_dict: Dictionary = world_state.get("residents", {})
	for key in [res_id, str(res_id)]:
		if residents_dict.has(key) and residents_dict[key] is Dictionary:
			residents_dict[key]["dod"] = current_sim_day
			residents_dict[key]["death_reason_code"] = death_code

	return true

static func _resolve_illness_onset(current_sim_day: int, payload: Dictionary) -> bool:
	if not _has_table("resident_health_conditions"):
		return false
	var res_id: int = int(payload.get("resident_id", 0))
	if res_id <= 0:
		return false

	var alive: Array = _DBManager.query_rows("SELECT resident_id FROM residents WHERE resident_id = %d AND dod IS NULL LIMIT 1;" % res_id)
	if alive.is_empty():
		return false

	var cond_code: String = str(payload.get("condition_code", "")).strip_edges().to_upper()
	if cond_code.is_empty():
		return false
	var cond_label_id: int = _DBManager.get_label_id("HEALTH_CONDITION", cond_code)
	var onset_reason_id: int = _DBManager.get_label_id("CHANGE_REASON", "ILLNESS_ONSET")
	var severity: float = clampf(float(payload.get("severity", 0.5)), 0.05, 1.0)
	var is_contagious: int = 1 if bool(payload.get("is_contagious", false)) else 0
	var is_chronic: int = 1 if bool(payload.get("is_chronic", false)) else 0
	var duration_days: int = maxi(1, int(payload.get("duration_days", 7)))
	var expected_recovery_sql: String = "NULL" if is_chronic == 1 else str(current_sim_day + duration_days)

	return _DBManager.execute_batch([
		"""
		INSERT INTO resident_health_conditions (
			resident_id, condition_label_id, severity, is_contagious, is_chronic,
			is_diagnosed, is_treated, contracted_day, expected_recovery_day,
			valid_from, valid_to, change_reason_id
		) VALUES (
			%d, %d, %.4f, %d, %d,
			0, 0, %d, %s,
			%d, NULL, %d
		);
		""" % [res_id, cond_label_id, severity, is_contagious, is_chronic, current_sim_day, expected_recovery_sql, current_sim_day, onset_reason_id]
	])

static func _resolve_due_recoveries(current_sim_day: int) -> int:
	if not _has_table("resident_health_conditions"):
		return 0
	var due_rows: Array = _DBManager.query_rows("""
		SELECT condition_id FROM resident_health_conditions
		WHERE valid_to IS NULL AND expected_recovery_day IS NOT NULL AND expected_recovery_day <= %d;
	""" % current_sim_day)
	if due_rows.is_empty():
		return 0
	var rec_reason_id: int = _DBManager.get_label_id("CHANGE_REASON", "ILLNESS_RECOVERY")
	_DBManager.execute_batch([
		"""
		UPDATE resident_health_conditions
		SET valid_to = %d, change_reason_id = %d
		WHERE valid_to IS NULL AND expected_recovery_day IS NOT NULL AND expected_recovery_day <= %d;
		""" % [current_sim_day, rec_reason_id, current_sim_day]
	])
	return due_rows.size()

# ==============================================================================
# UTILITY HELPERS
# ==============================================================================

static func _index_crew_observers_by_district(world_state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var residents: Dictionary = world_state.get("residents", {})
	for r_key in residents.keys():
		var rec = residents[r_key]
		if rec is Dictionary and bool(rec.get("is_crew", false)):
			var d_id: String = str(rec.get("current_district_id", "")).strip_edges()
			var rid: String = str(rec.get("resident_id", r_key)).strip_edges()
			if not d_id.is_empty() and not rid.is_empty():
				if not out.has(d_id):
					out[d_id] = []
				if not out[d_id].has(rid):
					out[d_id].append(rid)
	return out

static func _count_household_members(household_id: int) -> int:
	if household_id <= 0:
		return 1
	var rows: Array = _DBManager.query_rows("SELECT COUNT(*) AS cnt FROM residents WHERE household_id = %d AND dod IS NULL;" % household_id)
	return maxi(1, int(rows[0]["cnt"])) if not rows.is_empty() else 1

static func _stochastic_round(expected: float, rng: RandomNumberGenerator) -> int:
	if expected <= 0.0:
		return 0
	var whole: int = floori(expected)
	var frac: float = expected - float(whole)
	return whole + (1 if rng.randf() < frac else 0)

static func _pick_weighted_key(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for k in weights.keys():
		total += maxf(0.0, float(weights[k]))
	assert(total > 0.0, "FATAL: [LifeCycleProcessor] Cannot sample from empty or zero-weight dictionary.")
	var roll: float = rng.randf() * total
	var running: float = 0.0
	var last_key: String = ""
	for k in weights.keys():
		last_key = str(k)
		running += maxf(0.0, float(weights[k]))
		if roll <= running:
			return last_key
	return last_key

static func _has_table(table_name: String) -> bool:
	var rows: Array = _DBManager.query_rows(
		"SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='%s';" % table_name.replace("'", "''")
	)
	return not rows.is_empty() and int(rows[0].get("cnt", 0)) > 0