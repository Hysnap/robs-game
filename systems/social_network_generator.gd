# res://systems/social_network_generator.gd
class_name SocialNetworkGenerator
extends RefCounted

static var _lexicon: Dictionary = {}
static var _demographics: Dictionary = {}
static var _cultural: Dictionary = {}
static var _civic_hierarchy: Dictionary = {}
static var _housing: Dictionary = {}

## Resolves the scenario manifest path from business_rules.cfg
static func _get_configured_manifest_path() -> String:
	var cfg_path := "res://data_modules/core/business_rules.cfg"
	if not FileAccess.file_exists(cfg_path):
		push_error("[SocialNetwork CRITICAL] Missing business_rules.cfg at: %s" % cfg_path)
		assert(false, "HALT: business_rules.cfg is required for scenario configuration.")
		return ""
		
	var config := ConfigFile.new()
	var err := config.load(cfg_path)
	if err != OK:
		push_error("[SocialNetwork CRITICAL] Failed to parse business_rules.cfg (Error: %d)" % err)
		assert(false, "HALT: Corrupted business_rules.cfg.")
		return ""
		
	var manifest_path: String = config.get_value("society", "manifest_path", "")
	if manifest_path.is_empty():
		push_error("[SocialNetwork CRITICAL] Section [society] 'manifest_path' missing in business_rules.cfg")
		assert(false, "HALT: No society manifest_path declared in business_rules.cfg.")
		return ""
		
	return manifest_path

## Loads the master scenario manifest and all linked sub-modules
static func _load_configs() -> void:
	if not _demographics.is_empty() and not _lexicon.is_empty() and not _cultural.is_empty() and not _civic_hierarchy.is_empty() and not _housing.is_empty():
		return

	var manifest_path: String = _get_configured_manifest_path()
	var manifest: Dictionary = _load_json(manifest_path)
	var modules: Dictionary = manifest.get("modules", {})
	
	assert(modules.has("demographics"), "HALT: Manifest missing 'demographics' module mapping.")
	assert(modules.has("lexicon"), "HALT: Manifest missing 'lexicon' module mapping.")
	assert(modules.has("cultural_demographics"), "HALT: Manifest missing 'cultural_demographics' module mapping.")
	assert(modules.has("civic_hierarchy"), "HALT: Manifest missing 'civic_hierarchy' module mapping.")
	assert(modules.has("housing_and_tenure"), "HALT: Manifest missing 'housing_and_tenure' module mapping.")

	_demographics = _load_json(modules["demographics"])
	_lexicon = _load_json(modules["lexicon"])
	_cultural = _load_json(modules["cultural_demographics"])
	_civic_hierarchy = _load_json(modules["civic_hierarchy"])
	_housing = _load_json(modules["housing_and_tenure"])

