# res://systems/society/citizen_personality_hydrator.gd
class_name CitizenPersonalityHydrator
extends RefCounted

## Resolves the canonical OCEAN trait list strictly from ocean_personality_rules.json
static func _resolve_trait_keys(ocean_rules: Dictionary) -> Array:
	assert(ocean_rules.has("traits") and ocean_rules["traits"] is Array and not ocean_rules["traits"].is_empty(), "FATAL: ocean_rules missing non-empty 'traits' array!")
	return ocean_rules["traits"]

## Resolves the assortative mating trait list strictly from ocean_personality_rules.json
static func _resolve_assortative_traits(ocean_rules: Dictionary) -> Array:
	assert(ocean_rules.has("heritability") and ocean_rules["heritability"] is Dictionary, "FATAL: ocean_rules missing 'heritability'!")
	var herit: Dictionary = ocean_rules["heritability"]
	assert(herit.has("assortative_traits") and herit["assortative_traits"] is Array, "FATAL: ocean_rules.heritability missing 'assortative_traits' array!")
	return herit["assortative_traits"]

## Resolves the active population preset dictionary ("REALISTIC" or "CINEMATIC") from ocean_personality_rules.json
static func _resolve_active_preset(ocean_rules: Dictionary, preset_override: String = "") -> Dictionary:
	assert(ocean_rules.has("population_presets"), "FATAL: ocean_rules missing 'population_presets'!")
	var presets: Dictionary = ocean_rules["population_presets"]
	var mode_id: String = preset_override.strip_edges()
	if mode_id.is_empty():
		assert(ocean_rules.has("active_population_mode"), "FATAL: ocean_rules missing 'active_population_mode'!")
		mode_id = str(ocean_rules["active_population_mode"]).strip_edges()
	assert(presets.has(mode_id) and presets[mode_id] is Dictionary, "FATAL: Unknown population preset '%s' in ocean_rules!" % mode_id)
	return presets[mode_id]

## Applies preset extremity polarity around the neutral baseline so CINEMATIC populations produce bolder profiles
static func _apply_polarity_exponent(val: float, baseline: float, exponent: float) -> float:
	if is_equal_approx(exponent, 1.0):
		return val
	var offset: float = val - baseline
	var sign_dir: float = -1.0 if offset < 0.0 else 1.0
	var mag: float = clampf(absf(offset) * 2.0, 0.0, 1.0)
	return baseline + (sign_dir * pow(mag, exponent) * 0.5)

## Resolves a direct or inverted ('inverse_<axis>') trait score from the resident's trait dictionary
static func _resolve_propensity_axis_value(traits: Dictionary, axis_key: String, neutral_base: float) -> float:
	if axis_key.begins_with("inverse_"):
		var base_key: String = axis_key.trim_prefix("inverse_")
		if traits.has(base_key):
			return 1.0 - float(traits[base_key])
		return neutral_base
	if traits.has(axis_key):
		return float(traits[axis_key])
	return neutral_base

## Resolves the district archetype's ocean_nudges dictionary from archetypes.json
static func get_archetype_nudges(archetypes_cfg: Dictionary, archetype_id: String) -> Dictionary:
	if archetypes_cfg.has(archetype_id) and archetypes_cfg[archetype_id] is Dictionary:
		var arch_def: Dictionary = archetypes_cfg[archetype_id]
		if arch_def.has("ocean_nudges") and arch_def["ocean_nudges"] is Dictionary:
			return arch_def["ocean_nudges"]
	return {}

## Resolves the education tier's ocean_tier_nudges dictionary from demographics_1980s_uk.json
static func get_education_nudges(demographics_cfg: Dictionary, edu_code: String) -> Dictionary:
	assert(demographics_cfg.has("education_attainment_model"), "FATAL: demographics_cfg missing 'education_attainment_model'!")
	var edu_model: Dictionary = demographics_cfg["education_attainment_model"]
	assert(edu_model.has("ocean_tier_nudges"), "FATAL: education_attainment_model missing 'ocean_tier_nudges'!")
	var tier_nudges: Dictionary = edu_model["ocean_tier_nudges"]
	if tier_nudges.has(edu_code) and tier_nudges[edu_code] is Dictionary:
		return tier_nudges[edu_code]
	return {}

