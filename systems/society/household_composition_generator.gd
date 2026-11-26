# res://systems/society/household_composition_generator.gd
class_name HouseholdCompositionGenerator
extends RefCounted

## Extracts and validates the config-driven education tier_ranks map from demographics_cfg
static func get_education_rank_map(demographics: Dictionary) -> Dictionary:
	assert(demographics.has("education_attainment_model"), "FATAL: demographics missing 'education_attainment_model'!")
	var edu_model: Dictionary = demographics["education_attainment_model"]
	assert(edu_model.has("tier_ranks") and edu_model["tier_ranks"] is Dictionary, "FATAL: education_attainment_model missing 'tier_ranks' dictionary!")
	return edu_model["tier_ranks"]

## Creates a dynamic residual cohort tracker from demographics["population_pyramid"]
static func create_cohort_tracker(demographics: Dictionary) -> Dictionary:
	assert(demographics.has("population_pyramid") and demographics["population_pyramid"] is Array,
		"FATAL: demographics missing 'population_pyramid' array!")
	var pyramid: Array = demographics["population_pyramid"]
	var brackets: Array[Dictionary] = []
	var total_pct: float = 0.0

	for row in pyramid:
		var m_pct: float = float(row["male_pct"])
		var f_pct: float = float(row["female_pct"])
		total_pct += m_pct + f_pct
		brackets.append({
			"min_age": int(row["min_age"]),
			"max_age": int(row["max_age"]),
			"male_pct": m_pct,
			"female_pct": f_pct,
			"male_count": 0,
			"female_count": 0
		})

	var norm_denom: float = maxf(0.001, total_pct)
	for b in brackets:
		b["target_share"] = (float(b["male_pct"]) + float(b["female_pct"])) / norm_denom
		b["male_target_share"] = float(b["male_pct"]) / norm_denom
		b["female_target_share"] = float(b["female_pct"]) / norm_denom

	return {
		"brackets": brackets,
		"total_generated": 0
	}

## Resolves an ethno-religiously matched first name from lexicon pools with deterministic fallback
static func pick_first_name(
	lexicon: Dictionary,
	is_male: bool,
	surnames_pool: String,
	religion: String,
	rng: RandomNumberGenerator
) -> String:
	var gender_prefix: String = "first_names_male" if is_male else "first_names_female"
	var ethnic_suffix: String = ""
	if surnames_pool.begins_with("surnames_"):
		ethnic_suffix = "_" + surnames_pool.trim_prefix("surnames_")

	var rel_suffix: String = ""
	if not religion.is_empty():
		rel_suffix = "_" + religion.to_lower()

	# 1. Exact ethno-religious pool (e.g., first_names_male_south_asian_sikh)
	if not ethnic_suffix.is_empty() and not rel_suffix.is_empty():
		var full_key: String = gender_prefix + ethnic_suffix + rel_suffix
		if lexicon.has(full_key) and lexicon[full_key] is Array and not lexicon[full_key].is_empty():
			var pool: Array = lexicon[full_key]
			return str(pool[rng.randi() % pool.size()]).strip_edges().replace("'", "''")

	# 2. Ethnic pool (e.g., first_names_male_irish)
	if not ethnic_suffix.is_empty():
		var eth_key: String = gender_prefix + ethnic_suffix
		if lexicon.has(eth_key) and lexicon[eth_key] is Array and not lexicon[eth_key].is_empty():
			var pool: Array = lexicon[eth_key]
			return str(pool[rng.randi() % pool.size()]).strip_edges().replace("'", "''")

	# 3. Base regional pool (first_names_male / first_names_female)
	assert(lexicon.has(gender_prefix) and lexicon[gender_prefix] is Array and not lexicon[gender_prefix].is_empty(),
		"FATAL: Lexicon missing required base name pool '%s'!" % gender_prefix)
	var base_pool: Array = lexicon[gender_prefix]
	return str(base_pool[rng.randi() % base_pool.size()]).strip_edges().replace("'", "''")

