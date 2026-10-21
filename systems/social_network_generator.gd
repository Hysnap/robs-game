# res://systems/social_network_generator.gd
class_name SocialNetworkGenerator
extends RefCounted

static var _lexicon: Dictionary = {}
static var _demographics: Dictionary = {}
static var _cultural: Dictionary = {}

static func _load_demographics(path: String = "res://data_modules/core/spatial/society/demographics_1980s_uk.json") -> void:
	if not _demographics.is_empty():
		return
	if not FileAccess.file_exists(path):
		push_error("[SocialNetwork CRITICAL] Demographic configuration file missing: %s" % path)
		assert(false, "HALT: Cannot generate population without demographics JSON.")
		return
		
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_demographics = json.data
	else:
		push_error("[SocialNetwork CRITICAL] Invalid JSON syntax in: %s" % path)
		assert(false, "HALT: Corrupted demographics JSON.")

static func _load_lexicon(path: String = "res://data_modules/core/spatial/society/names.json") -> void:
	if not _lexicon.is_empty():
		return
	if not FileAccess.file_exists(path):
		push_error("[SocialNetwork CRITICAL] Names lexicon missing: %s" % path)
		assert(false, "HALT: Cannot generate population without names.json.")
		return
		
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_lexicon = json.data
	else:
		push_error("[SocialNetwork CRITICAL] Invalid JSON syntax in: %s" % path)
		assert(false, "HALT: Corrupted names lexicon JSON.")

static func _load_cultural_demographics(path: String = "res://data_modules/core/spatial/society/cultural_demographics_1980s_midlands.json") -> void:
	if not _cultural.is_empty():
		return
	if not FileAccess.file_exists(path):
		push_error("[SocialNetwork CRITICAL] Missing cultural demographics at: %s" % path)
		assert(false, "HALT: Cannot generate society without cultural demographics JSON.")
		return
		
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_cultural = json.data
	else:
		push_error("[SocialNetwork CRITICAL] Invalid cultural demographics JSON at: %s" % path)
		assert(false, "HALT: Corrupted cultural demographics JSON.")

