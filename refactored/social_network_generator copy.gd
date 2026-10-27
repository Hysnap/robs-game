# res://systems/social_network_generator.gd
class_name SocialNetworkGenerator_copy
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

static var _lexicon: Dictionary = {}
static var _demographics: Dictionary = {}
static var _cultural: Dictionary = {}
static var _civic_hierarchy: Dictionary = {}
static var _archetypes: Dictionary = {}
static var _building_classes: Dictionary = {}
static var _job_definitions: Dictionary = {}

## Loads all required scenario modules strictly via ScenarioManifestManager
static func _load_configs() -> void:
	if not _demographics.is_empty() and not _lexicon.is_empty() and not _cultural.is_empty() and not _civic_hierarchy.is_empty() and not _archetypes.is_empty() and not _building_classes.is_empty() and not _job_definitions.is_empty():
		return

	_demographics = MANIFEST_MGR.load_module("demographics")
	_lexicon = MANIFEST_MGR.load_module("lexicon")
	_cultural = MANIFEST_MGR.load_module("cultural_demographics")
	_civic_hierarchy = MANIFEST_MGR.load_module("civic_hierarchy")

	assert(MANIFEST_MGR.has_module("job_definitions"), "FATAL: Scenario manifest missing 'job_definitions' module.")
	_job_definitions = MANIFEST_MGR.load_module("job_definitions").get("roles", {})
	assert(not _job_definitions.is_empty(), "FATAL: 'job_definitions' module contains empty roles dictionary.")

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
	# PASS 0.5: PRECALCULATE DISTRICT M² METRICS, POPULATION & VACANCY
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(5.0, 100.0, "Pass 1: Generate Initial Land Parcels..")
		await Engine.get_main_loop().process_frame
	_precalculate_district_metrics(world_state, rng)

	# -------------------------------------------------------------------------
	# PASS 1: CIVIC CADENCE REALIGNMENT (DRY Spatial Allocation)
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

