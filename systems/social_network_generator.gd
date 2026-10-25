# res://systems/social_network_generator.gd
class_name SocialNetworkGenerator
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

static var _lexicon: Dictionary = {}
static var _demographics: Dictionary = {}
static var _cultural: Dictionary = {}
static var _civic_hierarchy: Dictionary = {}
static var _archetypes: Dictionary = {}
static var _building_classes: Dictionary = {}

## Loads all required scenario modules strictly via ScenarioManifestManager
static func _load_configs() -> void:
	if not _demographics.is_empty() and not _lexicon.is_empty() and not _cultural.is_empty() and not _civic_hierarchy.is_empty() and not _archetypes.is_empty() and not _building_classes.is_empty():
		return

	_demographics = MANIFEST_MGR.load_module("demographics")
	_lexicon = MANIFEST_MGR.load_module("lexicon")
	_cultural = MANIFEST_MGR.load_module("cultural_demographics")
	_civic_hierarchy = MANIFEST_MGR.load_module("civic_hierarchy")

	assert(MANIFEST_MGR.has_module("archetypes"), "FATAL: Scenario manifest missing 'archetypes' module.")
	_archetypes = MANIFEST_MGR.load_module("archetypes")
	assert(not _archetypes.is_empty(), "FATAL: Loaded archetypes dictionary is empty.")

	assert(MANIFEST_MGR.has_module("building_classes"), "FATAL: Scenario manifest missing 'building_classes' module.")
	_building_classes = MANIFEST_MGR.load_module("building_classes")
	assert(not _building_classes.is_empty(), "FATAL: Loaded building_classes dictionary is empty.")

## Main Generation Pipeline
static func generate_city_society(world_state: Dictionary, seed_id: String, force_regenerate: bool = false, on_progress: Callable = Callable()) -> void:
	if not force_regenerate and DB_MANAGER.is_society_populated(seed_id):
		print("[SocialNetwork] Society for seed '%s' already exists in SQLite. Skipping generation." % seed_id)
		return

	_load_configs()
	DB_MANAGER.initialize_database(true)
	DB_MANAGER.record_active_seed(seed_id)

	var start_ms: int = Time.get_ticks_msec()
	print("[SocialNetwork] Commencing 4-Pass urban society generation...")

	var districts: Dictionary = world_state.get("districts", {})
	assert(not districts.is_empty(), "FATAL: world_state has no districts during society generation.")

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_id.hash())

	# -------------------------------------------------------------------------
	# PASS 0.5: PRECALCULATE DISTRICT M² METRICS & SECTOR BUILDING SLOTS
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(5.0, 100.0, "Pass 1: Generate Initial Land Parcels..")
		await Engine.get_main_loop().process_frame
	_precalculate_district_metrics(world_state, rng)

	# -------------------------------------------------------------------------
	# PASS 1: CIVIC CADENCE REALIGNMENT (Macro Parcel Repurposing)
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(10.0, 100.0, "Pass 2: Realignment of dedicated civic parcels...")
		await Engine.get_main_loop().process_frame
	_run_civic_cadence_pass(world_state, rng)

	# -------------------------------------------------------------------------
	# PASS 2: PHYSICAL PREMISES, ESTABLISHMENTS & HOUSEHOLDS
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(20.0, 100.0, "Pass 3: Populating physical premises & tenancies...")
		await Engine.get_main_loop().process_frame
	var physical_state: Dictionary = await _generate_all_premises_and_workplaces(world_state, rng, on_progress)

	# -------------------------------------------------------------------------
	# PASS 2.5: MUNICIPAL BOROUGH CLUSTERING
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(25.0, 100.0, "Pass 4: Creating Boroughs...")
		await Engine.get_main_loop().process_frame
	_cluster_districts_into_boroughs(world_state, rng)

	# -------------------------------------------------------------------------
	# PASS 3: CITIZENS, CONTRACTS & PRIMARY KINSHIP
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(50.0, 100.0, "Pass 5: Hydrating citizens into households...")
		await Engine.get_main_loop().process_frame
	await _generate_citizens_and_demographics(physical_state, rng, on_progress)

	# -------------------------------------------------------------------------
	# PASS 4: DUNBAR NETWORK EDGES (Kinship, Workplace, Parish)
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(90.0, 100.0, "Pass 6: Weaving social relationship graphs...")
		await Engine.get_main_loop().process_frame
	_generate_social_networks(physical_state, rng)

	var elapsed: int = Time.get_ticks_msec() - start_ms
	if on_progress.is_valid():
		on_progress.call(100.0, 100.0, "Living society complete in %d ms." % elapsed)
		await Engine.get_main_loop().process_frame

	print("[SocialNetwork] Generation complete across all passes in %d ms." % elapsed)