static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[SocialNetwork CRITICAL] Missing config: %s" % path)
		assert(false, "HALT: Missing JSON file at %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return json.data
	push_error("[SocialNetwork CRITICAL] Invalid JSON syntax: %s" % path)
	assert(false, "HALT: Corrupted JSON at %s" % path)
	return {}

## Main Entry Point
static func generate_city_society(world_state: Dictionary, seed_id: String) -> void:
	_load_configs()
	DBManager.initialize_database(true)
	
	print("[SocialNetwork] Building living society, hierarchical establishments, and Dunbar ties...")
	var start_time := Time.get_ticks_msec()
	
	var districts: Dictionary = world_state.get("districts", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_id.hash())
	
	var labor_splits: Dictionary = _demographics["labor_market_splits"]
	var mean_household_size: float = float(_demographics.get("household_occupancy_mean", 2.6))
	var comm_share: float = float(labor_splits["commercial_tertiary_share"])
	
	var h_scales: Dictionary = _civic_hierarchy.get("hierarchy_scales", {})
	var blocks_per_borough: int = int(h_scales.get("blocks_per_borough", 90))
	var fam_min: int = int(h_scales.get("family_size_min", 1))
	var fam_max: int = int(h_scales.get("family_size_max", 4))
	
	# -------------------------------------------------------------
	# PASS 1: GENERATE ESTABLISHMENTS
	# -------------------------------------------------------------
	var est_data: Dictionary = _generate_all_establishments(districts, rng)
	var establishments_by_cat: Dictionary = est_data["by_category"]
	var total_est_count: int = est_data["total_count"]
	print("  ✓ Created %d total establishments across commercial, industrial, and civic sectors." % total_est_count)

	var male_names: Array = _lexicon.get("first_names_male", ["Terry"])
	var female_names: Array = _lexicon.get("first_names_female", ["Sharon"])
	
	var current_household_id: int = 1
	var current_resident_id: int = 1
	var total_edges: int = 0
	
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
		var default_pub: String = venue_keys[0] if not venue_keys.is_empty() else "NONE"
		
		var borough_idx: int = floori(float(block_index) / float(blocks_per_borough))
		var borough_id := "BOROUGH_%d" % (borough_idx + 1)
		block_index += 1
		
		var num_households: int = max(1, int(round(float(pop) / mean_household_size)))
		
		var household_inserts: Array[String] = []
		var resident_inserts: Array[String] = []
		var edge_inserts: Array[String] = []
		var district_resident_ids: Array[int] = []
		
		# Dynamically resolve housing archetype and wealth bracket from JSON
		var housing_profiles: Dictionary = _housing.get("district_housing_profiles", {})
		var fallback_housing: Dictionary = _housing.get("default_fallback", {"residence_type": "TERRACE", "wealth_bracket": 2})
		var profile: Dictionary = housing_profiles.get(district_type, fallback_housing)
		
		var residence_type: String = profile.get("primary_residence_type", fallback_housing.get("residence_type", "TERRACE"))
		var wealth_bracket: int = int(profile.get("wealth_bracket", fallback_housing.get("wealth_bracket", 2)))

		for _h in range(num_households):
			var h_id := current_household_id
			current_household_id += 1
			
			var assigned_pub: String = venue_keys[rng.randi() % venue_keys.size()] if not venue_keys.is_empty() else default_pub
			
			var culture: Dictionary = _roll_household_culture(rng, district_type)
			var h_ethnicity: String = culture["ethnicity"]
			var h_religion: String = culture["religion"]
			var pool_key: String = culture["surnames_pool"]
			var surname_list: Array = _lexicon.get(pool_key, _lexicon.get("surnames", ["Smith"]))
			var family_surname: String = surname_list[rng.randi() % surname_list.size()]
			
			household_inserts.append(
				"INSERT INTO households VALUES (%d, '%s', '%s', '%s', %d, '%s', '%s', '%s');" % [
					h_id, borough_id, dist_id, residence_type, wealth_bracket, assigned_pub, h_ethnicity, h_religion
				]
			)

			var family_size := rng.randi_range(fam_min, fam_max)
			var household_members: Array[int] = []
			
			for _m in range(family_size):
				var r_id := current_resident_id
				current_resident_id += 1
				household_members.append(r_id)
				district_resident_ids.append(r_id)
				
				var is_male: bool = (rng.randf() > 0.5)
				var is_high_dense: bool = district_type.begins_with("high_density")
				var first_name: String = male_names[rng.randi() % male_names.size()] if is_male else female_names[rng.randi() % female_names.size()]
				
				# PURELY DATA-DRIVEN RESOLUTION FROM JSON:
				var demo_profile: Dictionary = _resolve_citizen_demographics(rng, is_high_dense, is_male, unemp_rate, comm_share)
				var age: int = demo_profile["age"]
				var occ: String = demo_profile["occupation"]
				var anchor_category: String = demo_profile["anchor_category"]
				
				var assigned_est_id: int = _pick_anchor(establishments_by_cat, anchor_category, dist_id, rng)
				
				resident_inserts.append(
					"INSERT INTO residents VALUES (%d, %d, %d, '%s', '%s', %d, '%s', '%s', '%s', 0);" % [
						r_id, h_id, assigned_est_id, first_name.replace("'", "''"), family_surname.replace("'", "''"), age, occ, h_ethnicity, h_religion
					]
				)
			
			# Circle 1: Household Kinship
			if household_members.size() > 1:
				for a in household_members:
					for b in household_members:
						if a != b:
							edge_inserts.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'FAMILY', 0.90);" % [a, b])
							total_edges += 1
		
		# Circle 2: Pub Catchment Edges
		for r_id in district_resident_ids:
			var buddy_count := rng.randi_range(2, 4)
			for _b in range(buddy_count):
				var target_id: int = district_resident_ids[rng.randi() % district_resident_ids.size()]
				if target_id != r_id:
					edge_inserts.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'DRINKING_MATE', 0.55);" % [r_id, target_id])
					total_edges += 1
		
		DBManager.execute_batch(household_inserts)
		DBManager.execute_batch(resident_inserts)
		DBManager.execute_batch(edge_inserts)

	# Pass 3: Extended Kinship Across Households
	var ext_edges: int = _generate_extended_kinship(rng)
	total_edges += ext_edges
	print("  ✓ Stitched %d extended family connections across households." % ext_edges)

	# Pass 4: Establishment Peer Ties
	var peer_edges: int = _generate_establishment_peer_ties(rng)
	total_edges += peer_edges
	print("  ✓ Stitched %d peer & coworker relationship ties across establishments." % peer_edges)

	# Pass 5: Community & Parish Ties
	var faith_edges: int = _generate_faith_and_cultural_ties(rng)
	total_edges += faith_edges
	print("  ✓ Stitched %d community & parish connections." % faith_edges)

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

