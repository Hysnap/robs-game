# res://systems/society/citizen_personality_hydrator.gd
class_name CitizenPersonalityHydrator
extends RefCounted

const TRAIT_KEYS: Array[String] = [
	"openness",
	"conscientiousness",
	"extraversion",
	"agreeableness",
	"neuroticism"
]

const ASSORTATIVE_TRAITS: Array[String] = [
	"openness",
	"conscientiousness",
	"agreeableness"
]

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
	rng: RandomNumberGenerator
) -> Dictionary:
	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	var dist: Dictionary = ocean_rules["baseline_distribution"]
	var mean: float = float(dist["mean"])
	var std_dev: float = float(dist["std_dev"])
	var min_bound: float = float(dist["min_bound"])
	var max_bound: float = float(dist["max_bound"])

	var traits: Dictionary = {}
	for t_key in TRAIT_KEYS:
		var raw: float = rng.randfn(mean, std_dev)
		var nudge: float = float(arch_nudges.get(t_key, 0.0)) + float(edu_nudges.get(t_key, 0.0))
		traits[t_key] = snappedf(clampf(raw + nudge, min_bound, max_bound), 0.001)
	return traits

## Rolls a 5-trait OCEAN dictionary for a SPOUSE with assortative mating convergence toward the HEAD
static func roll_spouse_traits(
	head_traits: Dictionary,
	ocean_rules: Dictionary,
	arch_nudges: Dictionary,
	edu_nudges: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	assert(ocean_rules.has("heritability"), "FATAL: ocean_rules missing 'heritability'!")
	var dist: Dictionary = ocean_rules["baseline_distribution"]
	var min_bound: float = float(dist["min_bound"])
	var max_bound: float = float(dist["max_bound"])
	var assortative_blend: float = float(ocean_rules["heritability"]["spousal_assortative_mating_blend"])

	var traits: Dictionary = roll_independent_adult_traits(ocean_rules, arch_nudges, edu_nudges, rng)
	if head_traits.is_empty():
		return traits

	for t_key in ASSORTATIVE_TRAITS:
		if head_traits.has(t_key):
			var independent_val: float = float(traits[t_key])
			var head_val: float = float(head_traits[t_key])
			var blended: float = (independent_val * (1.0 - assortative_blend)) + (head_val * assortative_blend)
			traits[t_key] = snappedf(clampf(blended, min_bound, max_bound), 0.001)

	return traits

## Rolls a 5-trait OCEAN dictionary for a CHILD inheriting 50% from parental midpoint + 50% individual/environmental variance
static func roll_child_traits(
	parent_a_traits: Dictionary,
	parent_b_traits: Dictionary,
	ocean_rules: Dictionary,
	arch_nudges: Dictionary,
	edu_nudges: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	assert(ocean_rules.has("baseline_distribution"), "FATAL: ocean_rules missing 'baseline_distribution'!")
	assert(ocean_rules.has("heritability"), "FATAL: ocean_rules missing 'heritability'!")
	var dist: Dictionary = ocean_rules["baseline_distribution"]
	var mean: float = float(dist["mean"])
	var std_dev: float = float(dist["std_dev"])
	var min_bound: float = float(dist["min_bound"])
	var max_bound: float = float(dist["max_bound"])

	var herit: Dictionary = ocean_rules["heritability"]
	var parent_weight: float = float(herit["parental_midpoint_weight"])
	var indiv_weight: float = float(herit["individual_variance_weight"])

	var has_a: bool = not parent_a_traits.is_empty()
	var has_b: bool = not parent_b_traits.is_empty()

	var traits: Dictionary = {}
	for t_key in TRAIT_KEYS:
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
		traits[t_key] = snappedf(clampf(combined, min_bound, max_bound), 0.001)

	return traits

## Scores how well a resident's OCEAN vector aligns with a job role's ocean_affinities dictionary
static func calculate_role_ocean_multiplier(
	resident_traits: Dictionary,
	role_affinities: Dictionary,
	affinity_scale: float
) -> float:
	if resident_traits.is_empty() or role_affinities.is_empty():
		return 1.0

	var dot_delta: float = 0.0
	for t_key in role_affinities.keys():
		if resident_traits.has(t_key):
			# Centered around 0.50 neutral baseline so >0.5 boosts positive affinities and <0.5 penalizes them
			var centered_trait: float = float(resident_traits[t_key]) - 0.50
			var weight: float = float(role_affinities[t_key])
			dot_delta += centered_trait * weight

	return clampf(1.0 + (dot_delta * affinity_scale), 0.25, 2.50)