# res://systems/society/parcel_civic_planner.gd
class_name ParcelCivicPlanner
extends RefCounted

const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

## Pass 0.5: Precalculates surface area, typical building sizes, initial vacancy, and population bounds
static func precalculate_district_metrics(world_state: Dictionary, archetypes: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var cfg = ScenarioManifestManager.get_city_configuration()
	var std_w: float = float(cfg.get("block_size")) if (cfg and "block_size" in cfg) else 200.0
	var std_h: float = std_w
	var std_lot_sqm: float = std_w * std_h

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var arch: Dictionary = archetypes.get(dtype, {})

		var area_sqm: float = get_district_area_sqm(d, archetypes)
		d["area_sqm"] = area_sqm

		# Dedicated institutional anchors preserve authored capacity
		if arch.get("sector_class", "") == "CIVIC" or arch.get("is_unique_anchor", false):
			d["actual_building_count"] = 1
			d["avg_bldg_sqm"] = area_sqm
			d["building_allocations"] = []
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = int(arch.get("population_range", [0, 0])[0])
			d["expected_pop_min"] = d["estimated_population"]
			d["expected_pop_max"] = d["estimated_population"]
			d["is_initially_vacant"] = false
			continue

		# 8% to 10% Initial Vacancy Roll for Civic Demand Absorption
		var is_vacant_roll: bool = (rng.randf() < 0.09)
		if is_vacant_roll and arch.get("sector_class", "") != "CIVIC" and not arch.get("is_unique_anchor", false):
			d["is_initially_vacant"] = true
			d["initial_sector"] = str(arch.get("sector_class", "RESIDENTIAL"))
			d["actual_building_count"] = 0
			d["avg_bldg_sqm"] = 800.0
			d["building_allocations"] = []
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = 0
			d["expected_pop_min"] = 0
			d["expected_pop_max"] = 0
			continue

		d["is_initially_vacant"] = false
		d["initial_sector"] = str(arch.get("sector_class", "RESIDENTIAL"))

		var area_ratio: float = area_sqm / std_lot_sqm
		var base_pop_range: Array = arch.get("population_range", [0, 0])
		d["expected_pop_min"] = int(round(float(base_pop_range[0]) * area_ratio))
		d["expected_pop_max"] = int(round(float(base_pop_range[1]) * area_ratio))

		# Scale building footprint appropriately
		var base_footprint_sqm: float = float(arch.get("footprint_size", 1600.0))
		var b_range: Array = arch.get("buildings", [2, 4])
		var rolled_bldgs_for_base: int = rng.randi_range(int(b_range[0]), int(b_range[1]))
		var avg_bldg_sqm: float = maxf(50.0, base_footprint_sqm / float(maxi(1, rolled_bldgs_for_base)))
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
		d["estimated_population"] = int(round(float(sum_hab) * 2.6))

## Calculates the initial macro expected population of the city before civics are allocated
static func calculate_city_expected_population(world_state: Dictionary, archetypes: Dictionary) -> float:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return 0.0

	var cfg = ScenarioManifestManager.get_city_configuration()
	var std_w: float = float(cfg.get("block_size")) if (cfg and "block_size" in cfg) else 200.0
	var std_h: float = std_w
	var base_block_area_sqm: float = std_w * std_h
	var hectare_factor: float = base_block_area_sqm / 10000.0

	var setup: Dictionary = archetypes.get("setup", {})
	var overall_density: float = float(setup.get("default_overall_10000m2_pop_density_estimate", 75.0))
	var res_density: float = float(setup.get("default_residential_10000m2_pop_density_estimate", 125.0))
	var com_density: float = float(setup.get("default_commercial_10000m2_pop_density_estimate", 60.0))
	var ind_density: float = float(setup.get("default_industrial_10000m2_pop_density_estimate", 5.0))

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

	# Calculate initial baseline macro population before any civics are carved out
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

	var civic_rules: Array[Dictionary] = _harvest_all_civic_rules(archetypes)
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
			quota = maxi(1, int(round((total_city_est_pop / pop_ratio) * rng.randf_range(0.90, 1.10))))
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
			var host_area: float = float(chosen.get("area_sqm", 40000.0))

			# Case A: Facility exceeds single parcel area -> Amass contiguous blocks
			if req_footprint > (host_area * 1.05):
				var consolidated_ids: Array[String] = _amass_contiguous_blocks(districts, dist_id, req_footprint, archetypes)
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

				multi_block_count += 1
				placed += 1
				placed_by_type[code].append(chosen["center"])

			# Case B: True Whole Block Campus (Footprint is 70% to 105% of parcel or chosen parcel is vacant)
			elif chosen["is_vacant"] or req_footprint >= (host_area * 0.70):
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

	_reclassify_surplus_vacant_parcels(districts)
	_log_civic_cadence_audit(audit_stats, total_city_est_pop)

## Amasses adjacent orthogonal districts until the cumulative area satisfies target_sqm
static func _amass_contiguous_blocks(districts: Dictionary, seed_dist_id: String, target_sqm: float, archetypes: Dictionary) -> Array[String]:
	var seed_d: Dictionary = districts[seed_dist_id]
	var seed_coords: Vector2i = seed_d.get("grid_coords", Vector2i(0, 0))
	var gathered_ids: Array[String] = [seed_dist_id]
	var accumulated_sqm: float = float(seed_d.get("area_sqm", 40000.0))

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

			# Never absorb existing landmarks, dedicated civic institutions, or already repurposed civics
			if n_arch.get("sector_class", "") == "CIVIC" or n_arch.get("is_unique_anchor", false) or bool(nd.get("is_repurposed_civic", false)):
				continue

			gathered_ids.append(n_id)
			accumulated_sqm += float(nd.get("area_sqm", 40000.0))
			queue.append(next_coord)

			if accumulated_sqm >= target_sqm:
				break

	# Mark absorbed satellite blocks as non-zoned complex grounds
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

	# Handle case where the block was initially vacant
	if bool(chosen_d.get("is_initially_vacant", false)) or int(chosen_d.get("actual_building_count", 0)) == 0:
		chosen_d["is_initially_vacant"] = false
		chosen_d["is_repurposed_civic"] = false
		
		var host_sector: String = str(chosen_d.get("initial_sector", "RESIDENTIAL")).to_upper()
		var setup: Dictionary = archetypes.get("setup", {})
		var fallback_type: String = str(setup.get("default_fallback_archetype", "medium_density_residential"))

		for a_key in archetypes.keys():
			if a_key in ["_meta", "setup"]:
				continue
			var cand_arch: Dictionary = archetypes[a_key]
			if str(cand_arch.get("sector_class", "")).to_upper() == host_sector and not cand_arch.has("spatial_rules"):
				fallback_type = a_key
				break

		var arch: Dictionary = archetypes.get(fallback_type, {})
		var area_sqm: float = float(chosen_d.get("area_sqm", 40000.0))
		var rem_area: float = maxf(100.0, area_sqm - float(spec.get("footprint_sqm", 1600.0)))
		var avg_bldg: float = 800.0
		var surround_bldgs: int = maxi(1, int(round(rem_area / avg_bldg)))

		chosen_d["actual_building_count"] = surround_bldgs + 1
		chosen_d["avg_bldg_sqm"] = avg_bldg

		var perc_arr: Array = arch.get("res_com_ind_perc", [100, 0, 0])
		var hab_range: Array = arch.get("habitable_units_per_building", [2, 4])
		var comm_range: Array = arch.get("commercial_units_per_building", [0, 1])
		var ind_range: Array = arch.get("industrial_units_per_building", [0, 0])

		var allocations: Array[Dictionary] = []
		var sum_hab := 0
		var sum_comm := 0
		var sum_ind := 0

		for b_idx in range(surround_bldgs):
			var b_hab := 0
			var b_comm := 0
			var b_ind := 0

			if (rng.randf() * 100.0) < float(perc_arr[0]):
				b_hab = rng.randi_range(int(hab_range[0]), int(hab_range[1]))
			if (rng.randf() * 100.0) < float(perc_arr[1]):
				b_comm = rng.randi_range(int(comm_range[0]), int(comm_range[1]))
			if (rng.randf() * 100.0) < float(perc_arr[2]):
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

		chosen_d["building_allocations"] = allocations
		chosen_d["total_habitable_units"] = sum_hab
		chosen_d["total_commercial_units"] = sum_comm
		chosen_d["total_industrial_units"] = sum_ind
		chosen_d["estimated_population"] = int(round(float(sum_hab) * 2.6))
		block_estimates[chosen_d.get("district_id", "")] = chosen_d["estimated_population"]
		return

	# Handle case where block is already built
	var req_sqm: float = float(spec.get("footprint_sqm", 1600.0))
	var avg_bldg_sqm: float = float(chosen_d.get("avg_bldg_sqm", 800.0))
	var cur_bldgs: int = int(chosen_d.get("actual_building_count", 1))

	var bldgs_consumed: int = maxi(1, int(round(req_sqm / avg_bldg_sqm)))
	bldgs_consumed = mini(bldgs_consumed, maxi(1, int(cur_bldgs * 0.25)))

	var allocations: Array = chosen_d.get("building_allocations", [])
	var fraction_lost: float = float(bldgs_consumed) / float(maxi(1, cur_bldgs))

	var total_hab: int = int(chosen_d.get("total_habitable_units", 0))
	var total_comm: int = int(chosen_d.get("total_commercial_units", 0))
	var total_ind: int = int(chosen_d.get("total_industrial_units", 0))

	chosen_d["total_habitable_units"] = maxi(0, total_hab - int(round(float(total_hab) * fraction_lost)))
	chosen_d["total_commercial_units"] = maxi(0, total_comm - int(round(float(total_comm) * fraction_lost)))
	chosen_d["total_industrial_units"] = maxi(0, total_ind - int(round(float(total_ind) * fraction_lost)))

	for _k in range(bldgs_consumed):
		if not allocations.is_empty():
			allocations.pop_back()

	chosen_d["actual_building_count"] = allocations.size()

	var pop_lost: float = float(chosen_d.get("estimated_population", 0.0)) * fraction_lost
	total_city_est_pop = max(0.0, total_city_est_pop - pop_lost)
	chosen_d["estimated_population"] = max(0.0, float(chosen_d.get("estimated_population", 0.0)) - pop_lost)
	block_estimates[chosen_d.get("district_id", "")] = chosen_d["estimated_population"]

## Harvests all civic and institutional rules declaring spatial_rules
static func _harvest_all_civic_rules(archetypes: Dictionary) -> Array[Dictionary]:
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

		rules.append({
			"code": arch_key,
			"placement_mode": mode,
			"pop_ratio": p_ratio,
			"max_per_city": max_c,
			"min_pop": min_p,
			"travel_dist_m": float(sp_rules.get("travel_dist_m", sp_rules.get("min_sep_m", 750.0))),
			"min_sep_m": float(sp_rules.get("min_sep_m", 0.0)),
			"footprint_sqm": float(arch.get("footprint_size", arch.get("footprint_sqm", 40000.0))),
			"norm_dist_range": sp_rules.get("norm_distance_range", [0.0, 1.0]),
			"allowed_sectors": allowed_sec,
			"repel_sectors": sp_rules.get("repel_sectors", []),
			"forbidden_types": sp_rules.get("forbidden_types", []),
			"prefer_vacant": true
		})

	# Sort rules: multi-block & large facilities first (Town Hall, Hospital, Campus, Automotive)
	# then medium institutions, then cadence neighborhood civics (Primary, Church)
	rules.sort_custom(func(a, b):
		return float(a["footprint_sqm"]) > float(b["footprint_sqm"])
	)

	return rules

static func _reclassify_surplus_vacant_parcels(districts: Dictionary) -> void:
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
			d["actual_building_count"] = 1
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = 0
			d["building_allocations"] = []
			count += 1

	if count > 0:
		SystemLogger.log_info("  ✓ Reassigned %d surplus vacant parcels to allotments/cleared sites/scrap sidings." % count)

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
	var cfg = ScenarioManifestManager.get_city_configuration()
	var std_w: float = float(cfg.get("block_size")) if (cfg and "block_size" in cfg) else 200.0
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