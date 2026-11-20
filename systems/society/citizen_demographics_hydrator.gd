# res://systems/society/citizen_demographics_hydrator.gd
class_name CitizenDemographicsHydrator
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const HOUSEHOLD_COMPOSER = preload("res://systems/society/household_composition_generator.gd")
const PERSONALITY_HYDRATOR = preload("res://systems/society/citizen_personality_hydrator.gd")
const FAMILY_WEAVER = preload("res://systems/society/family_tree_weaver.gd")
const ANCHOR_ALLOCATOR = preload("res://systems/society/unified_anchor_allocator.gd")
const SPATIAL_RADIUS_INDEX = preload("res://systems/society/spatial_radius_index.gd")
const GENERATION_AUDITOR = preload("res://systems/society/society_generation_auditor.gd")

## Pass 3: Orchestrates household composition, OCEAN personalities, kinship trees, labor, org governance, and calendar schedules
static func run(
	physical_state: Dictionary,
	demographics: Dictionary,
	lexicon: Dictionary,
	job_definitions: Dictionary,
	cultural: Dictionary,
	rng: RandomNumberGenerator,
	on_progress: Callable
) -> void:
	var districts: Dictionary = physical_state.get("districts", {})
	var generated_households: Array[Dictionary] = physical_state["households"]
	var by_cat: Dictionary = physical_state["by_cat"]
	var district_residents_map: Dictionary = physical_state["district_residents_map"]
	var open_job_slots: Array[Dictionary] = physical_state["available_job_slots"]
	var available_tied_housing: Dictionary = physical_state.get("available_tied_housing", {})

	var archetypes_cfg: Dictionary = MANIFEST_MANAGER.load_module("archetypes")
	var ocean_rules: Dictionary = MANIFEST_MANAGER.load_module("ocean_personality")
	var civic_cfg: Dictionary = MANIFEST_MANAGER.load_module("civic_hierarchy")
	var kinship_rules: Dictionary = FAMILY_WEAVER.get_kinship_rules(demographics)
	var edu_rank_map: Dictionary = HOUSEHOLD_COMPOSER.get_education_rank_map(demographics)
	var job_roles_cfg: Dictionary = job_definitions.get("roles", job_definitions)

	var cfg := ConfigFile.new()
	var err: int = cfg.load(MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	assert(err == OK, "FATAL: [CitizenDemographicsHydrator] Could not load business_rules.cfg")
	var enable_commute: bool = bool(cfg.get_value("labor_market", "enable_commute_distances", false))

	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var male_gender_id: int = DB_MANAGER.get_label_id("GENDER", "M")
	var female_gender_id: int = DB_MANAGER.get_label_id("GENDER", "F")
	var contract_std_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", "STANDARD")
	var rel_civic_peer_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CIVIC_PEER")
	var default_daytime_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", "DAYTIME")

	var proprietor_hints: Dictionary = physical_state.get("proprietor_hints", {})

	# Build spatial position, capacity, and category ID indexes for UnifiedAnchorAllocator
	var by_cat_and_district: Dictionary = {}
	var cat_estab_ids: Dictionary = {}
	var estab_positions: Dictionary = {}
	var estab_capacities: Dictionary = {}
	var enrolled_counts: Dictionary = {}

	for cat in by_cat.keys():
		by_cat_and_district[cat] = {}
		cat_estab_ids[cat] = []
		for item in by_cat[cat]:
			var est_id: int = int(item["id"])
			var d_id: String = str(item.get("district_id", ""))
			if not by_cat_and_district[cat].has(d_id):
				by_cat_and_district[cat][d_id] = []
			by_cat_and_district[cat][d_id].append(item)
			cat_estab_ids[cat].append(est_id)

			var d_pos: Vector2 = Vector2.ZERO
			if districts.has(d_id):
				d_pos = SPATIAL_RESOLVER._resolve_vector2(districts[d_id].get("spatial_anchor", Vector2.ZERO))
			estab_positions[est_id] = d_pos
			estab_capacities[est_id] = int(item.get("capacity", 250))

	var church_estabs: Array = []
	for ch_cat in ["PLACE_OF_WORSHIP", "CHURCH", "COMMUNITY_PARISH"]:
		if cat_estab_ids.has(ch_cat):
			for cid in cat_estab_ids[ch_cat]:
				if not church_estabs.has(cid):
					church_estabs.append(cid)

	var pub_estabs: Array = []
	for pb_cat in ["LOCAL_PUB", "PUB", "PUBLIC_HOUSE", "SOCIAL_CLUB", "HOSPITALITY"]:
		if cat_estab_ids.has(pb_cat):
			for pid in cat_estab_ids[pb_cat]:
				if not pub_estabs.has(pid):
					pub_estabs.append(pid)

	# Normalize open_job_slots keys for UnifiedAnchorAllocator
	open_job_slots.shuffle()
	for slot in open_job_slots:
		if not slot.has("establishment_id") and slot.has("estab_id"):
			slot["establishment_id"] = int(slot["estab_id"])
		if not slot.has("role_code") and slot.has("role_title"):
			slot["role_code"] = str(slot["role_title"])
		if not slot.has("min_education_code"):
			var r_code: String = str(slot.get("role_code", ""))
			var r_def: Dictionary = job_roles_cfg.get(r_code, {})
			slot["min_education_code"] = str(slot.get("edu_req", r_def.get("education_required", "NO_FORMAL")))

	# Build 2D spatial hash indexes for O(1) moving-circle commute and venue queries
	var job_slot_index: SpatialRadiusIndex = ANCHOR_ALLOCATOR.build_job_slot_spatial_index(open_job_slots, estab_positions, 1500.0)
	var church_spatial_index: SpatialRadiusIndex = ANCHOR_ALLOCATOR.build_establishment_spatial_index(church_estabs, estab_positions, 1500.0)
	var pub_spatial_index: SpatialRadiusIndex = ANCHOR_ALLOCATOR.build_establishment_spatial_index(pub_estabs, estab_positions, 1500.0)
	var school_spatial_indexes: Dictionary = {}
	for s_cat in ["PRIMARY_SCHOOL", "SECONDARY_SCHOOL", "UNIVERSITY_OR_POLYTECHNIC"]:
		var s_ids: Array = cat_estab_ids.get(s_cat, [])
		if not s_ids.is_empty():
			school_spatial_indexes[s_cat] = ANCHOR_ALLOCATOR.build_establishment_spatial_index(s_ids, estab_positions, 1500.0)

	var resident_inserts: Array[String] = []
	var contract_inserts: Array[String] = []
	var org_member_inserts: Array[String] = []
	var edge_inserts: Array[String] = []
	var slot_updates: Array[String] = []
	var resident_updates: Array[String] = []
	var tied_household_inserts: Array[String] = []

	var residents_by_id: Dictionary = {}
	var kin_graph: Dictionary = {}
	var workplace_cohort_pubs: Dictionary = {}

	var current_resident_id: int = 1
	var total_hh: int = generated_households.size()
	var hh_idx: int = 0
	var next_household_id: int = total_hh + 1
	var is_headless: bool = (DisplayServer.get_name() == "headless")

	var pass3_start_ms: int = Time.get_ticks_msec()
	var chunk_start_ms: int = pass3_start_ms

	var tied_occupants: Array[Dictionary] = []
	var local_tied_relocated_count := 0
	var external_tied_influx_count := 0

	SystemLogger.log_info("  [Pass 3] Hydrating %d households with OCEAN traits, kinship trees, and individual anchors..." % total_hh)

	# --------------------------------------------------------------------------
	# STAGE 1: Standard Household Hydration & Local Tied Youth Relocation (50% -> 75%)
	# --------------------------------------------------------------------------
	for hh in generated_households:
		hh_idx += 1
		var surname_list: Array = lexicon.get(hh["surnames_pool"], ["Smith"])
		var family_surname: String = str(surname_list[rng.randi() % surname_list.size()]).replace("'", "''")
		var district_type: String = str(hh["district_type"])
		var is_high_dense: bool = district_type.begins_with("high_density")
		var unemp_rate: float = float(hh.get("unemp_rate", 0.10))
		var home_estab_id: int = int(hh["establishment_id"])
		var hh_id: int = int(hh["household_id"])
		var hh_dist_id: String = str(hh["district_id"])
		var home_pos: Vector2 = Vector2.ZERO
		if districts.has(hh_dist_id):
			home_pos = SPATIAL_RESOLVER._resolve_vector2(districts[hh_dist_id].get("spatial_anchor", Vector2.ZERO))

		var arch_nudges: Dictionary = PERSONALITY_HYDRATOR.get_archetype_nudges(archetypes_cfg, district_type)
		var planned_members: Array[Dictionary] = HOUSEHOLD_COMPOSER.generate_household_composition(demographics, rng)

		var has_child_under_5: bool = false
		var has_child_5_to_15: bool = false
		var is_married_couple: bool = false
		for m in planned_members:
			var age: int = int(m["age"])
			if age < 5:
				has_child_under_5 = true
			elif age <= 15:
				has_child_5_to_15 = true
			if str(m.get("role_in_home", "")) == "SPOUSE":
				is_married_couple = bool(m.get("is_married", true))

		var hh_member_records: Array[Dictionary] = []
		var head_traits: Dictionary = {}
		var spouse_traits: Dictionary = {}
		var head_church_id: int = -1
		var spouse_church_id: int = -1
		var hh_sibling_school_by_cat: Dictionary = {}

		for member in planned_members:
			var r_id := current_resident_id
			current_resident_id += 1
			district_residents_map[hh_dist_id].append(r_id)

			var is_male: bool = bool(member["is_male"])
			var gender_code: String = "MALE" if is_male else "FEMALE"
			var age_years: int = int(member["age"])
			var is_head: bool = bool(member.get("is_head", false))
			var is_married: bool = bool(member.get("is_married", false))
			var role_in_home: String = str(member.get("role_in_home", "CHILD"))

			if is_head:
				resident_updates.append("UPDATE households SET head_resident_id = %d WHERE household_id = %d;" % [r_id, hh_id])

			var gender_id: int = male_gender_id if is_male else female_gender_id
			var hh_religion: String = str(hh.get("religion", ""))
			var hh_surnames_pool: String = str(hh.get("surnames_pool", "surnames"))
			var first_name: String = HOUSEHOLD_COMPOSER.pick_first_name(lexicon, is_male, hh_surnames_pool, hh_religion, rng)
			var member_surname: String = family_surname

			if role_in_home == "PEER":
				var peer_surname_list: Array = lexicon.get(hh["surnames_pool"], ["Smith"])
				member_surname = str(peer_surname_list[rng.randi() % peer_surname_list.size()]).replace("'", "''")

			var days_old: int = int(round(float(age_years) * 365.25)) + rng.randi_range(0, 364)
			var dob_day: int = sim_start_day - days_old

			var edu_code: String = HOUSEHOLD_COMPOSER.resolve_citizen_education(demographics, rng, age_years, is_male, is_high_dense)
			var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", edu_code)
			var edu_nudges: Dictionary = PERSONALITY_HYDRATOR.get_education_nudges(demographics, edu_code)

			# 1. Roll OCEAN Personality Traits
			var ocean_traits: Dictionary = {}
			if role_in_home == "HEAD":
				ocean_traits = PERSONALITY_HYDRATOR.roll_independent_adult_traits(ocean_rules, arch_nudges, edu_nudges, rng)
				head_traits = ocean_traits
			elif role_in_home == "SPOUSE":
				ocean_traits = PERSONALITY_HYDRATOR.roll_spouse_traits(head_traits, ocean_rules, arch_nudges, edu_nudges, rng)
				spouse_traits = ocean_traits
			elif role_in_home == "CHILD":
				ocean_traits = PERSONALITY_HYDRATOR.roll_child_traits(head_traits, spouse_traits, ocean_rules, arch_nudges, edu_nudges, rng)
			else:
				ocean_traits = PERSONALITY_HYDRATOR.roll_independent_adult_traits(ocean_rules, arch_nudges, edu_nudges, rng)

			# 2. Resolve Individual Church / Parish Anchor
			var church_id: int = ANCHOR_ALLOCATOR.resolve_individual_church_id(
				role_in_home, hh_religion, home_pos, head_church_id, spouse_church_id,
				church_estabs, estab_positions, ocean_rules, rng, church_spatial_index
			)
			if role_in_home == "HEAD":
				head_church_id = church_id
			elif role_in_home == "SPOUSE":
				spouse_church_id = church_id

			# 3. Resolve Role & Employment / School Profile
			var demo_profile: Dictionary = HOUSEHOLD_COMPOSER.resolve_citizen_demographics(
				demographics, rng, age_years, is_male, unemp_rate, edu_code,
				is_married, has_child_under_5, has_child_5_to_15
			)

			var occ_title: String = demo_profile["occupation"]
			var anchor_cat: String = demo_profile["anchor_category"]
			var contract_class: String = demo_profile["contract_class"]
			var weekly_hours: float = float(demo_profile["weekly_hours"])
			var compensation_rate: float = float(demo_profile["compensation_rate"])
			var assigned_est_id: int = 0
			var active_contract_class_id: int = -1
			var active_role_title_id: int = -1
			var active_sched_id: int = default_daytime_id

			var candidate_ctx: Dictionary = {
				"resident_id": r_id,
				"age_years": age_years,
				"education_code": edu_code,
				"home_pos": home_pos,
				"ocean_traits": ocean_traits
			}

			if occ_title == "HOME_MAKER":
				assigned_est_id = home_estab_id
			elif contract_class == "FORMAL_LEGAL":
				var matched_idx: int = ANCHOR_ALLOCATOR.match_best_job_slot_for_resident(
					candidate_ctx, open_job_slots, edu_rank_map, job_roles_cfg,
					ocean_rules, estab_positions, enable_commute, rng, job_slot_index
				)

				if matched_idx >= 0:
					var slot: Dictionary = open_job_slots[matched_idx]
					slot["_claimed"] = true
					slot["_index"] = -1
					var back_slot: Dictionary = open_job_slots.back()
					open_job_slots[matched_idx] = back_slot
					back_slot["_index"] = matched_idx
					open_job_slots.pop_back()

					assert(slot.has("estab_id"), "FATAL: Slot missing mandatory 'estab_id'!")
					assert(slot.has("role_title"), "FATAL: Slot missing mandatory 'role_title'!")
					assert(slot.has("role_title_id"), "FATAL: Slot missing mandatory 'role_title_id'!")
					assert(slot.has("contract_class_id"), "FATAL: Slot missing mandatory 'contract_class_id'!")
					assert(slot.has("hours"), "FATAL: Slot missing mandatory 'hours'!")
					assert(slot.has("rate"), "FATAL: Slot missing mandatory 'rate'!")

					assigned_est_id = int(slot["estab_id"])
					occ_title = str(slot["role_title"])
					weekly_hours = float(slot["hours"])
					compensation_rate = float(slot["rate"])
					active_contract_class_id = int(slot["contract_class_id"])
					active_role_title_id = int(slot["role_title_id"])
					active_sched_id = int(slot.get("schedule_window_id", default_daytime_id))

					if slot.has("slot_id"):
						slot_updates.append("UPDATE workplace_job_slots SET is_filled = 1, active_resident_id = %d WHERE slot_id = %d;" % [
							r_id, int(slot["slot_id"])
						])

					# Bind organization governance membership for leadership/executive roles at owned establishments
					var slot_tier: String = str(slot.get("social_tier", "STAFF"))
					var slot_clearance: float = float(slot.get("intel_clearance", 0.3))
					if slot_tier == "MANAGEMENT" or slot_clearance >= 0.85:
						var auth_mask: int = 3 if slot_clearance >= 1.0 else 1
						org_member_inserts.append("""
							INSERT OR IGNORE INTO organization_members (
								org_id, resident_id, role_code, authority_mask, valid_from, valid_to, change_reason_id
							)
							SELECT owner_org_id, %d, '%s', %d, %d, NULL, %d
							FROM establishments
							WHERE establishment_id = %d AND owner_org_id IS NOT NULL AND owner_org_id != '';
						""" % [r_id, occ_title, auth_mask, sim_start_day, reason_world_gen_id, assigned_est_id])

					if proprietor_hints.has(assigned_est_id) and is_head:
						var hint: Dictionary = proprietor_hints[assigned_est_id]
						proprietor_hints.erase(assigned_est_id)
						var prop_surname: String = str(hint["surname"]).replace("'", "''")
						var prop_eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", str(hint["ethnicity"]))
						var prop_rel_id: int = DB_MANAGER.get_label_id("RELIGION", str(hint["religion"]))
						var prop_first: String = HOUSEHOLD_COMPOSER.pick_first_name(lexicon, is_male, str(hint["surnames_pool"]), str(hint["religion"]), rng)
						family_surname = prop_surname
						member_surname = prop_surname
						resident_updates.append("UPDATE residents SET birth_surname = '%s', current_surname = '%s', ethnicity_id = %d, religion_id = %d WHERE household_id = %d;" % [
							prop_surname, prop_surname, prop_eth_id, prop_rel_id, hh_id
						])
						resident_updates.append("UPDATE residents SET first_name = '%s' WHERE resident_id = %d;" % [
							prop_first, r_id
						])

					var tied_type: String = str(slot.get("tied_accomodation", ""))
					if not tied_type.is_empty() and available_tied_housing.has(tied_type) and not is_head:
						var unit_list: Array = available_tied_housing[tied_type]
						if not unit_list.is_empty():
							var tied_unit: Dictionary = unit_list.pop_back()
							var tied_h_id: int = next_household_id
							next_household_id += 1

							var tied_est_id: int = int(tied_unit["establishment_id"])
							var tied_res_type_id: int = int(tied_unit["residence_type_id"])
							var tied_wealth_id: int = int(tied_unit["wealth_bracket_id"])

							tied_household_inserts.append("""
								INSERT INTO households (
									household_id, establishment_id, head_resident_id, residence_type_id,
									wealth_bracket_id, ethnicity_id, religion_id,
									valid_from, valid_to, change_reason_id
								) VALUES (%d, %d, %d, %d, %d, %d, %d, %d, NULL, %d);
							""" % [
								tied_h_id, tied_est_id, r_id, tied_res_type_id,
								tied_wealth_id, hh["ethnicity_id"], hh["religion_id"], sim_start_day, reason_world_gen_id
							])

							resident_updates.append("UPDATE residents SET household_id = %d WHERE resident_id = %d;" % [tied_h_id, r_id])
							resident_updates.append("UPDATE establishments SET is_vacant = 0 WHERE establishment_id = %d;" % tied_est_id)

							tied_occupants.append({
								"resident_id": r_id,
								"establishment_id": tied_est_id,
								"workplace_id": assigned_est_id,
								"residence_type_id": tied_res_type_id,
								"age": age_years
							})
							local_tied_relocated_count += 1
				else:
					assigned_est_id = _transition_to_dole(by_cat, home_estab_id, rng)
					occ_title = "UNEMPLOYED"
					contract_class = "INFORMAL_GREY"
					weekly_hours = 0.0
					compensation_rate = 0.0
			elif contract_class == "ENCLAVE_STUDENT" or anchor_cat in ["PRIMARY_SCHOOL", "SECONDARY_SCHOOL", "UNIVERSITY_OR_POLYTECHNIC"]:
				var school_candidates: Array = cat_estab_ids.get(anchor_cat, [])
				var pref_sib_school: int = int(hh_sibling_school_by_cat.get(anchor_cat, -1))
				assigned_est_id = ANCHOR_ALLOCATOR.allocate_school_or_enclave_anchor(
					home_pos, school_candidates, estab_positions, estab_capacities,
					enrolled_counts, pref_sib_school, rng, school_spatial_indexes.get(anchor_cat, null)
				)
				if assigned_est_id > 0 and role_in_home == "CHILD":
					hh_sibling_school_by_cat[anchor_cat] = assigned_est_id
				if assigned_est_id <= 0:
					assigned_est_id = pick_anchor(demographics, by_cat, by_cat_and_district, anchor_cat, hh_dist_id, rng)
				if job_roles_cfg.has(occ_title):
					var comp: Dictionary = PremisesWorkplaceBuilder.resolve_standardized_compensation(job_roles_cfg[occ_title], job_definitions, 0.0)
					weekly_hours = float(comp["weekly_hours"])
					compensation_rate = float(comp["hourly_rate"])
					active_sched_id = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", str(comp["schedule_window"]))
			else:
				assigned_est_id = pick_anchor(demographics, by_cat, by_cat_and_district, anchor_cat, hh_dist_id, rng)
				if job_roles_cfg.has(occ_title):
					var comp: Dictionary = PremisesWorkplaceBuilder.resolve_standardized_compensation(job_roles_cfg[occ_title], job_definitions, 0.0)
					weekly_hours = float(comp["weekly_hours"])
					compensation_rate = float(comp["hourly_rate"])
					active_sched_id = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", str(comp["schedule_window"]))

			if assigned_est_id <= 0:
				assigned_est_id = _transition_to_dole(by_cat, home_estab_id, rng)

			var res_record: Dictionary = {
				"resident_id": r_id,
				"household_id": hh_id,
				"household_role": role_in_home,
				"birth_surname": member_surname,
				"ethnicity_id": int(hh["ethnicity_id"]),
				"gender_code": gender_code,
				"age_years": age_years,
				"dob": dob_day,
				"home_pos": home_pos,
				"church_id": church_id,
				"local_pub_id": -1,
				"employer_establishment_id": assigned_est_id,
				"role_code": occ_title,
				"ocean_traits": ocean_traits
			}

			# 4. Resolve Individual Social-Cohort Pub
			var local_pub_id: int = ANCHOR_ALLOCATOR.resolve_individual_pub_id(
				res_record, pub_estabs, estab_positions, estab_capacities,
				workplace_cohort_pubs, kin_graph, residents_by_id,
				job_roles_cfg, ocean_rules, rng, pub_spatial_index
			)
			res_record["local_pub_id"] = local_pub_id
			residents_by_id[r_id] = res_record
			hh_member_records.append(res_record)

			var church_sql_str: String = "NULL" if church_id <= 0 else str(church_id)
			var pub_sql_str: String = "NULL" if local_pub_id <= 0 else str(local_pub_id)

			resident_inserts.append("""
				INSERT INTO residents (
					resident_id, household_id, first_name, birth_surname, current_surname,
					dob, dod, death_reason_id, gender_id, education_level_id,
					ethnicity_id, religion_id, church_id, local_pub_id,
					openness, conscientiousness, extraversion, agreeableness, neuroticism,
					is_active_agent, valid_from, valid_to, change_reason_id
				) VALUES (
					%d, %d, '%s', '%s', '%s', %d, NULL, NULL, %d, %d, %d, %d, %s, %s,
					%.3f, %.3f, %.3f, %.3f, %.3f,
					0, %d, NULL, %d
				);
			""" % [
				r_id, hh_id, first_name, member_surname, member_surname,
				dob_day, gender_id, edu_id, int(hh["ethnicity_id"]), int(hh["religion_id"]),
				church_sql_str, pub_sql_str,
				float(ocean_traits["openness"]), float(ocean_traits["conscientiousness"]),
				float(ocean_traits["extraversion"]), float(ocean_traits["agreeableness"]),
				float(ocean_traits["neuroticism"]),
				sim_start_day, reason_world_gen_id
			])

			var class_id: int = active_contract_class_id if active_contract_class_id > 0 else DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)
			var role_id: int = active_role_title_id if active_role_title_id > 0 else DB_MANAGER.get_label_id("ROLE_TITLE", occ_title)

			contract_inserts.append("""
				INSERT INTO livelihood_contracts (
					resident_id, employer_org_id, employer_establishment_id, contract_class_id, role_title_id,
					contract_type_id, schedule_window_id, weekly_hours, compensation_rate, 
					valid_from, valid_to, change_reason_id
				) VALUES (
					%d, (SELECT owner_org_id FROM establishments WHERE establishment_id = %d), %d, %d, %d, %d, %d, %.1f, %.2f, %d, NULL, %d
				);
			""" % [
				r_id, assigned_est_id, assigned_est_id, class_id, role_id, contract_std_id, active_sched_id,
				weekly_hours, compensation_rate, sim_start_day, reason_world_gen_id
			])

		# 5. Weave Directional Intra-Household Nuclear Kinship Edges (with realistic marriage dates)
		if hh_member_records.size() > 1:
			FAMILY_WEAVER.weave_intra_household_edges(
				edge_inserts, hh_member_records, is_married_couple,
				home_estab_id, kinship_rules, reason_world_gen_id, kin_graph
			)

		# Flush batches every 250 households for low peak RAM and smooth progress bar updates
		if hh_idx % 250 == 0:
			var gen_time: int = Time.get_ticks_msec() - chunk_start_ms
			var db_t0: int = Time.get_ticks_msec()
			_flush_stage1_batches(
				resident_inserts, contract_inserts, org_member_inserts, edge_inserts,
				slot_updates, tied_household_inserts, resident_updates
			)
			var db_time: int = Time.get_ticks_msec() - db_t0

			if hh_idx % 1000 == 0:
				SystemLogger.log_info("  [Pass 3 Benchmark] HH %5d/%d | Pop %5d | Gen: %4dms | DB Batch: %4dms" % [
					hh_idx, total_hh, current_resident_id - 1, gen_time, db_time
				])

			if on_progress.is_valid():
				var pct: float = 50.0 + ((float(hh_idx) / float(max(1, total_hh))) * 25.0)
				on_progress.call(pct, 100.0, "Hydrating Citizens: ~%d pop (%d/%d homes)" % [current_resident_id - 1, hh_idx, total_hh])
				if not is_headless:
					var main_loop = Engine.get_main_loop()
					if main_loop is SceneTree:
						await (main_loop as SceneTree).process_frame

			chunk_start_ms = Time.get_ticks_msec()

	_flush_stage1_batches(
		resident_inserts, contract_inserts, org_member_inserts, edge_inserts,
		slot_updates, tied_household_inserts, resident_updates
	)

	# --------------------------------------------------------------------------
	# STAGE 2: External Migrant Influx (Unmarried Newcomers for Remaining Tied Slots)
	# --------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(75.5, 100.0, "Assigning Work-Tied Housing & Migrant Influx...")
		if not is_headless:
			var main_loop = Engine.get_main_loop()
			if main_loop is SceneTree:
				await (main_loop as SceneTree).process_frame

	var influx_resident_inserts: Array[String] = []
	var influx_contract_inserts: Array[String] = []
	var influx_org_member_inserts: Array[String] = []
	var influx_hh_inserts: Array[String] = []
	var influx_slot_updates: Array[String] = []
	var remaining_unfilled_slots: Array[Dictionary] = []

	for slot in open_job_slots:
		var tied_type: String = str(slot.get("tied_accomodation", ""))
		if not tied_type.is_empty() and available_tied_housing.has(tied_type) and not available_tied_housing[tied_type].is_empty():
			var tied_unit: Dictionary = available_tied_housing[tied_type].pop_back()
			var r_id: int = current_resident_id
			current_resident_id += 1

			assert(slot.has("role_title"), "FATAL: Influx slot missing mandatory 'role_title'!")
			assert(slot.has("role_title_id"), "FATAL: Influx slot missing mandatory 'role_title_id'!")
			assert(slot.has("contract_class_id"), "FATAL: Influx slot missing mandatory 'contract_class_id'!")
			assert(slot.has("hours"), "FATAL: Influx slot missing mandatory 'hours'!")
			assert(slot.has("rate"), "FATAL: Influx slot missing mandatory 'rate'!")

			var role_key: String = str(slot["role_title"])
			var master_def: Dictionary = job_roles_cfg.get(role_key, {})
			var age_min: int = int(master_def.get("age_min", 20))
			var age_max: int = int(master_def.get("age_max", 30))
			var migrant_age: int = rng.randi_range(age_min, age_max)
			var is_male: bool = (rng.randf() > 0.5)
			var gender_code: String = "MALE" if is_male else "FEMALE"

			var gender_id: int = male_gender_id if is_male else female_gender_id
			var cult: Dictionary = PremisesWorkplaceBuilder.roll_household_culture(cultural, rng, "suburban_low_density")
			var first_name: String = HOUSEHOLD_COMPOSER.pick_first_name(lexicon, is_male, str(cult["surnames_pool"]), str(cult["religion"]), rng)
			var eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", cult["ethnicity"])
			var rel_id: int = DB_MANAGER.get_label_id("RELIGION", cult["religion"])
			var surname_pool: Array = lexicon.get(cult["surnames_pool"], lexicon.get("surnames", ["Smith", "Jones"]))
			var migrant_surname: String = str(surname_pool[rng.randi() % surname_pool.size()]).replace("'", "''")

			var days_old: int = int(round(float(migrant_age) * 365.25)) + rng.randi_range(0, 364)
			var dob_day: int = sim_start_day - days_old

			var edu_req: String = str(slot.get("min_education_code", "O_LEVELS_CSE"))
			var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", edu_req)
			var edu_nudges: Dictionary = PERSONALITY_HYDRATOR.get_education_nudges(demographics, edu_req)
			var ocean_traits: Dictionary = PERSONALITY_HYDRATOR.roll_independent_adult_traits(ocean_rules, {}, edu_nudges, rng)

			var tied_h_id: int = next_household_id
			next_household_id += 1

			var tied_est_id: int = int(tied_unit["establishment_id"])
			var tied_res_type_id: int = int(tied_unit["residence_type_id"])
			var tied_wealth_id: int = int(tied_unit["wealth_bracket_id"])
			var influx_est_id: int = int(slot["estab_id"])
			var home_pos: Vector2 = estab_positions.get(tied_est_id, estab_positions.get(influx_est_id, Vector2.ZERO))

			var church_id: int = ANCHOR_ALLOCATOR.resolve_individual_church_id(
				"HEAD", str(cult["religion"]), home_pos, -1, -1,
				church_estabs, estab_positions, ocean_rules, rng, church_spatial_index
			)

			var res_record: Dictionary = {
				"resident_id": r_id,
				"household_id": tied_h_id,
				"household_role": "HEAD",
				"birth_surname": migrant_surname,
				"ethnicity_id": eth_id,
				"gender_code": gender_code,
				"age_years": migrant_age,
				"dob": dob_day,
				"home_pos": home_pos,
				"church_id": church_id,
				"local_pub_id": -1,
				"employer_establishment_id": influx_est_id,
				"role_code": role_key,
				"ocean_traits": ocean_traits
			}

			var local_pub_id: int = ANCHOR_ALLOCATOR.resolve_individual_pub_id(
				res_record, pub_estabs, estab_positions, estab_capacities,
				workplace_cohort_pubs, kin_graph, residents_by_id,
				job_roles_cfg, ocean_rules, rng, pub_spatial_index
			)
			res_record["local_pub_id"] = local_pub_id
			residents_by_id[r_id] = res_record

			var church_sql_str: String = "NULL" if church_id <= 0 else str(church_id)
			var pub_sql_str: String = "NULL" if local_pub_id <= 0 else str(local_pub_id)

			influx_hh_inserts.append("""
				INSERT INTO households (
					household_id, establishment_id, head_resident_id, residence_type_id,
					wealth_bracket_id, ethnicity_id, religion_id,
					valid_from, valid_to, change_reason_id
				) VALUES (%d, %d, %d, %d, %d, %d, %d, %d, NULL, %d);
			""" % [
				tied_h_id, tied_est_id, r_id, tied_res_type_id,
				tied_wealth_id, eth_id, rel_id, sim_start_day, reason_world_gen_id
			])

			influx_resident_inserts.append("""
				INSERT INTO residents (
					resident_id, household_id, first_name, birth_surname, current_surname,
					dob, dod, death_reason_id, gender_id, education_level_id,
					ethnicity_id, religion_id, church_id, local_pub_id,
					openness, conscientiousness, extraversion, agreeableness, neuroticism,
					is_active_agent, valid_from, valid_to, change_reason_id
				) VALUES (
					%d, %d, '%s', '%s', '%s', %d, NULL, NULL, %d, %d, %d, %d, %s, %s,
					%.3f, %.3f, %.3f, %.3f, %.3f,
					0, %d, NULL, %d
				);
			""" % [
				r_id, tied_h_id, first_name, migrant_surname, migrant_surname,
				dob_day, gender_id, edu_id, eth_id, rel_id,
				church_sql_str, pub_sql_str,
				float(ocean_traits["openness"]), float(ocean_traits["conscientiousness"]),
				float(ocean_traits["extraversion"]), float(ocean_traits["agreeableness"]),
				float(ocean_traits["neuroticism"]),
				sim_start_day, reason_world_gen_id
			])

			var class_id: int = int(slot["contract_class_id"])
			var role_id: int = int(slot["role_title_id"])
			var slot_sched_id: int = int(slot.get("schedule_window_id", default_daytime_id))

			influx_contract_inserts.append("""
				INSERT INTO livelihood_contracts (
					resident_id, employer_org_id, employer_establishment_id, contract_class_id, role_title_id,
					contract_type_id, schedule_window_id, weekly_hours, compensation_rate, 
					valid_from, valid_to, change_reason_id
				) VALUES (
					%d, (SELECT owner_org_id FROM establishments WHERE establishment_id = %d), %d, %d, %d, %d, %d, %.1f, %.2f, %d, NULL, %d
				);
			""" % [
				r_id, influx_est_id, influx_est_id, class_id, role_id, contract_std_id, slot_sched_id,
				float(slot["hours"]), float(slot["rate"]), sim_start_day, reason_world_gen_id
			])

			var slot_tier: String = str(slot.get("social_tier", "STAFF"))
			var slot_clearance: float = float(slot.get("intel_clearance", 0.3))
			if slot_tier == "MANAGEMENT" or slot_clearance >= 0.85:
				var auth_mask: int = 3 if slot_clearance >= 1.0 else 1
				influx_org_member_inserts.append("""
					INSERT OR IGNORE INTO organization_members (
						org_id, resident_id, role_code, authority_mask, valid_from, valid_to, change_reason_id
					)
					SELECT owner_org_id, %d, '%s', %d, %d, NULL, %d
					FROM establishments
					WHERE establishment_id = %d AND owner_org_id IS NOT NULL AND owner_org_id != '';
				""" % [r_id, role_key, auth_mask, sim_start_day, reason_world_gen_id, influx_est_id])

			if slot.has("slot_id"):
				influx_slot_updates.append("UPDATE workplace_job_slots SET is_filled = 1, active_resident_id = %d WHERE slot_id = %d;" % [
					r_id, int(slot["slot_id"])
				])
			influx_slot_updates.append("UPDATE establishments SET is_vacant = 0 WHERE establishment_id = %d;" % tied_est_id)

			tied_occupants.append({
				"resident_id": r_id,
				"establishment_id": tied_est_id,
				"workplace_id": influx_est_id,
				"residence_type_id": tied_res_type_id,
				"age": migrant_age
			})
			external_tied_influx_count += 1
		else:
			remaining_unfilled_slots.append(slot)

	open_job_slots.clear()
	open_job_slots.append_array(remaining_unfilled_slots)

	# Release Pass 3 spatial indexes once labor & venue allocation is finished
	job_slot_index.clear()
	church_spatial_index.clear()
	pub_spatial_index.clear()
	school_spatial_indexes.clear()

	if not influx_hh_inserts.is_empty():
		DB_MANAGER.execute_batch(influx_hh_inserts)
		DB_MANAGER.execute_batch(influx_resident_inserts)
		DB_MANAGER.execute_batch(influx_contract_inserts)
		if not influx_org_member_inserts.is_empty():
			DB_MANAGER.execute_batch(influx_org_member_inserts)
		DB_MANAGER.execute_batch(influx_slot_updates)

	# Ensure every seeded organization has at least senior contracted representatives in organization_members
	_backfill_seeded_org_leadership(sim_start_day, reason_world_gen_id)

	# --------------------------------------------------------------------------
	# STAGE 3: Cross-Household Extended Kinship Tree Weaving (76% -> 85%)
	# --------------------------------------------------------------------------
	# Prune fields not needed by FamilyTreeWeaver to keep Stage 3 working memory flat
	for res_key in residents_by_id.keys():
		var r_entry: Dictionary = residents_by_id[res_key]
		r_entry.erase("ocean_traits")
		r_entry.erase("local_pub_id")
		r_entry.erase("employer_establishment_id")
		r_entry.erase("role_code")
	var extended_kin_edges: Array[String] = []
	var extended_kin_count: int = await FAMILY_WEAVER.weave_extended_family_trees(
		extended_kin_edges, residents_by_id, kinship_rules,
		reason_world_gen_id, kin_graph, rng, on_progress
	)

	# Release heavy resident & kinship working dictionaries before Pass 4
	residents_by_id.clear()
	kin_graph.clear()
	workplace_cohort_pubs.clear()

	# --------------------------------------------------------------------------
	# STAGE 4: Intake-Cohort Peer Relationship Weaving (Tied Accommodation)
	# --------------------------------------------------------------------------
	var cohort_groups: Dictionary = {}
	for occ in tied_occupants:
		var key := "%d_%d_%d" % [occ["workplace_id"], occ["residence_type_id"], occ["age"]]
		if not cohort_groups.has(key):
			cohort_groups[key] = []
		cohort_groups[key].append(occ["resident_id"])

	var cohort_edge_inserts: Array[String] = []
	for group in cohort_groups.values():
		if group.size() > 1:
			for i in range(group.size()):
				for j in range(i + 1, group.size()):
					var a: int = group[i]
					var b: int = group[j]
					cohort_edge_inserts.append("""
						INSERT OR IGNORE INTO social_relationships (
							from_resident_id, to_resident_id, relationship_type_id,
							context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, %d, NULL, 0.75, %d, NULL, %d);
					""" % [a, b, rel_civic_peer_id, sim_start_day, reason_world_gen_id])
					cohort_edge_inserts.append("""
						INSERT OR IGNORE INTO social_relationships (
							from_resident_id, to_resident_id, relationship_type_id,
							context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, %d, NULL, 0.75, %d, NULL, %d);
					""" % [b, a, rel_civic_peer_id, sim_start_day, reason_world_gen_id])
					if cohort_edge_inserts.size() >= 1000:
						DB_MANAGER.execute_batch(cohort_edge_inserts)
						cohort_edge_inserts.clear()

	if not cohort_edge_inserts.is_empty():
		DB_MANAGER.execute_batch(cohort_edge_inserts)

	# --------------------------------------------------------------------------
	# STAGE 5: Layer A Civic & Employer Recurring Schedule Bricks (calendar_events)
	# --------------------------------------------------------------------------
	_seed_layer_a_calendar_schedules(civic_cfg, sim_start_day)

	for d_id in districts.keys():
		districts[d_id]["population"] = district_residents_map.get(d_id, []).size()

	if on_progress.is_valid():
		on_progress.call(85.0, 100.0, "Pass 3 Complete: %d Citizens Hydrated" % (current_resident_id - 1))

	var total_time_ms: int = Time.get_ticks_msec() - pass3_start_ms
	SystemLogger.log_info("  ✓ Pass 3 Completed in %dms | Created %d citizens (%d local relocated, %d external influx, %d extended kin edges)." % [
		total_time_ms, current_resident_id - 1, local_tied_relocated_count, external_tied_influx_count, extended_kin_count
	])
	GENERATION_AUDITOR.log_tied_housing_audit(available_tied_housing, local_tied_relocated_count, external_tied_influx_count)
	GENERATION_AUDITOR.audit_generated_jobs_by_education()