## Generates a household's member composition array with dynamic residual cohort balancing
static func generate_household_composition(
	demographics: Dictionary,
	rng: RandomNumberGenerator,
	cohort_tracker: Dictionary = {}
) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var legal_cfg: Dictionary = demographics["legal_and_pension_thresholds"]
	var min_head_age: int = int(legal_cfg["majority_head_of_household_age"])

	var head_sample: Dictionary = _sample_from_population_pyramid(demographics, rng, min_head_age, cohort_tracker)
	var head_age: int = int(head_sample["age"])
	var head_is_male: bool = bool(head_sample["is_male"])

	var typology_model: Dictionary = demographics["household_typology_model"]
	var archetype_str: String = _sample_typology(typology_model, head_age, rng, cohort_tracker)

	var is_married: bool = false
	if archetype_str in ["COUPLE_WITHOUT_DEP", "COUPLE_WITH_DEP"]:
		is_married = true
	else:
		is_married = _sample_marital_status(typology_model, head_age, rng) == "MARRIED"

	members.append({
		"role_in_home": "HEAD",
		"age": head_age,
		"is_male": head_is_male,
		"is_head": true,
		"is_married": is_married
	})

	match archetype_str:
		"SINGLE_PERSON":
			_record_generated_members(cohort_tracker, members)
			return members

		"FLATSHARE_SHARED":
			var shared_rules: Dictionary = typology_model["shared_household_rules"]
			var min_peers: int = int(shared_rules["min_peers"])
			var max_peers: int = int(shared_rules["max_peers"])
			var max_diff: int = int(shared_rules["max_age_difference"])
			var peer_count: int = rng.randi_range(min_peers, max_peers)

			for _i in range(peer_count):
				var p_age: int = _pick_balanced_age_in_range(
					maxi(min_head_age, head_age - max_diff),
					mini(92, head_age + max_diff),
					rng,
					cohort_tracker
				)
				var p_male: bool = _pick_balanced_sex_for_age(p_age, 0.5, rng, cohort_tracker)
				members.append({
					"role_in_home": "PEER",
					"age": p_age,
					"is_male": p_male,
					"is_head": false,
					"is_married": false
				})

		"COUPLE_WITHOUT_DEP":
			var sp_age: int = _calculate_spouse_age(typology_model, head_age, head_is_male, rng)
			members.append({
				"role_in_home": "SPOUSE",
				"age": sp_age,
				"is_male": not head_is_male,
				"is_head": false,
				"is_married": true
			})

		"COUPLE_WITH_DEP":
			var sp_age: int = _calculate_spouse_age(typology_model, head_age, head_is_male, rng)
			var spouse_is_male: bool = not head_is_male
			members.append({
				"role_in_home": "SPOUSE",
				"age": sp_age,
				"is_male": spouse_is_male,
				"is_head": false,
				"is_married": true
			})

			var mother_age: int = head_age if not head_is_male else sp_age
			var children: Array[Dictionary] = _generate_children(demographics, mother_age, rng, cohort_tracker)
			members.append_array(children)

		"LONE_PARENT":
			var lone_parent_is_female: bool = rng.randf() < float(typology_model["lone_parent_gender_split"]["female_parent_prob"])
			members[0]["is_male"] = not lone_parent_is_female
			members[0]["is_married"] = false

			var p_mother_age: int = head_age if lone_parent_is_female else maxi(18, head_age - 2)
			var lone_children: Array[Dictionary] = _generate_children(demographics, p_mother_age, rng, cohort_tracker)
			members.append_array(lone_children)

	_record_generated_members(cohort_tracker, members)
	return members

## Computes the residual deficit multiplier (>1.0 if under-represented, <1.0 if over-represented) for an age
static func _get_age_deficit_multiplier(cohort_tracker: Dictionary, age: int) -> float:
	if cohort_tracker.is_empty():
		return 1.0
	var total_gen: int = int(cohort_tracker.get("total_generated", 0))
	if total_gen < 25:
		return 1.0

	var brackets: Array = cohort_tracker.get("brackets", [])
	for b in brackets:
		if age >= int(b["min_age"]) and age <= int(b["max_age"]):
			var target_share: float = float(b["target_share"])
			var expected: float = float(total_gen) * target_share
			var actual: float = float(int(b["male_count"]) + int(b["female_count"]))
			var ratio: float = (expected + 1.0) / (actual + 1.0)
			return clampf(pow(ratio, 1.35), 0.25, 4.0)
	return 1.0

