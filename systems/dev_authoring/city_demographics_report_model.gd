# res://systems/dev_authoring/city_demographics_report_model.gd
class_name CityDemographicsReportModel
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

const CURVE_BINS: int = 20
const AGE_COHORTS: Array[Dictionary] = [
	{"label": "0-4", "min_age": 0, "max_age": 4},
	{"label": "5-15", "min_age": 5, "max_age": 15},
	{"label": "16-24", "min_age": 16, "max_age": 24},
	{"label": "25-34", "min_age": 25, "max_age": 34},
	{"label": "35-44", "min_age": 35, "max_age": 44},
	{"label": "45-54", "min_age": 45, "max_age": 54},
	{"label": "55-64", "min_age": 55, "max_age": 64},
	{"label": "65+", "min_age": 65, "max_age": 120}
]

## Builds the complete Expected (JSON) vs. Actual (SQLite) comparison report payload
static func generate_report(custom_db_path: String = "") -> Dictionary:
	var ok: bool = DB_MANAGER.initialize_database(false, custom_db_path)
	if not ok or not DB_MANAGER.is_society_populated():
		return {
			"success": false,
			"error": "No populated city database found. Generate or load a city first (path: %s)." % DB_MANAGER.active_db_path
		}

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
	var household_size_report: Dictionary = _build_household_size_distribution(demographics, total_pop)
	var family_size_report: Dictionary = _build_family_size_distribution(demographics, total_pop)
	var trait_series: Array[Dictionary] = _build_continuous_traits_comparison(ocean_rules, sim_day, total_pop)
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
		"total_family_units": int(family_size_report.get("total_family_units", 0)),
		"mean_family_size": float(family_size_report.get("mean_family_size", 0.0)),
		"expected_family_size": float(family_size_report.get("expected_family_size", 0.0)),
		"multi_family_residents": int(family_size_report.get("multi_family_residents", 0)),
		"multi_household_violations": int(household_size_report.get("multi_household_violations", 0)),
		"pyramid": pyramid_series,
		"household_size": household_size_report,
		"family_size": family_size_report,
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

