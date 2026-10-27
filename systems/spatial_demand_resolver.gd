# res://systems/spatial_demand_resolver.gd
class_name SpatialDemandResolver
extends RefCounted

# Education Tier Hierarchy Map
const EDU_TIER_RANK: Dictionary = {
	"NO_FORMAL": 0,
	"BASIC_SECONDARY": 1,
	"O_LEVELS_CSE": 1,
	"ENHANCED_SECONDARY": 2,
	"A_LEVELS": 2,
	"PRE_UNI_SECONDARY": 2,
	"POLYTECHNIC_DIPLOMA": 3,
	"DEGREE_OR_HIGHER": 4,
	"UNIVERSITY_DEGREE": 4
}

## Universal helper to resolve spatial coordinates regardless of whether they are Vector2, Vector2i, Array, or String
static func _resolve_vector2(val: Variant) -> Vector2:
	if val is Vector2:
		return val
	if val is Vector2i:
		return Vector2(float(val.x), float(val.y))
	if val is Array and val.size() >= 2:
		return Vector2(float(val[0]), float(val[1]))
	if val is String:
		var clean := (val as String).replace("(", "").replace(")", "").strip_edges()
		var parts := clean.split(",")
		if parts.size() >= 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO

## Evaluates whether an additional facility/tenancy can be supported at 'center_pos'
static func is_catchment_viable(
	center_pos: Vector2,
	existing_instance_positions: Array,
	districts: Dictionary,
	block_estimates: Dictionary,
	travel_dist_m: float,
	pop_ratio: float
) -> bool:
	var existing_count: int = 0
	for p in existing_instance_positions:
		if (p as Vector2).distance_to(center_pos) <= travel_dist_m:
			existing_count += 1

	if existing_count == 0:
		return true

	var local_pop: float = 0.0
	for d_id in districts.keys():
		var d_pos: Vector2 = _resolve_vector2(districts[d_id].get("spatial_anchor", Vector2.ZERO))
		if center_pos.distance_to(d_pos) <= travel_dist_m:
			local_pop += float(block_estimates.get(d_id, 0.0))

	var required_pop: float = float(existing_count + 1) * pop_ratio
	return local_pop >= required_pop