## Pass 0.5: Calculates exact m² area, building counts, and rolls independent unit quantities
## per building using res_com_ind_perc, habitable_units_per_building, etc.
static func _precalculate_district_metrics(world_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var setup: Dictionary = _archetypes.get("setup", {})
	var metrics: Dictionary = setup.get("block_metrics", {})
	var std_w: float = float(metrics.get("standard_block_width_m", 200.0))
	var std_h: float = float(metrics.get("standard_block_height_m", 200.0))
	var std_lot_sqm: float = std_w * std_h # Baseline 40,000 m²

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var arch: Dictionary = _archetypes.get(dtype, {})

		var area_sqm: float = _get_district_area_sqm(d)
		d["area_sqm"] = area_sqm

		# Dedicated institutional anchors (e.g. Hospital site, Town Hall, University)
		if arch.get("sector_class", "") == "CIVIC" or arch.get("is_unique_anchor", false):
			d["actual_building_count"] = 1
			d["avg_bldg_sqm"] = area_sqm
			d["building_allocations"] = []
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = int(arch.get("population_range", [0, 0])[0])
			continue

		# 1. Derive average footprint per building from archetype footprint_size and buildings range
		var base_footprint_sqm: float = float(arch.get("footprint_size", 1600.0))
		var b_range: Array = arch.get("buildings", [2, 4])
		var rolled_bldgs_for_base: int = rng.randi_range(int(b_range[0]), int(b_range[1]))
		var avg_bldg_sqm: float = maxf(50.0, base_footprint_sqm / float(maxi(1, rolled_bldgs_for_base)))
		d["avg_bldg_sqm"] = avg_bldg_sqm

		# 2. Derive total buildings for this district by dividing area by average building footprint
		var total_buildings: int = maxi(1, int(round(area_sqm / avg_bldg_sqm)))
		d["actual_building_count"] = total_buildings

		# 3. Independent unit evaluation per building using res_com_ind_perc & unit ranges
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

		# 4. Calculate estimated population based on total habitable units * 2.6 mean household size
		d["estimated_population"] = int(round(float(sum_hab) * 2.6))


## Pass 1: Uses estimated populations to replace the least-developed blocks with civic cadence facilities.
## If an exact footprint cannot be found, it merges adjacent low-development blocks.
## Pass 1: Uses estimated populations to place civic cadence facilities using true m² area.
## Handles sub-block replacement (reducing building counts) and multi-block neighbor merging.
static func _run_civic_cadence_pass(world_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var mean_hh_size: float = float(_demographics.get("household_occupancy_mean", 2.6))
	var block_estimates: Dictionary = {}
	var total_city_est_pop: float = 0.0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var arch: Dictionary = _archetypes.get(dtype, {})
		
		if arch.get("sector_class", "") == "CIVIC" or arch.get("is_unique_anchor", false):
			block_estimates[dist_id] = 0.0
			continue

		var b_count: int = int(d.get("actual_building_count", 1))
		var hab_range: Array = arch.get("habitable_units_per_building", [1, 2])
		var avg_units: float = (float(hab_range[0]) + float(hab_range[1])) * 0.5
		
		var est_pop: float = float(b_count) * avg_units * mean_hh_size
		block_estimates[dist_id] = est_pop
		total_city_est_pop += est_pop

	# Harvest Cadence Facilities directly from archetypes.json
	var cadence_rules: Array[Dictionary] = []
	for arch_key in _archetypes.keys():
		if arch_key in ["_meta", "setup"]:
			continue
		var arch: Dictionary = _archetypes[arch_key]
		var rules: Dictionary = arch.get("spatial_rules", {})
		if rules.get("placement_mode", "") == "CADENCE":
			cadence_rules.append({
				"type": arch_key,
				"pop_ratio": float(rules.get("pop_ratio", 2000.0)),
				"min_sep_m": float(rules.get("min_sep_m", 600.0)),
				"min_pop": int(rules.get("min_city_population", 0)),
				"footprint_sqm": float(arch.get("footprint_sqm", 40000.0)),
				"dist_range": rules.get("norm_distance_range", [0.0, 1.0])
			})

	if cadence_rules.is_empty():
		return

	var placed_civic_coords: Array[Vector2] = []
	var max_r: float = 1.0
	for dist_id in districts.keys():
		var d = districts[dist_id]
		var p: Vector2 = _resolve_spatial_vector2(d.get("spatial_anchor", Vector2.ZERO))
		max_r = max(max_r, p.length())
		var dtype: String = str(d.get("district_type", ""))
		if _archetypes.get(dtype, {}).get("sector_class", "") == "CIVIC":
			placed_civic_coords.append(p)

	var coord_to_dist_id: Dictionary = {}
	for dist_id in districts.keys():
		var gc: Vector2i = districts[dist_id].get("grid_coords", Vector2i(0, 0))
		coord_to_dist_id[gc] = dist_id

	# Evaluate each cadence institution class
	for fac in cadence_rules:
		var fac_type: String = str(fac["type"])
		var pop_ratio: float = float(fac["pop_ratio"])
		var min_sep_m: float = float(fac["min_sep_m"])
		var min_pop: int = int(fac["min_pop"])
		var req_sqm: float = float(fac["footprint_sqm"])
		var dist_range: Array = fac["dist_range"]

		if total_city_est_pop < float(min_pop):
			continue

		var demand_jitter := rng.randf_range(0.80, 1.20)
		var quota := maxi(1, int(round((total_city_est_pop / pop_ratio) * demand_jitter)))

		var placed_count := 0
		var attempts := 0
		var max_attempts := quota * 10

		while placed_count < quota and attempts < max_attempts:
			attempts += 1
			
			var candidates: Array[Dictionary] = []
			for dist_id in districts.keys():
				var d: Dictionary = districts[dist_id]
				var dtype: String = str(d.get("district_type", ""))
				var arch: Dictionary = _archetypes.get(dtype, {})
				
				if arch.get("sector_class", "") == "CIVIC" or dtype in ["industrial", "municipal_park"]:
					continue

				var center: Vector2 = _resolve_spatial_vector2(d.get("spatial_anchor", Vector2.ZERO))
				var norm_d: float = center.length() / max_r
				if norm_d < float(dist_range[0]) or norm_d > float(dist_range[1]):
					continue

				var too_close := false
				for c in placed_civic_coords:
					if center.distance_to(c) < min_sep_m:
						too_close = true
						break
				if too_close:
					continue

				var current_area: float = _get_district_area_sqm(d)
				var b_count: int = int(d.get("actual_building_count", 1))
				var est_p: float = block_estimates.get(dist_id, 0.0)
				var dev_score: float = float(b_count * 10) + est_p

				var neighbors_to_absorb: Array[String] = []
				var combined_area: float = current_area

				# If required area exceeds this block, gather contiguous orthogonal neighbors
				if combined_area < req_sqm:
					var gc: Vector2i = d.get("grid_coords", Vector2i(0, 0))
					var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
					for off in offsets:
						var check_coord: Vector2i = gc + off
						if coord_to_dist_id.has(check_coord):
							var n_id: String = coord_to_dist_id[check_coord]
							var n_d: Dictionary = districts.get(n_id, {})
							var n_dtype: String = str(n_d.get("district_type", ""))
							var n_arch: Dictionary = _archetypes.get(n_dtype, {})
							if n_arch.get("sector_class", "") != "CIVIC" and n_dtype != "industrial":
								neighbors_to_absorb.append(n_id)
								combined_area += _get_district_area_sqm(n_d)
								dev_score += float(int(n_d.get("actual_building_count", 1)) * 10)
								if combined_area >= req_sqm:
									break

				if combined_area >= req_sqm or req_sqm < current_area:
					candidates.append({
						"dist_id": dist_id,
						"dev_score": dev_score,
						"center": center,
						"est_pop": est_p,
						"current_area": current_area,
						"combined_area": combined_area,
						"neighbors": neighbors_to_absorb
					})

			if candidates.is_empty():
				break

			candidates.sort_custom(func(a, b): return a["dev_score"] < b["dev_score"])
			var chosen: Dictionary = candidates[0]
			var chosen_id: String = chosen["dist_id"]
			var chosen_d: Dictionary = districts[chosen_id]
			var block_area: float = chosen["current_area"]

			# --- SCENARIO A: Full-Block or Multi-Block Consolidation ---
			if req_sqm >= (block_area * 0.75):
				chosen_d["district_type"] = fac_type
				chosen_d["is_repurposed_civic"] = true
				total_city_est_pop = max(0.0, total_city_est_pop - chosen["est_pop"])
				block_estimates[chosen_id] = 0.0

				# Absorb neighbors if multi-block area was required
				for n_id in chosen["neighbors"]:
					if districts.has(n_id):
						var n_d: Dictionary = districts[n_id]
						total_city_est_pop = max(0.0, total_city_est_pop - block_estimates.get(n_id, 0.0))
						block_estimates.erase(n_id)
						coord_to_dist_id.erase(n_d.get("grid_coords", Vector2i(0, 0)))
						districts.erase(n_id)
						print("    ↳ Absorbed neighbor '%s' (consolidated area: %.0f m² for '%s')" % [
							n_id, chosen["combined_area"], fac_type
						])

		# --- SCENARIO B: Sub-Block Replacement (Proportional Unit Reduction) ---
			else:
				var avg_bldg_sqm: float = float(chosen_d.get("avg_bldg_sqm", 800.0))
				var bldgs_consumed: int = maxi(1, int(round(req_sqm / avg_bldg_sqm)))
				var cur_bldgs: int = int(chosen_d.get("actual_building_count", 1))
				var allocations: Array = chosen_d.get("building_allocations", [])

				# Calculate proportion of buildings removed
				var fraction_lost: float = float(bldgs_consumed) / float(maxi(1, cur_bldgs))

				var total_hab: int = int(chosen_d.get("total_habitable_units", 0))
				var total_comm: int = int(chosen_d.get("total_commercial_units", 0))
				var total_ind: int = int(chosen_d.get("total_industrial_units", 0))

				var units_lost_hab: int = int(round(float(total_hab) * fraction_lost))
				var units_lost_comm: int = int(round(float(total_comm) * fraction_lost))
				var units_lost_ind: int = int(round(float(total_ind) * fraction_lost))

				chosen_d["total_habitable_units"] = maxi(0, total_hab - units_lost_hab)
				chosen_d["total_commercial_units"] = maxi(0, total_comm - units_lost_comm)
				chosen_d["total_industrial_units"] = maxi(0, total_ind - units_lost_ind)

				# Remove the consumed building allocation entries from the district
				for _k in range(bldgs_consumed):
					if not allocations.is_empty():
						allocations.pop_back()

				chosen_d["actual_building_count"] = allocations.size()

				if not chosen_d.has("embedded_civics"):
					chosen_d["embedded_civics"] = []
				chosen_d["embedded_civics"].append(fac_type)

				# Depress estimated population proportionally
				var pop_lost: float = float(chosen_d.get("estimated_population", 0.0)) * fraction_lost
				total_city_est_pop = max(0.0, total_city_est_pop - pop_lost)
				chosen_d["estimated_population"] = max(0.0, float(chosen_d.get("estimated_population", 0.0)) - pop_lost)

				print("    ↳ Sub-block placement: '%s' consumed %d of %d buildings on '%s' [Lost -Hab: %d, -Comm: %d, -Ind: %d]" % [
					fac_type, bldgs_consumed, cur_bldgs, chosen_id, units_lost_hab, units_lost_comm, units_lost_ind
				])

			placed_civic_coords.append(chosen["center"])
			placed_count += 1

		print("  ✓ Pass 1 Cadence: Placed %d '%s' parcels (Quota: %d)" % [placed_count, fac_type, quota])

# =============================================================================
# PASS 2: PHYSICAL PREMISES, ESTABLISHMENTS & HOUSEHOLDS
# =============================================================================
static func _generate_all_premises_and_workplaces(world_state: Dictionary, rng: RandomNumberGenerator, on_progress: Callable) -> Dictionary:
	var districts: Dictionary = world_state.get("districts", {})
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var res_unit_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "RESIDENTIAL_UNIT")

	var comm_classes: Dictionary = _building_classes.get("commercial_tenants", {})
	var ind_classes: Dictionary = _building_classes.get("industrial_tenants", {})
	var embedded_civic_classes: Dictionary = _building_classes.get("civic_tenants", {})

	var dist_inserts: Array[String] = []
	var estab_inserts: Array[String] = []
	var household_inserts: Array[String] = []

	var by_cat: Dictionary = {}
	var commercial_instances_by_type: Dictionary = {}
	var generated_households: Array[Dictionary] = []
	var district_residents_map: Dictionary = {}

	var est_id: int = 1
	var current_household_id: int = 1
	var block_idx: int = 0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var district_type: String = str(d.get("district_type", ""))
		assert(_archetypes.has(district_type), "FATAL: Archetype '%s' not registered." % district_type)

		var arch: Dictionary = _archetypes[district_type]
		var coords: Vector2i = d.get("grid_coords", Vector2i(0, 0))
		var g_size: Vector2i = d.get("grid_size", Vector2i(1, 1))
		var building_count: int = int(d.get("actual_building_count", 1))
		var pop_range: Array = arch.get("population_range", [0, 0])
		var center_vec: Vector2 = _resolve_spatial_vector2(d.get("spatial_anchor", Vector2.ZERO))

		dist_inserts.append("""
			INSERT INTO districts (
				district_id, borough_id, display_name, district_type,
				grid_x, grid_z, grid_width, grid_height,
				target_building_count, expected_pop_min, expected_pop_max,
				base_unemployment_rate, base_disposable_income, base_zone_health, base_police_heat,
				is_home_turf, valid_from, valid_to, change_reason_id
			) VALUES (
				'%s', 'BOROUGH_UNASSIGNED', '%s', '%s',
				%d, %d, %d, %d,
				%d, %d, %d,
				%f, %f, %f, %f,
				0, %d, NULL, %d
			);
		""" % [
			dist_id, str(d.get("display_name", dist_id)).replace("'", "''"), district_type,
			coords.x, coords.y, g_size.x, g_size.y,
			building_count, pop_range[0], pop_range[1],
			float(d.get("unemployment_rate", 0.0)), float(d.get("avg_disposable_income", 75.0)),
			float(d.get("zone_health_index", 50.0)), float(d.get("actual_police_heat", 0.20)),
			sim_start_day, reason_world_gen_id
		])

		district_residents_map[dist_id] = []

		# 1. Dedicated Institutional Civic Anchor
		if arch.has("institution_profile"):
			var inst: Dictionary = arch["institution_profile"]
			var cat_name: String = str(arch.get("establishment_category", district_type.to_upper()))
			var display_label: String = str(arch.get("display_name", cat_name)).replace("'", "''")
			var capacity: int = int(inst.get("default_capacity", 250))
			var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_name)

			estab_inserts.append("""
				INSERT INTO establishments (
					establishment_id, district_id, building_index, unit_door_number,
					owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
				) VALUES (%d, '%s', 0, 'MAIN', 'CIVIC', '%s', %d, %d, 0, %d, NULL, %d);
			""" % [est_id, dist_id, display_label, cat_id, capacity, sim_start_day, reason_world_gen_id])

			_register_est_cat(by_cat, cat_name, est_id, dist_id)
			est_id += 1

		# 2. Sub-Block Embedded Civics placed in Pass 1
		if d.has("embedded_civics"):
			for civic_key in d["embedded_civics"]:
				var c_arch: Dictionary = _archetypes.get(civic_key, {})
				var c_inst: Dictionary = c_arch.get("institution_profile", {})
				var c_cat_name: String = str(c_arch.get("establishment_category", civic_key.to_upper()))
				var c_display: String = str(c_arch.get("display_name", c_cat_name)).replace("'", "''")
				var c_cap: int = int(c_inst.get("default_capacity", 250))
				var c_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", c_cat_name)

				estab_inserts.append("""
					INSERT INTO establishments (
						establishment_id, district_id, building_index, unit_door_number,
						owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
					) VALUES (%d, '%s', 0, 'CIVIC_PARCEL', 'CIVIC', '%s', %d, %d, 0, %d, NULL, %d);
				""" % [est_id, dist_id, c_display, c_cat_id, c_cap, sim_start_day, reason_world_gen_id])

				_register_est_cat(by_cat, c_cat_name, est_id, dist_id)
				est_id += 1

		# 3. Instantiate Units strictly from pre-calculated building_allocations
		var housing_prof: Dictionary = arch.get("housing_profile", {})
		var res_type_code: String = str(housing_prof.get("residence_type", "NONE"))
		var wealth_bracket: int = int(housing_prof.get("wealth_bracket", 2))
		var res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type_code)
		var tenure_type: String = str(housing_prof.get("tenure_type", "COUNCIL_TENANT"))

		var allocations: Array = d.get("building_allocations", [])
		for alloc in allocations:
			var b_idx: int = int(alloc["building_index"])
			var num_homes: int = int(alloc["habitable_units"])
			var num_comm: int = int(alloc["commercial_units"])
			var num_ind: int = int(alloc["industrial_units"])

			# A. Residential Units
			if num_homes > 0 and res_type_code != "NONE":
				for u_idx in range(num_homes):
					var unit_door := "Unit %d-%d" % [b_idx + 1, u_idx + 1]
					var unit_name := "%s, %s (%s)" % [unit_door, arch.get("display_name", "Parade"), dist_id]
					var is_vacant: int = 1 if (rng.randf() < 0.03) else 0

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', %d, '%s', '%s', '%s', %d, 5, %d, %d, NULL, %d);
					""" % [
						est_id, dist_id, b_idx, unit_door, tenure_type,
						unit_name.replace("'", "''"), res_unit_cat_id, is_vacant, sim_start_day, reason_world_gen_id
					])

					if is_vacant == 0:
						var culture: Dictionary = _roll_household_culture(rng, district_type)
						var eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", culture["ethnicity"])
						var religion_id: int = DB_MANAGER.get_label_id("RELIGION", culture["religion"])

						household_inserts.append("""
							INSERT INTO households (
								household_id, establishment_id, residence_type_id,
								wealth_bracket_id, local_pub_id, ethnicity_id, religion_id,
								valid_from, valid_to, change_reason_id
							) VALUES (%d, %d, %d, %d, NULL, %d, %d, %d, NULL, %d);
						""" % [
							current_household_id, est_id, res_type_id,
							wealth_bracket, eth_id, religion_id, sim_start_day, reason_world_gen_id
						])

						generated_households.append({
							"household_id": current_household_id,
							"establishment_id": est_id,
							"district_id": dist_id,
							"district_type": district_type,
							"ethnicity_id": eth_id,
							"religion_id": religion_id,
							"surnames_pool": culture["surnames_pool"],
							"unemp_rate": float(arch.get("unemployment_rate_range", [0.10, 0.15])[0])
						})
						current_household_id += 1

					est_id += 1

			# B. Commercial Units
			if num_comm > 0:
				for _c in range(num_comm):
					var tenancy: Dictionary = _pick_tenancy(rng, comm_classes, embedded_civic_classes, district_type)
					var cat_code: String = tenancy["code"]
					var display_title: String = tenancy["display_name"]
					var cap: int = int(tenancy.get("default_capacity", 20))
					var travel_dist: float = float(tenancy.get("customer_travel_distance_m", 600.0))
					var req_threshold: int = int(tenancy.get("required_customer_threshold", 100))

					var existing_in_range: int = _count_in_radius(commercial_instances_by_type, cat_code, center_vec, travel_dist)
					var req_pop: int = (existing_in_range + 1) * req_threshold
					var est_local_pop: int = int(d.get("estimated_population", 150))
					
					var is_vacant: int = 0
					if est_local_pop < req_pop and rng.randf() < 0.50:
						is_vacant = 1
						cap = 0

					var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_code)
					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', %d, 'SHOP', 'PRIVATE', '%s', %d, %d, %d, %d, NULL, %d);
					""" % [est_id, dist_id, b_idx, display_title.replace("'", "''"), cat_id, cap, is_vacant, sim_start_day, reason_world_gen_id])

					_record_comm_instance(commercial_instances_by_type, cat_code, center_vec)
					_register_est_cat(by_cat, cat_code, est_id, dist_id)
					_register_est_cat(by_cat, "COMMERCIAL", est_id, dist_id)
					est_id += 1

			# C. Industrial Units
			if num_ind > 0:
				for _i in range(num_ind):
					var ind_tenancy: Dictionary = _pick_tenancy(rng, ind_classes, {}, district_type)
					var i_code: String = ind_tenancy["code"]
					var i_title: String = ind_tenancy["display_name"]
					var i_cap: int = int(ind_tenancy.get("default_capacity", 40))
					var i_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", i_code)

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', %d, 'WORKS', 'PRIVATE', '%s', %d, %d, 0, %d, NULL, %d);
					""" % [est_id, dist_id, b_idx, i_title.replace("'", "''"), i_cat_id, i_cap, sim_start_day, reason_world_gen_id])

					_register_est_cat(by_cat, i_code, est_id, dist_id)
					_register_est_cat(by_cat, "INDUSTRIAL", est_id, dist_id)
					est_id += 1

		# Batch flush every 25 districts
		if block_idx > 0 and block_idx % 25 == 0:
			DB_MANAGER.execute_batch(dist_inserts)
			DB_MANAGER.execute_batch(estab_inserts)
			DB_MANAGER.execute_batch(household_inserts)
			dist_inserts.clear()
			estab_inserts.clear()
			household_inserts.clear()

			if on_progress.is_valid():
				var pct: float = 20.0 + ((float(block_idx) / float(districts.size())) * 30.0)
				on_progress.call(pct, 100.0, "Physical Premises: %d / %d blocks (%d units)" % [block_idx, districts.size(), est_id - 1])
				await Engine.get_main_loop().process_frame

		block_idx += 1

	if not dist_inserts.is_empty():
		DB_MANAGER.execute_batch(dist_inserts)
	if not estab_inserts.is_empty():
		DB_MANAGER.execute_batch(estab_inserts)
	if not household_inserts.is_empty():
		DB_MANAGER.execute_batch(household_inserts)

	print("  ✓ Pass 2: Generated %d establishments & %d households." % [est_id - 1, current_household_id - 1])

	return {
		"by_cat": by_cat,
		"households": generated_households,
		"district_residents_map": district_residents_map
	}

# =============================================================================
# PASS 3: CITIZENS, CONTRACTS & KINSHIP (Child Living Alone Guard)
# =============================================================================
static func _generate_citizens_and_demographics(physical_state: Dictionary, rng: RandomNumberGenerator, on_progress: Callable) -> void:
	var generated_households: Array[Dictionary] = physical_state["households"]
	var by_cat: Dictionary = physical_state["by_cat"]
	var district_residents_map: Dictionary = physical_state["district_residents_map"]

	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var male_gender_id: int = DB_MANAGER.get_label_id("GENDER", "M")
	var female_gender_id: int = DB_MANAGER.get_label_id("GENDER", "F")
	var contract_std_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", "STANDARD")
	var rel_family_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "FAMILY")

	var h_scales: Dictionary = _civic_hierarchy.get("hierarchy_scales", {})
	var fam_min: int = int(h_scales.get("family_size_min", 1))
	var fam_max: int = int(h_scales.get("family_size_max", 4))

	var male_names: Array = _lexicon.get("first_names_male", ["Terry"])
	var female_names: Array = _lexicon.get("first_names_female", ["Sharon"])

	var resident_inserts: Array[String] = []
	var contract_inserts: Array[String] = []
	var edge_inserts: Array[String] = []

	var current_resident_id: int = 1
	var total_hh: int = generated_households.size()
	var hh_idx: int = 0

	for hh in generated_households:
		hh_idx += 1
		var family_size := rng.randi_range(fam_min, fam_max)
		var surname_list: Array = _lexicon.get(hh["surnames_pool"], ["Smith"])
		var family_surname: String = str(surname_list[rng.randi() % surname_list.size()]).replace("'", "''")
		var is_high_dense: bool = str(hh["district_type"]).begins_with("high_density")
		var household_members: Array[int] = []

		for member_idx in range(family_size):
			var r_id := current_resident_id
			current_resident_id += 1
			household_members.append(r_id)
			district_residents_map[hh["district_id"]].append(r_id)

			var is_male: bool = (rng.randf() > 0.5)
			var gender_id: int = male_gender_id if is_male else female_gender_id
			var first_name: String = str(male_names[rng.randi() % male_names.size()] if is_male else female_names[rng.randi() % female_names.size()]).replace("'", "''")

			# Head of Household (index 0) is guaranteed to be adult
			var is_head: bool = (member_idx == 0)
			var demo_profile: Dictionary = _resolve_citizen_demographics(rng, is_high_dense, is_male, hh["unemp_rate"], 0.70, is_head)
			var age_years: int = int(demo_profile["age"])

			var days_old: int = int(round(float(age_years) * 365.25)) + rng.randi_range(0, 364)
			var dob_day: int = sim_start_day - days_old

			var edu_code: String = _resolve_citizen_education(rng, age_years, is_high_dense)
			var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", edu_code)

			resident_inserts.append("""
				INSERT INTO residents (
					resident_id, household_id, first_name, birth_surname, current_surname,
					dob, dod, death_reason_id, gender_id, education_level_id,
					ethnicity_id, religion_id, is_active_agent, valid_from, valid_to, change_reason_id
				) VALUES (
					%d, %d, '%s', '%s', '%s', %d, NULL, NULL, %d, %d, %d, %d, 0, %d, NULL, %d
				);
			""" % [
				r_id, hh["household_id"], first_name, family_surname, family_surname,
				dob_day, gender_id, edu_id, hh["ethnicity_id"], hh["religion_id"], sim_start_day, reason_world_gen_id
			])

			var occ_title: String = demo_profile["occupation"]
			var anchor_cat: String = demo_profile["anchor_category"]
			var contract_class: String = demo_profile["contract_class"]
			var weekly_hours: float = float(demo_profile["weekly_hours"])
			var compensation_rate: float = float(demo_profile["compensation_rate"])

			var assigned_est_id: int = _pick_anchor(by_cat, anchor_cat, hh["district_id"], rng)
			var class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)
			var role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", occ_title)

			contract_inserts.append("""
				INSERT INTO livelihood_contracts (
					resident_id, employer_entity_id, contract_class_id, role_title_id,
					contract_type_id, schedule_window, weekly_hours, compensation_rate, 
					valid_from, valid_to, change_reason_id
				) VALUES (
					%d, 'ESTAB_%d', %d, %d, %d, 'DAYTIME', %.1f, %.2f, %d, NULL, %d
				);
			""" % [
				r_id, assigned_est_id, class_id, role_id, contract_std_id,
				weekly_hours, compensation_rate, sim_start_day, reason_world_gen_id
			])

		# Kinship Edges inside Household
		if household_members.size() > 1:
			for a in household_members:
				for b in household_members:
					if a != b:
						edge_inserts.append("""
							INSERT INTO social_relationships (
								from_resident_id, to_resident_id, relationship_type_id,
								context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
							) VALUES (%d, %d, %d, NULL, 0.90, %d, NULL, %d);
						""" % [a, b, rel_family_id, sim_start_day, reason_world_gen_id])

		if resident_inserts.size() >= 500:
			DB_MANAGER.execute_batch(resident_inserts)
			DB_MANAGER.execute_batch(contract_inserts)
			DB_MANAGER.execute_batch(edge_inserts)
			resident_inserts.clear()
			contract_inserts.clear()
			edge_inserts.clear()

			if on_progress.is_valid():
				var pct: float = 50.0 + ((float(hh_idx) / float(max(1, total_hh))) * 40.0)
				on_progress.call(pct, 100.0, "Hydrating Citizens: ~%d pop (%d/%d homes)" % [current_resident_id - 1, hh_idx, total_hh])
				await Engine.get_main_loop().process_frame

	if not resident_inserts.is_empty():
		DB_MANAGER.execute_batch(resident_inserts)
		DB_MANAGER.execute_batch(contract_inserts)
		DB_MANAGER.execute_batch(edge_inserts)

	print("  ✓ Pass 3: Created %d citizens with legal guardians." % (current_resident_id - 1))

# =============================================================================
# PASS 4: DUNBAR NETWORK GRAPHS
# =============================================================================
static func _generate_social_networks(physical_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var rel_drinking_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "DRINKING_MATE")
	var district_residents_map: Dictionary = physical_state["district_residents_map"]

	# 1. Pub Catchment Edges per District
	var pub_edges: Array[String] = []
	for dist_id in district_residents_map.keys():
		var res_ids: Array = district_residents_map[dist_id]
		if res_ids.size() < 2:
			continue
		for r_id in res_ids:
			var buddy_count := rng.randi_range(2, 4)
			for _b in range(buddy_count):
				var target_id: int = res_ids[rng.randi() % res_ids.size()]
				if target_id != r_id:
					pub_edges.append("""
						INSERT INTO social_relationships (
							from_resident_id, to_resident_id, relationship_type_id,
							context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, %d, NULL, 0.55, %d, NULL, %d);
					""" % [r_id, target_id, rel_drinking_id, sim_start_day, reason_world_gen_id])
		if pub_edges.size() >= 500:
			DB_MANAGER.execute_batch(pub_edges)
			pub_edges.clear()

	if not pub_edges.is_empty():
		DB_MANAGER.execute_batch(pub_edges)

	# 2. Extended Kinship, Coworkers, and Congregational Faith Ties
	_generate_extended_kinship(rng, sim_start_day, reason_world_gen_id)
	_generate_establishment_peer_ties(rng, sim_start_day, reason_world_gen_id)
	_generate_faith_and_cultural_ties(rng, sim_start_day, reason_world_gen_id)

# =============================================================================
# HELPER ROUTINES (Zero hardcoded values; fully data-driven)
# =============================================================================
static func _pick_tenancy(rng: RandomNumberGenerator, primary_classes: Dictionary, secondary_classes: Dictionary, district_type: String) -> Dictionary:
	var pool: Array[Dictionary] = []
	
	for code in primary_classes.keys():
		var item: Dictionary = primary_classes[code]
		var spawns: Array = item.get("spawns_in_archetypes", [])
		if spawns.has(district_type) or spawns.is_empty():
			pool.append({"code": code, "display_name": item.get("display_name", code), "weight": item.get("weight", 10), "data": item})

	for code in secondary_classes.keys():
		var item: Dictionary = secondary_classes[code]
		var spawns: Array = item.get("spawns_in_archetypes", [])
		if spawns.has(district_type) or spawns.is_empty():
			pool.append({"code": code, "display_name": item.get("display_name", code), "weight": item.get("weight", 5), "data": item})

	if pool.is_empty():
		return {"code": "COMMERCIAL", "display_name": "Local Retail Unit", "default_capacity": 10, "required_customer_threshold": 50, "customer_travel_distance_m": 500.0}

	var total_w := 0
	for entry in pool:
		total_w += int(entry["weight"])

	var r: int = rng.randi() % max(1, total_w)
	var acc := 0
	for entry in pool:
		acc += int(entry["weight"])
		if r < acc:
			var res: Dictionary = entry["data"].duplicate()
			res["code"] = entry["code"]
			return res

	return pool[0]["data"]

static func _count_in_radius(instances_map: Dictionary, cat_code: String, pos: Vector2, radius_m: float) -> int:
	var list: Array = instances_map.get(cat_code, [])
	var count := 0
	for p in list:
		if (p as Vector2).distance_to(pos) <= radius_m:
			count += 1
	return count

static func _record_comm_instance(instances_map: Dictionary, cat_code: String, pos: Vector2) -> void:
	if not instances_map.has(cat_code):
		instances_map[cat_code] = []
	instances_map[cat_code].append(pos)

static func _register_est_cat(by_cat: Dictionary, cat_name: String, est_id: int, dist_id: String) -> void:
	if not by_cat.has(cat_name):
		by_cat[cat_name] = []
	by_cat[cat_name].append({"id": est_id, "district_id": dist_id})

static func _parse_vector2_string(s: String) -> Vector2:
	var clean := s.replace("(", "").replace(")", "").strip_edges()
	var parts := clean.split(",")
	if parts.size() >= 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO

static func _pick_anchor(by_cat: Dictionary, requested_category: String, _dist_id: String, rng: RandomNumberGenerator) -> int:
	var target_cat: String = requested_category
	var list: Array = by_cat.get(target_cat, [])

	if list.is_empty():
		var fallbacks: Dictionary = _demographics.get("anchor_category_fallbacks", {})
		if fallbacks.has(target_cat):
			target_cat = str(fallbacks[target_cat])
			list = by_cat.get(target_cat, [])
		elif fallbacks.has("DEFAULT"):
			target_cat = str(fallbacks["DEFAULT"])
			list = by_cat.get(target_cat, [])

	if list.is_empty():
		list = by_cat.get("COMMERCIAL", [])
	if list.is_empty():
		return 1

	var picked: Dictionary = list[rng.randi() % list.size()]
	return int(picked["id"])

static func _resolve_citizen_demographics(rng: RandomNumberGenerator, is_high_density: bool, is_male: bool, unemp_rate: float, comm_share: float, is_head_of_household: bool = false) -> Dictionary:
	var cohorts: Array = _demographics.get("cohort_profiles", [])
	assert(not cohorts.is_empty(), "FATAL: 'cohort_profiles' missing in demographics JSON")

	var thresholds: Dictionary = _demographics.get("legal_and_pension_thresholds", {})
	var life_caps: Dictionary = _demographics.get("life_expectancy_caps", {})

	var pen_age: int = int(thresholds["pension_age_male"] if is_male else thresholds["pension_age_female"])
	var max_age: int = int(life_caps["male_max_age"] if is_male else life_caps["female_max_age"])
	var majority_age: int = int(thresholds.get("majority_head_of_household_age", 18))
	var density_key := "high_density" if is_high_density else "suburban_low_density"

	# If primary householder, filter out youth cohorts under majority age
	var eligible_cohorts: Array = []
	for c in cohorts:
		if is_head_of_household and int(c.get("age_min", 0)) < majority_age and not c.has("age_min_dynamic"):
			continue
		eligible_cohorts.append(c)

	if eligible_cohorts.is_empty():
		eligible_cohorts = cohorts

	var roll := rng.randf()
	var cumulative := 0.0
	var chosen_cohort: Dictionary = eligible_cohorts[0]

	for c in eligible_cohorts:
		cumulative += float(c["density_weights"][density_key])
		if roll <= cumulative:
			chosen_cohort = c
			break

	var age_min: int = pen_age if (chosen_cohort.get("age_min_dynamic") == "pension_age") else int(chosen_cohort.get("age_min", majority_age if is_head_of_household else 0))
	var age_max: int = int(chosen_cohort.get("age_max", 70))
	if chosen_cohort.has("age_max_dynamic"):
		age_max = (pen_age - 1) if (chosen_cohort["age_max_dynamic"] == "pension_age") else max_age

	var resolved_age: int = rng.randi_range(maxi(age_min, majority_age if is_head_of_household else 0), age_max)
	
	var strategy: String = chosen_cohort.get("strategy", "FIXED")
	var profile_data: Dictionary = {}

	match strategy:
		"FIXED":
			profile_data = chosen_cohort
		"PROBABILISTIC":
			var prob: float = float(chosen_cohort["condition_probability"])
			profile_data = chosen_cohort["if_true"] if (rng.randf() < prob) else chosen_cohort["if_false"]
		"LABOR_MARKET":
			if rng.randf() < unemp_rate:
				profile_data = chosen_cohort["unemployed_branch"]
			elif rng.randf() < comm_share:
				profile_data = chosen_cohort["commercial_branch"]
			else:
				profile_data = chosen_cohort["industrial_branch"]

	return {
		"age": resolved_age,
		"occupation": str(profile_data.get("role", "COMMERCIAL_SERVICE")),
		"anchor_category": str(profile_data.get("anchor_category", "COMMERCIAL")),
		"contract_class": str(profile_data.get("contract_class", "FORMAL_LEGAL")),
		"weekly_hours": float(profile_data.get("weekly_hours", 37.5)),
		"compensation_rate": float(profile_data.get("compensation_rate", 3.50))
	}

static func _generate_extended_kinship(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var kinship_edges: Array[String] = []
	var edge_count: int = 0
	var ext_fam_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "EXTENDED_FAMILY")

	var surname_clusters = DB_MANAGER.query_rows("""
		SELECT current_surname as surname, e.district_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		GROUP BY current_surname, e.district_id
		HAVING count > 1;
	""")

	for cluster in surname_clusters:
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var pairs_to_attempt: int = min(ids.size(), 4)
		for _p in range(pairs_to_attempt):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a == b or rng.randf() > 0.60:
				continue

			kinship_edges.append("""
				INSERT OR IGNORE INTO social_relationships (
					from_resident_id, to_resident_id, relationship_type_id,
					context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
				) VALUES (%d, %d, %d, NULL, 0.80, %d, NULL, %d);
			""" % [a, b, ext_fam_id, sim_start_day, reason_id])
			kinship_edges.append("""
				INSERT OR IGNORE INTO social_relationships (
					from_resident_id, to_resident_id, relationship_type_id,
					context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
				) VALUES (%d, %d, %d, NULL, 0.80, %d, NULL, %d);
			""" % [b, a, ext_fam_id, sim_start_day, reason_id])
			edge_count += 2

		if kinship_edges.size() >= 500:
			DB_MANAGER.execute_batch(kinship_edges)
			kinship_edges.clear()

	if not kinship_edges.is_empty():
		DB_MANAGER.execute_batch(kinship_edges)

	return edge_count

static func _generate_establishment_peer_ties(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var peer_edges: Array[String] = []
	var edge_count: int = 0
	var peer_rel_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CIVIC_PEER")

	var est_clusters = DB_MANAGER.query_rows("""
		SELECT employer_entity_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM livelihood_contracts
		GROUP BY employer_entity_id
		HAVING count > 1;
	""")

	for cluster in est_clusters:
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var samples: int = min(ids.size(), 30)
		for _s in range(samples):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a != b:
				peer_edges.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, NULL, 0.50, %d, NULL, %d);
				""" % [a, b, peer_rel_id, sim_start_day, reason_id])
				edge_count += 1

		if peer_edges.size() >= 500:
			DB_MANAGER.execute_batch(peer_edges)
			peer_edges.clear()

	if not peer_edges.is_empty():
		DB_MANAGER.execute_batch(peer_edges)

	return edge_count