## Builds Actual vs. Expected Physical Household Size distribution (1, 2, 3, 4, 5, 6+ occupants)
static func _build_household_size_distribution(demographics: Dictionary, total_pop: int) -> Dictionary:
	var hh_size_rows: Array = DB_MANAGER.query_rows("""
		SELECT household_id, COUNT(*) AS sz
		FROM residents
		WHERE dod IS NULL AND household_id IS NOT NULL
		GROUP BY household_id;
	""")

	# Verify 1:1 resident-to-household invariant (every living resident appears in at most 1 household)
	var dup_rows: Array = DB_MANAGER.query_rows("""
		SELECT COUNT(*) AS cnt FROM (
			SELECT resident_id FROM residents WHERE dod IS NULL GROUP BY resident_id HAVING COUNT(DISTINCT household_id) > 1
		);
	""")
	var multi_hh_violations: int = int(dup_rows[0]["cnt"]) if not dup_rows.is_empty() else 0

	var bucket_labels: Array[String] = ["1", "2", "3", "4", "5", "6+"]
	var act_counts: PackedInt32Array = PackedInt32Array()
	act_counts.resize(6)
	var occupied_hh: int = maxi(1, hh_size_rows.size())
	var member_sum: int = 0

	for r in hh_size_rows:
		var sz: int = int(r["sz"])
		member_sum += sz
		var b_idx: int = clampi(sz - 1, 0, 5)
		act_counts[b_idx] += 1

	# Derive Expected Household Size distribution from demographics.household_typology_model + parity_distribution
	var typology_model: Dictionary = demographics.get("household_typology_model", {})
	var types_by_age: Array = typology_model.get("types_by_head_age", [])
	var pyramid: Array = demographics.get("population_pyramid", [])
	var parity_weights: Dictionary = demographics.get("fertility_and_family_model", {}).get("parity_distribution", {}).get("base_weights", {"1": 0.42, "2": 0.36, "3": 0.14, "4": 0.05})
	var parity_total: float = 0.0
	for k in parity_weights.keys():
		parity_total += float(parity_weights[k])
	parity_total = maxf(0.001, parity_total)
	var p1: float = float(parity_weights.get("1", 0.42)) / parity_total
	var p2: float = float(parity_weights.get("2", 0.36)) / parity_total
	var p3: float = float(parity_weights.get("3", 0.14)) / parity_total
	var p4plus: float = maxf(0.0, 1.0 - (p1 + p2 + p3))

	var exp_shares: PackedFloat64Array = PackedFloat64Array()
	exp_shares.resize(6)
	var total_adult_w: float = 0.0

	for band in pyramid:
		var min_a: int = int(band["min_age"])
		var max_a: int = int(band["max_age"])
		if max_a < 18:
			continue
		var mid_a: int = int((maxi(18, min_a) + max_a) / 2)
		var band_w: float = float(band["male_pct"]) + float(band["female_pct"])

		var matched_w: Dictionary = {}
		for row in types_by_age:
			if mid_a >= int(row["age_min"]) and mid_a <= int(row["age_max"]):
				matched_w = row.get("weights", {})
				break
		if matched_w.is_empty() and not types_by_age.is_empty():
			matched_w = types_by_age[-1].get("weights", {})

		var w_single: float = float(matched_w.get("SINGLE_PERSON", 0.0))
		var w_flat: float = float(matched_w.get("FLATSHARE_SHARED", 0.0))
		var w_couple_no: float = float(matched_w.get("COUPLE_WITHOUT_DEP", 0.0))
		var w_couple_dep: float = float(matched_w.get("COUPLE_WITH_DEP", 0.0))
		var w_lone: float = float(matched_w.get("LONE_PARENT", 0.0))

		exp_shares[0] += band_w * w_single
		exp_shares[1] += band_w * (w_couple_no + (w_flat * 0.34) + (w_lone * p1))
		exp_shares[2] += band_w * ((w_flat * 0.33) + (w_couple_dep * p1) + (w_lone * p2))
		exp_shares[3] += band_w * ((w_flat * 0.33) + (w_couple_dep * p2) + (w_lone * p3))
		exp_shares[4] += band_w * ((w_couple_dep * p3) + (w_lone * p4plus))
		exp_shares[5] += band_w * (w_couple_dep * p4plus)
		total_adult_w += band_w

	var norm_denom: float = maxf(0.001, total_adult_w)
	var exp_curve: Array[float] = []
	var act_curve: Array[float] = []
	var exp_mean_calc: float = 0.0
	for i in range(6):
		var ep: float = (exp_shares[i] / norm_denom) * 100.0
		var ap: float = (float(act_counts[i]) / float(occupied_hh)) * 100.0
		exp_curve.append(snappedf(ep, 0.1))
		act_curve.append(snappedf(ap, 0.1))
		exp_mean_calc += (ep / 100.0) * float(i + 1 if i < 5 else 6)

	var act_mean: float = float(member_sum) / float(occupied_hh)
	var exp_target_mean: float = float(demographics.get("household_occupancy_mean", exp_mean_calc))
	var delta_pct: float = snappedf(((act_mean - exp_target_mean) / maxf(0.01, exp_target_mean)) * 100.0, 0.1)

	return {
		"expected_curve": exp_curve,
		"actual_curve": act_curve,
		"x_labels": bucket_labels,
		"actual_mean": snappedf(act_mean, 0.02),
		"expected_mean": snappedf(exp_target_mean, 0.02),
		"occupied_households": hh_size_rows.size(),
		"multi_household_violations": multi_hh_violations,
		"delta_pct": delta_pct,
		"badge_text": "Exp:%.2f | Act:%.2f (%+.1f%%) | 1-HH Check:%s" % [
			exp_target_mean, act_mean, delta_pct, "OK" if multi_hh_violations == 0 else "ERR(%d)" % multi_hh_violations
		]
	}