## Scores and picks the best host district from world_state for a given placement rule
static func find_best_host_district(
	districts: Dictionary,
	block_estimates: Dictionary,
	placed_coords_for_this_type: Array,
	spec: Dictionary,
	max_city_radius_m: float
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var travel_dist: float = float(spec.get("travel_dist_m", 750.0))
	var pop_ratio: float = float(spec.get("pop_ratio", 1500.0))
	var min_sep: float = float(spec.get("min_sep_m", 0.0))
	var dist_range: Array = spec.get("norm_dist_range", [0.0, 1.0])
	var allowed_sectors: Array = spec.get("allowed_sectors", [])
	var forbidden_types: Array = spec.get("forbidden_types", [])
	var prefer_vacant: bool = bool(spec.get("prefer_vacant", true))
	var type_code: String = str(spec.get("code", ""))

	var cfg = ScenarioManifestManager.get_city_configuration()
	var default_area: float = 40000.0
	if cfg and "block_size" in cfg:
		var bs: float = float(cfg.get("block_size"))
		default_area = bs * bs

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var sector: String = str(d.get("initial_sector", d.get("sector_class", ""))).to_upper()

		if dtype in forbidden_types or bool(d.get("is_repurposed_civic", false)):
			continue
		if d.has("embedded_civics") and type_code in d["embedded_civics"]:
			continue

		var is_vacant: bool = bool(d.get("is_initially_vacant", false)) or int(d.get("actual_building_count", 0)) == 0

		if not is_vacant:
			if not allowed_sectors.is_empty() and not allowed_sectors.has(sector):
				continue

		var center: Vector2 = _resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		var norm_d: float = center.length() / max(1.0, max_city_radius_m)
		if norm_d < float(dist_range[0]) or norm_d > float(dist_range[1]):
			continue

		if min_sep > 0.0:
			var too_close := false
			for c in placed_coords_for_this_type:
				if center.distance_to(c) < min_sep:
					too_close = true
					break
			if too_close:
				continue

		if not is_catchment_viable(center, placed_coords_for_this_type, districts, block_estimates, travel_dist, pop_ratio):
			continue

		var b_count: int = int(d.get("actual_building_count", 0))
		var est_p: float = float(block_estimates.get(dist_id, 0.0))
		var dev_score: float = -1000.0 if (is_vacant and prefer_vacant) else (float(b_count * 10) + est_p)

		candidates.append({
			"dist_id": dist_id,
			"dev_score": dev_score,
			"center": center,
			"is_vacant": is_vacant,
			"est_pop": est_p,
			"area_sqm": float(d.get("area_sqm", default_area))
		})

	if candidates.is_empty():
		return {}

	candidates.sort_custom(func(a, b): return a["dev_score"] < b["dev_score"])
	return candidates[0]

## Calculates the true minimum distance from a point to the nearest perimeter edge of a district block
static func distance_to_district_edge(from_pos: Vector2, district_data: Dictionary) -> float:
	var center: Vector2 = _resolve_vector2(district_data.get("spatial_anchor", district_data.get("center", Vector2.ZERO)))
	
	var cfg = ScenarioManifestManager.get_city_configuration()
	var default_half: float = (float(cfg.get("block_size")) * 0.5) if (cfg and "block_size" in cfg) else 100.0
	var half_w: float = default_half
	var half_h: float = default_half

	if district_data.has("size"):
		var sz = district_data["size"]
		if sz is Array and sz.size() >= 2:
			half_w = float(sz[0]) * 0.5
			half_h = float(sz[1]) * 0.5
		elif sz is Vector2:
			half_w = sz.x * 0.5
			half_h = sz.y * 0.5

	var closest_x: float = clampf(from_pos.x, center.x - half_w, center.x + half_w)
	var closest_z: float = clampf(from_pos.y, center.y - half_h, center.y + half_h)
	return from_pos.distance_to(Vector2(closest_x, closest_z))

## Matches a resident to the nearest available establishment in by_cat[category]
static func pick_nearest_anchor(by_cat: Dictionary, requested_category: String, resident_pos: Vector2, districts: Dictionary) -> int:
	var list: Array = by_cat.get(requested_category, [])
	if list.is_empty():
		list = by_cat.get("COMMERCIAL", [])
	if list.is_empty():
		return 1

	var best_id: int = int(list[0]["id"])
	var best_dist: float = 1e12

	for item in list:
		var est_dist_id: String = str(item.get("district_id", ""))
		var est_pos: Vector2 = Vector2.ZERO
		if districts.has(est_dist_id):
			est_pos = _resolve_vector2(districts[est_dist_id].get("spatial_anchor", Vector2.ZERO))
		
		var d: float = resident_pos.distance_to(est_pos)
		if d < best_dist:
			best_dist = d
			best_id = int(item["id"])

	return best_id

static func is_education_eligible(citizen_edu: String, required_edu: String) -> bool:
	var citizen_rank: int = int(EDU_TIER_RANK.get(citizen_edu, 0))
	var required_rank: int = int(EDU_TIER_RANK.get(required_edu, 0))
	return citizen_rank >= required_rank

## Samples candidate job slots and picks one using education qualification and optional commute distance decay
static func pick_commute_matched_slot(
	slots_array: Array,
	worker_home_pos: Vector2,
	citizen_edu_code: String,
	districts: Dictionary,
	job_defs: Dictionary,
	rng: RandomNumberGenerator,
	enable_commute_decay: bool = true,
	sample_size: int = 20
) -> Dictionary:
	if slots_array.is_empty():
		return {}

	var candidates: Array[Dictionary] = []
	var candidate_indices: Array[int] = []

	var attempts := 0
	var max_scan: int = mini(slots_array.size(), 80)

	if slots_array.size() <= max_scan:
		for i in range(slots_array.size()):
			var s: Dictionary = slots_array[i]
			var req_edu: String = str(s.get("edu_req", "NO_FORMAL"))
			if is_education_eligible(citizen_edu_code, req_edu):
				candidates.append(s)
				candidate_indices.append(i)
	else:
		var picked_set := {}
		while candidates.size() < sample_size and attempts < max_scan:
			attempts += 1
			var idx: int = rng.randi() % slots_array.size()
			if not picked_set.has(idx):
				picked_set[idx] = true
				var s: Dictionary = slots_array[idx]
				var req_edu: String = str(s.get("edu_req", "NO_FORMAL"))
				if is_education_eligible(citizen_edu_code, req_edu):
					candidates.append(s)
					candidate_indices.append(idx)

	if candidates.is_empty():
		var start_offset: int = rng.randi() % slots_array.size()
		for offset in range(mini(slots_array.size(), 100)):
			var i: int = (start_offset + offset) % slots_array.size()
			var s: Dictionary = slots_array[i]
			var req_edu: String = str(s.get("edu_req", "NO_FORMAL"))
			if is_education_eligible(citizen_edu_code, req_edu):
				candidates.append(s)
				candidate_indices.append(i)
				if candidates.size() >= sample_size:
					break

	if candidates.is_empty():
		return {}

	if not enable_commute_decay:
		var pick_idx: int = rng.randi() % candidate_indices.size()
		var chosen_slot_global_idx: int = candidate_indices[pick_idx]
		var chosen_slot: Dictionary = slots_array[chosen_slot_global_idx]
		slots_array.remove_at(chosen_slot_global_idx)
		return chosen_slot

	var weights: Array[float] = []
	var total_weight: float = 0.0

	for slot in candidates:
		var job_code: String = str(slot.get("role", ""))
		var master_job: Dictionary = job_defs.get(job_code, {})
		var max_commute: float = float(master_job.get("max_commute", master_job.get("max_commute_m", 3000.0)))

		var est_dist_id: String = str(slot.get("district_id", ""))
		var d: float = 0.0
		if districts.has(est_dist_id):
			d = distance_to_district_edge(worker_home_pos, districts[est_dist_id])

		var w: float = 1.0
		if d <= max_commute:
			w = exp(-1.2 * (d / max(100.0, max_commute)))
		else:
			var excess_ratio: float = (d - max_commute) / max(100.0, max_commute)
			w = 0.02 * exp(-3.0 * excess_ratio)

		weights.append(w)
		total_weight += w

	var roll: float = rng.randf() * max(0.0001, total_weight)
	var accum: float = 0.0
	var chosen_candidate_idx: int = 0

	for i in range(weights.size()):
		accum += weights[i]
		if roll <= accum:
			chosen_candidate_idx = i
			break

	var chosen_slot_global_idx: int = candidate_indices[chosen_candidate_idx]
	var chosen_slot: Dictionary = slots_array[chosen_slot_global_idx]

	slots_array.remove_at(chosen_slot_global_idx)
	return chosen_slot