## Ensures seeded organizations have senior contracted staff registered in organization_members
static func _backfill_seeded_org_leadership(sim_start_day: int, reason_id: int) -> void:
	DB_MANAGER.execute_batch(["""
		INSERT OR IGNORE INTO organization_members (
			org_id, resident_id, role_code, authority_mask, valid_from, valid_to, change_reason_id
		)
		SELECT c.employer_org_id, c.resident_id, l_role.code, 2, %d, NULL, %d
		FROM livelihood_contracts c
		JOIN system_labels l_role ON c.role_title_id = l_role.label_id
		WHERE c.employer_org_id IS NOT NULL
		  AND c.employer_org_id != ''
		  AND c.valid_to IS NULL
		  AND c.compensation_rate >= 4.50
		GROUP BY c.employer_org_id, c.resident_id;
	""" % [sim_start_day, reason_id]])

## Seeds Layer A recurring civic, benefit, holiday, and employer payday rules into calendar_events
static func _seed_layer_a_calendar_schedules(civic_cfg: Dictionary, sim_start_day: int) -> void:
	var schedules: Dictionary = civic_cfg.get("civic_schedules", {})
	var authority_org: String = str(schedules.get("authority_org_id", "ORG:CIVIC"))
	var events_sql: Array[String] = []

	# 1. 5-Cohort Balanced Unemployment Sign-On (Mon-Fri Fortnightly) & Cascaded Giro Disbursement
	var sign_on_cfg: Dictionary = schedules.get("unemployment_sign_on", {})
	var cohort_weekdays: Array = sign_on_cfg.get("cohort_weekdays", [1, 2, 3, 4, 5])
	var sign_on_rec: int = int(sign_on_cfg.get("recurrence_days", 14))
	var giro_offset_wd: int = int(sign_on_cfg.get("giro_settlement_working_days", 3))
	var sign_on_cat: String = str(sign_on_cfg.get("sign_on_location_category", "JOBCENTRE"))
	var giro_cat: String = str(sign_on_cfg.get("giro_encash_location_category", "POST_OFFICE"))

	for idx in range(cohort_weekdays.size()):
		var cohort_num: int = idx + 1
		var target_dow: int = int(cohort_weekdays[idx])
		var first_sign_day: int = _next_day_for_weekday(sim_start_day, target_dow)
		var first_giro_day: int = CALENDAR_HELPER.add_working_days(first_sign_day, giro_offset_wd, "POSTAL")

		var sign_impacts := JSON.stringify([ {"cohort": "CLAIMANT_COHORT_%d" % cohort_num, "action": "SIGN_ON"}])
		events_sql.append("""
			INSERT INTO calendar_events (
				event_type, title_token, organizer_scope, organizer_id,
				location_scope, location_id, start_day, end_day, recurrence_days,
				visibility_scope, impacts_json, status, created_day
			) VALUES (
				'SIGN_ON_DAY', 'UI_CAL_SIGN_ON_COHORT_%d', 'ORG', '%s',
				'CATEGORY', '%s', %d, %d, %d,
				'PUBLIC', '%s', 'SCHEDULED', %d
			);
		""" % [cohort_num, authority_org, sign_on_cat, first_sign_day, first_sign_day, sign_on_rec, sign_impacts, sim_start_day])

		var giro_impacts := JSON.stringify([ {"cohort": "CLAIMANT_COHORT_%d" % cohort_num, "action": "GIRO_ENCASH"}])
		events_sql.append("""
			INSERT INTO calendar_events (
				event_type, title_token, organizer_scope, organizer_id,
				location_scope, location_id, start_day, end_day, recurrence_days,
				visibility_scope, impacts_json, status, created_day
			) VALUES (
				'GIRO_DAY', 'UI_CAL_GIRO_COHORT_%d', 'ORG', '%s',
				'CATEGORY', '%s', %d, %d, %d,
				'PUBLIC', '%s', 'SCHEDULED', %d
			);
		""" % [cohort_num, authority_org, giro_cat, first_giro_day, first_giro_day, sign_on_rec, giro_impacts, sim_start_day])

	# 2. State Pension Weekly Payday at Post Offices
	var pension_cfg: Dictionary = schedules.get("state_pension", {})
	var pension_dow: int = int(pension_cfg.get("weekday", 1))
	var pension_rec: int = int(pension_cfg.get("recurrence_days", 7))
	var pension_cat: String = str(pension_cfg.get("encash_location_category", "POST_OFFICE"))
	var first_pension_day: int = _next_day_for_weekday(sim_start_day, pension_dow)
	var pension_impacts := JSON.stringify([ {"cohort": "PENSIONERS", "action": "STATE_PENSION_DISBURSEMENT"}])
	events_sql.append("""
		INSERT INTO calendar_events (
			event_type, title_token, organizer_scope, organizer_id,
			location_scope, location_id, start_day, end_day, recurrence_days,
			visibility_scope, impacts_json, status, created_day
		) VALUES (
			'PENSION_DAY', 'UI_CAL_STATE_PENSION_DAY', 'ORG', '%s',
			'CATEGORY', '%s', %d, %d, %d,
			'PUBLIC', '%s', 'SCHEDULED', %d
		);
	""" % [authority_org, pension_cat, first_pension_day, first_pension_day, pension_rec, pension_impacts, sim_start_day])

	# 3. Organization-Inherited & Default Employer Paydays
	var default_paydays: Dictionary = schedules.get("employer_default_paydays", {})
	var weekly_cfg: Dictionary = default_paydays.get("WEEKLY", {"weekday": 5, "recurrence_days": 7})
	var monthly_cfg: Dictionary = default_paydays.get("MONTHLY", {"recurrence_days": 28})
	var first_weekly_pay: int = _next_day_for_weekday(sim_start_day, int(weekly_cfg.get("weekday", 5)))
	var weekly_rec: int = int(weekly_cfg.get("recurrence_days", 7))
	var monthly_rec: int = int(monthly_cfg.get("recurrence_days", 28))

	# Global fallback paydays for independent single-site employers
	events_sql.append("""
		INSERT INTO calendar_events (
			event_type, title_token, organizer_scope, organizer_id,
			location_scope, location_id, start_day, end_day, recurrence_days,
			visibility_scope, impacts_json, status, created_day
		) VALUES (
			'WEEKLY_PAYDAY', 'UI_CAL_WEEKLY_PAYDAY', 'GLOBAL', 'INDEPENDENT_EMPLOYERS',
			'GLOBAL', 'ALL', %d, %d, %d,
			'PUBLIC', '[{"pay_cadence":"WEEKLY"}]', 'SCHEDULED', %d
		);
	""" % [first_weekly_pay, first_weekly_pay, weekly_rec, sim_start_day])

	events_sql.append("""
		INSERT INTO calendar_events (
			event_type, title_token, organizer_scope, organizer_id,
			location_scope, location_id, start_day, end_day, recurrence_days,
			visibility_scope, impacts_json, status, created_day
		) VALUES (
			'MONTHLY_PAYDAY', 'UI_CAL_MONTHLY_PAYDAY', 'GLOBAL', 'INDEPENDENT_EMPLOYERS',
			'GLOBAL', 'ALL', %d, %d, %d,
			'PUBLIC', '[{"pay_cadence":"MONTHLY"}]', 'SCHEDULED', %d
		);
	""" % [sim_start_day + monthly_rec, sim_start_day + monthly_rec, monthly_rec, sim_start_day])

	# Organization-specific payday schedules inherited from civic_hierarchy institutions
	var seeded_orgs: Array = civic_cfg.get("institutions", {}).get("seeded_organizations", [])
	for org_def in seeded_orgs:
		if not (org_def is Dictionary):
			continue
		var oid: String = str(org_def.get("org_id", "")).strip_edges()
		if oid.is_empty():
			continue
		var cadence_raw: String = str(org_def.get("default_pay_cadence", "MONTHLY"))
		var is_weekly: bool = cadence_raw.begins_with("WEEKLY")
		var ev_type: String = "WEEKLY_PAYDAY" if is_weekly else "MONTHLY_PAYDAY"
		var start_d: int = first_weekly_pay if is_weekly else (sim_start_day + monthly_rec)
		var rec_d: int = weekly_rec if is_weekly else monthly_rec
		var org_impacts := JSON.stringify([ {"org_id": oid, "pay_cadence": "WEEKLY" if is_weekly else "MONTHLY"}])
		events_sql.append("""
			INSERT INTO calendar_events (
				event_type, title_token, organizer_scope, organizer_id,
				location_scope, location_id, start_day, end_day, recurrence_days,
				visibility_scope, impacts_json, status, created_day
			) VALUES (
				'%s', 'UI_CAL_%s', 'ORG', '%s',
				'ORG', '%s', %d, %d, %d,
				'PUBLIC', '%s', 'SCHEDULED', %d
			);
		""" % [ev_type, ev_type, oid, oid, start_d, start_d, rec_d, org_impacts, sim_start_day])

	# 4. Public Holidays for Current & Next Simulation Year
	var start_year: int = CALENDAR_HELPER.day_to_year(sim_start_day)
	for yr in [start_year, start_year + 1]:
		var yr_holidays: Dictionary = CALENDAR_HELPER._get_holidays_for_year(yr)
		var postal_map: Dictionary = yr_holidays.get("POSTAL", {})
		for h_day_raw in postal_map.keys():
			var h_day: int = int(h_day_raw)
			if h_day < sim_start_day:
				continue
			var h_id: String = str(postal_map[h_day_raw])
			var hol_impacts := JSON.stringify([ {"holiday_id": h_id, "uplift": "BANK_HOLIDAY"}])
			events_sql.append("""
				INSERT INTO calendar_events (
					event_type, title_token, organizer_scope, organizer_id,
					location_scope, location_id, start_day, end_day, recurrence_days,
					visibility_scope, impacts_json, status, created_day
				) VALUES (
					'PUBLIC_HOLIDAY', 'UI_HOLIDAY_%s', 'ORG', '%s',
					'GLOBAL', 'ALL', %d, %d, 0,
					'PUBLIC', '%s', 'SCHEDULED', %d
				);
			""" % [h_id, authority_org, h_day, h_day, hol_impacts, sim_start_day])

	if not events_sql.is_empty():
		DB_MANAGER.execute_batch(events_sql)
		SystemLogger.log_info("  ✓ Seeded %d Layer A recurring civic, holiday, and employer calendar schedules." % events_sql.size())