## Purely Data-Driven Demographic Engine
static func _resolve_citizen_demographics(rng: RandomNumberGenerator, is_high_density: bool, is_male: bool, unemp_rate: float, comm_share: float) -> Dictionary:
	var cohorts: Array = _demographics["cohort_profiles"]
	var thresholds: Dictionary = _demographics["legal_and_pension_thresholds"]
	var life_caps: Dictionary = _demographics["life_expectancy_caps"]
	
	var pen_age: int = int(thresholds["pension_age_male"] if is_male else thresholds["pension_age_female"])
	var max_age: int = int(life_caps["male_max_age"] if is_male else life_caps["female_max_age"])
	var density_key := "high_density" if is_high_density else "suburban_low_density"

	# 1. Roll for Cohort based on weighted density distribution in JSON
	var roll := rng.randf()
	var cumulative := 0.0
	var chosen_cohort: Dictionary = cohorts[0]
	
	for c in cohorts:
		var w: float = float(c["density_weights"][density_key])
		cumulative += w
		if roll <= cumulative:
			chosen_cohort = c
			break
			
	# 2. Determine Age boundaries dynamically
	var age_min: int = 0
	if chosen_cohort.has("age_min_dynamic"):
		age_min = pen_age
	else:
		age_min = int(chosen_cohort.get("age_min", 0))
		
	var age_max: int = 70
	if chosen_cohort.has("age_max_dynamic"):
		var dyn_key: String = chosen_cohort["age_max_dynamic"]
		age_max = pen_age - 1 if dyn_key == "pension_age" else max_age
	else:
		age_max = int(chosen_cohort.get("age_max", 70))
		
	var resolved_age: int = rng.randi_range(age_min, age_max)
	
	# 3. Dynamic Strategy Evaluation (Driven purely by the JSON cohort rules)
	var strategy: String = chosen_cohort.get("strategy", "FIXED")
	var resolved_occ: String = ""
	var resolved_anchor: String = ""
	
	match strategy:
		"FIXED":
			resolved_occ = chosen_cohort.get("role", "CITIZEN")
			resolved_anchor = chosen_cohort.get("anchor_category", "COMMERCIAL")
			
		"PROBABILISTIC":
			var prob: float = float(chosen_cohort.get("condition_probability", 0.5))
			var outcome_key: String = "if_true" if (rng.randf() < prob) else "if_false"
			var branch: Dictionary = chosen_cohort.get(outcome_key, {})
			resolved_occ = branch.get("role", "CITIZEN")
			resolved_anchor = branch.get("anchor_category", "COMMERCIAL")
			
		"LABOR_MARKET":
			if rng.randf() < unemp_rate:
				resolved_occ = chosen_cohort.get("unemployed_role", "UNEMPLOYED")
				resolved_anchor = chosen_cohort.get("unemployed_anchor", "JOBCENTRE")
			elif rng.randf() < comm_share:
				resolved_occ = chosen_cohort.get("commercial_role", "COMMERCIAL_SERVICE")
				resolved_anchor = chosen_cohort.get("commercial_anchor", "COMMERCIAL")
			else:
				resolved_occ = chosen_cohort.get("industrial_role", "MANUAL_WORKS")
				resolved_anchor = chosen_cohort.get("industrial_anchor", "INDUSTRIAL")

	return {
		"age": resolved_age,
		"occupation": resolved_occ,
		"anchor_category": resolved_anchor
	}