## Main Entry Point
static func generate_city_society(world_state: Dictionary, seed_id: String) -> void:
	_load_lexicon()
	_load_demographics()
	_load_cultural_demographics()
	
	var thresholds: Dictionary = _demographics["legal_and_pension_thresholds"]
	var labor_splits: Dictionary = _demographics["labor_market_splits"]
	var mean_household_size: float = float(_demographics.get("household_occupancy_mean", 2.6))
	var comm_share: float = float(labor_splits["commercial_tertiary_share"])
	
	DBManager.initialize_database(true)
	
	print("[SocialNetwork] Building living society, workplaces, and network ties in SQLite...")
	var start_time := Time.get_ticks_msec()
	
	var districts: Dictionary = world_state.get("districts", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_id.hash())
	
	# -------------------------------------------------------------
	# PASS 1: GENERATE WORKPLACES (Commercial & Industrial Establishments)
	# -------------------------------------------------------------
	var workplace_pool: Array[Dictionary] = _generate_workplaces(districts, rng)
	print("  ✓ Created %d workplaces across commercial and industrial zones." % workplace_pool.size())
	
	var male_names: Array = _lexicon.get("first_names_male", ["Terry"])
	var female_names: Array = _lexicon.get("first_names_female", ["Sharon"])
	
	var current_household_id: int = 1
	var current_resident_id: int = 1
	var total_edges: int = 0
	
	var commercial_wps: Array[int] = []
	var industrial_wps: Array[int] = []
	for wp in workplace_pool:
		if wp["sector"] == "COMMERCIAL":
			commercial_wps.append(wp["id"])
		else:
			industrial_wps.append(wp["id"])

	# -------------------------------------------------------------
	# PASS 2: GENERATE HOUSEHOLDS, RESIDENTS & PRIMARY KINSHIP
	# -------------------------------------------------------------
	for dist_id in districts.keys():
		var district: Dictionary = districts[dist_id]
		var pop: int = int(district.get("population", 0))
		if pop <= 0:
			continue
			
		var district_type: String = district.get("district_type", "suburban_low_density")
		var unemp_rate: float = float(district.get("unemployment_rate", 0.12))
		var venues: Dictionary = district.get("venues", {})
		var venue_keys: Array = venues.keys()
		var default_pub: String = venue_keys[0] if not venue_keys.is_empty() else "NONE"
		
		var num_households: int = max(1, int(round(float(pop) / mean_household_size)))
		
		var household_inserts: Array[String] = []
		var resident_inserts: Array[String] = []
		var edge_inserts: Array[String] = []
		var district_resident_ids: Array[int] = []
		
		var residence_type := "TERRACE"
		var wealth_bracket := 2

		match district_type:
			"high_density_high_rise":
				residence_type = "COUNCIL_FLAT"
				wealth_bracket = 1
			"high_density_low_rise":
				residence_type = "TERRACE"
				wealth_bracket = 2
			"suburban_low_density":
				residence_type = "SEMI_DETACHED"
				wealth_bracket = 4
			"commercial":
				residence_type = "FLAT_ABOVE_SHOP"
				wealth_bracket = 3

		for _h in range(num_households):
			var h_id := current_household_id
			current_household_id += 1
			
			var assigned_pub: String = venue_keys[rng.randi() % venue_keys.size()] if not venue_keys.is_empty() else default_pub
			
			# 1. Roll Household Cultural Identity
			var culture: Dictionary = _roll_household_culture(rng, district_type)
			var h_ethnicity: String = culture["ethnicity"]
			var h_religion: String = culture["religion"]
			var pool_key: String = culture["surnames_pool"]
			var surname_list: Array = _lexicon.get(pool_key, _lexicon.get("surnames", ["Smith"]))
			var family_surname: String = surname_list[rng.randi() % surname_list.size()]
			
			household_inserts.append(
				"INSERT INTO households VALUES (%d, '%s', '%s', %d, '%s', '%s', '%s');" % [
					h_id, dist_id, residence_type, wealth_bracket, assigned_pub, h_ethnicity, h_religion
				]
			)

			# 2. Roll Members of this Household
			var family_size := rng.randi_range(1, 4)
			var household_members: Array[int] = []
			
			for _m in range(family_size):
				var r_id := current_resident_id
				current_resident_id += 1
				household_members.append(r_id)
				district_resident_ids.append(r_id)
				
				var is_male: bool = (rng.randf() > 0.5)
				var is_high_dense: bool = district_type.begins_with("high_density")
				var first_name: String = male_names[rng.randi() % male_names.size()] if is_male else female_names[rng.randi() % female_names.size()]
				var age: int = _calculate_resident_age(rng, is_high_dense, is_male)
				
				# Determine Employment Status & Workplace
				var pen_age: int = int(thresholds["pension_age_male"] if is_male else thresholds["pension_age_female"])
				var min_school_age: int = int(thresholds["minimum_school_leaving_age"])
				var student_threshold: int = int(thresholds["youth_student_threshold_age"])
				var occ := "UNEMPLOYED"
				var assigned_wp_id: int = 0
				
				if age >= pen_age:
					occ = "PENSIONER"
				elif age < min_school_age:
					occ = "CHILD"
				elif age < student_threshold and rng.randf() < 0.35:
					occ = "STUDENT"
				elif rng.randf() < unemp_rate:
					occ = "UNEMPLOYED"
				else:
					if rng.randf() < comm_share and not commercial_wps.is_empty():
						occ = "COMMERCIAL_SERVICE"
						assigned_wp_id = commercial_wps[rng.randi() % commercial_wps.size()]
					elif not industrial_wps.is_empty():
						occ = "MANUAL_WORKS"
						assigned_wp_id = industrial_wps[rng.randi() % industrial_wps.size()]
					else:
						occ = "GENERAL_LABOUR"
				
				resident_inserts.append(
					"INSERT INTO residents VALUES (%d, %d, %d, '%s', '%s', %d, '%s', '%s', '%s', 0);" % [
						r_id, h_id, assigned_wp_id, first_name, family_surname, age, occ, h_ethnicity, h_religion
					]
				)
			
			# Circle 1: Kinship Edges (Shared household trust)
			if household_members.size() > 1:
				for a in household_members:
					for b in household_members:
						if a != b:
							edge_inserts.append(
								"INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'FAMILY', 0.90);" % [a, b]
							)
							total_edges += 1
		
		# Circle 2: Pub Catchment Edges (Drinking mates)
		for r_id in district_resident_ids:
			var buddy_count := rng.randi_range(2, 4)
			for _b in range(buddy_count):
				var target_id: int = district_resident_ids[rng.randi() % district_resident_ids.size()]
				if target_id != r_id:
					edge_inserts.append(
						"INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'DRINKING_MATE', 0.55);" % [r_id, target_id]
					)
					total_edges += 1
		
		# Commit batch for this district
		DBManager.execute_batch(household_inserts)
		DBManager.execute_batch(resident_inserts)
		DBManager.execute_batch(edge_inserts)

	# -------------------------------------------------------------
	# PASS 3: EXTENDED KINSHIP ACROSS HOUSEHOLDS
	# -------------------------------------------------------------
	var ext_edges: int = _generate_extended_kinship(rng)
	total_edges += ext_edges
	print("  ✓ Stitched %d extended family connections across households." % ext_edges)

	# -------------------------------------------------------------
	# PASS 4: COWORKER EDGES (Workplace Dunbar Ties)
	# -------------------------------------------------------------
	var coworker_edges: int = _generate_coworker_relationships(rng)
	total_edges += coworker_edges
	print("  ✓ Stitched %d coworker relationship ties across workplaces." % coworker_edges)

	# -------------------------------------------------------------
	# PASS 5: COMMUNITY & PARISH TIES (Shared Faith & Ethnicity)
	# -------------------------------------------------------------
	var faith_edges: int = _generate_faith_and_cultural_ties(rng)
	total_edges += faith_edges
	print("  ✓ Stitched %d community & parish connections." % faith_edges)

	var elapsed := Time.get_ticks_msec() - start_time
	print("=======================================================")
	print("       SOCIAL NETWORK GRAPH GENERATION COMPLETE        ")
	print("=======================================================")
	print("Elapsed Time:      %d ms" % elapsed)
	print("Total Workplaces:  %d" % workplace_pool.size())
	print("Total Households:  %d" % (current_household_id - 1))
	print("Total Citizens:    %d" % (current_resident_id - 1))
	print("Network Edges:     ~%d relationship connections" % total_edges)
	print("=======================================================\n")

