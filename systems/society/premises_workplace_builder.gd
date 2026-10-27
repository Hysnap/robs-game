# res://systems/society/premises_workplace_builder.gd
class_name PremisesWorkplaceBuilder
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

## Pass 2: Populates physical establishments, households, and job slots
static func run(
	world_state: Dictionary,
	archetypes: Dictionary,
	building_classes: Dictionary,
	job_definitions: Dictionary,
	cultural: Dictionary,
	rng: RandomNumberGenerator,
	on_progress: Callable
) -> Dictionary:
	var districts: Dictionary = world_state.get("districts", {})
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
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

	var est_id: int = 1
	var current_household_id: int = 1
	var current_slot_id: int = 1
	var block_idx: int = 0

	var block_estimates: Dictionary = {}
	for dist_id in districts.keys():
		block_estimates[dist_id] = float(districts[dist_id].get("estimated_population", 0.0))

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
			_register_est_cat(by_cat, "CIVIC", est_id, dist_id)
			
			current_slot_id = expand_staffing_slots(
				available_job_slots, job_slot_inserts, current_slot_id,
				est_id, dist_id, cat_name, cat_id,
				inst, job_definitions, sim_start_day, reason_world_gen_id, rng
			)
			est_id += 1

		# 2. Sub-Block Embedded Civics placed in Pass 1
		if d.has("embedded_civics"):
			for civic_key in d["embedded_civics"]:
				var c_arch: Dictionary = archetypes.get(civic_key, {})
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
				_register_est_cat(by_cat, "CIVIC", est_id, dist_id)

				current_slot_id = expand_staffing_slots(
					available_job_slots, job_slot_inserts, current_slot_id,
					est_id, dist_id, c_cat_name, c_cat_id,
					c_inst, job_definitions, sim_start_day, reason_world_gen_id, rng
				)
				est_id += 1

		# 3. Units from building_allocations
		var housing_prof: Dictionary = arch.get("housing_profile", {})
		var res_type_code: String = str(housing_prof.get("residence_type", "NONE"))
		var wealth_bracket: int = int(housing_prof.get("wealth_bracket", 2))
		var res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type_code)
		var tenure_type: String = str(housing_prof.get("tenure_type", "COUNCIL_TENANT"))

		var allocations: Array = d.get("building_allocations", [])
		var block_tenancy_counts: Dictionary = {}

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
							"ethnicity_id": eth_id,
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

					# Local block tenancy collision avoidance
					var max_per_block: int = 2 if cat_code in ["CORNER_SHOP", "LOCAL_PUB"] else 1
					var attempts := 0
					while block_tenancy_counts.get(cat_code, 0) >= max_per_block and attempts < 10:
						attempts += 1
						tenancy = pick_tenancy(rng, comm_classes, embedded_civic_classes, district_type)
						cat_code = tenancy["code"]

					block_tenancy_counts[cat_code] = block_tenancy_counts.get(cat_code, 0) + 1

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
						current_slot_id = expand_staffing_slots(
							available_job_slots, job_slot_inserts, current_slot_id,
							est_id, dist_id, "COMMERCIAL", cat_id,
							tenancy, job_definitions, sim_start_day, reason_world_gen_id, rng
						)

					est_id += 1

			# C. Industrial Units
			if num_ind > 0:
				for _i in range(num_ind):
					var ind_tenancy: Dictionary = pick_tenancy(rng, ind_classes, {}, district_type)
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

					current_slot_id = expand_staffing_slots(
						available_job_slots, job_slot_inserts, current_slot_id,
						est_id, dist_id, "INDUSTRIAL", i_cat_id,
						ind_tenancy, job_definitions, sim_start_day, reason_world_gen_id, rng
					)
					est_id += 1

		# Batch commit every 25 districts
		if block_idx > 0 and block_idx % 25 == 0:
			DB_MANAGER.execute_batch(dist_inserts)
			DB_MANAGER.execute_batch(estab_inserts)
			DB_MANAGER.execute_batch(household_inserts)
			DB_MANAGER.execute_batch(job_slot_inserts)
			dist_inserts.clear()
			estab_inserts.clear()
			household_inserts.clear()
			job_slot_inserts.clear()

			if on_progress.is_valid():
				var pct: float = 20.0 + ((float(block_idx) / float(districts.size())) * 30.0)
				on_progress.call(pct, 100.0, "Physical Premises: %d / %d blocks (%d units, %d slots)" % [block_idx, districts.size(), est_id - 1, current_slot_id - 1])
				await Engine.get_main_loop().process_frame

		block_idx += 1

	if not dist_inserts.is_empty():
		DB_MANAGER.execute_batch(dist_inserts)
	if not estab_inserts.is_empty():
		DB_MANAGER.execute_batch(estab_inserts)
	if not household_inserts.is_empty():
		DB_MANAGER.execute_batch(household_inserts)
	if not job_slot_inserts.is_empty():
		DB_MANAGER.execute_batch(job_slot_inserts)

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