## Rolls a 5-trait OCEAN dictionary for an independent adult (HEAD, PEER, or External Influx Worker)
static func roll_independent_adult_traits(
	ocean_rules: Dictionary,
	arch_nudges: Dictionary,
	edu_nudges: Dictionary,
	rng: RandomNumberGenerator,
	preset_override: String = ""
) -> Dictionary:
	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	var trait_keys: Array = _resolve_trait_keys(ocean_rules)
	var dist: Dictionary = ocean_rules["baseline_distribution"]
	var preset: Dictionary = _resolve_active_preset(ocean_rules, preset_override)
	var mean: float = float(dist["mean"])
	var baseline: float = float(dist["neutral_trait_baseline"])
	var std_dev: float = float(dist["std_dev"]) * float(preset["ocean_std_dev_multiplier"])
	var polarity_exp: float = float(preset["extremity_polarity_exponent"])
	var min_bound: float = float(dist["min_bound"])
	var max_bound: float = float(dist["max_bound"])

	var traits: Dictionary = {}
	for raw_key in trait_keys:
		var t_key: String = str(raw_key)
		var raw: float = rng.randfn(mean, std_dev)
		var nudge: float = float(arch_nudges.get(t_key, 0.0)) + float(edu_nudges.get(t_key, 0.0))
		var polarized: float = _apply_polarity_exponent(clampf(raw + nudge, min_bound, max_bound), baseline, polarity_exp)
		traits[t_key] = snappedf(clampf(polarized, min_bound, max_bound), 0.001)
	return traits

## Rolls a 5-trait OCEAN dictionary for a SPOUSE with assortative mating convergence toward the HEAD
static func roll_spouse_traits(
	head_traits: Dictionary,
	ocean_rules: Dictionary,
	arch_nudges: Dictionary,
	edu_nudges: Dictionary,
	rng: RandomNumberGenerator,
	preset_override: String = ""
) -> Dictionary:
	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	var assortative_traits: Array = _resolve_assortative_traits(ocean_rules)
	var dist: Dictionary = ocean_rules["baseline_distribution"]
	var min_bound: float = float(dist["min_bound"])
	var max_bound: float = float(dist["max_bound"])
	var assortative_blend: float = float(ocean_rules["heritability"]["spousal_assortative_mating_blend"])

	var traits: Dictionary = roll_independent_adult_traits(ocean_rules, arch_nudges, edu_nudges, rng, preset_override)
	if head_traits.is_empty():
		return traits

	for raw_key in assortative_traits:
		var t_key: String = str(raw_key)
		if head_traits.has(t_key):
			var independent_val: float = float(traits[t_key])
			var head_val: float = float(head_traits[t_key])
			var blended: float = (independent_val * (1.0 - assortative_blend)) + (head_val * assortative_blend)
			traits[t_key] = snappedf(clampf(blended, min_bound, max_bound), 0.001)

	return traits

## Rolls a 5-trait OCEAN dictionary for a CHILD inheriting parental midpoint + individual/environmental variance
static func roll_child_traits(
	parent_a_traits: Dictionary,
	parent_b_traits: Dictionary,
	ocean_rules: Dictionary,
	arch_nudges: Dictionary,
	edu_nudges: Dictionary,
	rng: RandomNumberGenerator,
	preset_override: String = ""
) -> Dictionary:
	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	assert(ocean_rules.has("heritability"), "FATAL: ocean_rules missing 'heritability'!")
	var trait_keys: Array = _resolve_trait_keys(ocean_rules)
	var dist: Dictionary = ocean_rules["baseline_distribution"]
	var preset: Dictionary = _resolve_active_preset(ocean_rules, preset_override)
	var mean: float = float(dist["mean"])
	var baseline: float = float(dist["neutral_trait_baseline"])
	var std_dev: float = float(dist["std_dev"]) * float(preset["ocean_std_dev_multiplier"])
	var polarity_exp: float = float(preset["extremity_polarity_exponent"])
	var min_bound: float = float(dist["min_bound"])
	var max_bound: float = float(dist["max_bound"])

	var herit: Dictionary = ocean_rules["heritability"]
	var parent_weight: float = float(herit["parental_midpoint_weight"])
	var indiv_weight: float = float(herit["individual_variance_weight"])

	var has_a: bool = not parent_a_traits.is_empty()
	var has_b: bool = not parent_b_traits.is_empty()

	var traits: Dictionary = {}
	for raw_key in trait_keys:
		var t_key: String = str(raw_key)
		var parental_mid: float = mean
		if has_a and has_b:
			parental_mid = (float(parent_a_traits.get(t_key, mean)) + float(parent_b_traits.get(t_key, mean))) * 0.5
		elif has_a:
			parental_mid = float(parent_a_traits.get(t_key, mean))
		elif has_b:
			parental_mid = float(parent_b_traits.get(t_key, mean))

		var indiv_draw: float = rng.randfn(mean, std_dev)
		var env_nudge: float = float(arch_nudges.get(t_key, 0.0)) + float(edu_nudges.get(t_key, 0.0))
		var combined: float = (parental_mid * parent_weight) + (indiv_draw * indiv_weight) + env_nudge
		var polarized: float = _apply_polarity_exponent(clampf(combined, min_bound, max_bound), baseline, polarity_exp)
		traits[t_key] = snappedf(clampf(polarized, min_bound, max_bound), 0.001)

	return traits