## Creates establishments dynamically from JSON configurations
static func _generate_all_establishments(districts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var inserts: Array[String] = []
	var by_cat: Dictionary = {}
	var est_id: int = 1
	var block_idx: int = 0
	
	var h_scales: Dictionary = _civic_hierarchy.get("hierarchy_scales", {})
	var blocks_per_borough: int = int(h_scales.get("blocks_per_borough", 90))
	var wp_rules: Dictionary = _civic_hierarchy.get("workplace_generation_rules", {})
	var est_templates: Dictionary = _civic_hierarchy.get("establishment_templates", {})
	var civic_insts: Dictionary = _civic_hierarchy.get("civic_institutions", {})
	
	# Dynamically initialize category buckets from the JSON templates and civic institutions
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

		for _c in range(num_commercial):
			var name: String = comm_names[rng.randi() % comm_names.size()].replace("'", "''")
			inserts.append("INSERT INTO establishments VALUES (%d, '%s', '%s', '%s', 'COMMERCIAL', %d);" % [est_id, borough_id, dist_id, name, comm_cap])
			by_cat["COMMERCIAL"].append({"id": est_id, "district_id": dist_id})
			est_id += 1

		var ind_temp: Dictionary = est_templates.get("INDUSTRIAL", {})
		var ind_names: Array = ind_temp.get("names", ["Industrial Works"])
		var ind_cap: int = int(ind_temp.get("default_capacity", 60))

		for _i in range(num_industrial):
			var name: String = ind_names[rng.randi() % ind_names.size()].replace("'", "''")
			inserts.append("INSERT INTO establishments VALUES (%d, '%s', '%s', '%s', 'INDUSTRIAL', %d);" % [est_id, borough_id, dist_id, name, ind_cap])
			by_cat["INDUSTRIAL"].append({"id": est_id, "district_id": dist_id})
			est_id += 1

		# 2. Civic Institutions
		for inst_key in civic_insts.keys():
			var inst_data: Dictionary = civic_insts[inst_key]
			var interval: int = int(inst_data.get("blocks_per_facility", 1))
			if block_idx % interval == 0:
				var label: String = inst_data.get("display_name", inst_key)
				var cap: int = int(inst_data.get("default_capacity", 100))
				inserts.append("INSERT INTO establishments VALUES (%d, '%s', '%s', '%s', '%s', %d);" % [est_id, borough_id, dist_id, label, inst_key, cap])
				if not by_cat.has(inst_key):
					by_cat[inst_key] = []
				by_cat[inst_key].append({"id": est_id, "district_id": dist_id})
				est_id += 1

		block_idx += 1

	DBManager.execute_batch(inserts)
	return {"by_category": by_cat, "total_count": est_id - 1}

## Helper: Picks the closest or random valid establishment of a given category
static func _pick_anchor(by_cat: Dictionary, category: String, _dist_id: String, rng: RandomNumberGenerator) -> int:
	var list: Array = by_cat.get(category, [])
	if list.is_empty():
		return 1
	var picked: Dictionary = list[rng.randi() % list.size()]
	return picked["id"]

## Pass 3: Extended Kinship Across Households
static func _generate_extended_kinship(rng: RandomNumberGenerator) -> int:
	var kinship_edges: Array[String] = []
	var edge_count: int = 0

	var surname_clusters = DBManager.query_rows("""
		SELECT surname, district_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		GROUP BY surname, district_id
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

			var existing = DBManager.query_rows("SELECT 1 FROM social_relationships WHERE from_resident_id = %d AND to_resident_id = %d;" % [a, b])
			if existing.is_empty():
				kinship_edges.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'EXTENDED_FAMILY', 0.80);" % [a, b])
				kinship_edges.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'EXTENDED_FAMILY', 0.80);" % [b, a])
				edge_count += 2

		if kinship_edges.size() >= 500:
			DBManager.execute_batch(kinship_edges)
			kinship_edges.clear()

	if not kinship_edges.is_empty():
		DBManager.execute_batch(kinship_edges)

	return edge_count

## Pass 4: Links peers and coworkers at the same establishment
static func _generate_establishment_peer_ties(rng: RandomNumberGenerator) -> int:
	var peer_edges: Array[String] = []
	var edge_count: int = 0

	var est_clusters = DBManager.query_rows("""
		SELECT establishment_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents
		GROUP BY establishment_id
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
				peer_edges.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'CIVIC_PEER', 0.50);" % [a, b])
				edge_count += 1

		if peer_edges.size() >= 500:
			DBManager.execute_batch(peer_edges)
			peer_edges.clear()

	if not peer_edges.is_empty():
		DBManager.execute_batch(peer_edges)

	return edge_count

## Pass 5: Links churchgoers, temple members, and cultural community networks
static func _generate_faith_and_cultural_ties(rng: RandomNumberGenerator) -> int:
	var ties: Array[String] = []
	var edge_count: int = 0

	var congregation_clusters = DBManager.query_rows("""
		SELECT h.district_id, r.ethnicity, r.religion, GROUP_CONCAT(r.resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		WHERE r.religion != 'SECULAR_NONE' AND r.age >= 18
		GROUP BY h.district_id, r.ethnicity, r.religion
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
				ties.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'COMMUNITY_PARISH', 0.65);" % [a, b])
				ties.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'COMMUNITY_PARISH', 0.65);" % [b, a])
				edge_count += 2

		if ties.size() >= 500:
			DBManager.execute_batch(ties)
			ties.clear()

	if not ties.is_empty():
		DBManager.execute_batch(ties)

	return edge_count

## Roll ethnicity and religion for a household based on district density
static func _roll_household_culture(rng: RandomNumberGenerator, district_type: String) -> Dictionary:
	var weights_key := "high_density" if district_type.begins_with("high_density") else ("commercial" if district_type == "commercial" else "suburban_low_density")
	var dist_weights: Dictionary = _cultural["district_ethnic_weights"][weights_key]
	var defaults: Dictionary = _cultural.get("defaults", {})
	
	# Fallback key dynamically pulled from JSON, or the first key in the weight table
	var ethnic_keys: Array = dist_weights.keys()
	var fallback_eth: String = defaults.get("fallback_ethnicity", ethnic_keys[0] if not ethnic_keys.is_empty() else "")
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
	
	# Default religion pulled from meta defaults, or the first key in this ethnicity's distribution
	var fallback_rel: String = defaults.get("secular_or_unaffiliated_religion_key", rel_keys[0] if not rel_keys.is_empty() else "")
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