## Single authoritative staffing generator: unrolls master job definitions, records DB rows, and queues slot tracking
static func expand_staffing_slots(
	slots_array: Array[Dictionary],
	sql_inserts: Array[String],
	starting_slot_id: int,
	estab_id: int,
	dist_id: String,
	category_code: String,
	cat_label_id: int,
	host_def: Dictionary,
	job_definitions: Dictionary,
	sim_start_day: int,
	reason_id: int,
	rng: RandomNumberGenerator
) -> int:
	var estab_multiplier: float = float(host_def.get("wage_multiplier", 1.0))
	var estab_bonus: float = float(host_def.get("wage_bonus", 0.0))
	var next_slot_id: int = starting_slot_id

	# 1. Multi-role detailed roster
	if host_def.has("staffing_roster"):
		for item in host_def["staffing_roster"]:
			var job_code: String = str(item.get("job_id", item.get("role_title", "COMMERCIAL_SERVICE")))
			var master_job: Dictionary = job_definitions.get(job_code, {})

			var contract_class: String = str(item.get("contract_class", master_job.get("contract_class", "FORMAL_LEGAL")))
			var edu_req: String = str(item.get("education_required", master_job.get("education_required", "NO_FORMAL")))
			var hours: float = float(item.get("weekly_hours", master_job.get("weekly_hours", 37.5)))
			var is_field: bool = bool(item.get("is_field_worker", master_job.get("is_field_worker", false)))
			var contract_type_code: String = str(item.get("contract_type", master_job.get("contract_type", "STANDARD")))
			var contract_type_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", contract_type_code)

			var schedule_code: String = str(item.get("schedule_window", master_job.get("schedule_window", "DAYTIME")))
			var schedule_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", schedule_code)
			
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

			var role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", job_code)
			var class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)
			var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", edu_req)

			for _i in range(count):
				var slot_id: int = next_slot_id
				next_slot_id += 1

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
					slot_id, estab_id, cat_label_id, role_id,
					class_id, contract_type_id, edu_id, schedule_id,
					hours, resolved_rate, 1 if is_field else 0,
					sim_start_day, reason_id
				])

				slots_array.append({
					"slot_id": slot_id,
					"estab_id": estab_id,
					"district_id": dist_id,
					"cat": category_code,
					"cat_id": cat_label_id,
					"role": job_code,
					"role_id": role_id,
					"contract_class": contract_class,
					"contract_class_id": class_id,
					"contract_type": contract_type_code,
					"contract_type_id": contract_type_id,
					"edu_req": edu_req,
					"edu_id": edu_id,
					"rate": resolved_rate,
					"hours": hours,
					"schedule_window": schedule_code,
					"schedule_window_id": schedule_id,
					"is_field_worker": is_field
				})

	# 2. Single employee_range fallback
	else:
		var emp_range: Array = host_def.get("employee_range", host_def.get("default_employees", [1, 3]))
		var count: int = rng.randi_range(int(emp_range[0]), int(emp_range[1]))
		var fallback_job: String = "MANUAL_WORKS" if category_code == "INDUSTRIAL" else "COMMERCIAL_SERVICE"
		var master: Dictionary = job_definitions.get(fallback_job, {})
		
		var default_edu: String = str(master.get("education_required", "NO_FORMAL"))
		var default_hours: float = float(master.get("weekly_hours", 37.5))
		var r_range: Array = master.get("hourly_rate_range", [3.20, 3.80])

		var role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", fallback_job)
		var class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", "FORMAL_LEGAL")
		var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", default_edu)
		var contract_type_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", "STANDARD")
		var schedule_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", "DAYTIME")
		
		for _i in range(count):
			var slot_id: int = next_slot_id
			next_slot_id += 1
			var rate: float = snappedf(rng.randf_range(float(r_range[0]), float(r_range[1])) * estab_multiplier, 0.05)

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
				slot_id, estab_id, cat_label_id, role_id,
				class_id, contract_type_id, edu_id, schedule_id,
				default_hours, rate,
				sim_start_day, reason_id
			])

			slots_array.append({
				"slot_id": slot_id,
				"estab_id": estab_id,
				"district_id": dist_id,
				"cat": category_code,
				"cat_id": cat_label_id,
				"role": fallback_job,
				"role_id": role_id,
				"contract_class": "FORMAL_LEGAL",
				"contract_class_id": class_id,
				"contract_type": "STANDARD",
				"contract_type_id": contract_type_id,
				"edu_req": default_edu,
				"edu_id": edu_id,
				"rate": rate,
				"hours": default_hours,
				"schedule_window": "DAYTIME",
				"schedule_window_id": schedule_id,
				"is_field_worker": false
			})

	return next_slot_id

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