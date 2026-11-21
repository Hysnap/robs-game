# res://systems/dev_authoring/city_demographics_report_model.gd
class_name CityDemographicsReportModel
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

## Builds the complete Expected (JSON) vs. Actual (SQLite) comparison report payload
static func generate_report(custom_db_path: String = "") -> Dictionary:
	var ok: bool = DB_MANAGER.initialize_database(false, custom_db_path)
	if not ok or not DB_MANAGER.is_society_populated():
		return {
			"success": false,
			"error": "No populated city database found. Generate or load a city first (path: %s)." % DB_MANAGER.active_db_path
		}

	# Verify that the target DB includes the current cognitive/clinical schema columns
	var col_rows: Array = DB_MANAGER.query_rows("PRAGMA table_info(residents);")
	var has_iq_col: bool = false
	for c in col_rows:
		if str(c.get("name", "")) == "iq_score":
			has_iq_col = true
			break
	if not has_iq_col:
		return {
			"success": false,
			"error": "Database '%s' uses an older pre-cognitive schema (missing iq_score). Delete old .db or generate a fresh city first." % DB_MANAGER.active_db_path
		}

	var demographics: Dictionary = MANIFEST_MANAGER.load_module("demographics")
	var cultural: Dictionary = MANIFEST_MANAGER.load_module("cultural_demographics")
	var ocean_rules: Dictionary = MANIFEST_MANAGER.load_module("ocean_personality")

	var sim_day: int = _resolve_reference_sim_day()
	var active_seed: String = DB_MANAGER.get_metadata("active_seed", "UNKNOWN")
	var pop_mode: String = str(ocean_rules.get("active_population_mode", "REALISTIC"))

	var pop_rows: Array = DB_MANAGER.query_rows("SELECT COUNT(*) AS cnt FROM residents WHERE dod IS NULL;")
	var total_pop: int = int(pop_rows[0]["cnt"]) if not pop_rows.is_empty() else 0
	if total_pop <= 0:
		return {
			"success": false,
			"error": "Active database contains 0 living residents."
		}

	var hh_rows: Array = DB_MANAGER.query_rows("SELECT COUNT(*) AS cnt FROM households WHERE valid_to IS NULL;")
	var total_hh: int = int(hh_rows[0]["cnt"]) if not hh_rows.is_empty() else 0

	var pyramid_series: Array[Dictionary] = _build_population_pyramid(demographics, sim_day, total_pop)
	var trait_series: Array[Dictionary] = _build_continuous_traits_comparison(ocean_rules, total_pop)
	var tag_series: Array[Dictionary] = _build_behavioral_tags_comparison(ocean_rules, sim_day, total_pop)
	var edu_series: Array[Dictionary] = _build_education_comparison(demographics, sim_day, total_pop)
	var ethnicity_series: Array[Dictionary] = _build_cultural_label_comparison("ETHNICITY", "ethnicity_id", cultural, total_pop)
	var religion_series: Array[Dictionary] = _build_cultural_label_comparison("RELIGION", "religion_id", cultural, total_pop)

	return {
		"success": true,
		"db_path": DB_MANAGER.active_db_path,
		"active_seed": active_seed,
		"population_mode": pop_mode,
		"total_population": total_pop,
		"total_households": total_hh,
		"mean_household_size": snappedf(float(total_pop) / float(maxi(1, total_hh)), 0.02),
		"expected_household_size": float(demographics.get("household_occupancy_mean", 2.6)),
		"pyramid": pyramid_series,
		"continuous_traits": trait_series,
		"behavioral_tags": tag_series,
		"education": edu_series,
		"ethnicity": ethnicity_series,
		"religion": religion_series
	}