## Helper: Creates realistic commercial and industrial establishments per block
static func _generate_workplaces(districts: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var wps: Array[Dictionary] = []
	var inserts: Array[String] = []
	var wp_id: int = 1
	
	var commercial_names := ["High St Retail", "Council Offices", "Depot & Logistics", "Co-Op Store", "Local Bakery", "Printing Works", "Post Office Branch"]
	var industrial_names := ["Foundry & Castings", "Metal Finishing", "Auto Component Plant", "Textile Mill", "Engineering Shed", "Plastics Moulding", "Scrap & Salvage"]
	
	for dist_id in districts.keys():
		var d = districts[dist_id]
		var dtype: String = d.get("district_type", "")
		
		var num_commercial := 0
		var num_industrial := 0
		
		if dtype == "commercial":
			num_commercial = rng.randi_range(6, 12)
			num_industrial = rng.randi_range(0, 2)
		elif dtype == "industrial":
			num_industrial = rng.randi_range(4, 8)
			num_commercial = rng.randi_range(1, 2)
		else:
			num_commercial = rng.randi_range(1, 3)
			num_industrial = 0
		
		for _c in range(num_commercial):
			var name = "%s (%s)" % [commercial_names[rng.randi() % commercial_names.size()], dist_id]
			var cap = rng.randi_range(8, 40)
			inserts.append("INSERT INTO workplaces VALUES (%d, '%s', '%s', 'COMMERCIAL', %d);" % [wp_id, dist_id, name, cap])
			wps.append({"id": wp_id, "district_id": dist_id, "sector": "COMMERCIAL"})
			wp_id += 1
			
		for _i in range(num_industrial):
			var name = "%s (%s)" % [industrial_names[rng.randi() % industrial_names.size()], dist_id]
			var cap = rng.randi_range(20, 80)
			inserts.append("INSERT INTO workplaces VALUES (%d, '%s', '%s', 'INDUSTRIAL', %d);" % [wp_id, dist_id, name, cap])
			wps.append({"id": wp_id, "district_id": dist_id, "sector": "INDUSTRIAL"})
			wp_id += 1

	DBManager.execute_batch(inserts)
	return wps

## Pass 3: Extended Kinship
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

## Pass 4: Links coworkers at the same workplace
static func _generate_coworker_relationships(rng: RandomNumberGenerator) -> int:
	var coworker_edges: Array[String] = []
	var edge_count: int = 0

	var workplace_clusters = DBManager.query_rows("""
		SELECT workplace_id, GROUP_CONCAT(resident_id) as worker_ids, COUNT(*) as count
		FROM residents
		WHERE workplace_id > 0
		GROUP BY workplace_id
		HAVING count > 1;
	""")

	for cluster in workplace_clusters:
		var ids_raw: String = cluster["worker_ids"]
		var id_strings: PackedStringArray = ids_raw.split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		for a in ids:
			var ties := rng.randi_range(1, 3)
			for _t in range(ties):
				var b: int = ids[rng.randi() % ids.size()]
				if a != b:
					coworker_edges.append("INSERT OR IGNORE INTO social_relationships VALUES (%d, %d, 'CO_WORKER', 0.60);" % [a, b])
					edge_count += 1

		if coworker_edges.size() >= 500:
			DBManager.execute_batch(coworker_edges)
			coworker_edges.clear()

	if not coworker_edges.is_empty():
		DBManager.execute_batch(coworker_edges)

	return edge_count

## Pass 5: Links churchgoers, temple members, and cultural community networks
static func _generate_faith_and_cultural_ties(rng: RandomNumberGenerator) -> int:
	var ties: Array[String] = []
	var edge_count: int = 0

	var congregation_clusters = DBManager.query_rows("""
		SELECT district_id, ethnicity, religion, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents
		WHERE religion != 'SECULAR_NONE' AND age >= 18
		GROUP BY district_id, ethnicity, religion
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

## Dynamically evaluates age based on loaded demographic cohort weights
static func _calculate_resident_age(rng: RandomNumberGenerator, is_high_density: bool, is_male: bool) -> int:
	var cohorts_key := "high_density" if is_high_density else "suburban_low_density"
	var cohorts: Dictionary = _demographics["cohort_distributions"][cohorts_key]
	var thresholds: Dictionary = _demographics["legal_and_pension_thresholds"]
	var life_caps: Dictionary = _demographics["life_expectancy_caps"]
	
	var p_female: int = int(thresholds["pension_age_female"])
	var p_male: int = int(thresholds["pension_age_male"])
	var pen_age: int = p_male if is_male else p_female
	var max_age: int = int(life_caps["male_max_age"] if is_male else life_caps["female_max_age"])

	var w_youth: float = float(cohorts["youth_0_15"])
	var w_young: float = w_youth + float(cohorts["young_adult_16_29"])
	var w_prime: float = w_young + float(cohorts["prime_adult_30_49"])
	var w_older: float = w_prime + float(cohorts["older_worker_50_plus"])

	var roll := rng.randf()
	if roll < w_youth:
		return rng.randi_range(0, 15)
	elif roll < w_young:
		return rng.randi_range(16, 29)
	elif roll < w_prime:
		return rng.randi_range(30, 49)
	elif roll < w_older:
		return rng.randi_range(50, pen_age - 1)
	else:
		return rng.randi_range(pen_age, max_age)

## Roll ethnicity and religion for a household based on district density
static func _roll_household_culture(rng: RandomNumberGenerator, district_type: String) -> Dictionary:
	var weights_key := "high_density" if district_type.begins_with("high_density") else ("commercial" if district_type == "commercial" else "suburban_low_density")
	var dist_weights: Dictionary = _cultural["district_ethnic_weights"][weights_key]
	
	var roll := rng.randf()
	var cumulative := 0.0
	var chosen_eth := "WHITE_BRITISH"
	
	for eth in dist_weights.keys():
		cumulative += float(dist_weights[eth])
		if roll <= cumulative:
			chosen_eth = eth
			break
			
	var eth_profile: Dictionary = _cultural["ethnicities"][chosen_eth]
	var rel_weights: Dictionary = eth_profile["religion_distribution"]
	
	roll = rng.randf()
	cumulative = 0.0
	var chosen_rel := "SECULAR_NONE"
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