# =============================================================================
# PASS 0.5: PHYSICAL LAND DENSITY & UNIT ROLL
# =============================================================================
static func _precalculate_district_metrics(world_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var setup: Dictionary = _archetypes.get("setup", {})
	var metrics: Dictionary = setup.get("block_metrics", {})
	var std_w: float = float(metrics.get("standard_block_width_m", 200.0))
	var std_h: float = float(metrics.get("standard_block_height_m", 200.0))
	var std_lot_sqm: float = std_w * std_h

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var arch: Dictionary = _archetypes.get(dtype, {})

		var area_sqm: float = _get_district_area_sqm(d)
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

		# Building counts derived from archetype base footprint
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

# =============================================================================
# PASS 1: DRY CIVIC CADENCE REALIGNMENT
# =============================================================================
static func _run_civic_cadence_pass(world_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var block_estimates: Dictionary = {}
	var total_city_est_pop: float = 0.0
	var max_r: float = 1.0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var p = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		max_r = max(max_r, p.length())
		
		if bool(d.get("is_initially_vacant", false)):
			block_estimates[dist_id] = 0.0
		else:
			var est_p: float = float(d.get("estimated_population", 0.0))
			block_estimates[dist_id] = est_p
			total_city_est_pop += est_p

	var cadence_rules: Array[Dictionary] = _harvest_cadence_rules()
	var placed_by_type: Dictionary = {}

	for spec in cadence_rules:
		var code: String = spec["code"]
		placed_by_type[code] = []

		if total_city_est_pop < float(spec.get("min_pop", 0)):
			continue

		var pop_ratio: float = float(spec["pop_ratio"])
		var quota: int = maxi(1, int(round((total_city_est_pop / pop_ratio) * rng.randf_range(0.85, 1.15))))
		var placed := 0

		for _attempt in range(quota * 15):
			if placed >= quota:
				break

			var chosen: Dictionary = SPATIAL_RESOLVER.find_best_host_district(
				districts, block_estimates, placed_by_type[code], spec, max_r
			)
			if chosen.is_empty():
				break

			var dist_id: String = chosen["dist_id"]
			var d: Dictionary = districts[dist_id]

			# Apply Placement: Full-block / Campus or Sub-block Carveout
			if chosen["is_vacant"] or float(spec["footprint_sqm"]) >= (chosen["area_sqm"] * 0.70):
				d["district_type"] = code
				d["is_repurposed_civic"] = true
				d["is_initially_vacant"] = false
				d["actual_building_count"] = 1
				total_city_est_pop = max(0.0, total_city_est_pop - chosen["est_pop"])
				block_estimates[dist_id] = 0.0
			else:
				_apply_sub_block_carveout(d, spec, total_city_est_pop, block_estimates)

			placed_by_type[code].append(chosen["center"])
			placed += 1

		print("  ✓ Cadence: Placed %d '%s' facilities (Quota: %d)" % [placed, code, quota])

	# Post-Cadence Reclassification for surplus vacant plots
	_reclassify_surplus_vacant_parcels(districts)

static func _apply_sub_block_carveout(chosen_d: Dictionary, spec: Dictionary, total_city_est_pop: float, block_estimates: Dictionary) -> void:
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

	var units_lost_hab: int = int(round(float(total_hab) * fraction_lost))
	var units_lost_comm: int = int(round(float(total_comm) * fraction_lost))
	var units_lost_ind: int = int(round(float(total_ind) * fraction_lost))

	chosen_d["total_habitable_units"] = maxi(0, total_hab - units_lost_hab)
	chosen_d["total_commercial_units"] = maxi(0, total_comm - units_lost_comm)
	chosen_d["total_industrial_units"] = maxi(0, total_ind - units_lost_ind)

	for _k in range(bldgs_consumed):
		if not allocations.is_empty():
			allocations.pop_back()

	chosen_d["actual_building_count"] = allocations.size()

	if not chosen_d.has("embedded_civics"):
		chosen_d["embedded_civics"] = []
	chosen_d["embedded_civics"].append(spec["code"])

	var pop_lost: float = float(chosen_d.get("estimated_population", 0.0)) * fraction_lost
	total_city_est_pop = max(0.0, total_city_est_pop - pop_lost)
	chosen_d["estimated_population"] = max(0.0, float(chosen_d.get("estimated_population", 0.0)) - pop_lost)
	block_estimates[chosen_d.get("district_id", "")] = chosen_d["estimated_population"]

static func _harvest_cadence_rules() -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	for arch_key in _archetypes.keys():
		if arch_key in ["_meta", "setup"]:
			continue
		var arch: Dictionary = _archetypes[arch_key]
		var sp_rules: Dictionary = arch.get("spatial_rules", {})
		if sp_rules.get("placement_mode", "") == "CADENCE":
			rules.append({
				"code": arch_key,
				"pop_ratio": float(sp_rules.get("pop_ratio", 1500.0)),
				"travel_dist_m": float(sp_rules.get("travel_dist_m", sp_rules.get("min_sep_m", 750.0))),
				"min_sep_m": 0.0,
				"min_pop": int(sp_rules.get("min_city_population", 0)),
				"footprint_sqm": float(arch.get("footprint_size", arch.get("footprint_sqm", 40000.0))),
				"norm_dist_range": sp_rules.get("norm_distance_range", [0.0, 1.0]),
				"allowed_sectors": ["RESIDENTIAL", "COMMERCIAL"],
				"forbidden_types": ["municipal_park", "industrial"],
				"prefer_vacant": true
			})
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
		print("  ✓ Reassigned %d surplus vacant parcels to allotments/cleared sites/scrap sidings." % count)

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
	var available_job_slots: Array[Dictionary] = []

	var est_id: int = 1
	var current_household_id: int = 1
	var block_idx: int = 0

	var block_estimates: Dictionary = {}
	for dist_id in districts.keys():
		block_estimates[dist_id] = float(districts[dist_id].get("estimated_population", 0.0))

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var district_type: String = str(d.get("district_type", ""))
		assert(_archetypes.has(district_type), "FATAL: Archetype '%s' not registered." % district_type)

		var arch: Dictionary = _archetypes[district_type]
		var coords: Vector2i = d.get("grid_coords", Vector2i(0, 0))
		var g_size: Vector2i = d.get("grid_size", Vector2i(1, 1))
		var building_count: int = int(d.get("actual_building_count", 1))
		var pop_range: Array = arch.get("population_range", [0, 0])
		var exp_min: int = int(d.get("expected_pop_min", pop_range[0]))
		var exp_max: int = int(d.get("expected_pop_max", pop_range[1]))
		var center_vec: Vector2 = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))

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
			building_count, exp_min, exp_max,
			float(d.get("unemployment_rate", 0.0)), float(d.get("avg_disposable_income", 75.0)),
			float(d.get("zone_health_index", 50.0)), float(d.get("actual_police_heat", 0.20)),
			sim_start_day, reason_world_gen_id
		])

		district_residents_map[dist_id] = []

		# 1. Dedicated Institutional Anchor
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
			_expand_staffing_slots(available_job_slots, est_id, dist_id, cat_name, inst, rng)
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
				_expand_staffing_slots(available_job_slots, est_id, dist_id, c_cat_name, c_inst, rng)
				est_id += 1

		# 3. Instantiate Units strictly from precalculated building_allocations
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
					var req_threshold: float = float(tenancy.get("required_customer_threshold", 100))

					var existing_list: Array = commercial_instances_by_type.get(cat_code, [])
					var is_viable: bool = SPATIAL_RESOLVER.is_catchment_viable(
						center_vec, existing_list, districts, block_estimates, travel_dist, req_threshold
					)

					var is_vacant: int = 0
					if not is_viable and rng.randf() < 0.50:
						is_vacant = 1
						cap = 0

					var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_code)
					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', %d, 'SHOP', 'PRIVATE', '%s', %d, %d, %d, %d, NULL, %d);
					""" % [est_id, dist_id, b_idx, display_title.replace("'", "''"), cat_id, cap, is_vacant, sim_start_day, reason_world_gen_id])

					if not commercial_instances_by_type.has(cat_code):
						commercial_instances_by_type[cat_code] = []
					commercial_instances_by_type[cat_code].append(center_vec)

					_register_est_cat(by_cat, cat_code, est_id, dist_id)
					_register_est_cat(by_cat, "COMMERCIAL", est_id, dist_id)

					if is_vacant == 0:
						_expand_staffing_slots(available_job_slots, est_id, dist_id, "COMMERCIAL", tenancy, rng)
					
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
					_expand_staffing_slots(available_job_slots, est_id, dist_id, "INDUSTRIAL", ind_tenancy, rng)
					est_id += 1

		# Batch commit every 25 districts
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

	print("  ✓ Pass 2: Generated %d establishments, %d households, and %d open workplace positions." % [
		est_id - 1, current_household_id - 1, available_job_slots.size()
	])

	return {
		"districts": districts,
		"by_cat": by_cat,
		"households": generated_households,
		"district_residents_map": district_residents_map,
		"available_job_slots": available_job_slots
	}
# =============================================================================
# PASS 3: CITIZENS, CONTRACTS & DEMOGRAPHICS (Job Slot Matching)
# =============================================================================
static func _generate_citizens_and_demographics(physical_state: Dictionary, rng: RandomNumberGenerator, on_progress: Callable) -> void:
	var districts: Dictionary = physical_state.get("districts", {})
	var generated_households: Array[Dictionary] = physical_state["households"]
	var by_cat: Dictionary = physical_state["by_cat"]
	var district_residents_map: Dictionary = physical_state["district_residents_map"]
	var open_job_slots: Array[Dictionary] = physical_state["available_job_slots"]

	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var male_gender_id: int = DB_MANAGER.get_label_id("GENDER", "M")
	var female_gender_id: int = DB_MANAGER.get_label_id("GENDER", "F")
	var contract_std_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", "STANDARD")
	var rel_family_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "FAMILY")

	open_job_slots.shuffle()

	# Create lookup queues by Category
	var jobs_by_cat: Dictionary = {}
	for slot in open_job_slots:
		var c: String = slot["cat"]
		if not jobs_by_cat.has(c):
			var _arr: Array[Dictionary] = []
			jobs_by_cat[c] = []
		jobs_by_cat[c].append(slot)

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
			var assigned_est_id: int = 0

			# 1. Active Formal Workforce: Claim open job slot matching commute
			if contract_class == "FORMAL_LEGAL":
				var worker_home_pos: Vector2 = SPATIAL_RESOLVER._resolve_vector2(
					districts[hh["district_id"]].get("spatial_anchor", Vector2.ZERO)
				)

				if jobs_by_cat.has(anchor_cat) and not jobs_by_cat[anchor_cat].is_empty():
					var slot: Dictionary = SPATIAL_RESOLVER.pick_commute_matched_slot(
						jobs_by_cat[anchor_cat],
						worker_home_pos,
						edu_code,
						districts,
						_job_definitions,
						rng
					)
					if not slot.is_empty():
						assigned_est_id = int(slot["estab_id"])
						occ_title = slot["role"]
						weekly_hours = slot["hours"]
						compensation_rate = slot["rate"]
					else:
						assigned_est_id = _pick_anchor(by_cat, anchor_cat, hh["district_id"], rng)
				else:
					var unemp_branch: Dictionary = demo_profile.get("unemployed_branch", {})
					if not unemp_branch.is_empty():
						occ_title = str(unemp_branch.get("role", "UNEMPLOYED"))
						anchor_cat = str(unemp_branch.get("anchor_category", "JOBCENTRE"))
						contract_class = str(unemp_branch.get("contract_class", "INFORMAL_GREY"))
						weekly_hours = float(unemp_branch.get("weekly_hours", 0.0))
						compensation_rate = float(unemp_branch.get("compensation_rate", 0.0))
					else:
						contract_class = "INFORMAL_GREY"
						weekly_hours = 0.0
						compensation_rate = 0.0

					assigned_est_id = _pick_anchor(by_cat, anchor_cat, hh["district_id"], rng)

			# 2. Non-Working Cohorts (Enclaves, Students, Pensioners, Unemployed)
			else:
				assigned_est_id = _pick_anchor(by_cat, anchor_cat, hh["district_id"], rng)

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

	print("  ✓ Pass 3: Created %d citizens with legal guardians and matched jobs." % (current_resident_id - 1))

	_audit_generated_jobs_by_education()

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
# HELPER ROUTINES & DEMOGRAPHIC RESOLUTION
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

static func _register_est_cat(by_cat: Dictionary, cat_name: String, est_id: int, dist_id: String) -> void:
	if not by_cat.has(cat_name):
		by_cat[cat_name] = []
	by_cat[cat_name].append({"id": est_id, "district_id": dist_id})

static func _pick_anchor(by_cat: Dictionary, requested_category: String, _dist_id: String, rng: RandomNumberGenerator) -> int:
	var target_cat: String = requested_category
	var fallbacks: Dictionary = _demographics.get("anchor_category_fallbacks", {})
	var visited: Dictionary = {}

	while not by_cat.has(target_cat) or by_cat[target_cat].is_empty():
		visited[target_cat] = true
		if fallbacks.has(target_cat) and not visited.has(fallbacks[target_cat]):
			target_cat = str(fallbacks[target_cat])
		elif fallbacks.has("DEFAULT") and not visited.has(fallbacks["DEFAULT"]):
			target_cat = str(fallbacks["DEFAULT"])
		else:
			break

	var list: Array = by_cat.get(target_cat, [])

	if list.is_empty():
		for cat_key in by_cat.keys():
			if not by_cat[cat_key].is_empty():
				list = by_cat[cat_key]
				break

	assert(not list.is_empty(), "FATAL: Society generation has zero establishments registered in by_cat.")

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

# =============================================================================
# PASS 2.5: BOROUGH CLUSTERING
# =============================================================================
static func _cluster_districts_into_boroughs(world_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var clustering_cfg: Dictionary = _civic_hierarchy.get("borough_clustering", {})
	var model_type: String = str(clustering_cfg.get("allocation_model", "uk_concentric_organic"))

	match model_type:
		"uk_concentric_organic":
			_cluster_boroughs_uk_concentric(world_state, rng, clustering_cfg)
		_:
			_cluster_boroughs_uk_concentric(world_state, rng, clustering_cfg)

static func _cluster_boroughs_uk_concentric(world_state: Dictionary, _rng: RandomNumberGenerator, cfg: Dictionary) -> void:
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

	var borough_defs: Array[Dictionary] = []
	var core_id: String = str(core_def.get("borough_id", "BOROUGH_CORE"))
	var core_title: String = str(core_def.get("display_name", "Central Municipal Core"))

	borough_defs.append({
		"id": core_id,
		"display_name": core_title,
		"is_core": true
	})

	var core_radius: float = float(cfg.get("core_radius_ratio", 0.22))
	var max_r := 1.0
	for d in districts.values():
		var pos = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		max_r = max(max_r, pos.length())
	var core_threshold := max_r * core_radius

	var outer_districts: Array[Dictionary] = []
	for dist_id in districts.keys():
		var d = districts[dist_id]
		var pos = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		var r := pos.length()

		if r <= core_threshold or str(d.get("district_type", "")) in ["commercial", "local_government"]:
			d["borough_id"] = core_id
		else:
			outer_districts.append({"id": dist_id, "pos": pos, "data": d})

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

static func _get_district_area_sqm(district: Dictionary) -> float:
	var setup: Dictionary = _archetypes.get("setup", {})
	var metrics: Dictionary = setup.get("block_metrics", {})
	var std_w: float = float(metrics.get("standard_block_width_m", 200.0))
	var std_h: float = float(metrics.get("standard_block_height_m", 200.0))

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

# =============================================================================
# AUDIT & VERIFICATION REPORT
# =============================================================================
static func _audit_generated_jobs_by_education() -> void:
	print("\n==========================================================================")
	print("               SOCIETY LABOR & EDUCATION AUDIT REPORT                     ")
	print("==========================================================================")

	var query := """
		SELECT 
			edu.code AS education_level,
			c_cls.code AS contract_class,
			role.code AS role_title,
			COUNT(c.resident_id) AS total_holders,
			AVG(c.compensation_rate) AS avg_hourly_rate,
			AVG(c.weekly_hours) AS avg_weekly_hours
		FROM livelihood_contracts c
		JOIN residents r ON c.resident_id = r.resident_id
		JOIN system_labels edu ON r.education_level_id = edu.label_id
		JOIN system_labels c_cls ON c.contract_class_id = c_cls.label_id
		JOIN system_labels role ON c.role_title_id = role.label_id
		GROUP BY edu.code, c_cls.code, role.code
		ORDER BY edu.code, c_cls.code, total_holders DESC;
	"""

	var results: Array = DB_MANAGER.query_rows(query)
	if results.is_empty():
		print("  [Audit] No contract records found.")
		print("==========================================================================\n")
		return

	var current_edu: String = ""
	var total_city_jobs: int = 0

	for row in results:
		var edu: String = str(row["education_level"])
		var cls: String = str(row["contract_class"])
		var role: String = str(row["role_title"])
		var count: int = int(row["total_holders"])
		var rate: float = float(row["avg_hourly_rate"])
		var hours: float = float(row["avg_weekly_hours"])
		total_city_jobs += count

		if edu != current_edu:
			current_edu = edu
			print("\n▶ [Education Tier: %s]" % current_edu)
			print("  %-24s | %-16s | %-6s | %-9s | %-8s" % ["Role Title", "Class", "Count", "Avg Rate", "Avg Hrs"])
			print("  ------------------------------------------------------------------------")

		print("  %-24s | %-16s | %-6d | £%-8.2f | %-5.1f hrs" % [role, cls, count, rate, hours])

	var summary_query := """
		SELECT 
			edu.code AS education_level,
			COUNT(r.resident_id) AS citizen_count,
			SUM(CASE WHEN c_cls.code = 'FORMAL_LEGAL' THEN 1 ELSE 0 END) AS formal_workers,
			SUM(CASE WHEN c_cls.code = 'ENCLAVE_STUDENT' THEN 1 ELSE 0 END) AS students_pupils,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code = 'PENSIONER' THEN 1 ELSE 0 END) AS pensioners,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code != 'PENSIONER' THEN 1 ELSE 0 END) AS unemployed_or_informal
		FROM residents r
		JOIN system_labels edu ON r.education_level_id = edu.label_id
		LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id
		LEFT JOIN system_labels c_cls ON c.contract_class_id = c_cls.label_id
		LEFT JOIN system_labels role ON c.role_title_id = role.label_id
		GROUP BY edu.code
		ORDER BY citizen_count DESC;
	"""
	var summary_results: Array = DB_MANAGER.query_rows(summary_query)

	print("\n--------------------------------------------------------------------------")
	print("                     SUMMARY BY EDUCATION LEVEL                           ")
	print("--------------------------------------------------------------------------")
	print("  %-20s | %-8s | %-14s | %-10s | %-18s | %-10s" % ["Education Level", "Pop", "Formal Workers", "Students", "Unemployed/Informal", "Pensioners"])
	print("  ------------------------------------------------------------------------------------------------")
	for s_row in summary_results:
		print("  %-20s | %-8d | %-14d | %-10d | %-18d | %-10d" % [
			str(s_row["education_level"]),
			int(s_row["citizen_count"]),
			int(s_row["formal_workers"]),
			int(s_row["students_pupils"]),
			int(s_row["unemployed_or_informal"]),
			int(s_row["pensioners"])
		])

	print("==========================================================================")
	print("  Total Contracted Citizens: %d" % total_city_jobs)
	print("==========================================================================\n")

## Unwraps staffing slots by merging master job definitions with local overrides and uplifts
static func _expand_staffing_slots(
	slots_array: Array[Dictionary], 
	estab_id: int, 
	dist_id: String, 
	category_code: String, 
	host_def: Dictionary, 
	rng: RandomNumberGenerator
) -> void:
	var estab_multiplier: float = float(host_def.get("wage_multiplier", 1.0))
	var estab_bonus: float = float(host_def.get("wage_bonus", 0.0))

	# 1. Multi-role detailed roster
	if host_def.has("staffing_roster"):
		for item in host_def["staffing_roster"]:
			var job_code: String = str(item.get("job_id", item.get("role_title", "COMMERCIAL_SERVICE")))
			var master_job: Dictionary = _job_definitions.get(job_code, {})

			var contract_class: String = str(item.get("contract_class", master_job.get("contract_class", "FORMAL_LEGAL")))
			var edu_req: String = str(item.get("education_required", master_job.get("education_required", "NO_FORMAL")))
			var hours: float = float(item.get("weekly_hours", master_job.get("weekly_hours", 37.5)))
			var is_field: bool = bool(item.get("is_field_worker", master_job.get("is_field_worker", false)))

			var resolved_rate: float = 3.50
			if item.has("hourly_rate"):
				resolved_rate = float(item["hourly_rate"])
			elif master_job.has("hourly_rate_range"):
				var r_range: Array = master_job["hourly_rate_range"]
				var base_rate: float = rng.randf_range(float(r_range[0]), float(r_range[1]))
				var role_multiplier: float = float(item.get("wage_multiplier", estab_multiplier))
				var role_bonus: float = float(item.get("wage_bonus", estab_bonus))
				resolved_rate = snappedf((base_rate * role_multiplier) + role_bonus, 0.05)
			elif master_job.has("hourly_rate"):
				resolved_rate = float(master_job["hourly_rate"])

			var count_range: Array = item.get("target_count", [1, 1])
			var count: int = rng.randi_range(int(count_range[0]), int(count_range[1]))

			for _i in range(count):
				slots_array.append({
					"estab_id": estab_id,
					"district_id": dist_id,
					"cat": category_code,
					"role": job_code,
					"contract_class": contract_class,
					"edu_req": edu_req,
					"rate": resolved_rate,
					"hours": hours,
					"is_field_worker": is_field
				})

	# 2. Fallback for single employee_range
	else:
		var emp_range: Array = host_def.get("employee_range", host_def.get("default_employees", [1, 3]))
		var count: int = rng.randi_range(int(emp_range[0]), int(emp_range[1]))
		var fallback_job: String = "MANUAL_WORKS" if category_code == "INDUSTRIAL" else "COMMERCIAL_SERVICE"
		var master: Dictionary = _job_definitions.get(fallback_job, {})
		
		var default_edu: String = str(master.get("education_required", "NO_FORMAL"))
		var default_hours: float = float(master.get("weekly_hours", 37.5))
		var r_range: Array = master.get("hourly_rate_range", [3.20, 3.80])
		
		for _i in range(count):
			var rate: float = snappedf(rng.randf_range(float(r_range[0]), float(r_range[1])) * estab_multiplier, 0.05)
			slots_array.append({
				"estab_id": estab_id,
				"district_id": dist_id,
				"cat": category_code,
				"role": fallback_job,
				"contract_class": "FORMAL_LEGAL",
				"edu_req": default_edu,
				"rate": rate,
				"hours": default_hours,
				"is_field_worker": false
			})