static func _generate_faith_and_cultural_ties(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var ties: Array[String] = []
	var edge_count: int = 0
	var congregational_rel_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CONGREGATIONAL")

	var congregation_clusters = DB_MANAGER.query_rows("""
		SELECT e.district_id, r.ethnicity_id, r.religion_id, GROUP_CONCAT(r.resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		WHERE r.dod IS NULL
		GROUP BY e.district_id, r.ethnicity_id, r.religion_id
		HAVING count > 1;
	""")

	for cluster in congregation_clusters:
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var samples: int = min(ids.size(), 5)
		for _s in range(samples):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a != b and rng.randf() < 0.40:
				ties.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, NULL, 0.65, %d, NULL, %d);
				""" % [a, b, congregational_rel_id, sim_start_day, reason_id])
				ties.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, NULL, 0.65, %d, NULL, %d);
				""" % [b, a, congregational_rel_id, sim_start_day, reason_id])
				edge_count += 2

		if ties.size() >= 500:
			DB_MANAGER.execute_batch(ties)
			ties.clear()

	if not ties.is_empty():
		DB_MANAGER.execute_batch(ties)

	return edge_count

static func _roll_household_culture(rng: RandomNumberGenerator, district_type: String) -> Dictionary:
	var weights_key := "high_density" if district_type.begins_with("high_density") else ("commercial" if district_type == "commercial" else "suburban_low_density")
	var dist_weights: Dictionary = _cultural["district_ethnic_weights"][weights_key]
	var defaults: Dictionary = _cultural["defaults"]

	var chosen_eth: String = defaults["fallback_ethnicity"]
	var roll := rng.randf()
	var cumulative := 0.0
	for eth in dist_weights.keys():
		cumulative += float(dist_weights[eth])
		if roll <= cumulative:
			chosen_eth = eth
			break

	var eth_profile: Dictionary = _cultural["ethnicities"][chosen_eth]
	var rel_weights: Dictionary = eth_profile["religion_distribution"]
	var chosen_rel: String = defaults["secular_or_unaffiliated_religion_key"]

	roll = rng.randf()
	cumulative = 0.0
	for rel in rel_weights.keys():
		cumulative += float(rel_weights[rel])
		if roll <= cumulative:
			chosen_rel = rel
			break

	return {
		"ethnicity": chosen_eth,
		"religion": chosen_rel,
		"surnames_pool": eth_profile.get("surnames_pool", "surnames")
	}