## Computes the average deficit multiplier across a range of ages (e.g., school-age children 5..15)
static func _get_range_deficit_multiplier(cohort_tracker: Dictionary, age_min: int, age_max: int) -> float:
	if cohort_tracker.is_empty() or int(cohort_tracker.get("total_generated", 0)) < 25:
		return 1.0
	var brackets: Array = cohort_tracker.get("brackets", [])
	var expected_sum: float = 0.0
	var actual_sum: float = 0.0
	var total_gen: float = float(cohort_tracker["total_generated"])

	for b in brackets:
		var b_min: int = int(b["min_age"])
		var b_max: int = int(b["max_age"])
		var overlap_min: int = maxi(age_min, b_min)
		var overlap_max: int = mini(age_max, b_max)
		if overlap_max >= overlap_min:
			var span: float = float(b_max - b_min + 1)
			var frac: float = float(overlap_max - overlap_min + 1) / maxf(1.0, span)
			expected_sum += total_gen * float(b["target_share"]) * frac
			actual_sum += float(int(b["male_count"]) + int(b["female_count"])) * frac

	if expected_sum <= 0.0:
		return 1.0
	return clampf((expected_sum + 2.0) / (actual_sum + 2.0), 0.35, 3.0)

## Picks an integer age within [min_age, max_age] weighted by each age's residual cohort deficit
static func _pick_balanced_age_in_range(min_age: int, max_age: int, rng: RandomNumberGenerator, cohort_tracker: Dictionary) -> int:
	if min_age >= max_age:
		return min_age
	if cohort_tracker.is_empty() or int(cohort_tracker.get("total_generated", 0)) < 25:
		return rng.randi_range(min_age, max_age)

	var total_w: float = 0.0
	var weights: PackedFloat32Array = PackedFloat32Array()
	var span: int = max_age - min_age + 1
	weights.resize(span)

	for i in range(span):
		var a: int = min_age + i
		var w: float = _get_age_deficit_multiplier(cohort_tracker, a)
		weights[i] = w
		total_w += w

	var roll: float = rng.randf() * total_w
	var cum: float = 0.0
	for i in range(span):
		cum += weights[i]
		if roll <= cum:
			return min_age + i
	return max_age

## Picks sex for a given age tilted toward whichever sex is below target share in that bracket
static func _pick_balanced_sex_for_age(age: int, base_male_prob: float, rng: RandomNumberGenerator, cohort_tracker: Dictionary) -> bool:
	if cohort_tracker.is_empty() or int(cohort_tracker.get("total_generated", 0)) < 25:
		return rng.randf() < base_male_prob

	var total_gen: float = float(cohort_tracker["total_generated"])
	for b in cohort_tracker.get("brackets", []):
		if age >= int(b["min_age"]) and age <= int(b["max_age"]):
			var exp_m: float = total_gen * float(b["male_target_share"]) + 1.0
			var exp_f: float = total_gen * float(b["female_target_share"]) + 1.0
			var act_m: float = float(b["male_count"]) + 1.0
			var act_f: float = float(b["female_count"]) + 1.0
			var m_weight: float = base_male_prob * clampf(exp_m / act_m, 0.5, 2.0)
			var f_weight: float = (1.0 - base_male_prob) * clampf(exp_f / act_f, 0.5, 2.0)
			return rng.randf() < (m_weight / maxf(0.001, m_weight + f_weight))

	return rng.randf() < base_male_prob

