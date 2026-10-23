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

## Loads configurations via the centralized ScenarioManifestManager
static func _load_configs() -> void:
	if not _demographics.is_empty() and not _lexicon.is_empty() and not _cultural.is_empty() and not _civic_hierarchy.is_empty() and not _archetypes.is_empty():
		return

	_demographics = MANIFEST_MGR.load_module("demographics")
	_lexicon = MANIFEST_MGR.load_module("lexicon")
	_cultural = MANIFEST_MGR.load_module("cultural_demographics")
	_civic_hierarchy = MANIFEST_MGR.load_module("civic_hierarchy")

	# Archetypes path resolved from business_rules.cfg or default
	var archetypes_path := "res://data_modules/core/spatial/districts/archetypes.json"
	var cfg := ConfigFile.new()
	if cfg.load(MANIFEST_MGR.BUSINESS_RULES_PATH) == OK:
		archetypes_path = cfg.get_value("spatial", "archetypes_path", archetypes_path)

	assert(FileAccess.file_exists(archetypes_path), "FATAL: Missing archetypes: %s" % archetypes_path)
	var f := FileAccess.open(archetypes_path, FileAccess.READ)
	assert(f != null, "FATAL: Cannot open: %s" % archetypes_path)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	assert(parsed is Dictionary, "FATAL: Archetypes root must be a Dictionary")
	_archetypes = parsed