## Resolves the exact simulation day epoch stored in the inspected database via CalendarHelper
static func _resolve_reference_sim_day() -> int:
	var helper_day: int = CALENDAR_HELPER.get_current_sim_day()
	if helper_day > 0:
		return helper_day
	var vf_rows: Array = DB_MANAGER.query_rows("SELECT MAX(valid_from) AS max_vf FROM residents;")
	if not vf_rows.is_empty() and vf_rows[0]["max_vf"] != null:
		return int(vf_rows[0]["max_vf"])
	return CALENDAR_HELPER.get_simulation_start_day()

## Compares actual age/gender distribution against demographics.population_pyramid
static func _build_population_pyramid(demographics: Dictionary, sim_day: int, total_pop: int) -> Array[Dictionary]:
	var actual_rows: Array = DB_MANAGER.query_rows("""
		SELECT
			CAST((%d - r.dob) / 365.25 AS INTEGER) AS age_years,
			l.code AS gender_code,
			COUNT(*) AS cnt
		FROM residents r
		JOIN system_labels l ON r.gender_id = l.label_id
		WHERE r.dod IS NULL
		GROUP BY age_years, l.code;
	""" % sim_day)

	var out: Array[Dictionary] = []
	var pyramid_cfg: Array = demographics.get("population_pyramid", [])
	for band in pyramid_cfg:
		var min_a: int = int(band["min_age"])
		var max_a: int = int(band["max_age"])
		var exp_m: float = float(band["male_pct"])
		var exp_f: float = float(band["female_pct"])

		var act_m_cnt: int = 0
		var act_f_cnt: int = 0
		for row in actual_rows:
			var a: int = int(row["age_years"])
			if a >= min_a and a <= max_a:
				var g: String = str(row["gender_code"]).to_upper()
				if g == "M" or g == "MALE":
					act_m_cnt += int(row["cnt"])
				else:
					act_f_cnt += int(row["cnt"])

		var act_m_pct: float = (float(act_m_cnt) / float(total_pop)) * 100.0
		var act_f_pct: float = (float(act_f_cnt) / float(total_pop)) * 100.0
		out.append({
			"label": "%d-%d" % [min_a, max_a],
			"expected_male_pct": snappedf(exp_m, 0.01),
			"actual_male_pct": snappedf(act_m_pct, 0.01),
			"expected_female_pct": snappedf(exp_f, 0.01),
			"actual_female_pct": snappedf(act_f_pct, 0.01)
		})

	return out

