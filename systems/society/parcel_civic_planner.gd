# res://systems/society/parcel_civic_planner.gd
class_name ParcelCivicPlanner
extends RefCounted

const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

## Extracts and validates mandatory parcel setup parameters from archetypes["setup"]
static func _get_parcel_setup(archetypes: Dictionary) -> Dictionary:
	assert(archetypes.has("setup") and archetypes["setup"] is Dictionary,
		"FATAL: [ParcelCivicPlanner] 'archetypes' module missing mandatory 'setup' section.")
	var setup: Dictionary = archetypes["setup"]
	for req_key in [
		"initial_vacant_roll_probability",
		"vacant_avg_bldg_sqm",
		"persons_per_habitable_unit",
		"min_building_footprint_sqm",
		"default_building_footprint_sqm",
		"multi_block_area_threshold_ratio",
		"whole_block_campus_min_ratio",
		"sub_block_max_carveout_ratio",
		"quota_variance_range",
		"default_travel_dist_m"
	]:
		assert(setup.has(req_key), "FATAL: [ParcelCivicPlanner] archetypes['setup'] missing mandatory key '%s'." % req_key)
	return setup

## Resolves standard city block area (sqm) strictly from city_configuration (fail-loud if unconfigured)
static func _get_standard_block_area_sqm() -> float:
	var cfg = MANIFEST_MGR.get_city_configuration()
	assert(cfg != null and "block_size" in cfg,
		"FATAL: [ParcelCivicPlanner] City configuration missing mandatory 'block_size'.")
	var block_w: float = float(cfg.get("block_size"))
	assert(block_w > 0.0, "FATAL: [ParcelCivicPlanner] City configuration 'block_size' must be positive.")
	return block_w * block_w

## Loads building_classes module and resolves an establishment's footprint_sqm by category key
static func _resolve_establishment_footprint_sqm(arch: Dictionary, fallback_arch_key: String, building_classes: Dictionary) -> float:
	var cat_name: String = str(arch.get("establishment_category", fallback_arch_key.to_upper())).strip_edges().to_upper()
	var class_def: Dictionary = _lookup_building_class(building_classes, cat_name)
	if class_def.has("footprint_sqm"):
		return float(class_def["footprint_sqm"])
	if arch.has("footprint_size"):
		return float(arch["footprint_size"])
	assert(building_classes.has("default_footprint_sqm"),
		"FATAL: [ParcelCivicPlanner] Neither class '%s', archetype '%s', nor building_classes['default_footprint_sqm'] defines a footprint." % [cat_name, fallback_arch_key])
	return float(building_classes["default_footprint_sqm"])

static func _lookup_building_class(building_classes: Dictionary, cat_name: String) -> Dictionary:
	for group_key in ["civic_tenants", "commercial_tenants", "industrial_tenants"]:
		var group = building_classes.get(group_key, {})
		if group is Dictionary and group.has(cat_name) and group[cat_name] is Dictionary:
			return group[cat_name]
	if building_classes.has(cat_name) and building_classes[cat_name] is Dictionary:
		return building_classes[cat_name]
	return {}