## Main Generation Pipeline
static func generate_city_society(world_state: Dictionary, seed_id: String, force_regenerate: bool = false) -> void:
	if not force_regenerate and DB_MANAGER.is_society_populated(seed_id):
		print("[SocialNetwork] Society for seed '%s' already exists in SQLite. Skipping generation." % seed_id)
		return

	_load_configs()
	DB_MANAGER.initialize_database(true) # Cleans schema, populates system_labels & temporal metadata
	DB_MANAGER.record_active_seed(seed_id)

	print("[SocialNetwork] Building living society, normalized establishments, and Dunbar graph...")
	var start_time := Time.get_ticks_msec()

	var districts: Dictionary = world_state.get("districts", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_id.hash())

	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var male_gender_id: int = DB_MANAGER.get_label_id("GENDER", "M")
	var female_gender_id: int = DB_MANAGER.get_label_id("GENDER", "F")

	var h_scales: Dictionary = _civic_hierarchy.get("hierarchy_scales", {})
	var blocks_per_borough: int = int(h_scales.get("blocks_per_borough", 90))
	var fam_min: int = int(h_scales.get("family_size_min", 1))
	var fam_max: int = int(h_scales.get("family_size_max", 4))
	var mean_household_size: float = float(_demographics.get("household_occupancy_mean", 2.6))
	var comm_share: float = float(_demographics["labor_market_splits"].get("commercial_tertiary_share", 0.70))

	# -------------------------------------------------------------
	# PASS 1: GENERATE ESTABLISHMENTS
	# -------------------------------------------------------------
	var est_data: Dictionary = _generate_all_establishments(districts, rng, sim_start_day, reason_world_gen_id)
	var establishments_by_cat: Dictionary = est_data["by_category"]
	var total_est_count: int = est_data["total_count"]
	print("  ✓ Created %d normalized establishments across sectors." % total_est_count)

	var male_names: Array = _lexicon.get("first_names_male", ["Terry"])
	var female_names: Array = _lexicon.get("first_names_female", ["Sharon"])

	var current_household_id: int = 1
	var current_resident_id: int = 1
	var total_edges: int = 0

	var rel_family_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "FAMILY")
	var rel_drinking_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "DRINKING_MATE")

	# -------------------------------------------------------------
	# PASS 2: GENERATE HOUSEHOLDS & RESIDENTS
	# -------------------------------------------------------------
	var block_index := 0
	for dist_id in districts.keys():
		var district: Dictionary = districts[dist_id]
		var pop: int = int(district.get("population", 0))
		if pop <= 0:
			block_index += 1
			continue

		var district_type: String = district.get("district_type", "suburban_low_density")
		var unemp_rate: float = float(district.get("unemployment_rate", 0.12))
		var venues: Dictionary = district.get("venues", {})
		var venue_keys: Array = venues.keys()

		var borough_idx: int = floori(float(block_index) / float(blocks_per_borough))
		var borough_id := "BOROUGH_%d" % (borough_idx + 1)
		block_index += 1

		var num_households: int = max(1, int(round(float(pop) / mean_household_size)))

		var household_inserts: Array[String] = []
		var resident_inserts: Array[String] = []
		var contract_inserts: Array[String] = []
		var edge_inserts: Array[String] = []
		var district_resident_ids: Array[int] = []

		# Housing profile dynamically resolved from archetypes.json
		var arch_data: Dictionary = _archetypes.get(district_type, {})
		var h_prof: Dictionary = arch_data.get("housing_profile", {})
		var res_type_code: String = str(h_prof.get("residence_type", "TERRACE"))
		var res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type_code)
		var wealth_bracket: int = int(h_prof.get("wealth_bracket", 2))

		for _h in range(num_households):
			var h_id := current_household_id
			current_household_id += 1

			# Resolve culture & localized taxonomy IDs
			var culture: Dictionary = _roll_household_culture(rng, district_type)
			var eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", culture["ethnicity"])
			var rel_id: int = DB_MANAGER.get_label_id("RELIGION", culture["religion"])

			var surname_list: Array = _lexicon.get(culture["surnames_pool"], _lexicon.get("surnames", ["Smith"]))
			var family_surname: String = str(surname_list[rng.randi() % surname_list.size()]).replace("'", "''")

			household_inserts.append("""
				INSERT INTO households (
					household_id, borough_id, district_id, residence_type_id, 
					wealth_bracket_id, local_pub_id, ethnicity_id, religion_id, 
					valid_from, valid_to, change_reason_id
				) VALUES (
					%d, '%s', '%s', %d, %d, NULL, %d, %d, %d, NULL, %d
				);
			""" % [
				h_id, borough_id, dist_id, res_type_id, wealth_bracket,
				eth_id, rel_id, sim_start_day, reason_world_gen_id
			])

			var family_size := rng.randi_range(fam_min, fam_max)
			var household_members: Array[int] = []

			for _m in range(family_size):
				var r_id := current_resident_id
				current_resident_id += 1
				household_members.append(r_id)
				district_resident_ids.append(r_id)

				var is_male: bool = (rng.randf() > 0.5)
				var gender_id: int = male_gender_id if is_male else female_gender_id
				var first_name: String = str(male_names[rng.randi() % male_names.size()] if is_male else female_names[rng.randi() % female_names.size()]).replace("'", "''")

				var is_high_dense: bool = district_type.begins_with("high_density")
				var demo_profile: Dictionary = _resolve_citizen_demographics(rng, is_high_dense, is_male, unemp_rate, comm_share)
				var age_years: int = demo_profile["age"]

				# Temporal calculation for exact Date of Birth
				var days_old: int = int(round(float(age_years) * 365.25)) + rng.randi_range(0, 364)
				var dob_day: int = sim_start_day - days_old

				# Resolve education based on age
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
					r_id, h_id, first_name, family_surname, family_surname,
					dob_day, gender_id, edu_id, eth_id, rel_id, sim_start_day, reason_world_gen_id
				])

				# Create contract in livelihood_contracts
				# 1. Resolve role and contract attributes from demographics profile
				var occ_title: String = demo_profile["occupation"]
				var anchor_cat: String = demo_profile["anchor_category"]
				var contract_class: String = demo_profile["contract_class"]
				var weekly_hours: float = float(demo_profile["weekly_hours"])
				var compensation_rate: float = float(demo_profile["compensation_rate"])
				var standard_contract_type_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", "STANDARD")
				
				var assigned_est_id: int = _pick_anchor(establishments_by_cat, anchor_cat, dist_id, rng)

				# 2. Strict lookup against pre-harvested system_labels (No auto-seeding!)
				var class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)
				var role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", occ_title)

				# 3. Insert into livelihood_contracts
				contract_inserts.append("""
					INSERT INTO livelihood_contracts (
						resident_id, employer_entity_id, contract_class_id, role_title_id,
						contract_type_id, schedule_window, weekly_hours, compensation_rate, 
						valid_from, valid_to, change_reason_id
					) VALUES (
						%d, 'ESTAB_%d', %d, %d, %d, 'DAYTIME', %.1f, %.2f, %d, NULL, %d
					);
				""" % [
					r_id, assigned_est_id, class_id, role_id, standard_contract_type_id,
					weekly_hours, compensation_rate, sim_start_day, reason_world_gen_id
				])

			# Circle 1: Household Kinship Multi-Edge
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
							total_edges += 1

		# Circle 2: Pub Catchment Edges
		for r_id in district_resident_ids:
			var buddy_count := rng.randi_range(2, 4)
			for _b in range(buddy_count):
				var target_id: int = district_resident_ids[rng.randi() % district_resident_ids.size()]
				if target_id != r_id:
					edge_inserts.append("""
						INSERT INTO social_relationships (
							from_resident_id, to_resident_id, relationship_type_id,
							context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, %d, NULL, 0.55, %d, NULL, %d);
					""" % [r_id, target_id, rel_drinking_id, sim_start_day, reason_world_gen_id])
					total_edges += 1

		DB_MANAGER.execute_batch(household_inserts)
		DB_MANAGER.execute_batch(resident_inserts)
		DB_MANAGER.execute_batch(contract_inserts)
		DB_MANAGER.execute_batch(edge_inserts)

	# Pass 3: Extended Kinship Across Households
	total_edges += _generate_extended_kinship(rng, sim_start_day, reason_world_gen_id)

	# Pass 4: Establishment Peer Ties
	total_edges += _generate_establishment_peer_ties(rng, sim_start_day, reason_world_gen_id)

	# Pass 5: Community & Parish Ties
	total_edges += _generate_faith_and_cultural_ties(rng, sim_start_day, reason_world_gen_id)

	var elapsed := Time.get_ticks_msec() - start_time
	print("=======================================================")
	print("       SOCIAL NETWORK GRAPH GENERATION COMPLETE        ")
	print("=======================================================")
	print("Elapsed Time:      %d ms" % elapsed)
	print("Total Estabs:      %d" % total_est_count)
	print("Total Households:  %d" % (current_household_id - 1))
	print("Total Citizens:    %d" % (current_resident_id - 1))
	print("Network Edges:     ~%d relationship connections" % total_edges)
	print("=======================================================\n")