## Records generated household members into the residual cohort tracker
static func _record_generated_members(cohort_tracker: Dictionary, members: Array[Dictionary]) -> void:
	if cohort_tracker.is_empty():
		return
	var brackets: Array = cohort_tracker.get("brackets", [])
	for m in members:
		var age: int = int(m["age"])
		var is_male: bool = bool(m["is_male"])
		cohort_tracker["total_generated"] = int(cohort_tracker["total_generated"]) + 1
		for b in brackets:
			if age >= int(b["min_age"]) and age <= int(b["max_age"]):
				if is_male:
					b["male_count"] = int(b["male_count"]) + 1
				else:
					b["female_count"] = int(b["female_count"]) + 1
				break

static func _sample_from_population_pyramid(
	demographics: Dictionary,
	rng: RandomNumberGenerator,
	min_allowed_age: int = 0,
	cohort_tracker: Dictionary = {}
) -> Dictionary:
	var pyramid: Array = demographics["population_pyramid"]
	var eligible: Array = []
	var bracket_weights: Array[float] = []
	var total_weight: float = 0.0

	for bracket in pyramid:
		var max_a: int = int(bracket["max_age"])
		if max_a < min_allowed_age:
			continue
		var min_a: int = maxi(int(bracket["min_age"]), min_allowed_age)
		var mid_a: int = int((min_a + max_a) / 2)
		var base_w: float = float(bracket["male_pct"]) + float(bracket["female_pct"])
		var mult: float = _get_age_deficit_multiplier(cohort_tracker, mid_a)
		var adj_w: float = base_w * mult

		eligible.append(bracket)
		bracket_weights.append(adj_w)
		total_weight += adj_w

	if eligible.is_empty():
		return { "age": maxi(min_allowed_age, 25), "is_male": true }

	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	var chosen: Dictionary = eligible[0]

	for idx in range(eligible.size()):
		cumulative += bracket_weights[idx]
		if roll <= cumulative:
			chosen = eligible[idx]
			break

	var b_min: int = maxi(int(chosen["min_age"]), min_allowed_age)
	var b_max: int = int(chosen["max_age"])
	var resolved_age: int = _pick_balanced_age_in_range(b_min, b_max, rng, cohort_tracker)

	var male_pct: float = float(chosen["male_pct"])
	var female_pct: float = float(chosen["female_pct"])
	var base_male_prob: float = male_pct / maxf(0.001, male_pct + female_pct)
	var is_male: bool = _pick_balanced_sex_for_age(resolved_age, base_male_prob, rng, cohort_tracker)

	return { "age": resolved_age, "is_male": is_male }

static func _sample_typology(
	typology_model: Dictionary,
	head_age: int,
	rng: RandomNumberGenerator,
	cohort_tracker: Dictionary = {}
) -> String:
	var table: Array = typology_model["types_by_head_age"]
	var chosen_row: Dictionary = {}

	for row in table:
		if head_age >= int(row["age_min"]) and head_age <= int(row["age_max"]):
			chosen_row = row
			break

	if chosen_row.is_empty() and not table.is_empty():
		chosen_row = table[-1]

	var child_deficit: float = _get_range_deficit_multiplier(cohort_tracker, 5, 15)
	var weights: Dictionary = chosen_row["weights"]
	var total_w: float = 0.0
	var adj_weights: Dictionary = {}

	for k in weights.keys():
		var key_str: String = str(k)
		var w: float = float(weights[k])
		# Slightly boost family households when school-age children (5-15) are under-represented
		if key_str in ["COUPLE_WITH_DEP", "LONE_PARENT"] and child_deficit > 1.05:
			w *= clampf(child_deficit, 1.0, 1.65)
		adj_weights[key_str] = w
		total_w += w

	var roll: float = rng.randf() * total_w
	var cum: float = 0.0
	for k in adj_weights.keys():
		cum += float(adj_weights[k])
		if roll <= cum:
			return str(k)

	return "SINGLE_PERSON"