static func _resolve_citizen_education(rng: RandomNumberGenerator, age_years: int, is_high_density: bool) -> String:
	var edu_model: Dictionary = _demographics["education_attainment_model"]
	var default_code: String = str(edu_model["default_code"])
	var tiers: Array = edu_model["tiers"]

	for tier in tiers:
		var min_age: int = int(tier["min_age"])
		if age_years < min_age:
			continue

		var prob: float = float(tier["base_probability"])
		if is_high_density and tier.has("high_density_penalty"):
			prob = max(0.01, prob - float(tier["high_density_penalty"]))

		if rng.randf() < prob:
			return str(tier["code"])

	return default_code

## Universal helper to resolve spatial coordinates regardless of whether they are Vector2, Array, or String
static func _resolve_spatial_vector2(val: Variant) -> Vector2:
	if val is Vector2:
		return val
	elif val is Vector2i:
		return Vector2(float(val.x), float(val.y))
	elif val is Array and val.size() >= 2:
		return Vector2(float(val[0]), float(val[1]))
	elif val is String:
		var clean := (val as String).replace("(", "").replace(")", "").strip_edges()
		var parts := clean.split(",")
		if parts.size() >= 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO

## Pass 2.5: Pluggable Borough Clustering Dispatcher
static func _cluster_districts_into_boroughs(world_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var clustering_cfg: Dictionary = _civic_hierarchy.get("borough_clustering", {})
	var model_type: String = str(clustering_cfg.get("allocation_model", "uk_concentric_organic"))

	match model_type:
		"uk_concentric_organic":
			_cluster_boroughs_uk_concentric(world_state, rng, clustering_cfg)
		_:
			_cluster_boroughs_uk_concentric(world_state, rng, clustering_cfg) # Default fallback

## Realistic UK Municipal Ward Clustering (Concentric Bands, Angular Offsets & Homogeneous Housing Tiers)
static func _cluster_boroughs_uk_concentric(world_state: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var num_districts: int = districts.size()
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	var lexicon_data: Dictionary = MANIFEST_MGR.load_module("lexicon")
	var borough_names: Array = lexicon_data.get("borough_names", ["Aston", "Edgbaston", "Selly Oak"])
	borough_names = borough_names.duplicate()
	borough_names.shuffle()

	var core_def: Dictionary = cfg.get("central_core_borough", {
		"borough_id": "BOROUGH_CORE",
		"display_name": "Central Municipal Core Council"
	})
	var target_pop_per_ward: float = float(cfg.get("target_population_per_ward", 25000.0))

	# 1. Define Central Core Borough
	var borough_defs: Array[Dictionary] = []
	var core_id: String = str(core_def.get("borough_id", "BOROUGH_CORE"))
	var core_title: String = str(core_def.get("display_name", "Central Municipal Core"))

	borough_defs.append({
		"id": core_id,
		"display_name": core_title,
		"is_core": true
	})

	# 2. Separate Core districts from Outer growth rings based on distance and sector
	var core_radius: float = float(cfg.get("core_radius_ratio", 0.22))
	var max_r := 1.0
	for d in districts.values():
		var pos = _resolve_spatial_vector2(d.get("spatial_anchor", Vector2.ZERO))
		max_r = max(max_r, pos.length())
	var core_threshold := max_r * core_radius

	var outer_districts: Array[Dictionary] = []
	for dist_id in districts.keys():
		var d = districts[dist_id]
		var pos = _resolve_spatial_vector2(d.get("spatial_anchor", Vector2.ZERO))
		var r := pos.length()

		if r <= core_threshold or str(d.get("district_type", "")) in ["commercial", "local_government"]:
			d["borough_id"] = core_id
		else:
			outer_districts.append({"id": dist_id, "pos": pos, "data": d})

	# 3. Organic Growth Bands with Angular Offsets (North, South, East, West + Intercardinal overlap)
	var angle_offset_radians: float = deg_to_rad(float(cfg.get("outer_ring_angle_offset_deg", 60.0)))
	var num_sectors: int = int(cfg.get("cardinal_sectors", 4))
	var sector_span: float = TAU / float(num_sectors)

	var sector_groups: Array = []
	for i in range(num_sectors):
		sector_groups.append([])

	for item in outer_districts:
		var pos: Vector2 = item["pos"]
		var angle := wrapf(atan2(pos.y, pos.x) + angle_offset_radians, -PI, PI)
		var sector_idx := int(floor((angle + PI) / sector_span)) % num_sectors
		sector_groups[sector_idx].append(item)

	# 4. Create Wards within sectors, clustering by dominant housing archetype for homogeneity
	var ward_counter := 0
	var dist_updates: Dictionary = {core_id: []}
	for d_id in districts.keys():
		if districts[d_id].get("borough_id") == core_id:
			dist_updates[core_id].append(d_id)

	for sector_list in sector_groups:
		if sector_list.is_empty():
			continue

		sector_list.sort_custom(func(a, b):
			return str(a["data"].get("district_type", "")) < str(b["data"].get("district_type", ""))
		)

		var current_ward_pop := 0.0
		var current_ward_dists: Array[String] = []
		var name_idx := ward_counter % borough_names.size()
		var b_name: String = borough_names[name_idx]
		var b_id := "BOROUGH_%s_%d" % [b_name.to_upper().replace(" ", "_"), ward_counter]
		var b_display := "%s Metropolitan Ward" % b_name

		for item in sector_list:
			var d: Dictionary = item["data"]
			current_ward_dists.append(item["id"])
			current_ward_pop += float(d.get("estimated_population", 500.0))

			if current_ward_pop >= target_pop_per_ward:
				borough_defs.append({"id": b_id, "display_name": b_display, "is_core": false})
				dist_updates[b_id] = current_ward_dists
				for d_id in current_ward_dists:
					d["borough_id"] = b_id
				
				ward_counter += 1
				name_idx = ward_counter % borough_names.size()
				b_name = borough_names[name_idx]
				b_id = "BOROUGH_%s_%d" % [b_name.to_upper().replace(" ", "_"), ward_counter]
				b_display = "%s Metropolitan Ward" % b_name
				current_ward_pop = 0.0
				current_ward_dists = []

		if not current_ward_dists.is_empty():
			borough_defs.append({"id": b_id, "display_name": b_display, "is_core": false})
			dist_updates[b_id] = current_ward_dists
			for d_id in current_ward_dists:
				districts[d_id]["borough_id"] = b_id
			ward_counter += 1

	# 5. Commit Boroughs & District Backreferences to SQLite
	var borough_inserts: Array[String] = []
	var update_statements: Array[String] = []

	for b in borough_defs:
		var b_id: String = b["id"]
		var b_title: String = b["display_name"]
		
		borough_inserts.append("""
			INSERT OR REPLACE INTO boroughs (
				borough_id, display_name, controlling_party_id, police_division_code, 
				base_council_tax_rate, valid_from, valid_to, change_reason_id
			) VALUES (
				'%s', '%s', NULL, 'D_DIVISION', 1.10, %d, NULL, %d
			);
		""" % [b_id, b_title.replace("'", "''"), sim_start_day, reason_world_gen_id])

		var assigned_dists: Array = dist_updates.get(b_id, [])
		if not assigned_dists.is_empty():
			var in_clause := ""
			for d_id in assigned_dists:
				in_clause += "'%s'," % d_id
			in_clause = in_clause.trim_suffix(",")

			update_statements.append("""
				UPDATE districts SET borough_id = '%s' WHERE district_id IN (%s);
			""" % [b_id, in_clause])

	DB_MANAGER.execute_batch(borough_inserts)
	DB_MANAGER.execute_batch(update_statements)

	print("  ✓ UK Organic Borough Realignment: Clustered %d districts into %d municipal wards." % [
		num_districts, borough_defs.size()
	])


## Calculates physical district surface area in square metres (geometry-agnostic)
static func _get_district_area_sqm(district: Dictionary) -> float:
	var setup: Dictionary = _archetypes.get("setup", {})
	var metrics: Dictionary = setup.get("block_metrics", {})
	var std_w: float = float(metrics.get("standard_block_width_m", 200.0))
	var std_h: float = float(metrics.get("standard_block_height_m", 200.0))
	var default_sqm: float = std_w * std_h

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