## Ensures dynamic role titles and categories exist in system_labels without crashing
static func _ensure_label_exists(domain: String, code: String, title: String) -> void:
	var check_sql := "SELECT label_id FROM system_labels WHERE domain = '%s' AND code = '%s';" % [domain.to_upper(), code.to_upper()]
	var res = DB_MANAGER.query_rows(check_sql)
	if res.is_empty():
		DB_MANAGER.query_rows("""
			INSERT INTO system_labels (domain, code, title, description)
			VALUES ('%s', '%s', '%s', 'Autogenerated runtime taxonomy');
		""" % [domain.to_upper(), code.to_upper(), title.replace("'", "''")])
		DB_MANAGER._rebuild_label_cache()

## Creates establishments dynamically from JSON configurations
static func _generate_all_establishments(districts: Dictionary, rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> Dictionary:
	var inserts: Array[String] = []
	var by_cat: Dictionary = {}
	var est_id: int = 1
	var block_idx: int = 0

	var h_scales: Dictionary = _civic_hierarchy.get("hierarchy_scales", {})
	var blocks_per_borough: int = int(h_scales.get("blocks_per_borough", 90))
	var wp_rules: Dictionary = _civic_hierarchy.get("workplace_generation_rules", {})
	var est_templates: Dictionary = _civic_hierarchy.get("establishment_templates", {})
	var civic_insts: Dictionary = _civic_hierarchy.get("civic_institutions", {})

	for cat in est_templates.keys():
		by_cat[cat] = []
	for cat in civic_insts.keys():
		by_cat[cat] = []

	for dist_id in districts.keys():
		var d = districts[dist_id]
		var dtype: String = d.get("district_type", "")
		var borough_id := "BOROUGH_%d" % (floori(float(block_idx) / float(blocks_per_borough)) + 1)

		# 1. Commercial & Industrial Workplaces
		var rule_key := dtype if wp_rules.has(dtype) else "residential_default"
		var rule: Dictionary = wp_rules[rule_key]
		var num_commercial: int = rng.randi_range(int(rule["commercial_min"]), int(rule["commercial_max"]))
		var num_industrial: int = rng.randi_range(int(rule["industrial_min"]), int(rule["industrial_max"]))

		var comm_temp: Dictionary = est_templates.get("COMMERCIAL", {})
		var comm_names: Array = comm_temp.get("names", ["Commercial Services"])
		var comm_cap: int = int(comm_temp.get("default_capacity", 30))
		_ensure_label_exists("ESTABLISHMENT_CATEGORY", "COMMERCIAL", "Commercial Sector")
		var comm_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "COMMERCIAL")

		for _c in range(num_commercial):
			var name: String = str(comm_names[rng.randi() % comm_names.size()]).replace("'", "''")
			inserts.append("""
				INSERT INTO establishments (
					establishment_id, borough_id, district_id, owning_entity, name,
					category_id, capacity, valid_from, valid_to, change_reason_id
				) VALUES (%d, '%s', '%s', 'CIVIC', '%s', %d, %d, %d, NULL, %d);
			""" % [est_id, borough_id, dist_id, name, comm_cat_id, comm_cap, sim_start_day, reason_id])
			by_cat["COMMERCIAL"].append({"id": est_id, "district_id": dist_id})
			est_id += 1

		var ind_temp: Dictionary = est_templates.get("INDUSTRIAL", {})
		var ind_names: Array = ind_temp.get("names", ["Industrial Works"])
		var ind_cap: int = int(ind_temp.get("default_capacity", 60))
		_ensure_label_exists("ESTABLISHMENT_CATEGORY", "INDUSTRIAL", "Industrial Sector")
		var ind_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "INDUSTRIAL")

		for _i in range(num_industrial):
			var name: String = str(ind_names[rng.randi() % ind_names.size()]).replace("'", "''")
			inserts.append("""
				INSERT INTO establishments (
					establishment_id, borough_id, district_id, owning_entity, name,
					category_id, capacity, valid_from, valid_to, change_reason_id
				) VALUES (%d, '%s', '%s', 'CIVIC', '%s', %d, %d, %d, NULL, %d);
			""" % [est_id, borough_id, dist_id, name, ind_cat_id, ind_cap, sim_start_day, reason_id])
			by_cat["INDUSTRIAL"].append({"id": est_id, "district_id": dist_id})
			est_id += 1

		# 2. Civic Institutions
		for inst_key in civic_insts.keys():
			var inst_data: Dictionary = civic_insts[inst_key]
			var interval: int = int(inst_data.get("blocks_per_facility", 1))
			if interval > 0 and block_idx % interval == 0:
				var label: String = str(inst_data.get("display_name", inst_key)).replace("'", "''")
				var cap: int = int(inst_data.get("default_capacity", 100))
				_ensure_label_exists("ESTABLISHMENT_CATEGORY", inst_key, label)
				var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", inst_key)

				inserts.append("""
					INSERT INTO establishments (
						establishment_id, borough_id, district_id, owning_entity, name,
						category_id, capacity, valid_from, valid_to, change_reason_id
					) VALUES (%d, '%s', '%s', 'CIVIC', '%s', %d, %d, %d, NULL, %d);
				""" % [est_id, borough_id, dist_id, label, cat_id, cap, sim_start_day, reason_id])

				if not by_cat.has(inst_key):
					by_cat[inst_key] = []
				by_cat[inst_key].append({"id": est_id, "district_id": dist_id})
				est_id += 1

		block_idx += 1

	DB_MANAGER.execute_batch(inserts)
	return {"by_category": by_cat, "total_count": est_id - 1}

