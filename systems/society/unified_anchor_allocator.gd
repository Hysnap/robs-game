# res://systems/society/unified_anchor_allocator.gd
class_name UnifiedAnchorAllocator
extends RefCounted

const PERSONALITY_HYDRATOR = preload("res://systems/society/citizen_personality_hydrator.gd")

## Resolves an individual resident's church_id using parental/spousal inheritance, religion, and spatial gravity
static func resolve_individual_church_id(
	household_role: String,
	religion_code: String,
	home_pos: Vector2,
	head_church_id: int,
	spouse_church_id: int,
	church_estabs: Array,
	estab_positions: Dictionary,
	ocean_rules: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	if church_estabs.is_empty():
		return -1

	assert(ocean_rules.has("venue_cohort_selection"), "FATAL: ocean_rules missing 'venue_cohort_selection'!")
	var venue_cfg: Dictionary = ocean_rules["venue_cohort_selection"]

	# 1. Spousal inheritance check
	if household_role == "SPOUSE" and head_church_id > 0:
		var spouse_prob: float = float(venue_cfg["spouse_shares_head_church_probability"])
		if rng.randf() < spouse_prob:
			return head_church_id

	# 2. Child parental inheritance check
	if household_role == "CHILD":
		var parent_church: int = head_church_id if head_church_id > 0 else spouse_church_id
		if parent_church > 0:
			var child_prob: float = float(venue_cfg["child_inherits_parent_church_probability"])
			if rng.randf() < child_prob:
				return parent_church

	# 3. Independent attendance roll based on secular vs practicing religion
	var is_secular: bool = (religion_code.to_upper() == "SECULAR_NONE" or religion_code.to_upper() == "NONE")
	var attend_prob: float = float(
		venue_cfg["secular_attends_church_probability"]
		if is_secular
		else venue_cfg["practicing_attends_church_probability"]
	)
	if rng.randf() > attend_prob:
		return -1

	return pick_gravity_establishment(home_pos, church_estabs, estab_positions, {}, rng)

## Allocates a finite-capacity school or institutional enclave (sharing school with older sibling if capacity permits)
static func allocate_school_or_enclave_anchor(
	home_pos: Vector2,
	candidate_estabs: Array,
	estab_positions: Dictionary,
	estab_capacities: Dictionary,
	inout_enrolled_counts: Dictionary,
	preferred_sibling_estab_id: int,
	rng: RandomNumberGenerator
) -> int:
	if candidate_estabs.is_empty():
		return -1

	# 1. Sibling co-enrollment preference if the school still has capacity
	if preferred_sibling_estab_id > 0 and candidate_estabs.has(preferred_sibling_estab_id):
		var cap: int = int(estab_capacities.get(preferred_sibling_estab_id, 999999))
		var cur: int = int(inout_enrolled_counts.get(preferred_sibling_estab_id, 0))
		if cur < cap or cap <= 0:
			inout_enrolled_counts[preferred_sibling_estab_id] = cur + 1
			return preferred_sibling_estab_id

	# 2. Filter to establishments with available capacity
	var available: Array = []
	for est_id in candidate_estabs:
		var cap: int = int(estab_capacities.get(est_id, 999999))
		var cur: int = int(inout_enrolled_counts.get(est_id, 0))
		if cap <= 0 or cur < cap:
			available.append(est_id)

	var pool: Array = available if not available.is_empty() else candidate_estabs
	var chosen_id: int = pick_gravity_establishment(home_pos, pool, estab_positions, estab_capacities, rng)
	if chosen_id > 0:
		inout_enrolled_counts[chosen_id] = int(inout_enrolled_counts.get(chosen_id, 0)) + 1
	return chosen_id

## Scores and selects the best open workplace job slot for a candidate using Education Tier + OCEAN Affinity + Commute Decay
static func match_best_job_slot_for_resident(
	candidate: Dictionary,
	open_slots: Array,
	edu_rank_map: Dictionary,
	job_roles_cfg: Dictionary,
	ocean_rules: Dictionary,
	estab_positions: Dictionary,
	enable_commute: bool,
	rng: RandomNumberGenerator
) -> int:
	if open_slots.is_empty():
		return -1

	assert(ocean_rules.has("job_matching_weights"), "FATAL: ocean_rules missing 'job_matching_weights'!")
	var match_weights: Dictionary = ocean_rules["job_matching_weights"]
	var exact_edu_bonus: float = float(match_weights["exact_education_tier_bonus"])
	var one_over_mult: float = float(match_weights["one_tier_overqualified_multiplier"])
	var two_over_mult: float = float(match_weights["two_plus_tiers_overqualified_multiplier"])
	var ocean_scale: float = float(match_weights["ocean_affinity_scale"])

	var cand_age: int = int(candidate["age_years"])
	var cand_edu_code: String = str(candidate["education_code"])
	var cand_edu_rank: int = int(edu_rank_map.get(cand_edu_code, 0))
	var cand_home_pos: Vector2 = candidate.get("home_pos", Vector2.ZERO)
	var cand_traits: Dictionary = candidate.get("ocean_traits", {})

	var best_idx: int = -1
	var best_score: float = -1.0

	# Sample up to 64 open slots for O(1) bounded performance on large cities while preserving high-fit matching
	var total_slots: int = open_slots.size()
	var sample_count: int = mini(total_slots, 64)
	var start_offset: int = rng.randi_range(0, total_slots - 1) if total_slots > 1 else 0

	for s_i in range(sample_count):
		var slot_idx: int = (start_offset + s_i) % total_slots
		var slot: Dictionary = open_slots[slot_idx]
		var role_code: String = str(slot["role_code"])

		var req_edu_code: String = str(slot.get("min_education_code", "NO_FORMAL"))
		var req_edu_rank: int = int(edu_rank_map.get(req_edu_code, 0))
		if cand_edu_rank < req_edu_rank:
			continue

		var role_def: Dictionary = job_roles_cfg.get(role_code, {})
		var age_min: int = int(role_def.get("age_min", 16))
		var age_max: int = int(role_def.get("age_max", 65))
		if cand_age < age_min or cand_age > age_max:
			continue

		var estab_id: int = int(slot["establishment_id"])
		var commute_factor: float = 1.0
		if enable_commute and estab_positions.has(estab_id):
			var work_pos: Vector2 = estab_positions[estab_id]
			var dist_m: float = cand_home_pos.distance_to(work_pos)
			var max_commute: float = float(role_def.get("max_commute", 10000.0))
			if dist_m > max_commute * 1.5:
				continue
			commute_factor = 1000.0 / (dist_m + 500.0)

		# Education tier fit
		var rank_diff: int = cand_edu_rank - req_edu_rank
		var edu_mult: float = exact_edu_bonus
		if rank_diff == 1:
			edu_mult = one_over_mult
		elif rank_diff >= 2:
			edu_mult = two_over_mult

		# OCEAN personality affinity fit
		var role_affinities: Dictionary = role_def.get("ocean_affinities", {})
		var ocean_mult: float = PERSONALITY_HYDRATOR.calculate_role_ocean_multiplier(cand_traits, role_affinities, ocean_scale)

		var jitter: float = rng.randf_range(0.85, 1.15)
		var score: float = edu_mult * ocean_mult * commute_factor * jitter

		if score > best_score:
			best_score = score
			best_idx = slot_idx

	return best_idx

## Resolves an adult resident's individual local_pub_id across Workplace, Sibling, Church, and Neighbourhood cohorts
static func resolve_individual_pub_id(
	resident: Dictionary,
	pub_estabs: Array,
	estab_positions: Dictionary,
	estab_capacities: Dictionary,
	workplace_cohort_pubs: Dictionary,
	kin_graph: Dictionary,
	residents_by_id: Dictionary,
	job_roles_cfg: Dictionary,
	ocean_rules: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	if pub_estabs.is_empty():
		return -1

	var age_years: int = int(resident.get("age_years", 0))
	if age_years < 16:
		return -1

	assert(ocean_rules.has("venue_cohort_selection"), "FATAL: ocean_rules missing 'venue_cohort_selection'!")
	var venue_cfg: Dictionary = ocean_rules["venue_cohort_selection"]
	var base_weights: Dictionary = venue_cfg["pub_cohort_base_weights"]
	var trait_mods: Dictionary = venue_cfg["pub_cohort_trait_modifiers"]
	var traits: Dictionary = resident.get("ocean_traits", {})
	var home_pos: Vector2 = resident.get("home_pos", Vector2.ZERO)

	# 1. Identify candidate pub IDs for each of the 4 social cohorts
	var cohort_candidates: Dictionary = {}

	# A. WORKPLACE_COHORT (stratified by workplace establishment + role social_tier)
	var work_estab_id: int = int(resident.get("employer_establishment_id", -1))
	var role_code: String = str(resident.get("role_code", ""))
	if work_estab_id > 0:
		var role_def: Dictionary = job_roles_cfg.get(role_code, {})
		var social_tier: String = str(role_def.get("social_tier", "STAFF"))
		var tier_group: String = "MGMT" if social_tier in ["MANAGEMENT", "PROFESSIONAL"] else "STAFF"
		var cohort_key: String = "%d:%s" % [work_estab_id, tier_group]

		if not workplace_cohort_pubs.has(cohort_key):
			var work_pos: Vector2 = estab_positions.get(work_estab_id, home_pos)
			workplace_cohort_pubs[cohort_key] = pick_gravity_establishment(work_pos, pub_estabs, estab_positions, estab_capacities, rng)
		var wp_pub: int = int(workplace_cohort_pubs[cohort_key])
		if wp_pub > 0:
			cohort_candidates["WORKPLACE_COHORT"] = wp_pub

	# B. SIBLING_COHORT (pulls toward an adult sibling's already-assigned local_pub_id)
	var res_id: int = int(resident["resident_id"])
	if kin_graph.has(res_id) and kin_graph[res_id].has("siblings"):
		var sib_ids: Array = kin_graph[res_id]["siblings"]
		for sib_id in sib_ids:
			if residents_by_id.has(sib_id):
				var sib_pub: int = int(residents_by_id[sib_id].get("local_pub_id", -1))
				if sib_pub > 0:
					cohort_candidates["SIBLING_COHORT"] = sib_pub
					break

	# C. CHURCH_COHORT (pub nearest the resident's parish church)
	var church_id: int = int(resident.get("church_id", -1))
	if church_id > 0 and estab_positions.has(church_id):
		var church_pos: Vector2 = estab_positions[church_id]
		var ch_pub: int = pick_gravity_establishment(church_pos, pub_estabs, estab_positions, estab_capacities, rng)
		if ch_pub > 0:
			cohort_candidates["CHURCH_COHORT"] = ch_pub

	# D. NEIGHBOURHOOD_COHORT (gravity-weighted pub near the resident's home)
	var neigh_pub: int = pick_gravity_establishment(home_pos, pub_estabs, estab_positions, estab_capacities, rng)
	if neigh_pub > 0:
		cohort_candidates["NEIGHBOURHOOD_COHORT"] = neigh_pub

	# 2. Score active cohorts using base_weights + OCEAN trait modifiers
	var weighted_cohorts: Array[Dictionary] = []
	var total_weight: float = 0.0

	for c_key in cohort_candidates.keys():
		var w: float = float(base_weights.get(c_key, 0.15))
		var mods: Dictionary = trait_mods.get(c_key, {})
		for t_key in mods.keys():
			if traits.has(t_key):
				var centered: float = float(traits[t_key]) - 0.50
				w += centered * float(mods[t_key])
		w = maxf(w, 0.02)
		total_weight += w
		weighted_cohorts.append({
			"pub_id": int(cohort_candidates[c_key]),
			"weight": w
		})

	if weighted_cohorts.is_empty():
		return neigh_pub

	var roll: float = rng.randf() * total_weight
	var accum: float = 0.0
	for item in weighted_cohorts:
		accum += float(item["weight"])
		if roll <= accum:
			return int(item["pub_id"])

	return int(weighted_cohorts.back()["pub_id"])

## Universal inverse-distance-squared gravity selector for establishments
static func pick_gravity_establishment(
	origin_pos: Vector2,
	candidate_ids: Array,
	estab_positions: Dictionary,
	estab_capacities: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	if candidate_ids.is_empty():
		return -1
	if candidate_ids.size() == 1:
		return int(candidate_ids[0])

	var weights: PackedFloat64Array = PackedFloat64Array()
	weights.resize(candidate_ids.size())
	var total_w: float = 0.0

	for i in range(candidate_ids.size()):
		var est_id: int = int(candidate_ids[i])
		var pos: Vector2 = estab_positions.get(est_id, origin_pos)
		var dist: float = origin_pos.distance_to(pos)
		var cap_mult: float = clampf(float(estab_capacities.get(est_id, 100)) / 100.0, 0.5, 4.0)
		var w: float = (100000.0 / ((dist + 150.0) * (dist + 150.0))) * cap_mult
		weights[i] = w
		total_w += w

	if total_w <= 0.0:
		return int(candidate_ids[rng.randi_range(0, candidate_ids.size() - 1)])

	var pick: float = rng.randf() * total_w
	var current: float = 0.0
	for i in range(candidate_ids.size()):
		current += weights[i]
		if pick <= current:
			return int(candidate_ids[i])

	return int(candidate_ids.back())