static func _next_day_for_weekday(base_day: int, target_dow: int) -> int:
	var current_dow: int = CALENDAR_HELPER.day_of_week(base_day)
	var delta: int = posmod(target_dow - current_dow, 7)
	return base_day + delta

static func _flush_stage1_batches(
	resident_inserts: Array[String],
	contract_inserts: Array[String],
	org_member_inserts: Array[String],
	edge_inserts: Array[String],
	slot_updates: Array[String],
	tied_household_inserts: Array[String],
	resident_updates: Array[String]
) -> void:
	if not resident_inserts.is_empty():
		DB_MANAGER.execute_batch(resident_inserts)
		resident_inserts.clear()
	if not contract_inserts.is_empty():
		DB_MANAGER.execute_batch(contract_inserts)
		contract_inserts.clear()
	if not org_member_inserts.is_empty():
		DB_MANAGER.execute_batch(org_member_inserts)
		org_member_inserts.clear()
	if not edge_inserts.is_empty():
		DB_MANAGER.execute_batch(edge_inserts)
		edge_inserts.clear()
	if not slot_updates.is_empty():
		DB_MANAGER.execute_batch(slot_updates)
		slot_updates.clear()
	if not tied_household_inserts.is_empty():
		DB_MANAGER.execute_batch(tied_household_inserts)
		tied_household_inserts.clear()
	if not resident_updates.is_empty():
		DB_MANAGER.execute_batch(resident_updates)
		resident_updates.clear()