static func _sample_marital_status(typology_model: Dictionary, head_age: int, rng: RandomNumberGenerator) -> String:
	var rows: Array = typology_model["marital_status_by_head_age"]
	for row in rows:
		if head_age >= int(row["age_min"]) and head_age <= int(row["age_max"]):
			var r: float = rng.randf()
			var m_p: float = float(row["married"])
			var nm_p: float = float(row["never_married"])
			var d_p: float = float(row["divorced"])
			if r < m_p:
				return "MARRIED"
			elif r < m_p + nm_p:
				return "NEVER_MARRIED"
			elif r < m_p + nm_p + d_p:
				return "DIVORCED"
			else:
				return "WIDOWED"
	return "NEVER_MARRIED"

static func _calculate_spouse_age(typology_model: Dictionary, head_age: int, head_is_male: bool, rng: RandomNumberGenerator) -> int:
	var sp_cfg: Dictionary = typology_model["spousal_age_difference"]
	var mean_diff: float = float(sp_cfg["husband_older_mean"])
	var std_dev: float = float(sp_cfg["husband_older_std_dev"])

	var sampled_diff: float = rng.randfn(mean_diff, std_dev)
	var sp_age: int = head_age
	if head_is_male:
		sp_age = int(round(float(head_age) - sampled_diff))
	else:
		sp_age = int(round(float(head_age) + sampled_diff))

	return clampi(sp_age, 16, 95)

