# res://systems/spatial_demand_resolver.gd
class_name SpatialDemandResolver
extends RefCounted

## Evaluates whether an additional facility/tenancy can be supported at 'center_pos'
static func is_catchment_viable(
	center_pos: Vector2,
	existing_instance_positions: Array,
	districts: Dictionary,
	block_estimates: Dictionary,
	travel_dist_m: float,
	pop_ratio: float
) -> bool:
	# 1. Count how many of THIS same facility exist within travel catchment
	var existing_count: int = 0
	for p in existing_instance_positions:
		if (p as Vector2).distance_to(center_pos) <= travel_dist_m:
			existing_count += 1

	# If none exist nearby, it is always viable
	if existing_count == 0:
		return true

	# 2. Sum resident population living within this catchment radius
	var local_pop: float = 0.0
	for d_id in districts.keys():
		var d_pos = _resolve_vector2(districts[d_id].get("spatial_anchor", Vector2.ZERO))
		if center_pos.distance_to(d_pos) <= travel_dist_m:
			local_pop += float(block_estimates.get(d_id, 0.0))

	# 3. Viable if local population supports (N + 1) facilities
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
	# var req_sqm: float = float(spec.get("footprint_sqm", 1600.0))
	var travel_dist: float = float(spec.get("travel_dist_m", 750.0))
	var pop_ratio: float = float(spec.get("pop_ratio", 1500.0))
	var min_sep: float = float(spec.get("min_sep_m", 0.0))
	var dist_range: Array = spec.get("norm_dist_range", [0.0, 1.0])
	var allowed_sectors: Array = spec.get("allowed_sectors", [])
	var forbidden_types: Array = spec.get("forbidden_types", [])
	var prefer_vacant: bool = bool(spec.get("prefer_vacant", true))
	var type_code: String = str(spec.get("code", ""))

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var sector: String = str(d.get("initial_sector", d.get("sector_class", ""))).to_upper()

		# Filter forbidden types / already repurposed blocks
		if dtype in forbidden_types or bool(d.get("is_repurposed_civic", false)):
			continue
		if not allowed_sectors.is_empty() and not allowed_sectors.has(sector):
			continue
		if d.has("embedded_civics") and type_code in d["embedded_civics"]:
			continue

		var center: Vector2 = _resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		var norm_d: float = center.length() / max(1.0, max_city_radius_m)
		if norm_d < float(dist_range[0]) or norm_d > float(dist_range[1]):
			continue

		# Physical separation check (if specified)
		if min_sep > 0.0:
			var too_close := false
			for c in placed_coords_for_this_type:
				if center.distance_to(c) < min_sep:
					too_close = true
					break
			if too_close:
				continue

		# Catchment Population Check (Unified Demand Rule)
		if not is_catchment_viable(center, placed_coords_for_this_type, districts, block_estimates, travel_dist, pop_ratio):
			continue

		# Scoring: Vacant plots get top priority (-1000.0)
		var is_vacant: bool = bool(d.get("is_initially_vacant", false)) or int(d.get("actual_building_count", 0)) == 0
		var b_count: int = int(d.get("actual_building_count", 0))
		var est_p: float = float(block_estimates.get(dist_id, 0.0))
		var dev_score: float = -1000.0 if (is_vacant and prefer_vacant) else (float(b_count * 10) + est_p)

		candidates.append({
			"dist_id": dist_id,
			"dev_score": dev_score,
			"center": center,
			"is_vacant": is_vacant,
			"est_pop": est_p,
			"area_sqm": float(d.get("area_sqm", 40000.0))
		})

	if candidates.is_empty():
		return {}

	# Lowest development score wins
	candidates.sort_custom(func(a, b): return a["dev_score"] < b["dev_score"])
	return candidates[0]


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

## Samples candidate job slots and picks one using probabilistic distance decay relative to max_commute
static func pick_commute_matched_slot(
	slots_array: Array,
	worker_home_pos: Vector2,
	districts: Dictionary,
	job_defs: Dictionary,
	rng: RandomNumberGenerator,
	sample_size: int = 15
) -> Dictionary:
	if slots_array.is_empty():
		return {}

	# If pool is small, evaluate all; otherwise sample a diverse subset for performance
	var candidates: Array[Dictionary] = []
	var candidate_indices: Array[int] = []

	if slots_array.size() <= sample_size:
		for i in range(slots_array.size()):
			candidates.append(slots_array[i])
			candidate_indices.append(i)
	else:
		# Sample distinct random candidates
		var picked_set := {}
		var attempts := 0
		while candidates.size() < sample_size and attempts < sample_size * 3:
			attempts += 1
			var idx: int = rng.randi() % slots_array.size()
			if not picked_set.has(idx):
				picked_set[idx] = true
				candidates.append(slots_array[idx])
				candidate_indices.append(idx)

	# Calculate distance weights
	var weights: Array[float] = []
	var total_weight: float = 0.0

	for slot in candidates:
		var job_code: String = str(slot.get("role", ""))
		var master_job: Dictionary = job_defs.get(job_code, {})
		var max_commute: float = float(master_job.get("max_commute", master_job.get("max_commute_m", 3000.0)))
		
		# Resolve employer establishment location
		var est_dist_id: String = str(slot.get("district_id", ""))
		var job_pos: Vector2 = worker_home_pos
		if districts.has(est_dist_id):
			job_pos = _resolve_vector2(districts[est_dist_id].get("spatial_anchor", Vector2.ZERO))

		var d: float = worker_home_pos.distance_to(job_pos)
		
		# Distance decay weight
		var w: float = 1.0
		if d <= max_commute:
			# Normal decay: closer is favored, but not absolute closest
			w = exp(-1.2 * (d / max(100.0, max_commute)))
		else:
			# Rare outlier: steep penalty for exceeding max commute
			var excess_ratio: float = (d - max_commute) / max(100.0, max_commute)
			w = 0.02 * exp(-3.0 * excess_ratio)

		weights.append(w)
		total_weight += w

	# Roulette wheel selection
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

	# Remove the claimed slot from the open ledger
	slots_array.remove_at(chosen_slot_global_idx)
	return chosen_slot