static func _transition_to_dole(by_cat: Dictionary, fallback_estab_id: int, rng: RandomNumberGenerator) -> int:
	if by_cat.has("JOBCENTRE") and not by_cat["JOBCENTRE"].is_empty():
		var jc_list: Array = by_cat["JOBCENTRE"]
		return int(jc_list[rng.randi() % jc_list.size()]["id"])

	for civic_key in ["LOCAL_GOVERNMENT", "CIVIC", "TOWN_HALL", "COMMUNITY_CENTRE"]:
		if by_cat.has(civic_key) and not by_cat[civic_key].is_empty():
			var c_list: Array = by_cat[civic_key]
			return int(c_list[rng.randi() % c_list.size()]["id"])

	if by_cat.has("CIVIC") and not by_cat["CIVIC"].is_empty():
		var civ_all: Array = by_cat["CIVIC"]
		return int(civ_all[rng.randi() % civ_all.size()]["id"])

	return maxi(1, fallback_estab_id)

static func pick_anchor(
	demographics: Dictionary,
	by_cat: Dictionary,
	by_cat_and_district: Dictionary,
	requested_category: String,
	dist_id: String,
	rng: RandomNumberGenerator
) -> int:
	if requested_category == "JOBCENTRE":
		return _transition_to_dole(by_cat, 1, rng)

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

	if by_cat_and_district.has(target_cat) and by_cat_and_district[target_cat].has(dist_id):
		var local_matches: Array = by_cat_and_district[target_cat][dist_id]
		if not local_matches.is_empty():
			return int(local_matches[rng.randi() % local_matches.size()]["id"])

	if by_cat.has(target_cat) and not by_cat[target_cat].is_empty():
		var list: Array = by_cat[target_cat]
		return int(list[rng.randi() % list.size()]["id"])

	return 1