## Reconstructs Nuclear Family Units ({parents} + {all linked children}) from directional kinship edges
## Note: Adults who are both children in their parents' family and parents/spouses in their own family appear in 2 family units.
static func _build_family_size_distribution(demographics: Dictionary, total_pop: int) -> Dictionary:
	var rel_rows: Array = DB_MANAGER.query_rows("""
		SELECT sr.from_resident_id AS from_id, sr.to_resident_id AS to_id, l.code AS rel_code
		FROM social_relationships sr
		JOIN system_labels l ON sr.relationship_type_id = l.label_id
		JOIN residents r1 ON sr.from_resident_id = r1.resident_id
		JOIN residents r2 ON sr.to_resident_id = r2.resident_id
		WHERE sr.valid_to IS NULL
		  AND r1.dod IS NULL
		  AND r2.dod IS NULL
		  AND l.code IN ('HUSBAND', 'WIFE', 'PARTNER', 'FATHER', 'MOTHER');
	""")

	var spouse_of: Dictionary = {} # resident_id -> partner_id
	var children_by_parent: Dictionary = {} # parent_id -> Dictionary{ child_id: true }

	for r in rel_rows:
		var a: int = int(r["from_id"])
		var b: int = int(r["to_id"])
		var code: String = str(r["rel_code"])
		if code in ["HUSBAND", "WIFE", "PARTNER"]:
			if not spouse_of.has(a):
				spouse_of[a] = b
			if not spouse_of.has(b):
				spouse_of[b] = a
		elif code in ["FATHER", "MOTHER"]:
			if not children_by_parent.has(a):
				children_by_parent[a] = {}
			children_by_parent[a][b] = true

	# Build canonical family units keyed by parental core ("C:min_p:max_p" or "L:parent_id")
	var family_units: Dictionary = {} # core_key -> Dictionary{ member_id: true }
	var processed_spouses: Dictionary = {}

	for p_id in spouse_of.keys():
		var a: int = int(p_id)
		var b: int = int(spouse_of[a])
		var lo: int = mini(a, b)
		var hi: int = maxi(a, b)
		var core_key: String = "C:%d:%d" % [lo, hi]
		if processed_spouses.has(core_key):
			continue
		processed_spouses[core_key] = true

		var members: Dictionary = {lo: true, hi: true}
		if children_by_parent.has(lo):
			for cid in children_by_parent[lo].keys():
				members[int(cid)] = true
		if children_by_parent.has(hi):
			for cid in children_by_parent[hi].keys():
				members[int(cid)] = true
		family_units[core_key] = members

	for p_id in children_by_parent.keys():
		var p: int = int(p_id)
		if spouse_of.has(p):
			continue
		var lone_key: String = "L:%d" % p
		var members: Dictionary = {p: true}
		for cid in children_by_parent[p].keys():
			members[int(cid)] = true
		family_units[lone_key] = members

	# Count family memberships per resident (adults with parents AND own family appear in 2 family units)
	var memberships_per_resident: Dictionary = {}
	var bucket_labels: Array[String] = ["2", "3", "4", "5", "6", "7+"]
	var act_counts: PackedInt32Array = PackedInt32Array()
	act_counts.resize(6)
	var total_family_members: int = 0

	for core_key in family_units.keys():
		var members: Dictionary = family_units[core_key]
		var sz: int = members.size()
		if sz < 2:
			continue
		total_family_members += sz
		var b_idx: int = clampi(sz - 2, 0, 5)
		act_counts[b_idx] += 1
		for m_id in members.keys():
			memberships_per_resident[m_id] = int(memberships_per_resident.get(m_id, 0)) + 1

	var multi_family_residents: int = 0
	for m_id in memberships_per_resident.keys():
		if int(memberships_per_resident[m_id]) >= 2:
			multi_family_residents += 1

	# Derive Expected Nuclear Family Unit Size curve from parity_distribution + couple/lone-parent ratios
	var parity_weights: Dictionary = demographics.get("fertility_and_family_model", {}).get("parity_distribution", {}).get("base_weights", {"1": 0.42, "2": 0.36, "3": 0.14, "4": 0.05})
	var parity_total: float = 0.0
	for k in parity_weights.keys():
		parity_total += float(parity_weights[k])
	parity_total = maxf(0.001, parity_total)
	var p1: float = float(parity_weights.get("1", 0.42)) / parity_total
	var p2: float = float(parity_weights.get("2", 0.36)) / parity_total
	var p3: float = float(parity_weights.get("3", 0.14)) / parity_total
	var p4plus: float = maxf(0.0, 1.0 - (p1 + p2 + p3))

	# Share of family units that are childless couples (~0.32), couples with children (~0.58), and lone parents (~0.10)
	var f_couple_no: float = 0.32
	var f_couple_dep: float = 0.58
	var f_lone: float = 0.10
	var exp_shares: Array[float] = [
		(f_couple_no + (f_lone * p1)) * 100.0,            # size 2
		((f_couple_dep * p1) + (f_lone * p2)) * 100.0,    # size 3
		((f_couple_dep * p2) + (f_lone * p3)) * 100.0,    # size 4
		((f_couple_dep * p3) + (f_lone * p4plus)) * 100.0,# size 5
		(f_couple_dep * p4plus * 0.72) * 100.0,           # size 6
		(f_couple_dep * p4plus * 0.28) * 100.0            # size 7+
	]

	var total_units: int = maxi(1, family_units.size())
	var act_curve: Array[float] = []
	var exp_curve: Array[float] = []
	var exp_mean: float = 0.0
	for i in range(6):
		var ep: float = exp_shares[i]
		var ap: float = (float(act_counts[i]) / float(total_units)) * 100.0
		exp_curve.append(snappedf(ep, 0.1))
		act_curve.append(snappedf(ap, 0.1))
		exp_mean += (ep / 100.0) * float(i + 2)

	var act_mean: float = float(total_family_members) / float(total_units) if not family_units.is_empty() else 0.0
	var delta_pct: float = snappedf(((act_mean - exp_mean) / maxf(0.01, exp_mean)) * 100.0, 0.1)
	var multi_fam_pct: float = (float(multi_family_residents) / float(maxi(1, total_pop))) * 100.0

	return {
		"expected_curve": exp_curve,
		"actual_curve": act_curve,
		"x_labels": bucket_labels,
		"total_family_units": family_units.size(),
		"actual_mean": snappedf(act_mean, 0.02),
		"expected_mean": snappedf(exp_mean, 0.02),
		"multi_family_residents": multi_family_residents,
		"multi_family_pct": snappedf(multi_fam_pct, 0.1),
		"delta_pct": delta_pct,
		"badge_text": "Exp:%.2f | Act:%.2f (%+.1f%%) | 2-Gen Overlap:%d (%.1f%%)" % [
			exp_mean, act_mean, delta_pct, multi_family_residents, multi_fam_pct
		]
	}