## Compares actual SQLite means/ranges for OCEAN, IQ, Mental Agility, and Dark Triad against ocean_personality_rules.json
static func _build_continuous_traits_comparison(ocean_rules: Dictionary, _total_pop: int) -> Array[Dictionary]:
	var stats_rows: Array = DB_MANAGER.query_rows("""
		SELECT
			AVG(openness) AS avg_o, MIN(openness) AS min_o, MAX(openness) AS max_o,
			AVG(conscientiousness) AS avg_c, MIN(conscientiousness) AS min_c, MAX(conscientiousness) AS max_c,
			AVG(extraversion) AS avg_e, MIN(extraversion) AS min_e, MAX(extraversion) AS max_e,
			AVG(agreeableness) AS avg_a, MIN(agreeableness) AS min_a, MAX(agreeableness) AS max_a,
			AVG(neuroticism) AS avg_n, MIN(neuroticism) AS min_n, MAX(neuroticism) AS max_n,
			AVG(iq_score) AS avg_iq, MIN(iq_score) AS min_iq, MAX(iq_score) AS max_iq,
			AVG(mental_agility) AS avg_ag, MIN(mental_agility) AS min_ag, MAX(mental_agility) AS max_ag,
			AVG(machiavellianism) AS avg_mach, MIN(machiavellianism) AS min_mach, MAX(machiavellianism) AS max_mach,
			AVG(empathy_affective) AS avg_emp, MIN(empathy_affective) AS min_emp, MAX(empathy_affective) AS max_emp,
			AVG(power_entitlement) AS avg_ent, MIN(power_entitlement) AS min_ent, MAX(power_entitlement) AS max_ent
		FROM residents
		WHERE dod IS NULL;
	""")
	if stats_rows.is_empty():
		return []

	var s: Dictionary = stats_rows[0]
	var base_mean: float = float(ocean_rules.get("baseline_distribution", {}).get("mean", 0.50))
	var cog: Dictionary = ocean_rules.get("cognitive_model", {})
	var iq_mean: float = float(cog.get("iq_reference_mean", 100.0))
	var ag_mean: float = float(cog.get("mental_agility", {}).get("baseline_mean", 0.50))
	var dark: Dictionary = ocean_rules.get("dark_and_empathy_axes", {})

	var specs: Array[Dictionary] = [
		{"key": "openness", "label": "Openness (O)", "exp": base_mean, "act": float(s["avg_o"]), "min": float(s["min_o"]), "max": float(s["max_o"]), "scale": 1.0},
		{"key": "conscientiousness", "label": "Conscientiousness (C)", "exp": base_mean, "act": float(s["avg_c"]), "min": float(s["min_c"]), "max": float(s["max_c"]), "scale": 1.0},
		{"key": "extraversion", "label": "Extraversion (E)", "exp": base_mean, "act": float(s["avg_e"]), "min": float(s["min_e"]), "max": float(s["max_e"]), "scale": 1.0},
		{"key": "agreeableness", "label": "Agreeableness (A)", "exp": base_mean, "act": float(s["avg_a"]), "min": float(s["min_a"]), "max": float(s["max_a"]), "scale": 1.0},
		{"key": "neuroticism", "label": "Neuroticism (N)", "exp": base_mean, "act": float(s["avg_n"]), "min": float(s["min_n"]), "max": float(s["max_n"]), "scale": 1.0},
		{"key": "iq_score", "label": "IQ Score (GMM)", "exp": iq_mean, "act": float(s["avg_iq"]), "min": float(s["min_iq"]), "max": float(s["max_iq"]), "scale": 165.0},
		{"key": "mental_agility", "label": "Mental Agility", "exp": ag_mean, "act": float(s["avg_ag"]), "min": float(s["min_ag"]), "max": float(s["max_ag"]), "scale": 1.0},
		{"key": "machiavellianism", "label": "Machiavellianism", "exp": float(dark.get("machiavellianism", {}).get("mean", 0.36)), "act": float(s["avg_mach"]), "min": float(s["min_mach"]), "max": float(s["max_mach"]), "scale": 1.0},
		{"key": "empathy_affective", "label": "Affective Empathy", "exp": float(dark.get("empathy_affective", {}).get("mean", 0.54)), "act": float(s["avg_emp"]), "min": float(s["min_emp"]), "max": float(s["max_emp"]), "scale": 1.0},
		{"key": "power_entitlement", "label": "Power Entitlement", "exp": float(dark.get("power_entitlement", {}).get("mean", 0.38)), "act": float(s["avg_ent"]), "min": float(s["min_ent"]), "max": float(s["max_ent"]), "scale": 1.0}
	]

	var out: Array[Dictionary] = []
	for item in specs:
		var scale: float = float(item["scale"])
		var exp_v: float = float(item["exp"])
		var act_v: float = float(item["act"])
		out.append({
			"label": str(item["label"]),
			"expected_display": "%.1f" % exp_v if scale > 1.0 else "%.3f" % exp_v,
			"actual_display": "%.1f" % act_v if scale > 1.0 else "%.3f" % act_v,
			"range_display": "[%.1f..%.1f]" % [float(item["min"]), float(item["max"])] if scale > 1.0 else "[%.2f..%.2f]" % [float(item["min"]), float(item["max"])],
			"expected_norm": clampf(exp_v / scale, 0.0, 1.0),
			"actual_norm": clampf(act_v / scale, 0.0, 1.0),
			"delta_pct": snappedf(((act_v - exp_v) / maxf(0.001, exp_v)) * 100.0, 0.1)
		})

	return out