static func _generate_children(
	demographics: Dictionary,
	mother_age: int,
	rng: RandomNumberGenerator,
	cohort_tracker: Dictionary = {}
) -> Array[Dictionary]:
	var children: Array[Dictionary] = []
	var fert_model: Dictionary = demographics["fertility_and_family_model"]
	var parity_cfg: Dictionary = fert_model["parity_distribution"]
	var base_weights: Dictionary = parity_cfg["base_weights"]
	var continuation_p: float = float(parity_cfg["continuation_probability_beyond_4"])
	var abs_max: int = int(parity_cfg["absolute_max_children"])

	var deficit_0_4: float = _get_range_deficit_multiplier(cohort_tracker, 0, 4)
	var deficit_5_14: float = _get_range_deficit_multiplier(cohort_tracker, 5, 14)
	var target_children: int = 1
	var total_w: float = 0.0
	var adj_parity: Dictionary = {}

	for k in base_weights.keys():
		var parity_n: int = int(k)
		var w: float = float(base_weights[k])
		# Tilt parity upward toward 2-4 children when 5-14 cohort is under-represented
		if parity_n >= 2 and deficit_5_14 > 1.05:
			w *= clampf(pow(deficit_5_14, 0.85 * float(parity_n - 1)), 1.0, 2.5)
		adj_parity[k] = w
		total_w += w

	var roll: float = rng.randf() * total_w
	var cum: float = 0.0
	for k in adj_parity.keys():
		cum += float(adj_parity[k])
		if roll <= cum:
			target_children = int(k)
			break

	if target_children == 4:
		var adj_cont_p: float = clampf(continuation_p * clampf(deficit_5_14, 0.85, 1.5), 0.05, 0.75)
		while target_children < abs_max and rng.randf() < adj_cont_p:
			target_children += 1

	var maternal_rules: Dictionary = fert_model["maternal_age_rules"]
	var min_m_age: int = int(maternal_rules["min_mother_age_at_birth"])
	var max_m_age: int = int(maternal_rules["max_mother_age_at_birth"])
	var first_birth_dist: Array = maternal_rules["maternal_age_first_birth_distribution"]

	if mother_age < min_m_age:
		return children

	var fb_total_w: float = 0.0
	var fb_weights: Array[float] = []
	for row in first_birth_dist:
		var r_min: int = int(row["min_age"])
		var r_max: int = int(row["max_age"])
		var mid_fb: int = int((r_min + r_max) / 2)
		var implied_oldest_child: int = mother_age - mid_fb
		var w: float = float(row["weight"])
		if implied_oldest_child >= 0:
			var age_def: float = _get_age_deficit_multiplier(cohort_tracker, implied_oldest_child)
			w *= clampf(pow(age_def, 1.65), 0.25, 3.5)
		fb_weights.append(w)
		fb_total_w += w

	var fb_roll: float = rng.randf() * fb_total_w
	var fb_cum: float = 0.0
	var first_birth_age: int = 24

	for idx in range(first_birth_dist.size()):
		fb_cum += fb_weights[idx]
		if fb_roll <= fb_cum:
			var row: Dictionary = first_birth_dist[idx]
			first_birth_age = rng.randi_range(int(row["min_age"]), int(row["max_age"]))
			break

	first_birth_age = mini(first_birth_age, mother_age)

	var twin_p: float = float(fert_model["multiple_birth_rates"]["twin_probability"])
	var spacing_cfg: Dictionary = fert_model["birth_spacing"]
	var min_spacing: int = int(spacing_cfg["min_spacing_years"])
	var max_spacing: int = int(spacing_cfg["max_spacing_years"])

	var current_m_age_at_birth: int = first_birth_age
	var spawned_count: int = 0

	var retention_cfg: Dictionary = fert_model["cohabiting_adult_offspring_retention"]
	var stay_18_21: float = float(retention_cfg["age_18_to_21_stay_rate"])
	var stay_22_25: float = float(retention_cfg["age_22_to_25_stay_rate"])
	var stay_26_plus: float = float(retention_cfg["age_26_plus_stay_rate"])

	while spawned_count < target_children and current_m_age_at_birth <= max_m_age and current_m_age_at_birth <= mother_age:
		var c_age: int = mother_age - current_m_age_at_birth
		# Avoid spilling extra parity births into 0-4 if 0-4 is already at or above target share
		if c_age <= 4 and deficit_0_4 < 0.96 and not children.is_empty():
			break

		var is_twin: bool = (rng.randf() < twin_p) and (spawned_count + 1 < target_children)
		var birth_size: int = 2 if is_twin else 1

		for _b in range(birth_size):
			var retain_in_home: bool = true
			var age_mult: float = _get_age_deficit_multiplier(cohort_tracker, c_age)
			if c_age >= 26:
				retain_in_home = (rng.randf() < clampf(stay_26_plus * age_mult, 0.0, 0.25))
			elif c_age >= 22:
				retain_in_home = (rng.randf() < clampf(stay_22_25 * age_mult, 0.02, 0.35))
			elif c_age >= 18:
				retain_in_home = (rng.randf() < clampf(stay_18_21 * age_mult, 0.08, 0.60))
			elif c_age >= 15:
				# Throttle 15-17 co-residing youths if 15-19 bracket is already over-populated
				var leave_prob: float = clampf((1.0 - age_mult) * 1.25, 0.0, 0.45)
				retain_in_home = (rng.randf() >= leave_prob)

			if retain_in_home:
				var c_is_male: bool = _pick_balanced_sex_for_age(c_age, 0.51, rng, cohort_tracker)
				children.append({
					"role_in_home": "CHILD",
					"age": c_age,
					"is_male": c_is_male,
					"is_head": false,
					"is_married": false
				})
			spawned_count += 1

		current_m_age_at_birth += rng.randi_range(min_spacing, max_spacing)

	return children

## Resolves education attainment using config-driven tier_ranks without hardcoded tier arrays
static func resolve_citizen_education(
	demographics: Dictionary,
	rng: RandomNumberGenerator,
	age_years: int,
	is_male: bool,
	is_high_density: bool
) -> String:
	var edu_model: Dictionary = demographics["education_attainment_model"]
	var default_code: String = str(edu_model["default_code"])
	var tier_ranks: Dictionary = get_education_rank_map(demographics)
	var rates: Array = edu_model["cohort_attainment_rates"]
	var min_school_leaving_age: int = int(demographics["legal_and_pension_thresholds"]["minimum_school_leaving_age"])

	if age_years < min_school_leaving_age:
		return default_code

	var matched_row: Dictionary = {}
	for row in rates:
		if age_years >= int(row["age_min"]) and age_years <= int(row["age_max"]):
			matched_row = row
			break

	if matched_row.is_empty():
		return default_code

	var penalty: float = float(matched_row.get("high_density_penalty", 0.0)) if is_high_density else 0.0
	var prob_dict: Dictionary = matched_row["male_probabilities"] if is_male else matched_row["female_probabilities"]

	# Sort candidate education codes descending by their configured tier_ranks value
	var candidate_tiers: Array = prob_dict.keys()
	candidate_tiers.sort_custom(func(a, b) -> bool:
		return int(tier_ranks.get(str(a), 0)) > int(tier_ranks.get(str(b), 0))
	)

	for tier_code in candidate_tiers:
		var code_str: String = str(tier_code)
		var p: float = maxf(0.01, float(prob_dict[code_str]) - penalty)
		if rng.randf() < p:
			return code_str

	return default_code