## Builds 2-curve distributions (Expected vs Actual) AND Age x Sex breakdowns for every psychological continuous axis
static func _build_continuous_traits_comparison(ocean_rules: Dictionary, sim_day: int, total_pop: int) -> Array[Dictionary]:
	var base_cfg: Dictionary = ocean_rules.get("baseline_distribution", {})
	var base_mean: float = float(base_cfg.get("mean", 0.50))
	var base_sd: float = float(base_cfg.get("std_dev", 0.16))
	var cog: Dictionary = ocean_rules.get("cognitive_model", {})
	var iq_mean: float = float(cog.get("iq_reference_mean", 100.0))
	var ag_cfg: Dictionary = cog.get("mental_agility", {})
	var ag_base_mean: float = float(ag_cfg.get("baseline_mean", 0.50))
	var ag_base_sd: float = float(ag_cfg.get("baseline_std_dev", 0.17))
	var ag_skew_exp: float = float(ag_cfg.get("right_skew_exponent", 1.15))
	var dark: Dictionary = ocean_rules.get("dark_and_empathy_axes", {})
	var d_min: float = float(dark.get("min_bound", 0.02))
	var d_max: float = float(dark.get("max_bound", 0.98))

	# Single pass over living residents to compute exact 20-bin histograms and Age x Sex means
	var res_rows: Array = DB_MANAGER.query_rows("""
		SELECT
			CAST((%d - r.dob) / 365.25 AS INTEGER) AS age_years,
			l.code AS gender_code,
			r.openness, r.conscientiousness, r.extraversion, r.agreeableness, r.neuroticism,
			r.iq_score, r.mental_agility, r.machiavellianism, r.empathy_affective, r.power_entitlement
		FROM residents r
		JOIN system_labels l ON r.gender_id = l.label_id
		WHERE r.dod IS NULL;
	""" % sim_day)

	var n_pop: int = maxi(1, res_rows.size())

	# Compute demographic-adjusted expected Mental Agility across the city's actual age profile
	var age_curve: Dictionary = ag_cfg.get("age_curve", {})
	var peak_age: float = float(age_curve.get("peak_age", 25.0))
	var child_floor: float = float(age_curve.get("childhood_floor_multiplier", 0.62))
	var elder_floor: float = float(age_curve.get("elder_floor_multiplier", 0.55))
	var post_decay: float = float(age_curve.get("annual_decay_post_peak", 0.0045))
	var age_mults: PackedFloat32Array = PackedFloat32Array()
	age_mults.resize(res_rows.size())
	var ag_exp_sum: float = 0.0
	for r_i in range(res_rows.size()):
		var ay: float = float(res_rows[r_i]["age_years"])
		var mult: float = 1.0
		if ay < peak_age:
			mult = lerpf(child_floor, 1.0, clampf(ay / maxf(1.0, peak_age), 0.0, 1.0))
		else:
			mult = maxf(elder_floor, 1.0 - ((ay - peak_age) * post_decay))
		age_mults[r_i] = mult
		ag_exp_sum += pow(clampf(ag_base_mean * mult, 0.02, 0.98), ag_skew_exp)
	var ag_demo_exp_mean: float = (ag_exp_sum / float(n_pop)) if not res_rows.is_empty() else ag_base_mean

	var specs: Array[Dictionary] = [
		{"key": "openness", "label": "Openness (O)", "exp": base_mean, "sd": base_sd, "min_v": 0.0, "max_v": 1.0, "model": "GAUSSIAN"},
		{"key": "conscientiousness", "label": "Conscientiousness (C)", "exp": base_mean, "sd": base_sd, "min_v": 0.0, "max_v": 1.0, "model": "GAUSSIAN"},
		{"key": "extraversion", "label": "Extraversion (E)", "exp": base_mean, "sd": base_sd, "min_v": 0.0, "max_v": 1.0, "model": "GAUSSIAN"},
		{"key": "agreeableness", "label": "Agreeableness (A)", "exp": base_mean, "sd": base_sd, "min_v": 0.0, "max_v": 1.0, "model": "GAUSSIAN"},
		{"key": "neuroticism", "label": "Neuroticism (N)", "exp": base_mean, "sd": base_sd, "min_v": 0.0, "max_v": 1.0, "model": "GAUSSIAN"},
		{"key": "iq_score", "label": "IQ Score (3-Component GMM)", "exp": iq_mean, "sd": 15.0, "min_v": 40.0, "max_v": 165.0, "model": "IQ_GMM"},
		{"key": "mental_agility", "label": "Mental Agility (Age-Adjusted)", "exp": ag_demo_exp_mean, "sd": ag_base_sd, "min_v": 0.0, "max_v": 1.0, "model": "MENTAL_AGILITY"},
		{"key": "machiavellianism", "label": "Machiavellianism", "exp": float(dark.get("machiavellianism", {}).get("mean", 0.36)), "sd": float(dark.get("machiavellianism", {}).get("std_dev", 0.16)) * 1.12, "min_v": 0.0, "max_v": 1.0, "model": "SMOOTH_BOUNDED"},
		{"key": "empathy_affective", "label": "Affective Empathy", "exp": float(dark.get("empathy_affective", {}).get("mean", 0.54)), "sd": float(dark.get("empathy_affective", {}).get("std_dev", 0.16)) * 1.12, "min_v": 0.0, "max_v": 1.0, "model": "SMOOTH_BOUNDED"},
		{"key": "power_entitlement", "label": "Power Entitlement", "exp": float(dark.get("power_entitlement", {}).get("mean", 0.38)), "sd": float(dark.get("power_entitlement", {}).get("std_dev", 0.17)) * 1.12, "min_v": 0.0, "max_v": 1.0, "model": "SMOOTH_BOUNDED"}
	]

	var out: Array[Dictionary] = []

	for item in specs:
		var col_key: String = str(item["key"])
		var min_v: float = float(item["min_v"])
		var max_v: float = float(item["max_v"])
		var span: float = maxf(0.001, max_v - min_v)
		var exp_v: float = float(item["exp"])
		var sd_v: float = float(item["sd"])
		var dist_model: String = str(item.get("model", "GAUSSIAN"))
		var is_iq: bool = (dist_model == "IQ_GMM")

		var bin_counts: PackedInt32Array = PackedInt32Array()
		bin_counts.resize(CURVE_BINS)
		var sum_val: float = 0.0
		var obs_min: float = max_v
		var obs_max: float = min_v

		var cohort_male_sum: PackedFloat64Array = PackedFloat64Array()
		var cohort_male_cnt: PackedInt32Array = PackedInt32Array()
		var cohort_female_sum: PackedFloat64Array = PackedFloat64Array()
		var cohort_female_cnt: PackedInt32Array = PackedInt32Array()
		cohort_male_sum.resize(AGE_COHORTS.size())
		cohort_male_cnt.resize(AGE_COHORTS.size())
		cohort_female_sum.resize(AGE_COHORTS.size())
		cohort_female_cnt.resize(AGE_COHORTS.size())

		for r in res_rows:
			var val: float = float(r[col_key])
			sum_val += val
			obs_min = minf(obs_min, val)
			obs_max = maxf(obs_max, val)

			var norm_pos: float = clampf((val - min_v) / span, 0.0, 0.9999)
			var b_idx: int = int(floor(norm_pos * float(CURVE_BINS)))
			bin_counts[b_idx] += 1

			var age_y: int = int(r["age_years"])
			var is_m: bool = str(r["gender_code"]).to_upper() in ["M", "MALE"]
			for c_idx in range(AGE_COHORTS.size()):
				var c_def: Dictionary = AGE_COHORTS[c_idx]
				if age_y >= int(c_def["min_age"]) and age_y <= int(c_def["max_age"]):
					if is_m:
						cohort_male_sum[c_idx] += val
						cohort_male_cnt[c_idx] += 1
					else:
						cohort_female_sum[c_idx] += val
						cohort_female_cnt[c_idx] += 1
					break

		var act_mean: float = sum_val / float(n_pop)

		# Expected theoretical PDF across the 20 bins
		var exp_raw: PackedFloat32Array = PackedFloat32Array()
		exp_raw.resize(CURVE_BINS)
		var exp_sum: float = 0.0

		if dist_model == "MENTAL_AGILITY" and not age_mults.is_empty():
			# Convolve N(ag_base_mean * age_mult, ag_base_sd * age_mult) ^ ag_skew_exp over city age profile
			var stride: int = maxi(1, int(age_mults.size() / 250))
			var sample_idx: int = 0
			while sample_idx < age_mults.size():
				var m: float = age_mults[sample_idx]
				var mu_m: float = ag_base_mean * m
				var sd_m: float = maxf(0.04, ag_base_sd * m)
				for b in range(CURVE_BINS):
					var mid_y: float = clampf((float(b) + 0.5) / float(CURVE_BINS), 0.005, 0.995)
					var pre_skew_x: float = pow(mid_y, 1.0 / maxf(0.1, ag_skew_exp))
					var jacobian: float = pow(mid_y, (1.0 / maxf(0.1, ag_skew_exp)) - 1.0)
					var pdf_y: float = _gaussian_pdf(pre_skew_x, mu_m, sd_m) * jacobian
					exp_raw[b] += pdf_y
					exp_sum += pdf_y
				sample_idx += stride
		elif dist_model == "SMOOTH_BOUNDED":
			# Integrate smoothed-bound PDF over fine raw grid so lower/upper knees match CitizenPersonalityHydrator
			var fine_steps: int = 200
			for s_i in range(fine_steps):
				var raw_x: float = -0.35 + ((float(s_i) + 0.5) / float(fine_steps)) * 1.70
				var p_raw: float = _gaussian_pdf(raw_x, exp_v, sd_v)
				var mapped_y: float = _eval_smooth_bound(raw_x, d_min, d_max, 0.10)
				var b_idx: int = int(floor(clampf(mapped_y, 0.0, 0.9999) * float(CURVE_BINS)))
				exp_raw[b_idx] += p_raw
				exp_sum += p_raw
		else:
			for b in range(CURVE_BINS):
				var mid_x: float = min_v + ((float(b) + 0.5) / float(CURVE_BINS)) * span
				var pdf: float = 0.0
				if is_iq:
					pdf = (
						0.975 * _gaussian_pdf(mid_x, exp_v, 15.0) +
						0.0175 * _gaussian_pdf(mid_x, 55.0, 12.0) +
						0.0075 * _gaussian_pdf(mid_x, 115.0, 22.0)
					)
				else:
					pdf = _gaussian_pdf(mid_x, exp_v, sd_v)
				exp_raw[b] = pdf
				exp_sum += pdf

		var expected_curve: Array[float] = []
		var actual_curve: Array[float] = []
		for b in range(CURVE_BINS):
			var exp_pct_bin: float = (exp_raw[b] / maxf(0.00001, exp_sum)) * 100.0
			var act_pct_bin: float = (float(bin_counts[b]) / float(n_pop)) * 100.0
			expected_curve.append(snappedf(exp_pct_bin, 0.05))
			actual_curve.append(snappedf(act_pct_bin, 0.05))

		var age_sex_rows: Array[Dictionary] = []
		for c_idx in range(AGE_COHORTS.size()):
			var c_def: Dictionary = AGE_COHORTS[c_idx]
			var m_avg: float = float(cohort_male_sum[c_idx] / float(maxi(1, cohort_male_cnt[c_idx]))) if cohort_male_cnt[c_idx] > 0 else 0.0
			var f_avg: float = float(cohort_female_sum[c_idx] / float(maxi(1, cohort_female_cnt[c_idx]))) if cohort_female_cnt[c_idx] > 0 else 0.0
			age_sex_rows.append({
				"label": str(c_def["label"]),
				"male_val": snappedf(m_avg, 0.01 if is_iq else 0.001),
				"female_val": snappedf(f_avg, 0.01 if is_iq else 0.001),
				"male_display": "%.1f" % m_avg if is_iq else "%.3f" % m_avg,
				"female_display": "%.1f" % f_avg if is_iq else "%.3f" % f_avg
			})

		out.append({
			"key": col_key,
			"label": str(item["label"]),
			"expected_mean_display": "%.1f" % exp_v if is_iq else "%.3f" % exp_v,
			"actual_mean_display": "%.1f" % act_mean if is_iq else "%.3f" % act_mean,
			"range_display": "[%.1f..%.1f]" % [obs_min, obs_max] if is_iq else "[%.2f..%.2f]" % [obs_min, obs_max],
			"expected_mean_norm": clampf((exp_v - min_v) / span, 0.0, 1.0),
			"actual_mean_norm": clampf((act_mean - min_v) / span, 0.0, 1.0),
			"x_min_label": "%.0f" % min_v if is_iq else "0.00",
			"x_max_label": "%.0f" % max_v if is_iq else "1.00",
			"y_max_scale": max_v,
			"delta_pct": snappedf(((act_mean - exp_v) / maxf(0.001, exp_v)) * 100.0, 0.1),
			"expected_curve": expected_curve,
			"actual_curve": actual_curve,
			"age_sex_breakdown": age_sex_rows
		})

	return out