## Hydrates cognitive (iq_score, mental_agility), dark/empathy axes, and Single Normalized Propensity Curve tags onto a trait dictionary
static func populate_cognitive_and_clinical_profile(
	traits: Dictionary,
	ocean_rules: Dictionary,
	age_years: float,
	edu_code: String,
	deprivation_ratio: float,
	rng: RandomNumberGenerator,
	preset_override: String = ""
) -> Dictionary:
	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	assert(ocean_rules.has("cognitive_model"), "FATAL: ocean_rules missing 'cognitive_model'!")
	assert(ocean_rules.has("dark_and_empathy_axes"), "FATAL: ocean_rules missing 'dark_and_empathy_axes'!")
	assert(ocean_rules.has("propensity_curve_defaults"), "FATAL: ocean_rules missing 'propensity_curve_defaults'!")
	assert(ocean_rules.has("neurodivergence_and_clinical_profiles"), "FATAL: ocean_rules missing 'neurodivergence_and_clinical_profiles'!")

	var dist: Dictionary = ocean_rules["baseline_distribution"]
	var neutral_base: float = float(dist["neutral_trait_baseline"])
	var preset: Dictionary = _resolve_active_preset(ocean_rules, preset_override)
	var tail_mult: float = float(preset["iq_tail_weight_multiplier"])
	var dark_spread_mult: float = float(preset["dark_trait_spread_multiplier"])
	var prop_sd_mult: float = float(preset.get("propensity_std_dev_multiplier", 1.0))

	var cog: Dictionary = ocean_rules["cognitive_model"]
	var iq_ref_mean: float = float(cog["iq_reference_mean"])
	var iq_ref_sd: float = float(cog["iq_reference_sd"])
	var iq_z_clamp: float = float(cog["iq_z_clamp"])

	var openness: float = float(traits.get("openness", neutral_base))
	var conscientiousness: float = float(traits.get("conscientiousness", neutral_base))
	var extraversion: float = float(traits.get("extraversion", neutral_base))
	var agreeableness: float = float(traits.get("agreeableness", neutral_base))
	var neuroticism: float = float(traits.get("neuroticism", neutral_base))

	# 1. IQ Score via 3-Component Gaussian Mixture Model (GMM) with preset tail scaling
	var comps: Array = cog["iq_gmm_components"]
	var scaled_weights: Array[float] = []
	var total_weight: float = 0.0
	for comp in comps:
		var w: float = float(comp["weight"])
		if str(comp["id"]) != "MAIN_POPULATION":
			w *= tail_mult
		scaled_weights.append(w)
		total_weight += w

	var gmm_roll: float = rng.randf() * total_weight
	var accum_weight: float = 0.0
	var comp_mean: float = iq_ref_mean
	var comp_sd: float = iq_ref_sd
	for i in range(comps.size()):
		accum_weight += scaled_weights[i]
		if gmm_roll <= accum_weight:
			comp_mean = float(comps[i]["mean"])
			comp_sd = float(comps[i]["std_dev"])
			break

	var cov: Dictionary = cog["iq_covariates"]
	var raw_iq: float = rng.randfn(comp_mean, comp_sd)
	var openness_delta: float = (openness - neutral_base) * iq_ref_sd * float(cov["openness_correlation"])
	var edu_bonuses: Dictionary = cov["education_tier_iq_bonus"]
	var edu_delta: float = float(edu_bonuses.get(edu_code, 0.0))
	var dep_penalty: float = clampf(deprivation_ratio, 0.0, 1.0) * float(cov["deprivation_scarr_rowe_max_penalty"])
	var iq_score: float = snappedf(
		clampf(raw_iq + openness_delta + edu_delta - dep_penalty, float(cog["iq_min_bound"]), float(cog["iq_max_bound"])),
		0.1
	)
	traits["iq_score"] = iq_score
	var iq_z: float = clampf((iq_score - iq_ref_mean) / iq_ref_sd, -iq_z_clamp, iq_z_clamp)

	# 2. Dark Triad & Affective Empathy Axes
	var dark_cfg: Dictionary = ocean_rules["dark_and_empathy_axes"]
	var d_min: float = float(dark_cfg["min_bound"])
	var d_max: float = float(dark_cfg["max_bound"])

	var mach_cfg: Dictionary = dark_cfg["machiavellianism"]
	var mach_raw: float = rng.randfn(float(mach_cfg["mean"]), float(mach_cfg["std_dev"]) * dark_spread_mult)
	mach_raw += (neutral_base - agreeableness) * float(mach_cfg["inverse_agreeableness_weight"])
	mach_raw += (conscientiousness - neutral_base) * float(mach_cfg["conscientiousness_weight"])
	mach_raw += iq_z * float(mach_cfg["iq_strategic_weight"])
	var machiavellianism: float = snappedf(clampf(mach_raw, d_min, d_max), 0.001)
	traits["machiavellianism"] = machiavellianism

	var emp_cfg: Dictionary = dark_cfg["empathy_affective"]
	var emp_raw: float = rng.randfn(float(emp_cfg["mean"]), float(emp_cfg["std_dev"]) * dark_spread_mult)
	emp_raw += (agreeableness - neutral_base) * float(emp_cfg["agreeableness_weight"])
	emp_raw += (neutral_base - machiavellianism) * float(emp_cfg["inverse_machiavellianism_weight"])
	var empathy_affective: float = snappedf(clampf(emp_raw, d_min, d_max), 0.001)
	traits["empathy_affective"] = empathy_affective

	var ent_cfg: Dictionary = dark_cfg["power_entitlement"]
	var ent_raw: float = rng.randfn(float(ent_cfg["mean"]), float(ent_cfg["std_dev"]) * dark_spread_mult)
	ent_raw += (neutral_base - agreeableness) * float(ent_cfg["inverse_agreeableness_weight"])
	ent_raw += (extraversion - neutral_base) * float(ent_cfg["extraversion_weight"])
	ent_raw += (1.0 - clampf(deprivation_ratio, 0.0, 1.0)) * float(ent_cfg["affluence_district_bonus"])
	var power_entitlement: float = snappedf(clampf(ent_raw, d_min, d_max), 0.001)
	traits["power_entitlement"] = power_entitlement

	# 3. Single Normalized Propensity Curve Tag Evaluation (uniform >= cutoff right-tail rule)
	var curve_cfg: Dictionary = ocean_rules["propensity_curve_defaults"]
	var curve_min: float = float(curve_cfg["curve_min"])
	var curve_max: float = float(curve_cfg["curve_max"])
	var def_mean: float = float(curve_cfg["default_mean"])
	var def_sd: float = float(curve_cfg["default_std_dev"])
	var sev_min: float = float(curve_cfg["severity_min"])
	var sev_max: float = float(curve_cfg["severity_max"])

	var profiles_cfg: Dictionary = ocean_rules["neurodivergence_and_clinical_profiles"]
	var tags: Array[Dictionary] = []
	var iq_agility_decouple: float = 0.0
	var agility_var_mult: float = 1.0

	for tag_code in profiles_cfg.keys():
		var p_def: Dictionary = profiles_cfg[tag_code]
		if age_years < float(p_def["min_age"]) or age_years > float(p_def["max_age"]):
			continue

		var p_mean: float = float(p_def.get("propensity_mean", def_mean))
		var p_sd: float = float(p_def.get("propensity_std_dev", def_sd)) * prop_sd_mult
		var cutoff: float = float(p_def["cutoff"])
		var axis_weights: Dictionary = p_def.get("axis_weights", {})

		var axis_shift: float = 0.0
		for axis_key in axis_weights.keys():
			var a_val: float = _resolve_propensity_axis_value(traits, str(axis_key), neutral_base)
			axis_shift += (a_val - neutral_base) * float(axis_weights[axis_key])

		var propensity: float = clampf(rng.randfn(p_mean, p_sd) + axis_shift, curve_min, curve_max)
		if propensity >= cutoff:
			var span: float = maxf(0.0001, curve_max - cutoff)
			var tail_ratio: float = clampf((propensity - cutoff) / span, 0.0, 1.0)
			var severity: float = snappedf(lerpf(sev_min, sev_max, tail_ratio), 0.01)
			tags.append({
				"code": str(tag_code),
				"propensity": snappedf(propensity, 0.001),
				"severity": severity
			})
			var effects: Dictionary = p_def.get("effects", {})
			if effects.has("iq_agility_decouple_factor"):
				iq_agility_decouple = maxf(iq_agility_decouple, float(effects["iq_agility_decouple_factor"]))
			if effects.has("agility_variance_multiplier"):
				agility_var_mult = maxf(agility_var_mult, float(effects["agility_variance_multiplier"]))

	traits["behavioral_tags"] = tags

	# 4. Mental Agility (Correlated to IQ, shaped by Lifespan Inverted-U & OCEAN, decoupled via config effects)
	var ag_cfg: Dictionary = cog["mental_agility"]
	var corr: float = float(ag_cfg["iq_copula_correlation"]) * (1.0 - iq_agility_decouple)
	var ag_sd: float = float(ag_cfg["baseline_std_dev"]) * agility_var_mult
	var indep_z: float = rng.randfn(0.0, 1.0)
	var combined_z: float = (corr * iq_z) + (sqrt(maxf(0.0, 1.0 - (corr * corr))) * indep_z)
	var raw_agility: float = float(ag_cfg["baseline_mean"]) + (combined_z * ag_sd)

	# Inverted-U Lifespan Curve
	var age_curve: Dictionary = ag_cfg["age_curve"]
	var peak_age: float = float(age_curve["peak_age"])
	var age_mult: float = 1.0
	if age_years < peak_age:
		var child_floor: float = float(age_curve["childhood_floor_multiplier"])
		age_mult = lerpf(child_floor, 1.0, clampf(age_years / peak_age, 0.0, 1.0))
	else:
		var decay: float = (age_years - peak_age) * float(age_curve["annual_decay_post_peak"])
		age_mult = maxf(float(age_curve["elder_floor_multiplier"]), 1.0 - decay)

	var t_mods: Dictionary = ag_cfg["trait_modifiers"]
	var trait_shift: float = (openness - neutral_base) * float(t_mods["openness_weight"])
	trait_shift -= maxf(0.0, neuroticism - neutral_base) * float(t_mods["neuroticism_penalty_weight"])
	if conscientiousness > float(t_mods["extreme_conscientiousness_threshold"]):
		trait_shift -= float(t_mods["extreme_conscientiousness_rigidity_penalty"])

	var scaled_agility: float = clampf((raw_agility * age_mult) + trait_shift, float(ag_cfg["min_bound"]), float(ag_cfg["max_bound"]))
	var skewed_agility: float = pow(scaled_agility, float(ag_cfg["right_skew_exponent"]))
	traits["mental_agility"] = snappedf(clampf(skewed_agility, float(ag_cfg["min_bound"]), float(ag_cfg["max_bound"])), 0.001)

	return traits

## Scores how well a resident's OCEAN vector aligns with a job role's ocean_affinities dictionary
static func calculate_role_ocean_multiplier(
	resident_traits: Dictionary,
	role_affinities: Dictionary,
	ocean_rules: Dictionary
) -> float:
	if resident_traits.is_empty() or role_affinities.is_empty():
		return 1.0

	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	assert(ocean_rules.has("job_matching_weights"), "FATAL: ocean_rules missing 'job_matching_weights'!")
	var neutral_base: float = float(ocean_rules["baseline_distribution"]["neutral_trait_baseline"])
	var jw: Dictionary = ocean_rules["job_matching_weights"]
	var affinity_scale: float = float(jw["ocean_affinity_scale"])
	var min_mult: float = float(jw["min_affinity_multiplier"])
	var max_mult: float = float(jw["max_affinity_multiplier"])

	var dot_delta: float = 0.0
	for t_key in role_affinities.keys():
		if resident_traits.has(t_key):
			var centered_trait: float = float(resident_traits[t_key]) - neutral_base
			var weight: float = float(role_affinities[t_key])
			dot_delta += centered_trait * weight

	return clampf(1.0 + (dot_delta * affinity_scale), min_mult, max_mult)