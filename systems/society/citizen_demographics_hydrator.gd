# res://systems/society/citizen_demographics_hydrator.gd
class_name CitizenDemographicsHydrator
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

## Pass 3: Hydrates living citizens, verifies qualifications, and matches jobs via edge commute
static func run(
	physical_state: Dictionary,
	demographics: Dictionary,
	lexicon: Dictionary,
	job_definitions: Dictionary,
	rng: RandomNumberGenerator,
	on_progress: Callable
) -> void:
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

	# Create strictly typed queues by category
	var jobs_by_cat: Dictionary = {}
	for slot in open_job_slots:
		var c: String = str(slot["cat"])
		if not jobs_by_cat.has(c):
			var arr: Array[Dictionary] = []
			jobs_by_cat[c] = arr
		jobs_by_cat[c].append(slot)

	var male_names: Array = lexicon.get("first_names_male", ["Terry"])
	var female_names: Array = lexicon.get("first_names_female", ["Sharon"])

	var resident_inserts: Array[String] = []
	var contract_inserts: Array[String] = []
	var edge_inserts: Array[String] = []

	var current_resident_id: int = 1
	var total_hh: int = generated_households.size()
	var hh_idx: int = 0

	for hh in generated_households:
		hh_idx += 1
		var family_size := rng.randi_range(1, 4)
		var surname_list: Array = lexicon.get(hh["surnames_pool"], ["Smith"])
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
			var demo_profile: Dictionary = resolve_citizen_demographics(demographics, rng, is_high_dense, is_male, hh["unemp_rate"], 0.70, is_head)
			var age_years: int = int(demo_profile["age"])

			var days_old: int = int(round(float(age_years) * 365.25)) + rng.randi_range(0, 364)
			var dob_day: int = sim_start_day - days_old

			var edu_code: String = resolve_citizen_education(demographics, rng, age_years, is_high_dense)
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

			# 1. Active Formal Workforce: Match via Commute Radius & Education Eligibility
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
						job_definitions,
						rng
					)
					if not slot.is_empty():
						assigned_est_id = int(slot["estab_id"])
						occ_title = slot["role"]
						weekly_hours = slot["hours"]
						compensation_rate = slot["rate"]
					else:
						# Saturated or Unqualified -> Transition to Unemployment
						assigned_est_id = _transition_to_dole(demo_profile, by_cat, hh["district_id"], rng)
						occ_title = demo_profile.get("unemployed_branch", {}).get("role", "UNEMPLOYED")
						contract_class = "INFORMAL_GREY"
						weekly_hours = 0.0
						compensation_rate = 0.0
				else:
					assigned_est_id = _transition_to_dole(demo_profile, by_cat, hh["district_id"], rng)
					occ_title = demo_profile.get("unemployed_branch", {}).get("role", "UNEMPLOYED")
					contract_class = "INFORMAL_GREY"
					weekly_hours = 0.0
					compensation_rate = 0.0
			else:
				assigned_est_id = pick_anchor(demographics, by_cat, anchor_cat, hh["district_id"], rng)

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
	audit_generated_jobs_by_education()

static func _transition_to_dole(demo_profile: Dictionary, by_cat: Dictionary, dist_id: String, rng: RandomNumberGenerator) -> int:
	var unemp_branch: Dictionary = demo_profile.get("unemployed_branch", {})
	var cat: String = str(unemp_branch.get("anchor_category", "JOBCENTRE"))
	return pick_anchor(demo_profile, by_cat, cat, dist_id, rng)

static func pick_anchor(demographics: Dictionary, by_cat: Dictionary, requested_category: String, _dist_id: String, rng: RandomNumberGenerator) -> int:
	var target_cat: String = requested_category
	var fallbacks: Dictionary = demographics.get("anchor_category_fallbacks", {})
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

	assert(not list.is_empty(), "FATAL: Zero establishments registered in by_cat.")
	var picked: Dictionary = list[rng.randi() % list.size()]
	return int(picked["id"])

static func resolve_citizen_demographics(demographics: Dictionary, rng: RandomNumberGenerator, is_high_density: bool, is_male: bool, unemp_rate: float, comm_share: float, is_head_of_household: bool = false) -> Dictionary:
	var cohorts: Array = demographics.get("cohort_profiles", [])
	var thresholds: Dictionary = demographics.get("legal_and_pension_thresholds", {})
	var life_caps: Dictionary = demographics.get("life_expectancy_caps", {})

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
		"compensation_rate": float(profile_data.get("compensation_rate", 3.50)),
		"unemployed_branch": chosen_cohort.get("unemployed_branch", {})
	}

static func resolve_citizen_education(demographics: Dictionary, rng: RandomNumberGenerator, age_years: int, is_high_density: bool) -> String:
	var edu_model: Dictionary = demographics["education_attainment_model"]
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

static func audit_generated_jobs_by_education() -> void:
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