## Compares sparse neurodivergence & clinical behavioral tags against ocean_personality_rules.json
static func _build_behavioral_tags_comparison(ocean_rules: Dictionary, sim_day: int, total_pop: int) -> Array[Dictionary]:
	var tag_rows: Array = DB_MANAGER.query_rows("""
		SELECT l.code AS tag_code, COUNT(DISTINCT t.resident_id) AS cnt, AVG(t.severity) AS avg_sev
		FROM resident_behavioral_tags t
		JOIN system_labels l ON t.tag_label_id = l.label_id
		JOIN residents r ON t.resident_id = r.resident_id
		WHERE t.valid_to IS NULL AND r.dod IS NULL
		GROUP BY l.code;
	""")
	var actual_map: Dictionary = {}
	for r in tag_rows:
		actual_map[str(r["tag_code"])] = {
			"count": int(r["cnt"]),
			"avg_sev": float(r["avg_sev"])
		}

	var preset_mode: String = str(ocean_rules.get("active_population_mode", "REALISTIC"))
	var prev_mult: float = float(ocean_rules.get("population_presets", {}).get(preset_mode, {}).get("profile_prevalence_multiplier", 1.0))
	var profiles: Dictionary = ocean_rules.get("neurodivergence_and_clinical_profiles", {})

	var out: Array[Dictionary] = []
	for tag_code in profiles.keys():
		var p_def: Dictionary = profiles[tag_code]
		var min_a: int = int(p_def.get("min_age", 0))
		var max_a: int = int(p_def.get("max_age", 99))
		var elig_rows: Array = DB_MANAGER.query_rows("""
			SELECT COUNT(*) AS cnt FROM residents
			WHERE dod IS NULL
			  AND CAST((%d - dob) / 365.25 AS INTEGER) BETWEEN %d AND %d;
		""" % [sim_day, min_a, max_a])
		var elig_pop: int = int(elig_rows[0]["cnt"]) if not elig_rows.is_empty() else total_pop
		elig_pop = maxi(1, elig_pop)

		var exp_pct: float = float(p_def.get("base_prevalence", 0.0)) * prev_mult * 100.0
		var act_info: Dictionary = actual_map.get(str(tag_code), {"count": 0, "avg_sev": 0.0})
		var act_cnt: int = int(act_info["count"])
		var act_pct: float = (float(act_cnt) / float(elig_pop)) * 100.0

		out.append({
			"label": "%s (n=%d)" % [str(tag_code), act_cnt],
			"expected_pct": snappedf(exp_pct, 0.01),
			"actual_pct": snappedf(act_pct, 0.01),
			"avg_severity": snappedf(float(act_info["avg_sev"]), 0.02),
			"delta_pct": snappedf(act_pct - exp_pct, 0.01)
		})

	return out

