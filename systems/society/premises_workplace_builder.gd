# res://systems/society/premises_workplace_builder.gd
class_name PremisesWorkplaceBuilder
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

## Pass 2: Populates physical establishments, households, and job slots with authentic UK addresses and era-accurate business names
static func run(
	world_state: Dictionary,
	archetypes: Dictionary,
	building_classes: Dictionary,
	job_definitions: Dictionary,
	cultural: Dictionary,
	lexicon: Dictionary,
	rng: RandomNumberGenerator,
	on_progress: Callable
) -> Dictionary:
	var districts: Dictionary = world_state.get("districts", {})
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var sim_start_year: int = int(world_state.get("metadata", {}).get("calendar_year", 1980))
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var res_unit_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "RESIDENTIAL_UNIT")

	var comm_classes: Dictionary = building_classes.get("commercial_tenants", {})
	var ind_classes: Dictionary = building_classes.get("industrial_tenants", {})
	var embedded_civic_classes: Dictionary = building_classes.get("civic_tenants", {})

	var dist_inserts: Array[String] = []
	var estab_inserts: Array[String] = []
	var household_inserts: Array[String] = []
	var job_slot_inserts: Array[String] = []

	var by_cat: Dictionary = {}
	var commercial_instances_by_type: Dictionary = {}
	var generated_households: Array[Dictionary] = []
	var district_residents_map: Dictionary = {}
	var available_job_slots: Array[Dictionary] = []
	var available_tied_housing: Dictionary = {}
	var proprietor_hints: Dictionary = {}

	var est_id: int = 1
	var current_household_id: int = 1
	var current_slot_id: int = 1
	var block_idx: int = 0
	var total_tied_units_count: int = 0

	var block_estimates: Dictionary = {}
	for dist_id in districts.keys():
		block_estimates[dist_id] = float(districts[dist_id].get("estimated_population", 0.0))

	# Address & commercial resolution tables from merged lexicon
	var street_cfg: Dictionary = lexicon.get("street_names", {})
	var street_roots: Array = street_cfg.get("roots", [])
	var street_suffixes: Array = street_cfg.get("suffixes", [])
	assert(not street_roots.is_empty() and not street_suffixes.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing street_names in lexicon.")

	var bldg_cfg: Dictionary = lexicon.get("residential_building_names", {})
	var bldg_roots: Array = bldg_cfg.get("roots", [])
	var bldg_suffixes: Array = bldg_cfg.get("suffixes", [])
	assert(not bldg_roots.is_empty() and not bldg_suffixes.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing residential_building_names in lexicon.")

	var address_fmts: Dictionary = lexicon.get("address_formats", {})
	var fmt_flat_unit: String = str(address_fmts.get("flat_unit", "Flat {door}, {building}"))
	var fmt_flat_door: String = str(address_fmts.get("flat_door", "Flat {door}"))
	var fmt_street_unit: String = str(address_fmts.get("street_unit", "{door} {street}"))
	var fmt_street_door: String = str(address_fmts.get("street_door", "{door}"))

	var comm_naming: Dictionary = lexicon.get("commercial_naming", {})
	assert(not comm_naming.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'commercial_naming' in spatial lexicon.")

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var district_type: String = str(d.get("district_type", ""))
		assert(archetypes.has(district_type), "FATAL: Archetype '%s' not registered." % district_type)

		var arch: Dictionary = archetypes[district_type]
		var coords: Vector2i = d.get("grid_coords", Vector2i(0, 0))
		var g_size: Vector2i = d.get("grid_size", Vector2i(1, 1))
		var building_count: int = int(d.get("actual_building_count", 1))
		var pop_range: Array = arch.get("population_range", [0, 0])
		var exp_min: int = int(d.get("expected_pop_min", pop_range[0]))
		var exp_max: int = int(d.get("expected_pop_max", pop_range[1]))
		var center_vec: Vector2 = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))

		# 1. Establish Primary Street Name & District Prefix for this parcel
		var street_root: String = str(street_roots[rng.randi() % street_roots.size()])
		var street_suf: String = str(street_suffixes[rng.randi() % street_suffixes.size()])
		var parcel_street_name := "%s %s" % [street_root, street_suf]
		var district_display: String = str(d.get("display_name", dist_id))
		var district_prefix: String = district_display.split(" ")[0] if not district_display.is_empty() else street_root
		var street_door_counter: int = 1
		var used_names_in_district: Dictionary = {}

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
			dist_id, district_display.replace("'", "''"), district_type,
			coords.x, coords.y, g_size.x, g_size.y,
			building_count, exp_min, exp_max,
			float(d.get("unemployment_rate", 0.0)), float(d.get("avg_disposable_income", 75.0)),
			float(d.get("zone_health_index", 50.0)), float(d.get("actual_police_heat", 0.20)),
			sim_start_day, reason_world_gen_id
		])

		district_residents_map[dist_id] = []

		# 2. Dedicated Institutional Anchor
		if arch.has("institution_profile"):
			var inst: Dictionary = arch["institution_profile"]
			var cat_name: String = str(arch.get("establishment_category", district_type.to_upper()))
			assert(arch.has("sector_class"), "FATAL: Archetype '%s' with institution_profile is missing mandatory 'sector_class'!" % district_type)
			var inst_sector: String = str(arch["sector_class"]).to_upper()
			var display_label: String = str(arch.get("display_name", cat_name)).replace("'", "''")
			var capacity: int = int(inst.get("default_capacity", 250))
			var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_name)
			var institution_estab_id: int = est_id

			estab_inserts.append("""
				INSERT INTO establishments (
					establishment_id, district_id, building_index, unit_door_number,
					owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
				) VALUES (%d, '%s', 0, 'MAIN', 'CIVIC', '%s', %d, %d, 0, %d, NULL, %d);
			""" % [institution_estab_id, dist_id, display_label, cat_id, capacity, sim_start_day, reason_world_gen_id])

			_register_est_cat(by_cat, cat_name, institution_estab_id, dist_id)
			current_slot_id = expand_staffing_slots(
				available_job_slots, job_slot_inserts, current_slot_id, institution_estab_id, dist_id,
				inst_sector, inst, job_definitions, sim_start_day, reason_world_gen_id, rng
			)
			est_id += 1

			# Generate Tied Living Accommodation Units anchored to this institution
			var housing_profiles: Array[Dictionary] = _extract_housing_profiles(arch)
			for h_prof in housing_profiles:
				var res_type: String = str(h_prof.get("residence_type", "NONE"))
				if res_type == "NONE":
					continue

				var int_res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type)
				var int_tenure_type: String = str(h_prof.get("tenure_type", "EMPLOYMENT_TIED"))
				var int_wealth_bracket: int = int(h_prof.get("wealth_bracket", 3))

				var units_to_generate: int = 1
				if h_prof.has("capacity"):
					units_to_generate = maxi(1, int(round(float(h_prof["capacity"]) / 2.0)))
				elif arch.has("population_range"):
					var p_rng: Array = arch["population_range"]
					units_to_generate = maxi(1, int(round(float(p_rng[1]) / 2.5)))

				units_to_generate = mini(units_to_generate, 60)

				if not available_tied_housing.has(res_type):
					available_tied_housing[res_type] = []

				for u_idx in range(units_to_generate):
					var unit_num: int = u_idx + 1
					var unit_door: String = "Room %d" % unit_num
					var unit_title: String = "%s %s %s" % [display_label, res_type.replace("_", " ").capitalize(), unit_door]

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', 0, '%s', '%s', '%s', %d, 2, 1, %d, NULL, %d);
					""" % [
						est_id, dist_id, unit_door, int_tenure_type,
						unit_title.replace("'", "''"), res_unit_cat_id, sim_start_day, reason_world_gen_id
					])

					available_tied_housing[res_type].append({
						"establishment_id": est_id,
						"district_id": dist_id,
						"residence_type": res_type,
						"residence_type_id": int_res_type_id,
						"wealth_bracket_id": int_wealth_bracket,
						"tenure_type": int_tenure_type,
						"parent_workplace_id": institution_estab_id
					})

					total_tied_units_count += 1
					est_id += 1

		# 3. Sub-Block Embedded Civics placed in Pass 1
		if d.has("embedded_civics"):
			for civic_key in d["embedded_civics"]:
				var c_arch: Dictionary = archetypes.get(civic_key, {})
				var c_inst: Dictionary = c_arch.get("institution_profile", {})
				var c_cat_name: String = str(c_arch.get("establishment_category", civic_key.to_upper()))
				assert(c_arch.has("sector_class"), "FATAL: Embedded civic archetype '%s' missing mandatory 'sector_class'!" % civic_key)
				var c_sector: String = str(c_arch["sector_class"]).to_upper()
				var c_display: String = str(c_arch.get("display_name", c_cat_name)).replace("'", "''")
				var c_cap: int = int(c_inst.get("default_capacity", 250))
				var c_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", c_cat_name)
				var embedded_estab_id: int = est_id

				estab_inserts.append("""
					INSERT INTO establishments (
						establishment_id, district_id, building_index, unit_door_number,
						owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
					) VALUES (%d, '%s', 0, 'CIVIC_PARCEL', 'CIVIC', '%s', %d, %d, 0, %d, NULL, %d);
				""" % [embedded_estab_id, dist_id, c_display, c_cat_id, c_cap, sim_start_day, reason_world_gen_id])

				_register_est_cat(by_cat, c_cat_name, embedded_estab_id, dist_id)
				current_slot_id = expand_staffing_slots(
					available_job_slots, job_slot_inserts, current_slot_id, embedded_estab_id, dist_id,
					c_sector, c_inst, job_definitions, sim_start_day, reason_world_gen_id, rng
				)
				est_id += 1

				# Embedded civic tied accommodations
				var embedded_h_profiles: Array[Dictionary] = _extract_housing_profiles(c_arch)
				for eh_prof in embedded_h_profiles:
					var e_res_type: String = str(eh_prof.get("residence_type", "NONE"))
					if e_res_type == "NONE":
						continue

					var e_res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", e_res_type)
					var e_wealth: int = int(eh_prof.get("wealth_bracket", 2))
					var e_tenure: String = str(eh_prof.get("tenure_type", "EMPLOYMENT_TIED"))
					var e_door := "Lodge 1"
					var e_title := "%s %s" % [c_display, e_door]

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', 0, '%s', '%s', '%s', %d, 4, 1, %d, NULL, %d);
					""" % [
						est_id, dist_id, e_door, e_tenure,
						e_title.replace("'", "''"), res_unit_cat_id, sim_start_day, reason_world_gen_id
					])

					if not available_tied_housing.has(e_res_type):
						available_tied_housing[e_res_type] = []

					available_tied_housing[e_res_type].append({
						"establishment_id": est_id,
						"district_id": dist_id,
						"residence_type": e_res_type,
						"residence_type_id": e_res_type_id,
						"wealth_bracket_id": e_wealth,
						"tenure_type": e_tenure,
						"parent_workplace_id": embedded_estab_id
					})

					total_tied_units_count += 1
					est_id += 1

		# 4. Units from building_allocations
		var h_profiles: Array[Dictionary] = _extract_housing_profiles(arch)
		var housing_prof: Dictionary = h_profiles[0] if not h_profiles.is_empty() else {}
		var res_type_code: String = str(housing_prof.get("residence_type", "NONE"))
		var wealth_bracket: int = int(housing_prof.get("wealth_bracket", 2))
		var res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type_code)
		var tenure_type: String = str(housing_prof.get("tenure_type", "COUNCIL_TENANT"))

		var is_multi_flat_block: bool = (res_type_code == "COUNCIL_FLAT" or res_type_code == "FLAT_ABOVE_SHOP" or district_type == "high_density_high_rise")

		var allocations: Array = d.get("building_allocations", [])
		var block_tenancy_counts: Dictionary = {}

		for alloc in allocations:
			var b_idx: int = int(alloc["building_index"])
			var num_homes: int = int(alloc["habitable_units"])
			var num_comm: int = int(alloc["commercial_units"])
			var num_ind: int = int(alloc["industrial_units"])

			# A. Residential Units
			if num_homes > 0 and res_type_code != "NONE":
				var building_name := ""
				if is_multi_flat_block:
					var b_root: String = str(bldg_roots[rng.randi() % bldg_roots.size()])
					var b_suf: String = str(bldg_suffixes[rng.randi() % bldg_suffixes.size()])
					building_name = "%s %s" % [b_root, b_suf]

				for u_idx in range(num_homes):
					var unit_door := ""
					var unit_name := ""

					if is_multi_flat_block:
						var flat_num: int = u_idx + 1
						unit_door = fmt_flat_door.replace("{door}", str(flat_num))
						unit_name = fmt_flat_unit.replace("{door}", str(flat_num)).replace("{building}", building_name)
					else:
						var door_num: int = street_door_counter
						street_door_counter += 1
						unit_door = fmt_street_door.replace("{door}", str(door_num))
						unit_name = fmt_street_unit.replace("{door}", str(door_num)).replace("{street}", parcel_street_name)

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
						var cult: Dictionary = roll_household_culture(cultural, rng, district_type)
						var eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", cult["ethnicity"])
						var religion_id: int = DB_MANAGER.get_label_id("RELIGION", cult["religion"])

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
							"ethnicity": cult["ethnicity"],
							"ethnicity_id": eth_id,
							"religion": cult["religion"],
							"religion_id": religion_id,
							"surnames_pool": cult["surnames_pool"],
							"unemp_rate": float(arch.get("unemployment_rate_range", [0.10, 0.15])[0])
						})
						current_household_id += 1

					est_id += 1

			# B. Commercial Units
			if num_comm > 0:
				for _c in range(num_comm):
					var tenancy: Dictionary = pick_tenancy(rng, comm_classes, embedded_civic_classes, district_type)
					var cat_code: String = tenancy["code"]

					var max_per_block: int = 2 if cat_code in ["CORNER_SHOP", "LOCAL_PUB"] else 1
					var attempts := 0
					while block_tenancy_counts.get(cat_code, 0) >= max_per_block and attempts < 10:
						attempts += 1
						tenancy = pick_tenancy(rng, comm_classes, embedded_civic_classes, district_type)
						cat_code = tenancy["code"]

					block_tenancy_counts[cat_code] = block_tenancy_counts.get(cat_code, 0) + 1

					var name_result: Dictionary = _generate_business_name(
						cat_code, tenancy["display_name"], false, district_type,
						street_root, district_prefix, sim_start_year,
						comm_naming, cultural, lexicon, used_names_in_district, rng
					)
					var display_title: String = str(name_result["title"])
					used_names_in_district[display_title] = true
					if name_result.has("proprietor"):
						proprietor_hints[est_id] = name_result["proprietor"]

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
						assert(tenancy.has("sector"), "FATAL: Commercial tenancy '%s' missing mandatory 'sector' field!" % cat_code)
						var comm_sector: String = str(tenancy["sector"]).to_upper()
						current_slot_id = expand_staffing_slots(
							available_job_slots, job_slot_inserts, current_slot_id, est_id, dist_id,
							comm_sector, tenancy, job_definitions, sim_start_day, reason_world_gen_id, rng
						)

					est_id += 1

			# C. Industrial Units
			if num_ind > 0:
				for _i in range(num_ind):
					var ind_tenancy: Dictionary = pick_tenancy(rng, ind_classes, {}, district_type)
					var i_code: String = ind_tenancy["code"]
					var ind_name_res: Dictionary = _generate_business_name(
						i_code, ind_tenancy["display_name"], true, district_type,
						street_root, district_prefix, sim_start_year,
						comm_naming, cultural, lexicon, used_names_in_district, rng
					)
					var i_title: String = str(ind_name_res["title"])
					used_names_in_district[i_title] = true
					if ind_name_res.has("proprietor"):
						proprietor_hints[est_id] = ind_name_res["proprietor"]

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

					assert(ind_tenancy.has("sector"), "FATAL: Industrial tenancy '%s' missing mandatory 'sector' field!" % i_code)
					var ind_sector: String = str(ind_tenancy["sector"]).to_upper()
					current_slot_id = expand_staffing_slots(
						available_job_slots, job_slot_inserts, current_slot_id, est_id, dist_id,
						ind_sector, ind_tenancy, job_definitions, sim_start_day, reason_world_gen_id, rng
					)
					est_id += 1

		# Batch commit every 25 districts
		if block_idx > 0 and block_idx % 25 == 0:
			DB_MANAGER.execute_batch(dist_inserts)
			DB_MANAGER.execute_batch(estab_inserts)
			DB_MANAGER.execute_batch(household_inserts)
			if not job_slot_inserts.is_empty():
				DB_MANAGER.execute_batch(job_slot_inserts)
				job_slot_inserts.clear()

			dist_inserts.clear()
			estab_inserts.clear()
			household_inserts.clear()

			if on_progress.is_valid():
				var pct: float = 20.0 + ((float(block_idx) / float(districts.size())) * 30.0)
				on_progress.call(pct, 100.0, "Physical Premises: %d / %d blocks (%d units, %d slots)" % [block_idx, districts.size(), est_id - 1, current_slot_id - 1])
				var loop = Engine.get_main_loop()
				if loop is SceneTree:
					await (loop as SceneTree).process_frame

		block_idx += 1

	if not dist_inserts.is_empty():
		DB_MANAGER.execute_batch(dist_inserts)
	if not estab_inserts.is_empty():
		DB_MANAGER.execute_batch(estab_inserts)
	if not household_inserts.is_empty():
		DB_MANAGER.execute_batch(household_inserts)
	if not job_slot_inserts.is_empty():
		DB_MANAGER.execute_batch(job_slot_inserts)
		job_slot_inserts.clear()

	SystemLogger.log_info("  ✓ Pass 2: Generated %d establishments, %d active households, %d vacant tied living units, and %d workplace positions." % [
		est_id - 1, current_household_id - 1, total_tied_units_count, available_job_slots.size()
	])

	return {
		"districts": districts,
		"by_cat": by_cat,
		"households": generated_households,
		"district_residents_map": district_residents_map,
		"available_job_slots": available_job_slots,
		"available_tied_housing": available_tied_housing,
		"proprietor_hints": proprietor_hints
	}

