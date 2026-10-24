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

## Loads configurations strictly via the centralized ScenarioManifestManager
static func _load_configs() -> void:
	if not _demographics.is_empty() and not _lexicon.is_empty() and not _cultural.is_empty() and not _civic_hierarchy.is_empty() and not _archetypes.is_empty():
		return

	_demographics = MANIFEST_MGR.load_module("demographics")
	_lexicon = MANIFEST_MGR.load_module("lexicon")
	_cultural = MANIFEST_MGR.load_module("cultural_demographics")
	_civic_hierarchy = MANIFEST_MGR.load_module("civic_hierarchy")

	# Archetypes ingested strictly through ScenarioManifestManager
	assert(MANIFEST_MGR.has_module("archetypes") or MANIFEST_MGR.has_module("spatial_archetypes"), 
		"FATAL: Scenario manifest missing 'archetypes' module registration.")
	
	if MANIFEST_MGR.has_module("archetypes"):
		_archetypes = MANIFEST_MGR.load_module("archetypes")
	else:
		_archetypes = MANIFEST_MGR.load_module("spatial_archetypes")

	assert(not _archetypes.is_empty(), "FATAL: Loaded archetypes dictionary is empty.")

## Main Generation Pipeline
static func generate_city_society(world_state: Dictionary, seed_id: String, force_regenerate: bool = false, on_progress: Callable = Callable()) -> void:
	if not force_regenerate and DB_MANAGER.is_society_populated(seed_id):
		print("[SocialNetwork] Society for seed '%s' already exists in SQLite. Skipping generation." % seed_id)
		return

	_load_configs()
	DB_MANAGER.initialize_database(true)
	DB_MANAGER.record_active_seed(seed_id)

	var start_ms: int = Time.get_ticks_msec()
	print("[SocialNetwork] Building living society, normalized establishments, and Dunbar graph...")

	var districts: Dictionary = world_state.get("districts", {})
	assert(not districts.is_empty(), "FATAL: world_state has no districts during society generation.")

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_id.hash())

	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var male_gender_id: int = DB_MANAGER.get_label_id("GENDER", "M")
	var female_gender_id: int = DB_MANAGER.get_label_id("GENDER", "F")
	var contract_std_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", "STANDARD")
	var comm_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "COMMERCIAL")
	var ind_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "INDUSTRIAL")
	var res_unit_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "RESIDENTIAL_UNIT")

	var h_scales: Dictionary = _civic_hierarchy.get("hierarchy_scales", {})
	assert(h_scales.has("blocks_per_borough"), "FATAL: 'blocks_per_borough' missing in hierarchy_scales.")
	assert(h_scales.has("family_size_min"), "FATAL: 'family_size_min' missing in hierarchy_scales.")
	assert(h_scales.has("family_size_max"), "FATAL: 'family_size_max' missing in hierarchy_scales.")

	var blocks_per_borough: int = int(h_scales["blocks_per_borough"])
	var fam_min: int = int(h_scales["family_size_min"])
	var fam_max: int = int(h_scales["family_size_max"])

	var est_templates: Dictionary = _civic_hierarchy.get("establishment_templates", {})
	var comm_names: Array = est_templates.get("COMMERCIAL", {}).get("names", ["High St Retail"])
	var ind_names: Array = est_templates.get("INDUSTRIAL", {}).get("names", ["Depot & Works"])
	var comm_cap: int = int(est_templates.get("COMMERCIAL", {}).get("default_capacity", 30))
	var ind_cap: int = int(est_templates.get("INDUSTRIAL", {}).get("default_capacity", 60))

	var male_names: Array = _lexicon.get("first_names_male", [])
	var female_names: Array = _lexicon.get("first_names_female", [])
	assert(not male_names.is_empty(), "FATAL: 'first_names_male' empty in lexicon.")
	assert(not female_names.is_empty(), "FATAL: 'first_names_female' empty in lexicon.")

	var by_cat: Dictionary = {
		"COMMERCIAL": [],
		"INDUSTRIAL": [],
		"RESIDENTIAL_UNIT": []
	}

	var estab_inserts: Array[String] = []
	var household_inserts: Array[String] = []
	var resident_inserts: Array[String] = []
	var contract_inserts: Array[String] = []
	var edge_inserts: Array[String] = []

	var est_id: int = 1
	var current_household_id: int = 1
	var current_resident_id: int = 1
	var block_idx: int = 0

	var generated_households: Array[Dictionary] = []
	var district_residents_map: Dictionary = {}
	var dist_inserts: Array[String] = []

	# =========================================================================
	# UNIFIED PHYSICAL PASS: BUILDINGS, UNITS, ESTABLISHMENTS & HOUSEHOLDS
	# =========================================================================
	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var district_type: String = str(d.get("district_type", ""))
		assert(_archetypes.has(district_type), "FATAL: Archetype '%s' not registered." % district_type)

		var arch: Dictionary = _archetypes[district_type]
		var borough_id := 1
		var coords: Vector2i = d.get("grid_coords", Vector2i(0,0))
		var bldgs_range: Array = arch.get("buildings", [1, 1])
		var pop_range: Array = arch.get("population_range", [0, 0])

		dist_inserts.append("""
	        INSERT INTO districts (
    	        district_id, borough_id, display_name, district_type,
       		    grid_x, grid_z, grid_width, grid_height,
	            target_building_count, expected_pop_min, expected_pop_max,
            	base_unemployment_rate, base_disposable_income, base_zone_health, base_police_heat,
	            is_home_turf, valid_from, valid_to, change_reason_id
    	    ) VALUES (
	            '%s', '%s', '%s', '%s',
	            %d, %d, %d, %d,
	            %d, %d, %d,
	            %f, %f, %f, %f,
            	0, %d, NULL, %d
        	);
    	""" % [
        	dist_id, borough_id, str(d.get("display_name", dist_id)).replace("'", "''"), district_type,
        	coords.x, coords.y, d.get("grid_size", Vector2i(1,1)).x, d.get("grid_size", Vector2i(1,1)).y,
        	d.get("actual_building_count", bldgs_range[0]), pop_range[0], pop_range[1],
        	float(d.get("unemployment_rate", 0.0)), float(d.get("avg_disposable_income", 75.0)),
        	float(d.get("zone_health_index", 50.0)), float(d.get("actual_police_heat", 0.20)),
        	sim_start_day, reason_world_gen_id
    	])

		DB_MANAGER.execute_batch(dist_inserts)

		district_residents_map[dist_id] = []

		# 1. Macro Civic Anchor Check (Town Hall, Hospital, School, etc.)
		if arch.has("institution_profile"):
			var inst: Dictionary = arch["institution_profile"]
			var cat_name: String = str(arch.get("establishment_category", district_type.to_upper()))
			var display_label: String = str(arch.get("display_name", cat_name)).replace("'", "''")
			var capacity: int = int(inst.get("default_capacity", 250))
			var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_name)

			estab_inserts.append("""
				INSERT INTO establishments (
					establishment_id, borough_id, district_id, owning_entity, name,
					category_id, capacity, valid_from, valid_to, change_reason_id
				) VALUES (%d, '%s', '%s', 'CIVIC', '%s', %d, %d, %d, NULL, %d);
			""" % [est_id, borough_id, dist_id, display_label, cat_id, capacity, sim_start_day, reason_world_gen_id])

			if not by_cat.has(cat_name):
				by_cat[cat_name] = []
			by_cat[cat_name].append({"id": est_id, "district_id": dist_id})
			est_id += 1

		# 2. Multi-cell block scale factor
		var block_size: Vector2i = d.get("grid_size", Vector2i(1, 1))
		var native_footprint: Array = arch.get("footprint_size", [1, 1])

		# 3. Roll physical buildings ONCE per block
		var scale_factor: float = float(block_size.x * block_size.y) if (int(native_footprint[0]) * int(native_footprint[1]) == 1) else 1.0
		var min_bldgs: int = int(round(float(bldgs_range[0]) * scale_factor))
		var max_bldgs: int = int(round(float(bldgs_range[1]) * scale_factor))
		var building_count: int = rng.randi_range(min_bldgs, max_bldgs)
		d["actual_building_count"] = building_count

		var hab_range: Array = arch.get("habitable_units_per_building", [0, 0])
		var comm_range: Array = arch.get("commercial_units_per_building", [0, 0])
		var ind_range: Array = arch.get("industrial_units_per_building", [0, 0])
		var perc_arr: Array = arch.get("res_com_ind_perc", [100, 0, 0])

		var r_chance: float = float(perc_arr[0])
		var c_chance: float = float(perc_arr[1])
		var i_chance: float = float(perc_arr[2])

		var housing_prof: Dictionary = arch.get("housing_profile", {})
		var res_type_code: String = str(housing_prof.get("residence_type", "NONE"))
		var wealth_bracket: int = int(housing_prof.get("wealth_bracket", 2))
		var res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type_code)
		var tenure_type: String = str(housing_prof.get("tenure_type", "COUNCIL_TENANT"))

		# 4. Generate discrete physical units across each building
		for b_idx in range(building_count):
			# A. Residential Units (Flats / Houses as Establishments + Households)
			if res_type_code != "NONE" and (rng.randf() * 100.0) < r_chance:
				var num_homes: int = rng.randi_range(int(hab_range[0]), int(hab_range[1]))
				for u_idx in range(num_homes):
					var unit_door := "Unit %d-%d" % [b_idx + 1, u_idx + 1]
					var unit_name := "%s, %s (%s)" % [unit_door, arch.get("display_name", "Parade"), dist_id]
					var is_vacant: int = 1 if (rng.randf() < 0.04) else 0 # 4% natural baseline vacancy

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, borough_id, district_id, building_id, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', '%s', '%s','%s', '%s', '%s', %d, 5, %d, %d, NULL, %d);
					""" % [
						est_id, borough_id, dist_id, b_idx, unit_door, tenure_type,
						unit_name.replace("'", "''"), res_unit_cat_id, is_vacant, sim_start_day, reason_world_gen_id
					])

					if is_vacant == 0:
						var culture: Dictionary = _roll_household_culture(rng, district_type)
						var eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", culture["ethnicity"])
						var rel_id: int = DB_MANAGER.get_label_id("RELIGION", culture["religion"])

						household_inserts.append("""
							INSERT INTO households (
								household_id, establishment_id, residence_type_id,
								wealth_bracket_id, local_pub_id, ethnicity_id, religion_id,
								valid_from, valid_to, change_reason_id
							) VALUES (%d, %d, %d, %d, NULL, %d, %d, %d, NULL, %d);
						""" % [
							current_household_id, est_id, res_type_id,
							wealth_bracket, eth_id, rel_id, sim_start_day, reason_world_gen_id
						])

						generated_households.append({
							"household_id": current_household_id,
							"establishment_id": est_id,
							"district_id": dist_id,
							"district_type": district_type,
							"ethnicity_id": eth_id,
							"religion_id": rel_id,
							"surnames_pool": culture["surnames_pool"],
							"unemp_rate": float(arch.get("unemployment_rate_range", [0.10, 0.15])[0])
						})
						current_household_id += 1

					est_id += 1

			# B. Commercial Establishments
			if (rng.randf() * 100.0) < c_chance:
				var num_comm: int = rng.randi_range(int(comm_range[0]), int(comm_range[1]))
				for _c in range(num_comm):
					var c_name: String = "%s (%s)" % [comm_names[rng.randi() % comm_names.size()], dist_id]
					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, borough_id, district_id, building_id, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', '%s', '%s', 'SHOP', 'PRIVATE', '%s', %d, %d, 0, %d, NULL, %d);
					""" % [est_id, borough_id, dist_id, b_idx, c_name.replace("'", "''"), comm_cat_id, comm_cap, sim_start_day, reason_world_gen_id])

					by_cat["COMMERCIAL"].append({"id": est_id, "district_id": dist_id})
					est_id += 1

			# C. Industrial Establishments
			if (rng.randf() * 100.0) < i_chance:
				var num_ind: int = rng.randi_range(int(ind_range[0]), int(ind_range[1]))
				for _i in range(num_ind):
					var i_name: String = "%s (%s)" % [ind_names[rng.randi() % ind_names.size()], dist_id]
					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, borough_id, district_id, building_id, unit_door_number,
							owning_entity, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', '%s', '%s',  'WORKS', 'PRIVATE', '%s', %d, %d, 0, %d, NULL, %d);
					""" % [est_id, borough_id, dist_id, b_idx, i_name.replace("'", "''"), ind_cat_id, ind_cap, sim_start_day, reason_world_gen_id])

					by_cat["INDUSTRIAL"].append({"id": est_id, "district_id": dist_id})
					est_id += 1

			if on_progress.is_valid() and (block_idx % 20 == 0 or block_idx == districts.size()):
				on_progress.call(float(block_idx), float(districts.size()), "Ward %d / %d" % [block_idx, districts.size()])
				# Yield frame so the UI bar can animate smoothly
				Engine.get_main_loop().process_frame

		block_idx += 1

	# Commit Establishments and Households to SQLite
	DB_MANAGER.execute_batch(estab_inserts)
	DB_MANAGER.execute_batch(household_inserts)
	print("  ✓ Created %d normalized establishments across sectors." % (est_id - 1))
	print("  ✓ Created %d physical household tenancies." % (current_household_id - 1))

	# =========================================================================
	# RESIDENT CITIZEN HYDRATION & CONTRACT ATTACHMENTS
	# =========================================================================
	var rel_family_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "FAMILY")
	var rel_drinking_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "DRINKING_MATE")

	for hh in generated_households:
		var family_size := rng.randi_range(fam_min, fam_max)
		var surname_list: Array = _lexicon.get(hh["surnames_pool"], ["Smith"])
		var family_surname: String = str(surname_list[rng.randi() % surname_list.size()]).replace("'", "''")
		var is_high_dense: bool = str(hh["district_type"]).begins_with("high_density")
		var household_members: Array[int] = []

		for _m in range(family_size):
			var r_id := current_resident_id
			current_resident_id += 1
			household_members.append(r_id)
			district_residents_map[hh["district_id"]].append(r_id)

			var is_male: bool = (rng.randf() > 0.5)
			var gender_id: int = male_gender_id if is_male else female_gender_id
			var first_name: String = str(male_names[rng.randi() % male_names.size()] if is_male else female_names[rng.randi() % female_names.size()]).replace("'", "''")

			var demo_profile: Dictionary = _resolve_citizen_demographics(rng, is_high_dense, is_male, hh["unemp_rate"], 0.70)
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

			# Contract linking
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

		# Circle 1: Kinship
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

	if not resident_inserts.is_empty():
		DB_MANAGER.execute_batch(resident_inserts)
		DB_MANAGER.execute_batch(contract_inserts)
		DB_MANAGER.execute_batch(edge_inserts)

	# Circle 2: Pub Catchment Edges per district
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

	# Secondary Dunbar Passes
	_generate_extended_kinship(rng, sim_start_day, reason_world_gen_id)
	_generate_establishment_peer_ties(rng, sim_start_day, reason_world_gen_id)
	_generate_faith_and_cultural_ties(rng, sim_start_day, reason_world_gen_id)

	var elapsed: int = Time.get_ticks_msec() - start_ms
	print("  ✓ Created %d living residents across households." % (current_resident_id - 1))
	print("[SocialNetwork] Completed living society generation in %d ms." % elapsed)

## Picks a valid establishment ID for a category, resolving fallbacks via demographics config
static func _pick_anchor(by_cat: Dictionary, requested_category: String, dist_id: String, rng: RandomNumberGenerator) -> int:
	var target_cat: String = requested_category
	var list: Array = by_cat.get(target_cat, [])

	# If category has no instances, consult anchor_category_fallbacks from demographics.json
	if list.is_empty():
		var fallbacks: Dictionary = _demographics.get("anchor_category_fallbacks", {})
		if fallbacks.has(target_cat):
			target_cat = str(fallbacks[target_cat])
			list = by_cat.get(target_cat, [])
		elif fallbacks.has("DEFAULT"):
			target_cat = str(fallbacks["DEFAULT"])
			list = by_cat.get(target_cat, [])

	assert(not list.is_empty(), 
		"FATAL: No establishment exists for category '%s' (fallback '%s') referenced by district '%s'" % [
			requested_category, target_cat, dist_id
		])

	var picked: Dictionary = list[rng.randi() % list.size()]
	return picked["id"]

## Purely Data-Driven Demographic Engine
static func _resolve_citizen_demographics(rng: RandomNumberGenerator, is_high_density: bool, is_male: bool, unemp_rate: float, comm_share: float) -> Dictionary:
	var cohorts: Array = _demographics.get("cohort_profiles", [])
	assert(not cohorts.is_empty(), "FATAL: 'cohort_profiles' missing in demographics JSON")

	var thresholds: Dictionary = _demographics.get("legal_and_pension_thresholds", {})
	assert(thresholds.has("pension_age_male") and thresholds.has("pension_age_female"), "FATAL: Pension thresholds missing.")

	var life_caps: Dictionary = _demographics.get("life_expectancy_caps", {})
	assert(life_caps.has("male_max_age") and life_caps.has("female_max_age"), "FATAL: Life expectancy caps missing.")

	var pen_age: int = int(thresholds["pension_age_male"] if is_male else thresholds["pension_age_female"])
	var max_age: int = int(life_caps["male_max_age"] if is_male else life_caps["female_max_age"])
	var density_key := "high_density" if is_high_density else "suburban_low_density"

	# 1. Roll Cohort based on weighted density distribution
	var roll := rng.randf()
	var cumulative := 0.0
	var chosen_cohort: Dictionary = cohorts[0]

	for c in cohorts:
		assert(c.has("density_weights") and c["density_weights"].has(density_key), "FATAL: Cohort missing density weight for '%s'" % density_key)
		cumulative += float(c["density_weights"][density_key])
		if roll <= cumulative:
			chosen_cohort = c
			break

	# 2. Determine Age
	assert(chosen_cohort.has("age_min") or chosen_cohort.has("age_min_dynamic"), "FATAL: Cohort missing age_min specification.")
	assert(chosen_cohort.has("age_max") or chosen_cohort.has("age_max_dynamic"), "FATAL: Cohort missing age_max specification.")

	var age_min: int = pen_age if (chosen_cohort.get("age_min_dynamic") == "pension_age") else int(chosen_cohort["age_min"])
	var age_max: int = int(chosen_cohort.get("age_max", 70))
	if chosen_cohort.has("age_max_dynamic"):
		age_max = (pen_age - 1) if (chosen_cohort["age_max_dynamic"] == "pension_age") else max_age

	var resolved_age: int = rng.randi_range(age_min, age_max)
	
	# 3. Resolve Contract & Role strictly from configuration strategy
	assert(chosen_cohort.has("strategy"), "FATAL: Cohort missing 'strategy'")
	var strategy: String = chosen_cohort["strategy"]
	var profile_data: Dictionary = {}

	match strategy:
		"FIXED":
			profile_data = chosen_cohort

		"PROBABILISTIC":
			assert(chosen_cohort.has("condition_probability"), "FATAL: PROBABILISTIC cohort missing condition_probability")
			assert(chosen_cohort.has("if_true") and chosen_cohort.has("if_false"), "FATAL: PROBABILISTIC cohort missing if_true/if_false")
			var prob: float = float(chosen_cohort["condition_probability"])
			profile_data = chosen_cohort["if_true"] if (rng.randf() < prob) else chosen_cohort["if_false"]

		"LABOR_MARKET":
			assert(chosen_cohort.has("unemployed_branch"), "FATAL: LABOR_MARKET cohort missing unemployed_branch")
			assert(chosen_cohort.has("commercial_branch"), "FATAL: LABOR_MARKET cohort missing commercial_branch")
			assert(chosen_cohort.has("industrial_branch"), "FATAL: LABOR_MARKET cohort missing industrial_branch")
			
			if rng.randf() < unemp_rate:
				profile_data = chosen_cohort["unemployed_branch"]
			elif rng.randf() < comm_share:
				profile_data = chosen_cohort["commercial_branch"]
			else:
				profile_data = chosen_cohort["industrial_branch"]

		_:
			assert(false, "FATAL: Unrecognized cohort strategy: '%s'" % strategy)

	assert(profile_data.has("role"), "FATAL: Demographics profile missing 'role'")
	assert(profile_data.has("anchor_category"), "FATAL: Demographics profile missing 'anchor_category'")
	assert(profile_data.has("contract_class"), "FATAL: Demographics profile missing 'contract_class'")
	assert(profile_data.has("weekly_hours"), "FATAL: Demographics profile missing 'weekly_hours'")
	assert(profile_data.has("compensation_rate"), "FATAL: Demographics profile missing 'compensation_rate'")

	return {
		"age": resolved_age,
		"occupation": str(profile_data["role"]),
		"anchor_category": str(profile_data["anchor_category"]),
		"contract_class": str(profile_data["contract_class"]),
		"weekly_hours": float(profile_data["weekly_hours"]),
		"compensation_rate": float(profile_data["compensation_rate"])
	}

## Pass 3: Extended Kinship Across Households
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
		var ids_raw: String = cluster["member_ids"]
		var id_strings: PackedStringArray = ids_raw.split(",")
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

## Pass 4: Links peers and coworkers at the same establishment
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
		var ids_raw: String = cluster["member_ids"]
		var id_strings: PackedStringArray = ids_raw.split(",")
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

## Pass 5: Links churchgoers, temple members, and cultural community networks
static func _generate_faith_and_cultural_ties(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var ties: Array[String] = []
	var edge_count: int = 0
	var parish_rel_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "COMMUNITY_PARISH")

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
		var ids_raw: String = cluster["member_ids"]
		var id_strings: PackedStringArray = ids_raw.split(",")
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
				""" % [a, b, parish_rel_id, sim_start_day, reason_id])
				ties.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, NULL, 0.65, %d, NULL, %d);
				""" % [b, a, parish_rel_id, sim_start_day, reason_id])
				edge_count += 2

		if ties.size() >= 500:
			DB_MANAGER.execute_batch(ties)
			ties.clear()

	if not ties.is_empty():
		DB_MANAGER.execute_batch(ties)

	return edge_count

## Roll ethnicity and religion for a household dynamically from cultural module
static func _roll_household_culture(rng: RandomNumberGenerator, district_type: String) -> Dictionary:
	assert(_cultural.has("district_ethnic_weights"), "FATAL: 'district_ethnic_weights' missing in cultural_demographics")
	assert(_cultural.has("defaults"), "FATAL: 'defaults' block missing in cultural_demographics")
	assert(_cultural.has("ethnicities"), "FATAL: 'ethnicities' block missing in cultural_demographics")

	var weights_key := "high_density" if district_type.begins_with("high_density") else ("commercial" if district_type == "commercial" else "suburban_low_density")
	assert(_cultural["district_ethnic_weights"].has(weights_key), "FATAL: Missing district ethnic weight key: %s" % weights_key)
	
	var dist_weights: Dictionary = _cultural["district_ethnic_weights"][weights_key]
	var defaults: Dictionary = _cultural["defaults"]
	assert(defaults.has("fallback_ethnicity"), "FATAL: defaults missing 'fallback_ethnicity'")
	assert(defaults.has("secular_or_unaffiliated_religion_key"), "FATAL: defaults missing 'secular_or_unaffiliated_religion_key'")

	var chosen_eth: String = defaults["fallback_ethnicity"]
	var roll := rng.randf()
	var cumulative := 0.0
	for eth in dist_weights.keys():
		cumulative += float(dist_weights[eth])
		if roll <= cumulative:
			chosen_eth = eth
			break

	assert(_cultural["ethnicities"].has(chosen_eth), "FATAL: Ethnicity '%s' not registered in cultural ethnicities" % chosen_eth)
	var eth_profile: Dictionary = _cultural["ethnicities"][chosen_eth]
	assert(eth_profile.has("religion_distribution"), "FATAL: Ethnicity '%s' missing religion_distribution" % chosen_eth)
	
	var rel_weights: Dictionary = eth_profile["religion_distribution"]
	var chosen_rel: String = defaults["secular_or_unaffiliated_religion_key"]

	roll = rng.randf()
	cumulative = 0.0
	for rel in rel_weights.keys():
		cumulative += float(rel_weights[rel])
		if roll <= cumulative:
			chosen_rel = rel
			break

	assert(eth_profile.has("surnames_pool"), "FATAL: Ethnicity '%s' missing surnames_pool" % chosen_eth)
	return {
		"ethnicity": chosen_eth,
		"religion": chosen_rel,
		"surnames_pool": eth_profile["surnames_pool"]
	}

static func _resolve_citizen_education(rng: RandomNumberGenerator, age_years: int, is_high_density: bool) -> String:
	assert(_demographics.has("education_attainment_model"), "FATAL: 'education_attainment_model' missing in demographics")
	var edu_model: Dictionary = _demographics["education_attainment_model"]
	assert(edu_model.has("default_code"), "FATAL: edu_model missing 'default_code'")
	assert(edu_model.has("tiers"), "FATAL: edu_model missing 'tiers'")

	var default_code: String = str(edu_model["default_code"])
	var tiers: Array = edu_model["tiers"]

	for tier in tiers:
		assert(tier.has("min_age"), "FATAL: Education tier missing min_age")
		assert(tier.has("base_probability"), "FATAL: Education tier missing base_probability")
		assert(tier.has("code"), "FATAL: Education tier missing code")

		var min_age: int = int(tier["min_age"])
		if age_years < min_age:
			continue

		var prob: float = float(tier["base_probability"])
		if is_high_density and tier.has("high_density_penalty"):
			prob = max(0.01, prob - float(tier["high_density_penalty"]))

		if rng.randf() < prob:
			return str(tier["code"])

	return default_code