## Compares actual education attainment percentages against demographics.education_attainment_model
static func _build_education_comparison(demographics: Dictionary, sim_day: int, _total_pop: int) -> Array[Dictionary]:
	var adult_rows: Array = DB_MANAGER.query_rows("""
		SELECT l.code AS edu_code, COUNT(*) AS cnt
		FROM residents r
		JOIN system_labels l ON r.education_level_id = l.label_id
		WHERE r.dod IS NULL AND CAST((%d - r.dob) / 365.25 AS INTEGER) >= 16
		GROUP BY l.code;
	""" % sim_day)

	var total_adults: int = 0
	var act_counts: Dictionary = {}
	for r in adult_rows:
		var c: int = int(r["cnt"])
		act_counts[str(r["edu_code"])] = c
		total_adults += c
	total_adults = maxi(1, total_adults)

	var rates: Array = demographics.get("education_attainment_model", {}).get("cohort_attainment_rates", [])
	var exp_accum: Dictionary = {
		"UNIVERSITY_DEGREE": 0.0,
		"POLYTECHNIC_DIPLOMA": 0.0,
		"A_LEVELS": 0.0,
		"O_LEVELS_CSE": 0.0,
		"NO_FORMAL": 0.0
	}
	var cohort_n: float = float(maxi(1, rates.size()))
	for band in rates:
		var mp: Dictionary = band.get("male_probabilities", {})
		var fp: Dictionary = band.get("female_probabilities", {})
		var u_p: float = (float(mp.get("UNIVERSITY_DEGREE", 0.0)) + float(fp.get("UNIVERSITY_DEGREE", 0.0))) * 0.5
		var p_p: float = (float(mp.get("POLYTECHNIC_DIPLOMA", 0.0)) + float(fp.get("POLYTECHNIC_DIPLOMA", 0.0))) * 0.5
		var a_p: float = (float(mp.get("A_LEVELS", 0.0)) + float(fp.get("A_LEVELS", 0.0))) * 0.5
		var o_p: float = (float(mp.get("O_LEVELS_CSE", 0.0)) + float(fp.get("O_LEVELS_CSE", 0.0))) * 0.5
		var sum_qual: float = minf(1.0, u_p + p_p + a_p + (o_p * 0.5))
		exp_accum["UNIVERSITY_DEGREE"] += u_p / cohort_n
		exp_accum["POLYTECHNIC_DIPLOMA"] += p_p / cohort_n
		exp_accum["A_LEVELS"] += a_p / cohort_n
		exp_accum["O_LEVELS_CSE"] += (o_p * 0.5) / cohort_n
		exp_accum["NO_FORMAL"] += maxf(0.0, 1.0 - sum_qual) / cohort_n

	var out: Array[Dictionary] = []
	for code in ["NO_FORMAL", "O_LEVELS_CSE", "A_LEVELS", "POLYTECHNIC_DIPLOMA", "UNIVERSITY_DEGREE"]:
		var exp_pct: float = float(exp_accum.get(code, 0.0)) * 100.0
		var act_pct: float = (float(act_counts.get(code, 0)) / float(total_adults)) * 100.0
		out.append({
			"label": code,
			"expected_pct": snappedf(exp_pct, 0.1),
			"actual_pct": snappedf(act_pct, 0.1),
			"delta_pct": snappedf(act_pct - exp_pct, 0.1)
		})
	return out

## Compares actual ETHNICITY or RELIGION distribution against cultural_demographics baseline weights
static func _build_cultural_label_comparison(domain: String, fk_col: String, cultural: Dictionary, total_pop: int) -> Array[Dictionary]:
	var rows: Array = DB_MANAGER.query_rows("""
		SELECT l.code AS code, COUNT(*) AS cnt
		FROM residents r
		JOIN system_labels l ON r.%s = l.label_id
		WHERE r.dod IS NULL
		GROUP BY l.code
		ORDER BY cnt DESC;
	""" % fk_col)

	var weight_key: String = "ethnicity_weights" if domain == "ETHNICITY" else "religion_weights"
	var exp_weights: Dictionary = {}
	var archetypes_map: Dictionary = cultural.get("archetypes", cultural)
	var arch_count: int = 0
	for k in archetypes_map.keys():
		var entry = archetypes_map[k]
		if entry is Dictionary and entry.has(weight_key):
			arch_count += 1
			var w_dict: Dictionary = entry[weight_key]
			for wk in w_dict.keys():
				exp_weights[str(wk)] = float(exp_weights.get(str(wk), 0.0)) + float(w_dict[wk])

	var out: Array[Dictionary] = []
	for r in rows:
		var code: String = str(r["code"])
		var act_pct: float = (float(r["cnt"]) / float(total_pop)) * 100.0
		var exp_pct: float = (float(exp_weights.get(code, 0.0)) / float(maxi(1, arch_count))) * 100.0
		out.append({
			"label": code,
			"expected_pct": snappedf(exp_pct, 0.1),
			"actual_pct": snappedf(act_pct, 0.1),
			"delta_pct": snappedf(act_pct - exp_pct, 0.1)
		})
	return out