## Resolves a citizen's demographic cohort and labor market participation branch
static func resolve_citizen_demographics(
	demographics: Dictionary,
	rng: RandomNumberGenerator,
	age_years: int,
	is_male: bool,
	unemp_rate: float,
	edu_code: String,
	is_married: bool,
	has_child_under_5: bool,
	has_child_5_to_15: bool
) -> Dictionary:
	var cohorts: Array = demographics["cohort_profiles"]
	var thresholds: Dictionary = demographics["legal_and_pension_thresholds"]
	var pen_age: int = int(thresholds["pension_age_male"] if is_male else thresholds["pension_age_female"])

	var chosen_cohort: Dictionary = cohorts[0]
	for c in cohorts:
		var c_min: int = int(c.get("age_min", 0))
		if c.has("age_min_dynamic") and c["age_min_dynamic"] == "pension_age":
			c_min = pen_age

		var c_max: int = int(c.get("age_max", 95))
		if c.has("age_max_dynamic") and c["age_max_dynamic"] == "pension_age":
			c_max = pen_age - 1

		if age_years >= c_min and age_years <= c_max:
			chosen_cohort = c
			break

	var strategy: String = str(chosen_cohort["strategy"])
	var profile_data: Dictionary = {}

	match strategy:
		"FIXED":
			profile_data = chosen_cohort
		"PROBABILISTIC":
			var prob: float = float(chosen_cohort["condition_probability"])
			profile_data = chosen_cohort["if_true"] if (rng.randf() < prob) else chosen_cohort["if_false"]
		"LABOR_MARKET":
			var participates_in_formal_labor: bool = true
			if not is_male:
				var part_mods: Dictionary = demographics["fertility_and_family_model"]["female_labor_participation_modifiers"]
				var base_rate: float = float(part_mods["base_married_rate"] if is_married else part_mods["base_unmarried_rate"])

				if has_child_under_5:
					base_rate *= float(part_mods["has_infant_under_5_multiplier"])
				elif has_child_5_to_15:
					base_rate *= float(part_mods["has_school_child_5_to_15_multiplier"])

				var edu_boosts: Dictionary = part_mods["education_boost"]
				base_rate *= float(edu_boosts.get(edu_code, 1.0))

				if rng.randf() > base_rate:
					participates_in_formal_labor = false

			if not participates_in_formal_labor:
				profile_data = {
					"role": "HOME_MAKER",
					"anchor_category": "RESIDENTIAL_UNIT",
					"contract_class": "INFORMAL_GREY",
					"weekly_hours": 0.0,
					"compensation_rate": 0.0
				}
			elif rng.randf() < unemp_rate:
				profile_data = chosen_cohort["unemployed_branch"]
			else:
				profile_data = {
					"role": "WORKER_SEEKER",
					"anchor_category": "COMMERCIAL",
					"contract_class": "FORMAL_LEGAL",
					"weekly_hours": 37.5,
					"compensation_rate": 3.75
				}

	return {
		"age": age_years,
		"occupation": str(profile_data["role"]),
		"anchor_category": str(profile_data["anchor_category"]),
		"contract_class": str(profile_data["contract_class"]),
		"weekly_hours": float(profile_data["weekly_hours"]),
		"compensation_rate": float(profile_data["compensation_rate"])
	}