## Builds 2-curve propensity distributions (with upper-tail cutoff) AND Age x Sex prevalence breakdowns for behavioral/clinical tags
static func _build_behavioral_tags_comparison(ocean_rules: Dictionary, sim_day: int, total_pop: int) -> Array[Dictionary]:
	# Base cohort denominators by age x sex
	var denom_rows: Array = DB_MANAGER.query_rows("""
		SELECT
			CAST((%d - r.dob) / 365.25 AS INTEGER) AS age_years,
			l.code AS gender_code,
			COUNT(*) AS cnt
		FROM residents r
		JOIN system_labels l ON r.gender_id = l.label_id
		WHERE r.dod IS NULL
		GROUP BY age_years, l.code;
	""" % sim_day)

	var cohort_m_denom: PackedInt32Array = PackedInt32Array()
	var cohort_f_denom: PackedInt32Array = PackedInt32Array()
	cohort_m_denom.resize(AGE_COHORTS.size())
	cohort_f_denom.resize(AGE_COHORTS.size())
	for dr in denom_rows:
		var a: int = int(dr["age_years"])
		var cnt: int = int(dr["cnt"])
		var is_m: bool = str(dr["gender_code"]).to_upper() in ["M", "MALE"]
		for c_idx in range(AGE_COHORTS.size()):
			if a >= int(AGE_COHORTS[c_idx]["min_age"]) and a <= int(AGE_COHORTS[c_idx]["max_age"]):
				if is_m:
					cohort_m_denom[c_idx] += cnt
				else:
					cohort_f_denom[c_idx] += cnt
				break

	# Active tag rows joined with resident age & sex
	var tag_detail_rows: Array = DB_MANAGER.query_rows("""
		SELECT
			l.code AS tag_code,
			t.severity AS severity,
			CAST((%d - r.dob) / 365.25 AS INTEGER) AS age_years,
			lg.code AS gender_code
		FROM resident_behavioral_tags t
		JOIN system_labels l ON t.tag_label_id = l.label_id
		JOIN residents r ON t.resident_id = r.resident_id
		JOIN system_labels lg ON r.gender_id = lg.label_id
		WHERE t.valid_to IS NULL AND r.dod IS NULL;
	""" % sim_day)

	var tag_stats: Dictionary = {}
	for tr in tag_detail_rows:
		var code: String = str(tr["tag_code"])
		if not tag_stats.has(code):
			var m_c: PackedInt32Array = PackedInt32Array()
			var f_c: PackedInt32Array = PackedInt32Array()
			m_c.resize(AGE_COHORTS.size())
			f_c.resize(AGE_COHORTS.size())
			tag_stats[code] = {
				"count": 0,
				"sev_sum": 0.0,
				"severities": [],
				"m_counts": m_c,
				"f_counts": f_c
			}
		var entry: Dictionary = tag_stats[code]
		entry["count"] = int(entry["count"]) + 1
		var sev: float = float(tr["severity"])
		entry["sev_sum"] = float(entry["sev_sum"]) + sev
		entry["severities"].append(sev)

		var a: int = int(tr["age_years"])
		var is_m: bool = str(tr["gender_code"]).to_upper() in ["M", "MALE"]
		for c_idx in range(AGE_COHORTS.size()):
			if a >= int(AGE_COHORTS[c_idx]["min_age"]) and a <= int(AGE_COHORTS[c_idx]["max_age"]):
				if is_m:
					entry["m_counts"][c_idx] += 1
				else:
					entry["f_counts"][c_idx] += 1
				break

	var preset_mode: String = str(ocean_rules.get("active_population_mode", "REALISTIC"))
	var prev_mult: float = float(ocean_rules.get("population_presets", {}).get(preset_mode, {}).get("profile_prevalence_multiplier", 1.0))
	var profiles: Dictionary = ocean_rules.get("neurodivergence_and_clinical_profiles", {})

	var out: Array[Dictionary] = []
	for tag_code in profiles.keys():
		var code_str: String = str(tag_code)
		var p_def: Dictionary = profiles[code_str]
		var min_a: int = int(p_def.get("min_age", 0))
		var max_a: int = int(p_def.get("max_age", 99))
		var elig_rows: Array = DB_MANAGER.query_rows("""
			SELECT COUNT(*) AS cnt FROM residents
			WHERE dod IS NULL
			  AND CAST((%d - dob) / 365.25 AS INTEGER) BETWEEN %d AND %d;
		""" % [sim_day, min_a, max_a])
		var elig_pop: int = maxi(1, int(elig_rows[0]["cnt"]) if not elig_rows.is_empty() else total_pop)

		var exp_prev: float = clampf(float(p_def.get("base_prevalence", 0.0)) * prev_mult, 0.0005, 0.95)
		var exp_pct: float = exp_prev * 100.0
		var info: Dictionary = tag_stats.get(code_str, {})
		var act_cnt: int = int(info.get("count", 0))
		var act_prev: float = clampf(float(act_cnt) / float(elig_pop), 0.0, 0.95)
		var act_pct: float = act_prev * 100.0
		var avg_sev: float = float(info.get("sev_sum", 0.0)) / float(maxi(1, act_cnt)) if act_cnt > 0 else 0.0

		# Normalized latent propensity curve N(0.50, 0.16) with uniform right-tail cutoff tau
		var cutoff_norm: float = _inverse_normal_upper_tail(exp_prev, 0.50, 0.16)
		var shift_mu: float = 0.50 + ((act_prev - exp_prev) * 0.85)
		var exp_raw: PackedFloat32Array = PackedFloat32Array()
		var act_raw: PackedFloat32Array = PackedFloat32Array()
		exp_raw.resize(CURVE_BINS)
		act_raw.resize(CURVE_BINS)
		var exp_sum: float = 0.0
		var act_sum: float = 0.0
		for b in range(CURVE_BINS):
			var mid_x: float = (float(b) + 0.5) / float(CURVE_BINS)
			var ep: float = _gaussian_pdf(mid_x, 0.50, 0.16)
			var ap: float = _gaussian_pdf(mid_x, clampf(shift_mu, 0.15, 0.85), 0.16)
			exp_raw[b] = ep
			act_raw[b] = ap
			exp_sum += ep
			act_sum += ap

		var expected_curve: Array[float] = []
		var actual_curve: Array[float] = []
		for b in range(CURVE_BINS):
			expected_curve.append(snappedf((exp_raw[b] / maxf(0.00001, exp_sum)) * 100.0, 0.05))
			actual_curve.append(snappedf((act_raw[b] / maxf(0.00001, act_sum)) * 100.0, 0.05))

		var m_counts: PackedInt32Array = info.get("m_counts", PackedInt32Array())
		var f_counts: PackedInt32Array = info.get("f_counts", PackedInt32Array())
		var age_sex_rows: Array[Dictionary] = []
		var max_cohort_pct: float = 1.0
		for c_idx in range(AGE_COHORTS.size()):
			var c_def: Dictionary = AGE_COHORTS[c_idx]
			var mc: int = m_counts[c_idx] if c_idx < m_counts.size() else 0
			var fc: int = f_counts[c_idx] if c_idx < f_counts.size() else 0
			var m_pct: float = (float(mc) / float(maxi(1, cohort_m_denom[c_idx]))) * 100.0 if cohort_m_denom[c_idx] > 0 else 0.0
			var f_pct: float = (float(fc) / float(maxi(1, cohort_f_denom[c_idx]))) * 100.0 if cohort_f_denom[c_idx] > 0 else 0.0
			max_cohort_pct = maxf(max_cohort_pct, maxf(m_pct, f_pct))
			age_sex_rows.append({
				"label": str(c_def["label"]),
				"male_val": snappedf(m_pct, 0.02),
				"female_val": snappedf(f_pct, 0.02),
				"male_display": "%.1f%%" % m_pct,
				"female_display": "%.1f%%" % f_pct
			})

		out.append({
			"key": code_str,
			"label": "%s (n=%d, age %d-%d)" % [code_str, act_cnt, min_a, max_a],
			"expected_pct": snappedf(exp_pct, 0.02),
			"actual_pct": snappedf(act_pct, 0.02),
			"avg_severity": snappedf(avg_sev, 0.02),
			"delta_pct": snappedf(act_pct - exp_pct, 0.02),
			"cutoff_norm": cutoff_norm,
			"x_min_label": "0.00",
			"x_max_label": "1.00",
			"y_max_scale": ceilf(max_cohort_pct * 1.15),
			"expected_curve": expected_curve,
			"actual_curve": actual_curve,
			"age_sex_breakdown": age_sex_rows
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

static func _eval_smooth_bound(val: float, min_b: float, max_b: float, margin: float = 0.10) -> float:
	var low_knee: float = min_b + margin
	var high_knee: float = max_b - margin
	if val < low_knee:
		var excess_low: float = (low_knee - val) / maxf(0.001, margin)
		return min_b + (margin * exp(-excess_low))
	if val > high_knee:
		var excess_high: float = (val - high_knee) / maxf(0.001, margin)
		return max_b - (margin * exp(-excess_high))
	return val

static func _gaussian_pdf(x: float, mean: float, sd: float) -> float:
	var s: float = maxf(0.0001, sd)
	var z: float = (x - mean) / s
	return exp(-0.5 * z * z) / (s * 2.50662827)

## Approximates upper-tail cutoff tau in [0.05..0.98] where P(X >= tau) = tail_prob for N(mean, sd)
static func _inverse_normal_upper_tail(tail_prob: float, mean: float, sd: float) -> float:
	var p: float = clampf(tail_prob, 0.0005, 0.9995)
	var q: float = 1.0 - p
	# Rational approximation (Abramowitz & Stegun) for standard normal quantile z
	var t: float = sqrt(-2.0 * log(minf(q, 1.0 - q)))
	var z: float = t - ((2.515517 + 0.802853 * t + 0.010328 * t * t) / (1.0 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t))
	if q < 0.5:
		z = -z
	return clampf(mean + (z * sd), 0.05, 0.98)