## Resolves an era-appropriate brand, pub, location-anchored, or family proprietor business title
static func _generate_business_name(
	cat_code: String,
	base_trade_name: String,
	is_industrial: bool,
	district_type: String,
	street_root: String,
	district_prefix: String,
	calendar_year: int,
	comm_naming: Dictionary,
	cultural: Dictionary,
	lexicon: Dictionary,
	used_names: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	# 1. Dedicated Pub Name Pool
	if cat_code == "LOCAL_PUB":
		var pub_names: Array = comm_naming.get("pub_names", [])
		assert(not pub_names.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'pub_names' in commercial_naming.")
		var candidate_pub: String = str(pub_names[rng.randi() % pub_names.size()])
		if used_names.has(candidate_pub):
			candidate_pub = "%s (%s)" % [candidate_pub, street_root]
		return { "title": candidate_pub }

	# 2. Era-Windowed Corporate / High-Street Chains
	var era_brands: Dictionary = comm_naming.get("era_brands", {})
	if era_brands.has(cat_code):
		var active_brands: Array[String] = []
		for entry in era_brands[cat_code]:
			if entry is Dictionary:
				var from_yr: int = int(entry.get("valid_from_year", 1900))
				var to_yr: int = int(entry.get("valid_to_year", 2100))
				if calendar_year >= from_yr and calendar_year <= to_yr:
					active_brands.append(str(entry["name"]))
		if not active_brands.is_empty():
			var raw_brand: String = active_brands[rng.randi() % active_brands.size()]
			var resolved_brand: String = raw_brand.replace("{street_root}", street_root).replace("{district_prefix}", district_prefix)
			if used_names.has(resolved_brand) and not raw_brand.contains("{"):
				resolved_brand = "%s (%s)" % [resolved_brand, street_root]
			return { "title": resolved_brand }

	# 3. Industrial Formats
	if is_industrial:
		var ind_formats: Array = comm_naming.get("industrial_formats", [])
		assert(not ind_formats.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'industrial_formats' in commercial_naming.")
		var fmt: String = str(ind_formats[rng.randi() % ind_formats.size()])
		var cult: Dictionary = roll_household_culture(cultural, rng, district_type)
		var pool_key: String = str(cult.get("surnames_pool", "surnames"))
		var surnames_arr: Array = lexicon.get(pool_key, lexicon.get("surnames", ["Smith"]))
		var surname: String = str(surnames_arr[rng.randi() % surnames_arr.size()])
		var title: String = fmt.replace("{surname}", surname).replace("{district_prefix}", district_prefix).replace("{street_root}", street_root).replace("{trade}", base_trade_name)
		var res: Dictionary = { "title": title }
		if fmt.contains("{surname}"):
			res["proprietor"] = {
				"surname": surname,
				"ethnicity": cult["ethnicity"],
				"religion": cult["religion"],
				"surnames_pool": pool_key
			}
		return res

	# 4. Independent Commercial Trades (Family Proprietor vs Street/District Location)
	var fam_prob: float = float(comm_naming.get("family_trade_probability", 0.65))
	if rng.randf() < fam_prob:
		var fam_formats: Array = comm_naming.get("family_formats", [])
		assert(not fam_formats.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'family_formats' in commercial_naming.")
		var fmt: String = str(fam_formats[rng.randi() % fam_formats.size()])
		var cult: Dictionary = roll_household_culture(cultural, rng, district_type)
		var pool_key: String = str(cult.get("surnames_pool", "surnames"))
		var surnames_arr: Array = lexicon.get(pool_key, lexicon.get("surnames", ["Smith"]))
		var surname: String = str(surnames_arr[rng.randi() % surnames_arr.size()])
		var initial_char: String = char(65 + (rng.randi() % 26))
		var title: String = fmt.replace("{initial}", initial_char).replace("{surname}", surname).replace("{trade}", base_trade_name)
		if used_names.has(title):
			title = "%s (%s)" % [title, street_root]
		return {
			"title": title,
			"proprietor": {
				"surname": surname,
				"ethnicity": cult["ethnicity"],
				"religion": cult["religion"],
				"surnames_pool": pool_key
			}
		}
	else:
		var loc_formats: Array = comm_naming.get("location_formats", [])
		assert(not loc_formats.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'location_formats' in commercial_naming.")
		var fmt: String = str(loc_formats[rng.randi() % loc_formats.size()])
		var title: String = fmt.replace("{street_root}", street_root).replace("{district_prefix}", district_prefix).replace("{trade}", base_trade_name)
		if used_names.has(title):
			title = "%s (%s)" % [title, street_root]
		return { "title": title }

static func _extract_housing_profiles(arch: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not arch.has("housing_profile"):
		return result
	var hp = arch["housing_profile"]
	if hp is Array:
		for item in hp:
			if item is Dictionary:
				result.append(item)
	elif hp is Dictionary and not hp.is_empty():
		result.append(hp)
	return result

static func expand_staffing_slots(
	slots_array: Array[Dictionary],
	sql_inserts: Array[String],
	starting_slot_id: int,
	estab_id: int, 
	dist_id: String, 
	sector_category_code: String, 
	host_def: Dictionary, 
	job_definitions: Dictionary,
	sim_start_day: int,
	reason_id: int,
	rng: RandomNumberGenerator
) -> int:
	var slot_id_counter: int = starting_slot_id
	var estab_multiplier: float = float(host_def.get("wage_multiplier", 1.0))
	var estab_bonus: float = float(host_def.get("wage_bonus", 0.0))

	# Sector Category lookup - fail loud if missing or invalid
	assert(not sector_category_code.is_empty(), "FATAL: Empty sector_category provided for establishment ID %d!" % estab_id)
	var sector_category_id: int = DB_MANAGER.get_label_id("SECTOR_CATEGORY", sector_category_code)

	# Extract canonical master roles dictionary
	var master_roles: Dictionary = job_definitions.get("roles", job_definitions)

	if host_def.has("staffing_roster"):
		for item in host_def["staffing_roster"]:
			var job_code: String = str(item.get("job_id", item.get("role_title", "")))
			assert(not job_code.is_empty(), "FATAL: Staffing roster entry missing 'job_id' or 'role_title' in establishment %d!" % estab_id)
			assert(master_roles.has(job_code), "FATAL: Undefined job role '%s' referenced in staffing roster for establishment %d!" % [job_code, estab_id])
			var master_job: Dictionary = master_roles[job_code]

			# Resolve contract_type: Roster item override > Building Class override > Job definition baseline
			var contract_type_code: String = ""
			if item.has("contract_type"):
				contract_type_code = str(item["contract_type"])
			elif host_def.has("contract_type"):
				contract_type_code = str(host_def["contract_type"])
			elif master_job.has("contract_type"):
				contract_type_code = str(master_job["contract_type"])
			else:
				assert(false, "FATAL: Job role '%s' (establishment %d) is missing mandatory 'contract_type' in roster item, building_classes, or job_definitions!" % [job_code, estab_id])

			var contract_type_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", contract_type_code)

			var contract_class: String = str(item.get("contract_class", master_job.get("contract_class", "")))
			assert(not contract_class.is_empty(), "FATAL: Role '%s' missing mandatory 'contract_class'!" % job_code)
			var class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)

			var edu_req: String = str(item.get("education_required", master_job.get("education_required", "")))
			assert(not edu_req.is_empty(), "FATAL: Role '%s' missing mandatory 'education_required'!" % job_code)
			var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", edu_req)

			var schedule_code: String = str(item.get("schedule_window", master_job.get("schedule_window", "")))
			assert(not schedule_code.is_empty(), "FATAL: Role '%s' missing mandatory 'schedule_window'!" % job_code)
			var sched_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", schedule_code)

			var hours: float = float(item.get("weekly_hours", master_job.get("weekly_hours", 37.5)))
			var is_field: bool = bool(item.get("is_field_worker", master_job.get("is_field_worker", false)))
			var tied_res: String = str(item.get("tied_accomodation", ""))

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
			else:
				assert(false, "FATAL: No hourly rate or range declared for role '%s'!" % job_code)

			var count_range: Array = item.get("target_count", [1, 1])
			var count: int = rng.randi_range(int(count_range[0]), int(count_range[1]))
			var role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", job_code)

			for _i in range(count):
				var s_id: int = slot_id_counter
				slot_id_counter += 1

				slots_array.append({
					"slot_id": s_id,
					"estab_id": estab_id,
					"district_id": dist_id,
					"sector_category_id": sector_category_id,
					"role_title": job_code,
					"role_title_id": role_id,
					"contract_class": contract_class,
					"contract_class_id": class_id,
					"contract_type_id": contract_type_id,
					"edu_req": edu_req,
					"min_education_level_id": edu_id,
					"schedule_window_id": sched_id,
					"rate": resolved_rate,
					"hours": hours,
					"is_field_worker": is_field,
					"tied_accomodation": tied_res
				})

				sql_inserts.append("""
					INSERT INTO workplace_job_slots (
						slot_id, establishment_id, sector_category_id, role_title_id,
						contract_class_id, contract_type_id, min_education_level_id, schedule_window_id,
						weekly_hours, hourly_rate, is_field_worker,
						is_filled, active_resident_id, valid_from, valid_to, change_reason_id
					) VALUES (
						%d, %d, %d, %d,
						%d, %d, %d, %d,
						%.1f, %.2f, %d,
						0, NULL, %d, NULL, %d
					);
				""" % [
					s_id, estab_id, sector_category_id, role_id,
					class_id, contract_type_id, edu_id, sched_id,
					hours, resolved_rate, 1 if is_field else 0,
					sim_start_day, reason_id
				])

	else:
		var emp_range: Array = host_def.get("employee_range", host_def.get("default_employees", [1, 3]))
		var count: int = rng.randi_range(int(emp_range[0]), int(emp_range[1]))
		var fallback_job: String = "MANUAL_WORKS" if sector_category_code == "INDUSTRIAL" else "COMMERCIAL_SERVICE"
		assert(master_roles.has(fallback_job), "FATAL: Standard fallback role '%s' missing in job_definitions!" % fallback_job)
		var master: Dictionary = master_roles[fallback_job]

		# Resolve contract_type: Building Class override > Fallback role baseline
		var contract_type_code: String = ""
		if host_def.has("contract_type"):
			contract_type_code = str(host_def["contract_type"])
		elif master.has("contract_type"):
			contract_type_code = str(master["contract_type"])
		else:
			assert(false, "FATAL: Fallback role '%s' missing mandatory 'contract_type' in building_classes or job_definitions!" % fallback_job)

		var contract_type_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", contract_type_code)

		var contract_class: String = str(master.get("contract_class", "FORMAL_LEGAL"))
		var formal_class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)

		var default_edu: String = str(master.get("education_required", "NO_FORMAL"))
		var fallback_edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", default_edu)

		var fallback_sched_code: String = str(master.get("schedule_window", "DAYTIME"))
		var fallback_sched_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", fallback_sched_code)

		var default_hours: float = float(master.get("weekly_hours", 37.5))
		var r_range: Array = master.get("hourly_rate_range", [3.20, 3.80])
		var fallback_role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", fallback_job)

		for _i in range(count):
			var s_id: int = slot_id_counter
			slot_id_counter += 1

			var rate: float = snappedf(rng.randf_range(float(r_range[0]), float(r_range[1])) * estab_multiplier, 0.05)

			slots_array.append({
				"slot_id": s_id,
				"estab_id": estab_id,
				"district_id": dist_id,
				"sector_category_id": sector_category_id,
				"role_title": fallback_job,
				"role_title_id": fallback_role_id,
				"contract_class": contract_class,
				"contract_class_id": formal_class_id,
				"contract_type_id": contract_type_id,
				"edu_req": default_edu,
				"min_education_level_id": fallback_edu_id,
				"schedule_window_id": fallback_sched_id,
				"rate": rate,
				"hours": default_hours,
				"is_field_worker": false,
				"tied_accomodation": ""
			})

			sql_inserts.append("""
				INSERT INTO workplace_job_slots (
					slot_id, establishment_id, sector_category_id, role_title_id,
					contract_class_id, contract_type_id, min_education_level_id, schedule_window_id,
					weekly_hours, hourly_rate, is_field_worker,
					is_filled, active_resident_id, valid_from, valid_to, change_reason_id
				) VALUES (
					%d, %d, %d, %d,
					%d, %d, %d, %d,
					%.1f, %.2f, 0,
					0, NULL, %d, NULL, %d
				);
			""" % [
				s_id, estab_id, sector_category_id, fallback_role_id,
				formal_class_id, contract_type_id, fallback_edu_id, fallback_sched_id,
				default_hours, rate,
				sim_start_day, reason_id
			])

	return slot_id_counter

static func pick_tenancy(rng: RandomNumberGenerator, primary_classes: Dictionary, secondary_classes: Dictionary, district_type: String) -> Dictionary:
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
		return {"code": "COMMERCIAL", "display_name": "Local Retail Unit", "sector": "COMMERCIAL", "default_capacity": 10, "required_customer_threshold": 50, "customer_travel_distance_m": 500.0}

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

static func roll_household_culture(cultural: Dictionary, rng: RandomNumberGenerator, district_type: String) -> Dictionary:
	var weights_key := "high_density" if district_type.begins_with("high_density") else ("commercial" if district_type == "commercial" else "suburban_low_density")
	var dist_weights: Dictionary = cultural["district_ethnic_weights"][weights_key]
	var defaults: Dictionary = cultural["defaults"]

	var chosen_eth: String = defaults["fallback_ethnicity"]
	var roll := rng.randf()
	var cumulative := 0.0
	for eth in dist_weights.keys():
		cumulative += float(dist_weights[eth])
		if roll <= cumulative:
			chosen_eth = eth
			break

	var eth_profile: Dictionary = cultural["ethnicities"][chosen_eth]
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