## Pass 0.5: Precalculates surface area, typical building sizes, initial vacancy, leftover area, and population bounds
static func precalculate_district_metrics(world_state: Dictionary, archetypes: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var setup: Dictionary = _get_parcel_setup(archetypes)
	var std_lot_sqm: float = _get_standard_block_area_sqm()
	var building_classes: Dictionary = MANIFEST_MGR.load_module("building_classes") if MANIFEST_MGR.has_module("building_classes") else {}

	var vacant_prob: float = float(setup["initial_vacant_roll_probability"])
	var vacant_avg_bldg: float = float(setup["vacant_avg_bldg_sqm"])
	var persons_per_unit: float = float(setup["persons_per_habitable_unit"])
	var min_bldg_sqm: float = float(setup["min_building_footprint_sqm"])
	var default_bldg_sqm: float = float(setup["default_building_footprint_sqm"])

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		assert(archetypes.has(dtype), "FATAL: [ParcelCivicPlanner] District '%s' has unknown archetype '%s'." % [dist_id, dtype])
		var arch: Dictionary = archetypes[dtype]

		var area_sqm: float = get_district_area_sqm(d, archetypes)
		d["area_sqm"] = area_sqm

		# Dedicated institutional anchors preserve building_classes footprint and allocate leftover area per setup mode
		if arch.get("sector_class", "") == "CIVIC" or arch.get("is_unique_anchor", false):
			var anchor_footprint: float = minf(area_sqm, _resolve_establishment_footprint_sqm(arch, dtype, building_classes))
			d["actual_building_count"] = 1
			d["avg_bldg_sqm"] = anchor_footprint
			d["building_allocations"] = []
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			var pop_rng: Array = arch.get("population_range", [0, 0])
			d["estimated_population"] = int(pop_rng[0])
			d["expected_pop_min"] = d["estimated_population"]
			d["expected_pop_max"] = d["estimated_population"]
			d["is_initially_vacant"] = false
			_apply_leftover_area_allocation(d, arch, archetypes, anchor_footprint)
			continue

		# Config-driven Initial Vacancy Roll for Civic Demand Absorption
		var is_vacant_roll: bool = (rng.randf() < vacant_prob)
		if is_vacant_roll and arch.get("sector_class", "") != "CIVIC" and not arch.get("is_unique_anchor", false):
			d["is_initially_vacant"] = true
			d["initial_sector"] = str(arch.get("sector_class", "RESIDENTIAL"))
			d["actual_building_count"] = 0
			d["avg_bldg_sqm"] = vacant_avg_bldg
			d["building_allocations"] = []
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = 0
			d["expected_pop_min"] = 0
			d["expected_pop_max"] = 0
			d["built_sqm"] = 0.0
			d["vacant_sqm"] = area_sqm
			continue

		d["is_initially_vacant"] = false
		d["initial_sector"] = str(arch.get("sector_class", "RESIDENTIAL"))

		var area_ratio: float = area_sqm / std_lot_sqm
		var base_pop_range: Array = arch.get("population_range", [0, 0])
		d["expected_pop_min"] = int(round(float(base_pop_range[0]) * area_ratio))
		d["expected_pop_max"] = int(round(float(base_pop_range[1]) * area_ratio))

		# Scale building footprint appropriately
		var base_footprint_sqm: float = float(arch.get("footprint_size", default_bldg_sqm))
		var b_range: Array = arch.get("buildings", [1, 1])
		var rolled_bldgs_for_base: int = rng.randi_range(int(b_range[0]), int(b_range[1]))
		var avg_bldg_sqm: float = maxf(min_bldg_sqm, base_footprint_sqm / float(maxi(1, rolled_bldgs_for_base)))
		d["avg_bldg_sqm"] = avg_bldg_sqm

		var total_buildings: int = maxi(1, int(round(area_sqm / avg_bldg_sqm)))
		d["actual_building_count"] = total_buildings

		# Per-building independent tenancy allocation
		var perc_arr: Array = arch.get("res_com_ind_perc", [100, 0, 0])
		var r_chance: float = float(perc_arr[0])
		var c_chance: float = float(perc_arr[1])
		var i_chance: float = float(perc_arr[2])

		var hab_range: Array = arch.get("habitable_units_per_building", [0, 0])
		var comm_range: Array = arch.get("commercial_units_per_building", [0, 0])
		var ind_range: Array = arch.get("industrial_units_per_building", [0, 0])

		var allocations: Array[Dictionary] = []
		var sum_hab := 0
		var sum_comm := 0
		var sum_ind := 0

		for b_idx in range(total_buildings):
			var b_hab := 0
			var b_comm := 0
			var b_ind := 0

			if (rng.randf() * 100.0) < r_chance and hab_range[1] > 0:
				b_hab = rng.randi_range(int(hab_range[0]), int(hab_range[1]))
			if (rng.randf() * 100.0) < c_chance and comm_range[1] > 0:
				b_comm = rng.randi_range(int(comm_range[0]), int(comm_range[1]))
			if (rng.randf() * 100.0) < i_chance and ind_range[1] > 0:
				b_ind = rng.randi_range(int(ind_range[0]), int(ind_range[1]))

			sum_hab += b_hab
			sum_comm += b_comm
			sum_ind += b_ind

			allocations.append({
				"building_index": b_idx,
				"habitable_units": b_hab,
				"commercial_units": b_comm,
				"industrial_units": b_ind
			})

		d["building_allocations"] = allocations
		d["total_habitable_units"] = sum_hab
		d["total_commercial_units"] = sum_comm
		d["total_industrial_units"] = sum_ind
		d["estimated_population"] = int(round(float(sum_hab) * persons_per_unit))
		var initial_built_sqm: float = minf(area_sqm, float(total_buildings) * avg_bldg_sqm)
		_apply_leftover_area_allocation(d, arch, archetypes, initial_built_sqm)

## Calculates the initial macro expected population of the city before civics are allocated
static func calculate_city_expected_population(world_state: Dictionary, archetypes: Dictionary) -> float:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return 0.0

	var base_block_area_sqm: float = _get_standard_block_area_sqm()
	var hectare_factor: float = base_block_area_sqm / 10000.0

	var setup: Dictionary = _get_parcel_setup(archetypes)
	var overall_density: float = float(setup["default_overall_10000m2_pop_density_estimate"])
	var res_density: float = float(setup["default_residential_10000m2_pop_density_estimate"])
	var com_density: float = float(setup["default_commercial_10000m2_pop_density_estimate"])
	var ind_density: float = float(setup["default_industrial_10000m2_pop_density_estimate"])

	var res_blocks := 0
	var com_blocks := 0
	var ind_blocks := 0
	var total_active_blocks := 0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var arch: Dictionary = archetypes.get(dtype, {})
		var sector: String = str(arch.get("sector_class", d.get("initial_sector", ""))).to_upper()

		total_active_blocks += 1
		match sector:
			"RESIDENTIAL":
				res_blocks += 1
			"COMMERCIAL":
				com_blocks += 1
			"INDUSTRIAL":
				ind_blocks += 1
			_:
				res_blocks += 1

	var total_expected_residents := 0.0
	if (res_blocks + com_blocks + ind_blocks) > 0:
		var exp_res: float = float(res_blocks) * hectare_factor * res_density
		var exp_com: float = float(com_blocks) * hectare_factor * com_density
		var exp_ind: float = float(ind_blocks) * hectare_factor * ind_density
		total_expected_residents = exp_res + exp_com + exp_ind
		SystemLogger.log_info("  [Macro Population Baseline] Sector Split Known: %d Res (%.0f pop), %d Com (%.0f pop), %d Ind (%.0f pop) | Total Est: %.0f" % [
			res_blocks, exp_res, com_blocks, exp_com, ind_blocks, exp_ind, total_expected_residents
		])
	else:
		total_expected_residents = float(total_active_blocks) * hectare_factor * overall_density
		SystemLogger.log_info("  [Macro Population Baseline] Sector Split Unknown: %d Total Blocks | Total Est: %.0f" % [
			total_active_blocks, total_expected_residents
		])

	return total_expected_residents

## Pass 1: Dynamically places all population-ratio civic facilities and absorbs vacant plots
static func run_civic_cadence_pass(world_state: Dictionary, archetypes: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var setup: Dictionary = _get_parcel_setup(archetypes)
	var std_lot_sqm: float = _get_standard_block_area_sqm()
	var building_classes: Dictionary = MANIFEST_MGR.load_module("building_classes") if MANIFEST_MGR.has_module("building_classes") else {}

	var multi_block_ratio: float = float(setup["multi_block_area_threshold_ratio"])
	var whole_block_ratio: float = float(setup["whole_block_campus_min_ratio"])
	var quota_var: Array = setup["quota_variance_range"]
	var quota_min_mult: float = float(quota_var[0])
	var quota_max_mult: float = float(quota_var[1])

	var total_city_est_pop: float = calculate_city_expected_population(world_state, archetypes)
	if total_city_est_pop <= 0.0:
		for dist_id in districts.keys():
			total_city_est_pop += float(districts[dist_id].get("estimated_population", 0.0))

	var block_estimates: Dictionary = {}
	var max_r: float = 1.0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var p: Vector2 = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		max_r = max(max_r, p.length())
		block_estimates[dist_id] = float(d.get("estimated_population", 0.0))

	var civic_rules: Array[Dictionary] = _harvest_all_civic_rules(archetypes, building_classes)
	var placed_by_type: Dictionary = {}
	var audit_stats: Array[Dictionary] = []

	for spec in civic_rules:
		var code: String = spec["code"]
		placed_by_type[code] = []

		var min_p: float = float(spec.get("min_pop", 0))
		if total_city_est_pop < min_p:
			audit_stats.append({
				"code": code,
				"mode": spec.get("placement_mode", "CADENCE"),
				"quota": 0,
				"placed": 0,
				"full_block": 0,
				"multi_block": 0,
				"sub_block": 0,
				"reason": "Below min_pop (%.0f < %.0f)" % [total_city_est_pop, min_p]
			})
			continue

		var pop_ratio: float = float(spec["pop_ratio"])
		var max_per_city: int = int(spec.get("max_per_city", 999))
		var quota: int = 1
		if pop_ratio > 0.0:
			quota = maxi(1, int(round((total_city_est_pop / pop_ratio) * rng.randf_range(quota_min_mult, quota_max_mult))))
		quota = mini(quota, max_per_city)

		var placed := 0
		var full_block_count := 0
		var multi_block_count := 0
		var sub_block_count := 0
		var req_footprint: float = float(spec["footprint_sqm"])

		for _attempt in range(quota * 25):
			if placed >= quota:
				break

			var chosen: Dictionary = SPATIAL_RESOLVER.find_best_host_district(
				districts, block_estimates, placed_by_type[code], spec, max_r
			)
			if chosen.is_empty():
				break

			var dist_id: String = chosen["dist_id"]
			var d: Dictionary = districts[dist_id]
			var host_area: float = float(chosen.get("area_sqm", std_lot_sqm))

			# Case A: Facility exceeds single parcel area -> Amass contiguous blocks
			if req_footprint > (host_area * multi_block_ratio):
				var consolidated_ids: Array[String] = _amass_contiguous_blocks(districts, dist_id, req_footprint, archetypes, std_lot_sqm)
				d["district_type"] = code
				d["is_repurposed_civic"] = true
				d["is_initially_vacant"] = false
				d["actual_building_count"] = 1
				d["building_allocations"] = []
				d["total_habitable_units"] = 0
				d["total_commercial_units"] = 0
				d["total_industrial_units"] = 0
				d["estimated_population"] = 0

				for c_id in consolidated_ids:
					total_city_est_pop = max(0.0, total_city_est_pop - float(block_estimates.get(c_id, 0.0)))
					block_estimates[c_id] = 0.0
				_apply_leftover_area_allocation(d, archetypes.get(code, {}), archetypes, req_footprint)

				multi_block_count += 1
				placed += 1
				placed_by_type[code].append(chosen["center"])

			# Case B: True Whole Block Campus (Footprint >= whole_block_ratio of parcel or chosen parcel is vacant)
			elif chosen["is_vacant"] or req_footprint >= (host_area * whole_block_ratio):
				d["district_type"] = code
				d["is_repurposed_civic"] = true
				d["is_initially_vacant"] = false
				d["actual_building_count"] = 1
				d["building_allocations"] = []
				d["total_habitable_units"] = 0
				d["total_commercial_units"] = 0
				d["total_industrial_units"] = 0
				total_city_est_pop = max(0.0, total_city_est_pop - chosen["est_pop"])
				block_estimates[dist_id] = 0.0
				d["estimated_population"] = 0
				_apply_leftover_area_allocation(d, archetypes.get(code, {}), archetypes, req_footprint)

				full_block_count += 1
				placed += 1
				placed_by_type[code].append(chosen["center"])

			# Case C: Sub-Block Facility on an active or vacant block
			else:
				_apply_sub_block_carveout(d, spec, total_city_est_pop, block_estimates, archetypes, rng)
				sub_block_count += 1
				placed += 1
				placed_by_type[code].append(chosen["center"])

		audit_stats.append({
			"code": code,
			"mode": spec.get("placement_mode", "CADENCE"),
			"quota": quota,
			"placed": placed,
			"full_block": full_block_count,
			"multi_block": multi_block_count,
			"sub_block": sub_block_count,
			"reason": "OK" if placed >= quota else "Exhausted viable candidate plots"
		})

	_reclassify_surplus_vacant_parcels(districts, std_lot_sqm)
	_log_civic_cadence_audit(audit_stats, total_city_est_pop)

## Amasses adjacent orthogonal districts until the cumulative area satisfies target_sqm
static func _amass_contiguous_blocks(
	districts: Dictionary,
	seed_dist_id: String,
	target_sqm: float,
	archetypes: Dictionary,
	std_lot_sqm: float
) -> Array[String]:
	var seed_d: Dictionary = districts[seed_dist_id]
	var seed_coords: Vector2i = seed_d.get("grid_coords", Vector2i(0, 0))
	var gathered_ids: Array[String] = [seed_dist_id]
	var accumulated_sqm: float = float(seed_d.get("area_sqm", std_lot_sqm))

	var coord_map: Dictionary = {}
	for d_id in districts.keys():
		var cd: Vector2i = districts[d_id].get("grid_coords", Vector2i(0, 0))
		coord_map[cd] = d_id

	var queue: Array[Vector2i] = [seed_coords]
	var visited: Dictionary = {seed_coords: true}
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while not queue.is_empty() and accumulated_sqm < target_sqm:
		var current: Vector2i = queue.pop_front()

		for dir in directions:
			var next_coord: Vector2i = current + dir
			if visited.has(next_coord) or not coord_map.has(next_coord):
				continue
			visited[next_coord] = true

			var n_id: String = coord_map[next_coord]
			var nd: Dictionary = districts[n_id]
			var n_type: String = str(nd.get("district_type", ""))
			var n_arch: Dictionary = archetypes.get(n_type, {})

			if n_arch.get("sector_class", "") == "CIVIC" or n_arch.get("is_unique_anchor", false) or bool(nd.get("is_repurposed_civic", false)):
				continue

			gathered_ids.append(n_id)
			accumulated_sqm += float(nd.get("area_sqm", std_lot_sqm))
			queue.append(next_coord)

			if accumulated_sqm >= target_sqm:
				break

	for i in range(1, gathered_ids.size()):
		var absorbed_id: String = gathered_ids[i]
		var ad: Dictionary = districts[absorbed_id]
		ad["is_absorbed_civic"] = true
		ad["master_civic_id"] = seed_dist_id
		ad["district_type"] = seed_d.get("district_type", "civic_grounds")
		ad["actual_building_count"] = 0
		ad["building_allocations"] = []
		ad["total_habitable_units"] = 0
		ad["total_commercial_units"] = 0
		ad["total_industrial_units"] = 0
		ad["estimated_population"] = 0
		ad["built_sqm"] = 0.0
		ad["vacant_sqm"] = float(ad.get("area_sqm", std_lot_sqm))

	seed_d["area_sqm"] = accumulated_sqm
	seed_d["amalgamated_block_count"] = gathered_ids.size()
	return gathered_ids

static func _apply_sub_block_carveout(
	chosen_d: Dictionary, 
	spec: Dictionary, 
	total_city_est_pop: float, 
	block_estimates: Dictionary, 
	archetypes: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	if not chosen_d.has("embedded_civics"):
		chosen_d["embedded_civics"] = []
	chosen_d["embedded_civics"].append(spec["code"])

	var setup: Dictionary = _get_parcel_setup(archetypes)
	var std_lot_sqm: float = _get_standard_block_area_sqm()
	var vacant_avg_bldg: float = float(setup["vacant_avg_bldg_sqm"])
	var persons_per_unit: float = float(setup["persons_per_habitable_unit"])
	var min_bldg_sqm: float = float(setup["min_building_footprint_sqm"])
	var max_carveout_ratio: float = float(setup["sub_block_max_carveout_ratio"])
	var req_sqm: float = float(spec["footprint_sqm"])
	var parcel_area_sqm: float = float(chosen_d.get("area_sqm", std_lot_sqm))

	# Handle case where the block was initially vacant
	if bool(chosen_d.get("is_initially_vacant", false)) or int(chosen_d.get("actual_building_count", 0)) == 0:
		chosen_d["is_initially_vacant"] = false
		chosen_d["is_repurposed_civic"] = false
		
		var host_sector: String = str(chosen_d.get("initial_sector", "RESIDENTIAL")).to_upper()
		var fallback_type: String = str(setup["default_fallback_archetype"])

		for a_key in archetypes.keys():
			if a_key in ["_meta", "setup"]:
				continue
			var cand_arch: Dictionary = archetypes[a_key]
			if str(cand_arch.get("sector_class", "")).to_upper() == host_sector and not cand_arch.has("spatial_rules"):
				fallback_type = a_key
				break

		var infill_arch: Dictionary = archetypes.get(fallback_type, {})
		var rem_area: float = maxf(min_bldg_sqm, parcel_area_sqm - req_sqm)
		var surround_bldgs: int = maxi(1, int(round(rem_area / vacant_avg_bldg)))

		chosen_d["actual_building_count"] = surround_bldgs + 1
		chosen_d["avg_bldg_sqm"] = vacant_avg_bldg

		var perc_arr: Array = infill_arch.get("res_com_ind_perc", [100, 0, 0])
		var hab_range: Array = infill_arch.get("habitable_units_per_building", [0, 0])
		var comm_range: Array = infill_arch.get("commercial_units_per_building", [0, 0])
		var ind_range: Array = infill_arch.get("industrial_units_per_building", [0, 0])

		var infill_allocations: Array[Dictionary] = []
		var sum_hab := 0
		var sum_comm := 0
		var sum_ind := 0

		for b_idx in range(surround_bldgs):
			var b_hab := 0
			var b_comm := 0
			var b_ind := 0

			if (rng.randf() * 100.0) < float(perc_arr[0]) and hab_range[1] > 0:
				b_hab = rng.randi_range(int(hab_range[0]), int(hab_range[1]))
			if (rng.randf() * 100.0) < float(perc_arr[1]) and comm_range[1] > 0:
				b_comm = rng.randi_range(int(comm_range[0]), int(comm_range[1]))
			if (rng.randf() * 100.0) < float(perc_arr[2]) and ind_range[1] > 0:
				b_ind = rng.randi_range(int(ind_range[0]), int(ind_range[1]))

			sum_hab += b_hab
			sum_comm += b_comm
			sum_ind += b_ind
			infill_allocations.append({
				"building_index": b_idx,
				"habitable_units": b_hab,
				"commercial_units": b_comm,
				"industrial_units": b_ind
			})

		chosen_d["building_allocations"] = infill_allocations
		chosen_d["total_habitable_units"] = sum_hab
		chosen_d["total_commercial_units"] = sum_comm
		chosen_d["total_industrial_units"] = sum_ind
		chosen_d["estimated_population"] = int(round(float(sum_hab) * persons_per_unit))
		block_estimates[chosen_d.get("district_id", "")] = chosen_d["estimated_population"]
		var total_built: float = minf(parcel_area_sqm, req_sqm + (float(surround_bldgs) * vacant_avg_bldg))
		_apply_leftover_area_allocation(chosen_d, infill_arch, archetypes, total_built)
		return

	# Handle case where block is already built
	var avg_bldg_sqm: float = float(chosen_d.get("avg_bldg_sqm", vacant_avg_bldg))
	var cur_bldgs: int = int(chosen_d.get("actual_building_count", 1))

	var bldgs_consumed: int = maxi(1, int(round(req_sqm / avg_bldg_sqm)))
	bldgs_consumed = mini(bldgs_consumed, maxi(1, int(float(cur_bldgs) * max_carveout_ratio)))

	var existing_allocations: Array = chosen_d.get("building_allocations", [])
	var fraction_lost: float = float(bldgs_consumed) / float(maxi(1, cur_bldgs))

	var total_hab: int = int(chosen_d.get("total_habitable_units", 0))
	var total_comm: int = int(chosen_d.get("total_commercial_units", 0))
	var total_ind: int = int(chosen_d.get("total_industrial_units", 0))

	chosen_d["total_habitable_units"] = maxi(0, total_hab - int(round(float(total_hab) * fraction_lost)))
	chosen_d["total_commercial_units"] = maxi(0, total_comm - int(round(float(total_comm) * fraction_lost)))
	chosen_d["total_industrial_units"] = maxi(0, total_ind - int(round(float(total_ind) * fraction_lost)))

	for _k in range(bldgs_consumed):
		if not existing_allocations.is_empty():
			existing_allocations.pop_back()

	chosen_d["actual_building_count"] = existing_allocations.size()

	var pop_lost: float = float(chosen_d.get("estimated_population", 0.0)) * fraction_lost
	total_city_est_pop = max(0.0, total_city_est_pop - pop_lost)
	chosen_d["estimated_population"] = max(0.0, float(chosen_d.get("estimated_population", 0.0)) - pop_lost)
	block_estimates[chosen_d.get("district_id", "")] = chosen_d["estimated_population"]

	var host_dtype: String = str(chosen_d.get("district_type", ""))
	var host_arch: Dictionary = archetypes.get(host_dtype, {})
	var updated_built: float = minf(parcel_area_sqm, (float(existing_allocations.size()) * avg_bldg_sqm) + req_sqm)
	_apply_leftover_area_allocation(chosen_d, host_arch, archetypes, updated_built)

## Harvests all civic and institutional rules declaring spatial_rules, resolving footprints from building_classes
static func _harvest_all_civic_rules(archetypes: Dictionary, building_classes: Dictionary) -> Array[Dictionary]:
	var setup: Dictionary = _get_parcel_setup(archetypes)
	var default_travel: float = float(setup["default_travel_dist_m"])
	var rules: Array[Dictionary] = []

	for arch_key in archetypes.keys():
		if arch_key in ["_meta", "setup"]:
			continue
		var arch: Dictionary = archetypes[arch_key]
		var sp_rules: Dictionary = arch.get("spatial_rules", {})
		if sp_rules.is_empty():
			continue

		var mode: String = str(sp_rules.get("placement_mode", "CADENCE"))
		var p_ratio: float = float(sp_rules.get("pop_ratio", 0.0))
		var max_c: int = int(sp_rules.get("max_per_city", 999))
		var min_p: int = int(sp_rules.get("min_city_population", 0))
		var allowed_sec: Array = sp_rules.get("prefer_sectors", sp_rules.get("allowed_sectors", ["RESIDENTIAL", "COMMERCIAL"]))
		var footprint: float = _resolve_establishment_footprint_sqm(arch, arch_key, building_classes)

		rules.append({
			"code": arch_key,
			"placement_mode": mode,
			"pop_ratio": p_ratio,
			"max_per_city": max_c,
			"min_pop": min_p,
			"travel_dist_m": float(sp_rules.get("travel_dist_m", sp_rules.get("min_sep_m", default_travel))),
			"min_sep_m": float(sp_rules.get("min_sep_m", 0.0)),
			"footprint_sqm": footprint,
			"norm_dist_range": sp_rules.get("norm_distance_range", [0.0, 1.0]),
			"allowed_sectors": allowed_sec,
			"repel_sectors": sp_rules.get("repel_sectors", []),
			"forbidden_types": sp_rules.get("forbidden_types", []),
			"prefer_vacant": true
		})

	rules.sort_custom(func(a, b):
		return float(a["footprint_sqm"]) > float(b["footprint_sqm"])
	)

	return rules

static func _reclassify_surplus_vacant_parcels(districts: Dictionary, std_lot_sqm: float) -> void:
	var count := 0
	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		if bool(d.get("is_initially_vacant", false)):
			var orig_sector: String = str(d.get("initial_sector", "RESIDENTIAL")).to_upper()
			match orig_sector:
				"RESIDENTIAL":
					d["district_type"] = "municipal_allotments"
				"COMMERCIAL":
					d["district_type"] = "demolition_cleared_site"
				"INDUSTRIAL":
					d["district_type"] = "railway_sidings_and_scrap"
				_:
					d["district_type"] = "municipal_allotments"
			
			d["is_initially_vacant"] = false
			d["actual_building_count"] = 0
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = 0
			d["building_allocations"] = []
			d["built_sqm"] = 0.0
			d["vacant_sqm"] = float(d.get("area_sqm", std_lot_sqm))
			count += 1

	if count > 0:
		SystemLogger.log_info("  ✓ Reassigned %d surplus vacant parcels to allotments/cleared sites/scrap sidings." % count)

## Allocates leftover square meterage when built_sqm < district area_sqm per archetypes["setup"]["leftover_area_mode"]
static func _apply_leftover_area_allocation(
	d: Dictionary,
	arch: Dictionary,
	archetypes: Dictionary,
	built_sqm: float
) -> void:
	var std_lot_sqm: float = _get_standard_block_area_sqm()
	var area_sqm: float = float(d.get("area_sqm", std_lot_sqm))
	var clamped_built: float = clampf(built_sqm, 0.0, area_sqm)
	var leftover_sqm: float = maxf(0.0, area_sqm - clamped_built)
	var setup: Dictionary = _get_parcel_setup(archetypes)
	var mode: String = str(setup.get("leftover_area_mode", "VACANT")).to_upper().strip_edges()

	d["built_sqm"] = clamped_built
	if mode == "PROPORTIONAL_SECTOR_SPLIT" and leftover_sqm > 0.0:
		var perc_arr: Array = arch.get("res_com_ind_perc", [0, 0, 0])
		var r_w: float = maxf(0.0, float(perc_arr[0])) if perc_arr.size() > 0 else 0.0
		var c_w: float = maxf(0.0, float(perc_arr[1])) if perc_arr.size() > 1 else 0.0
		var i_w: float = maxf(0.0, float(perc_arr[2])) if perc_arr.size() > 2 else 0.0
		var w_sum: float = r_w + c_w + i_w
		if w_sum > 0.0:
			var norm: float = maxf(100.0, w_sum)
			var res_extra: float = leftover_sqm * (r_w / norm)
			var com_extra: float = leftover_sqm * (c_w / norm)
			var ind_extra: float = leftover_sqm * (i_w / norm)
			d["leftover_residential_sqm"] = res_extra
			d["leftover_commercial_sqm"] = com_extra
			d["leftover_industrial_sqm"] = ind_extra
			d["vacant_sqm"] = maxf(0.0, leftover_sqm - (res_extra + com_extra + ind_extra))
			return

	d["leftover_residential_sqm"] = 0.0
	d["leftover_commercial_sqm"] = 0.0
	d["leftover_industrial_sqm"] = 0.0
	d["vacant_sqm"] = leftover_sqm

static func _log_civic_cadence_audit(audit_stats: Array[Dictionary], macro_pop: float) -> void:
	SystemLogger.log_info("\n==========================================================================================================")
	SystemLogger.log_info("                                     CIVIC PLACEMENT AUDIT REPORT                                         ")
	SystemLogger.log_info("==========================================================================================================")
	SystemLogger.log_info("  Macro City Expected Population: %.0f" % macro_pop)
	SystemLogger.log_info("  %-28s | %-16s | %-6s | %-6s | %-10s | %-11s | %-10s | %-12s" % [
		"Civic Archetype", "Mode", "Quota", "Placed", "Full-Block", "Multi-Block", "Sub-Block", "Status"
	])
	SystemLogger.log_info("  --------------------------------------------------------------------------------------------------------")

	for row in audit_stats:
		var code: String = str(row["code"])
		var mode: String = str(row["mode"])
		var quota: int = int(row["quota"])
		var placed: int = int(row["placed"])
		var fb: int = int(row["full_block"])
		var mb: int = int(row["multi_block"])
		var sb: int = int(row["sub_block"])
		var reason: String = str(row["reason"])

		SystemLogger.log_info("  %-28s | %-16s | %-6d | %-6d | %-10d | %-11d | %-10d | %-12s" % [
			code, mode, quota, placed, fb, mb, sb, reason
		])

		if placed < quota:
			SystemLogger.log_warn("  [Audit Deficit] %s fell short of quota by %d facilities (%s)" % [
				code, quota - placed, reason
			])

	SystemLogger.log_info("==========================================================================================================\n")

static func get_district_area_sqm(district: Dictionary, _archetypes: Dictionary) -> float:
	var cfg = MANIFEST_MGR.get_city_configuration()
	assert(cfg != null and "block_size" in cfg,
		"FATAL: [ParcelCivicPlanner] City configuration missing mandatory 'block_size'.")
	var std_w: float = float(cfg.get("block_size"))
	var std_h: float = std_w

	if district.has("boundary_polygon"):
		var poly: PackedVector2Array = district["boundary_polygon"]
		if poly.size() >= 3:
			var area := 0.0
			for i in range(poly.size()):
				var j := (i + 1) % poly.size()
				area += poly[i].x * poly[j].y
				area -= poly[j].x * poly[i].y
			return absf(area) * 0.5

	if district.has("size"):
		var sz = district["size"]
		if sz is Array and sz.size() >= 2:
			return float(sz[0]) * float(sz[1])
		elif sz is Vector2:
			return float(sz.x * sz.y)

	var g_size: Vector2i = district.get("grid_size", Vector2i(1, 1))
	return float(g_size.x) * std_w * float(g_size.y) * std_h