## Helper: Picks the closest or random valid establishment of a given category
static func _pick_anchor(by_cat: Dictionary, category: String, _dist_id: String, rng: RandomNumberGenerator) -> int:
	var list: Array = by_cat.get(category, [])
	if list.is_empty():
		return 1
	var picked: Dictionary = list[rng.randi() % list.size()]
	return picked["id"]

## Purely Data-Driven Demographic Engine (Zero Hardcoded Roles or Rates)
static func _resolve_citizen_demographics(rng: RandomNumberGenerator, is_high_density: bool, is_male: bool, unemp_rate: float, comm_share: float) -> Dictionary:
	var cohorts: Array = _demographics.get("cohort_profiles", [])
	var thresholds: Dictionary = _demographics["legal_and_pension_thresholds"]
	var life_caps: Dictionary = _demographics["life_expectancy_caps"]

	var pen_age: int = int(thresholds["pension_age_male"] if is_male else thresholds["pension_age_female"])
	var max_age: int = int(life_caps["male_max_age"] if is_male else life_caps["female_max_age"])
	var density_key := "high_density" if is_high_density else "suburban_low_density"

	assert(not cohorts.is_empty(), "FATAL: 'cohort_profiles' missing in demographics JSON")

	# 1. Roll Cohort based on weighted density distribution
	var roll := rng.randf()
	var cumulative := 0.0
	var chosen_cohort: Dictionary = cohorts[0]

	for c in cohorts:
		var w: float = float(c["density_weights"].get(density_key, 0.2))
		cumulative += w
		if roll <= cumulative:
			chosen_cohort = c
			break

	# 2. Determine Age
	var age_min: int = int(chosen_cohort.get("age_min", 0))
	if chosen_cohort.has("age_min_dynamic") and chosen_cohort["age_min_dynamic"] == "pension_age":
		age_min = pen_age

	var age_max: int = int(chosen_cohort.get("age_max", 70))
	if chosen_cohort.has("age_max_dynamic"):
		var dyn_key: String = chosen_cohort["age_max_dynamic"]
		age_max = pen_age - 1 if dyn_key == "pension_age" else max_age

	var resolved_age: int = rng.randi_range(age_min, age_max)
	var strategy: String = chosen_cohort.get("strategy", "FIXED")

	var role: String = "CITIZEN"
	var anchor: String = "COMMERCIAL"
	var contract_class: String = "FORMAL_LEGAL"
	var weekly_hours: float = 37.5
	var comp_rate: float = 3.50

	match strategy:
		"FIXED":
			role = str(chosen_cohort.get("role", "CITIZEN"))
			anchor = str(chosen_cohort.get("anchor_category", "COMMERCIAL"))
			contract_class = str(chosen_cohort.get("contract_class", "FORMAL_LEGAL"))
			weekly_hours = float(chosen_cohort.get("weekly_hours", 0.0))
			comp_rate = float(chosen_cohort.get("compensation_rate", 0.0))

		"PROBABILISTIC":
			var prob: float = float(chosen_cohort.get("condition_probability", 0.5))
			var branch_key: String = "if_true" if (rng.randf() < prob) else "if_false"
			var branch: Dictionary = chosen_cohort.get(branch_key, {})
			role = str(branch.get("role", "CITIZEN"))
			anchor = str(branch.get("anchor_category", "COMMERCIAL"))
			contract_class = str(branch.get("contract_class", "FORMAL_LEGAL"))
			weekly_hours = float(branch.get("weekly_hours", 37.5))
			comp_rate = float(branch.get("compensation_rate", 3.00))

		"LABOR_MARKET":
			if rng.randf() < unemp_rate:
				role = str(chosen_cohort.get("unemployed_role", "UNEMPLOYED"))
				anchor = str(chosen_cohort.get("unemployed_anchor", "JOBCENTRE"))
				contract_class = str(chosen_cohort.get("unemployed_contract_class", "INFORMAL_GREY"))
				weekly_hours = float(chosen_cohort.get("unemployed_hours", 0.0))
				comp_rate = float(chosen_cohort.get("unemployed_rate", 0.0))
			elif rng.randf() < comm_share:
				role = str(chosen_cohort.get("commercial_role", "COMMERCIAL_SERVICE"))
				anchor = str(chosen_cohort.get("commercial_anchor", "COMMERCIAL"))
				contract_class = str(chosen_cohort.get("commercial_contract_class", "FORMAL_LEGAL"))
				weekly_hours = float(chosen_cohort.get("commercial_hours", 37.5))
				comp_rate = float(chosen_cohort.get("commercial_rate", 3.75))
			else:
				role = str(chosen_cohort.get("industrial_role", "MANUAL_WORKS"))
				anchor = str(chosen_cohort.get("industrial_anchor", "INDUSTRIAL"))
				contract_class = str(chosen_cohort.get("industrial_contract_class", "FORMAL_LEGAL"))
				weekly_hours = float(chosen_cohort.get("industrial_hours", 40.0))
				comp_rate = float(chosen_cohort.get("industrial_rate", 4.20))

	return {
		"age": resolved_age,
		"occupation": role,
		"anchor_category": anchor,
		"contract_class": contract_class,
		"weekly_hours": weekly_hours,
		"compensation_rate": comp_rate
	}

## Pass 3: Extended Kinship Across Households
static func _generate_extended_kinship(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var kinship_edges: Array[String] = []
	var edge_count: int = 0
	var ext_fam_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "EXTENDED_FAMILY")

	var surname_clusters = DB_MANAGER.query_rows("""
		SELECT current_surname as surname, district_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		GROUP BY current_surname, district_id
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
		SELECT h.district_id, r.ethnicity_id, r.religion_id, GROUP_CONCAT(r.resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		WHERE r.dod IS NULL
		GROUP BY h.district_id, r.ethnicity_id, r.religion_id
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

## Roll ethnicity and religion for a household based on district density
static func _roll_household_culture(rng: RandomNumberGenerator, district_type: String) -> Dictionary:
	var weights_key := "high_density" if district_type.begins_with("high_density") else ("commercial" if district_type == "commercial" else "suburban_low_density")
	var dist_weights: Dictionary = _cultural["district_ethnic_weights"][weights_key]
	var defaults: Dictionary = _cultural.get("defaults", {})

	var ethnic_keys: Array = dist_weights.keys()
	var fallback_eth: String = defaults.get("fallback_ethnicity", ethnic_keys[0] if not ethnic_keys.is_empty() else "WHITE_BRITISH")
	var chosen_eth: String = fallback_eth

	var roll := rng.randf()
	var cumulative := 0.0
	for eth in dist_weights.keys():
		cumulative += float(dist_weights[eth])
		if roll <= cumulative:
			chosen_eth = eth
			break

	var eth_profile: Dictionary = _cultural["ethnicities"][chosen_eth]
	var rel_weights: Dictionary = eth_profile["religion_distribution"]
	var rel_keys: Array = rel_weights.keys()

	var fallback_rel: String = defaults.get("secular_or_unaffiliated_religion_key", rel_keys[0] if not rel_keys.is_empty() else "PROTESTANT_COFE")
	var chosen_rel: String = fallback_rel

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
	var edu_model: Dictionary = _demographics.get("education_attainment_model", {})
	var default_code: String = str(edu_model.get("default_code", "NO_FORMAL"))
	var tiers: Array = edu_model.get("tiers", [])

	for tier in tiers:
		var min_age: int = int(tier.get("min_age", 16))
		if age_years < min_age:
			continue

		var prob: float = float(tier.get("base_probability", 0.10))
		if is_high_density:
			prob = max(0.01, prob - float(tier.get("high_density_penalty", 0.0)))

		if rng.randf() < prob:
			return str(tier.get("code", default_code))

	return default_code