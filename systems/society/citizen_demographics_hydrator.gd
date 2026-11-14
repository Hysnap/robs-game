# res://systems/society/citizen_demographics_hydrator.gd
class_name CitizenDemographicsHydrator
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

## Pass 3: Generates realistic family structures, allocates labor, and populates tied accommodation
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

	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var male_gender_id: int = DB_MANAGER.get_label_id("GENDER", "M")
	var female_gender_id: int = DB_MANAGER.get_label_id("GENDER", "F")
	var contract_std_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", "STANDARD")
	var rel_family_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "FAMILY")
	var rel_civic_peer_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CIVIC_PEER")
	var default_daytime_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", "DAYTIME")

	var proprietor_hints: Dictionary = physical_state.get("proprietor_hints", {})

	# Spatial index for non-working establishments
	var by_cat_and_district: Dictionary = {}
	for cat in by_cat.keys():
		by_cat_and_district[cat] = {}
		for item in by_cat[cat]:
			var d_id: String = str(item.get("district_id", ""))
			if not by_cat_and_district[cat].has(d_id):
				by_cat_and_district[cat][d_id] = []
			by_cat_and_district[cat][d_id].append(item)

	open_job_slots.shuffle()

	var resident_inserts: Array[String] = []
	var contract_inserts: Array[String] = []
	var edge_inserts: Array[String] = []
	var slot_updates: Array[String] = []
	var resident_updates: Array[String] = []
	var tied_household_inserts: Array[String] = []

	var current_resident_id: int = 1
	var total_hh: int = generated_households.size()
	var hh_idx: int = 0
	var next_household_id: int = total_hh + 1
	var is_headless: bool = (DisplayServer.get_name() == "headless")

	var pass3_start_ms: int = Time.get_ticks_msec()
	var chunk_start_ms: int = pass3_start_ms
	var _db_accum_ms: int = 0
	var _gen_accum_ms: int = 0

	# Tracking for tied housing cohort peer weaving: Array of { resident_id, estab_id, workplace_id, res_type_id, age }
	var tied_occupants: Array[Dictionary] = []
	var local_tied_relocated_count := 0
	var external_tied_influx_count := 0

	SystemLogger.log_info("  [Pass 3] Hydrating %d households with realistic family archetypes..." % total_hh)

	# --------------------------------------------------------------------------
	# STAGE 1: Standard Household Hydration & Local Tied Youth Relocation
	# --------------------------------------------------------------------------
	for hh in generated_households:
		hh_idx += 1
		var surname_list: Array = lexicon.get(hh["surnames_pool"], ["Smith"])
		var family_surname: String = str(surname_list[rng.randi() % surname_list.size()]).replace("'", "''")
		var is_high_dense: bool = str(hh["district_type"]).begins_with("high_density")
		var unemp_rate: float = float(hh.get("unemp_rate", 0.10))
		var home_estab_id: int = int(hh["establishment_id"])

		var planned_members: Array[Dictionary] = _generate_household_composition(demographics, rng)

		var has_child_under_5: bool = false
		var has_child_5_to_15: bool = false
		for m in planned_members:
			var age: int = int(m["age"])
			if age < 5:
				has_child_under_5 = true
			elif age <= 15:
				has_child_5_to_15 = true

		var household_member_ids: Array[int] = []

		for member in planned_members:
			var r_id := current_resident_id
			current_resident_id += 1
			household_member_ids.append(r_id)
			district_residents_map[hh["district_id"]].append(r_id)

			var is_male: bool = bool(member["is_male"])
			var age_years: int = int(member["age"])
			var is_head: bool = bool(member.get("is_head", false))
			var is_married: bool = bool(member.get("is_married", false))
			var role_in_home: String = str(member.get("role_in_home", "CHILD"))

			var gender_id: int = male_gender_id if is_male else female_gender_id
			var hh_religion: String = str(hh.get("religion", ""))
			var hh_surnames_pool: String = str(hh.get("surnames_pool", "surnames"))
			var first_name: String = _pick_first_name(lexicon, is_male, hh_surnames_pool, hh_religion, rng)
			var member_surname: String = family_surname

			if role_in_home == "PEER":
				var peer_surname_list: Array = lexicon.get(hh["surnames_pool"], ["Smith"])
				member_surname = str(peer_surname_list[rng.randi() % peer_surname_list.size()]).replace("'", "''")

			var days_old: int = int(round(float(age_years) * 365.25)) + rng.randi_range(0, 364)
			var dob_day: int = sim_start_day - days_old

			var edu_code: String = resolve_citizen_education(demographics, rng, age_years, is_male, is_high_dense)
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
				r_id, hh["household_id"], first_name, member_surname, member_surname,
				dob_day, gender_id, edu_id, hh["ethnicity_id"], hh["religion_id"], sim_start_day, reason_world_gen_id
			])

			# Resolve Role & Employment Profile
			var demo_profile: Dictionary = resolve_citizen_demographics(
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

			if occ_title == "HOME_MAKER":
				assigned_est_id = home_estab_id
			elif contract_class == "FORMAL_LEGAL":
				var worker_home_pos: Vector2 = SPATIAL_RESOLVER._resolve_vector2(
					districts[hh["district_id"]].get("spatial_anchor", Vector2.ZERO)
				)

				var slot: Dictionary = SPATIAL_RESOLVER.pick_commute_matched_slot(
					open_job_slots,
					worker_home_pos,
					edu_code,
					districts,
					job_definitions,
					rng
				)

				if not slot.is_empty():
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

					if slot.has("slot_id"):
						slot_updates.append("UPDATE workplace_job_slots SET is_filled = 1, active_resident_id = %d WHERE slot_id = %d;" % [
							r_id, int(slot["slot_id"])
						])
					
					# Align proprietor and their household with family-named business sign
					if proprietor_hints.has(assigned_est_id) and is_head:
						var hint: Dictionary = proprietor_hints[assigned_est_id]
						proprietor_hints.erase(assigned_est_id)
						var prop_surname: String = str(hint["surname"]).replace("'", "''")
						var prop_eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", str(hint["ethnicity"]))
						var prop_rel_id: int = DB_MANAGER.get_label_id("RELIGION", str(hint["religion"]))
						var prop_first: String = _pick_first_name(lexicon, is_male, str(hint["surnames_pool"]), str(hint["religion"]), rng)
						resident_updates.append("UPDATE residents SET birth_surname = '%s', current_surname = '%s', ethnicity_id = %d, religion_id = %d WHERE household_id = %d;" % [
							prop_surname, prop_surname, prop_eth_id, prop_rel_id, int(hh["household_id"])
						])
						resident_updates.append("UPDATE residents SET first_name = '%s' WHERE resident_id = %d;" % [
							prop_first, r_id
						])

					# Check for tied accommodation relocation (e.g. Student Nurse, Junior Doctor, Constable, Uni Student)
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
									household_id, establishment_id, residence_type_id,
									wealth_bracket_id, local_pub_id, ethnicity_id, religion_id,
									valid_from, valid_to, change_reason_id
								) VALUES (%d, %d, %d, %d, NULL, %d, %d, %d, NULL, %d);
							""" % [
								tied_h_id, tied_est_id, tied_res_type_id,
								tied_wealth_id, hh["ethnicity_id"], hh["religion_id"], sim_start_day, reason_world_gen_id
							])

							# Relocate resident's household pointer while family relationship edges remain intact
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
			else:
				assigned_est_id = pick_anchor(demographics, by_cat, by_cat_and_district, anchor_cat, hh["district_id"], rng)

			if assigned_est_id <= 0:
				assigned_est_id = _transition_to_dole(by_cat, home_estab_id, rng)

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
				r_id, assigned_est_id, assigned_est_id, class_id, role_id, contract_std_id, default_daytime_id,
				weekly_hours, compensation_rate, sim_start_day, reason_world_gen_id
			])

		# Weave domestic FAMILY relationships across co-living household members
		if household_member_ids.size() > 1:
			for a in household_member_ids:
				for b in household_member_ids:
					if a != b:
						edge_inserts.append("""
							INSERT INTO social_relationships (
								from_resident_id, to_resident_id, relationship_type_id,
								context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
							) VALUES (%d, %d, %d, NULL, 0.90, %d, NULL, %d);
						""" % [a, b, rel_family_id, sim_start_day, reason_world_gen_id])

		# Flush batches every 500 households
		if hh_idx % 500 == 0:
			var gen_time: int = Time.get_ticks_msec() - chunk_start_ms
			_gen_accum_ms += gen_time

			var db_t0: int = Time.get_ticks_msec()
			DB_MANAGER.execute_batch(resident_inserts)
			DB_MANAGER.execute_batch(contract_inserts)
			DB_MANAGER.execute_batch(edge_inserts)
			if not slot_updates.is_empty():
				DB_MANAGER.execute_batch(slot_updates)
				slot_updates.clear()
			if not tied_household_inserts.is_empty():
				DB_MANAGER.execute_batch(tied_household_inserts)
				tied_household_inserts.clear()
			if not resident_updates.is_empty():
				DB_MANAGER.execute_batch(resident_updates)
				resident_updates.clear()

			var db_time: int = Time.get_ticks_msec() - db_t0
			_db_accum_ms += db_time

			SystemLogger.log_info("  [Pass 3 Benchmark] HH %5d/%d | Pop %5d | Gen: %4dms | DB Batch: %4dms" % [
				hh_idx, total_hh, current_resident_id - 1, gen_time, db_time
			])

			resident_inserts.clear()
			contract_inserts.clear()
			edge_inserts.clear()

			if on_progress.is_valid():
				var pct: float = 50.0 + ((float(hh_idx) / float(max(1, total_hh))) * 35.0)
				on_progress.call(pct, 100.0, "Hydrating Citizens: ~%d pop (%d/%d homes)" % [current_resident_id - 1, hh_idx, total_hh])
				if not is_headless:
					var main_loop = Engine.get_main_loop()
					if main_loop is SceneTree:
						await (main_loop as SceneTree).process_frame

			chunk_start_ms = Time.get_ticks_msec()

	# Flush remaining Stage 1 records
	if not resident_inserts.is_empty():
		DB_MANAGER.execute_batch(resident_inserts)
		resident_inserts.clear()
	if not contract_inserts.is_empty():
		DB_MANAGER.execute_batch(contract_inserts)
		contract_inserts.clear()
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

	# --------------------------------------------------------------------------
	# STAGE 2: External Migrant Influx (Unmarried Newcomers for Remaining Tied Slots)
	# --------------------------------------------------------------------------
	var influx_resident_inserts: Array[String] = []
	var influx_contract_inserts: Array[String] = []
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
			var master_def: Dictionary = job_definitions.get(role_key, {})
			var age_min: int = int(master_def.get("age_min", 20))
			var age_max: int = int(master_def.get("age_max", 30))
			var migrant_age: int = rng.randi_range(age_min, age_max)
			var is_male: bool = (rng.randf() > 0.5)

			var gender_id: int = male_gender_id if is_male else female_gender_id
			# Roll authentic culture from cultural configuration rather than hardcoding
			var cult: Dictionary = PremisesWorkplaceBuilder.roll_household_culture(cultural, rng, "suburban_low_density")
			var first_name: String = _pick_first_name(lexicon, is_male, str(cult["surnames_pool"]), str(cult["religion"]), rng)
			var eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", cult["ethnicity"])
			var rel_id: int = DB_MANAGER.get_label_id("RELIGION", cult["religion"])
			var surname_pool: Array = lexicon.get(cult["surnames_pool"], lexicon.get("surnames", ["Smith", "Jones"]))
			var migrant_surname: String = str(surname_pool[rng.randi() % surname_pool.size()]).replace("'", "''")

			var days_old: int = int(round(float(migrant_age) * 365.25)) + rng.randi_range(0, 364)
			var dob_day: int = sim_start_day - days_old

			var edu_req: String = str(slot.get("edu_req", "O_LEVELS_CSE"))
			var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", edu_req)

			var tied_h_id: int = next_household_id
			next_household_id += 1

			var tied_est_id: int = int(tied_unit["establishment_id"])
			var tied_res_type_id: int = int(tied_unit["residence_type_id"])
			var tied_wealth_id: int = int(tied_unit["wealth_bracket_id"])

			influx_hh_inserts.append("""
				INSERT INTO households (
					household_id, establishment_id, residence_type_id,
					wealth_bracket_id, local_pub_id, ethnicity_id, religion_id,
					valid_from, valid_to, change_reason_id
				) VALUES (%d, %d, %d, %d, NULL, %d, %d, %d, NULL, %d);
			""" % [
				tied_h_id, tied_est_id, tied_res_type_id,
				tied_wealth_id, eth_id, rel_id, sim_start_day, reason_world_gen_id
			])

			influx_resident_inserts.append("""
				INSERT INTO residents (
					resident_id, household_id, first_name, birth_surname, current_surname,
					dob, dod, death_reason_id, gender_id, education_level_id,
					ethnicity_id, religion_id, is_active_agent, valid_from, valid_to, change_reason_id
				) VALUES (
					%d, %d, '%s', '%s', '%s', %d, NULL, NULL, %d, %d, %d, %d, 0, %d, NULL, %d
				);
			""" % [
				r_id, tied_h_id, first_name, migrant_surname, migrant_surname,
				dob_day, gender_id, edu_id, eth_id, rel_id, sim_start_day, reason_world_gen_id
			])

			var class_id: int = int(slot["contract_class_id"])
			var role_id: int = int(slot["role_title_id"])

			var influx_est_id: int = int(slot["estab_id"])
			influx_contract_inserts.append("""
				INSERT INTO livelihood_contracts (
					resident_id, employer_org_id, employer_establishment_id, contract_class_id, role_title_id,
					contract_type_id, schedule_window_id, weekly_hours, compensation_rate, 
					valid_from, valid_to, change_reason_id
				) VALUES (
					%d, (SELECT owner_org_id FROM establishments WHERE establishment_id = %d), %d, %d, %d, %d, %d, %.1f, %.2f, %d, NULL, %d
				);
			""" % [
				r_id, influx_est_id, influx_est_id, class_id, role_id, contract_std_id, default_daytime_id,
				float(slot["hours"]), float(slot["rate"]), sim_start_day, reason_world_gen_id
			])

			if slot.has("slot_id"):
				influx_slot_updates.append("UPDATE workplace_job_slots SET is_filled = 1, active_resident_id = %d WHERE slot_id = %d;" % [
					r_id, int(slot["slot_id"])
				])
			influx_slot_updates.append("UPDATE establishments SET is_vacant = 0 WHERE establishment_id = %d;" % tied_est_id)

			tied_occupants.append({
				"resident_id": r_id,
				"establishment_id": tied_est_id,
				"workplace_id": int(slot["estab_id"]),
				"residence_type_id": tied_res_type_id,
				"age": migrant_age
			})
			external_tied_influx_count += 1
		else:
			remaining_unfilled_slots.append(slot)

	# Overwrite open_job_slots with remaining unfilled slots
	open_job_slots.clear()
	open_job_slots.append_array(remaining_unfilled_slots)

	if not influx_hh_inserts.is_empty():
		DB_MANAGER.execute_batch(influx_hh_inserts)
		DB_MANAGER.execute_batch(influx_resident_inserts)
		DB_MANAGER.execute_batch(influx_contract_inserts)
		DB_MANAGER.execute_batch(influx_slot_updates)

	# --------------------------------------------------------------------------
	# STAGE 3: Intake-Cohort Peer Relationship Weaving
	# (Connects residents of the same age living in tied accommodation)
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

	if not cohort_edge_inserts.is_empty():
		DB_MANAGER.execute_batch(cohort_edge_inserts)

	# Update district population aggregates
	for d_id in districts.keys():
		districts[d_id]["population"] = district_residents_map.get(d_id, []).size()

	var total_time_ms: int = Time.get_ticks_msec() - pass3_start_ms
	SystemLogger.log_info("  ✓ Pass 3 Completed in %dms | Created %d citizens (%d local relocated, %d external influx)." % [
		total_time_ms, current_resident_id - 1, local_tied_relocated_count, external_tied_influx_count
	])
	_log_tied_housing_audit(available_tied_housing, local_tied_relocated_count, external_tied_influx_count)
	audit_generated_jobs_by_education()

## Resolves an ethno-religiously matched first name from lexicon pools with deterministic fallback
static func _pick_first_name(
	lexicon: Dictionary,
	is_male: bool,
	surnames_pool: String,
	religion: String,
	rng: RandomNumberGenerator
) -> String:
	var gender_prefix: String = "first_names_male" if is_male else "first_names_female"
	var ethnic_suffix: String = ""
	if surnames_pool.begins_with("surnames_"):
		ethnic_suffix = "_" + surnames_pool.trim_prefix("surnames_")

	var rel_suffix: String = ""
	if not religion.is_empty():
		rel_suffix = "_" + religion.to_lower()

	# 1. Exact ethno-religious pool (e.g., first_names_male_south_asian_sikh)
	if not ethnic_suffix.is_empty() and not rel_suffix.is_empty():
		var full_key: String = gender_prefix + ethnic_suffix + rel_suffix
		if lexicon.has(full_key) and lexicon[full_key] is Array and not lexicon[full_key].is_empty():
			var pool: Array = lexicon[full_key]
			return str(pool[rng.randi() % pool.size()]).strip_edges().replace("'", "''")

	# 2. Ethnic pool (e.g., first_names_male_irish)
	if not ethnic_suffix.is_empty():
		var eth_key: String = gender_prefix + ethnic_suffix
		if lexicon.has(eth_key) and lexicon[eth_key] is Array and not lexicon[eth_key].is_empty():
			var pool: Array = lexicon[eth_key]
			return str(pool[rng.randi() % pool.size()]).strip_edges().replace("'", "''")

	# 3. Base regional pool (first_names_male / first_names_female)
	var base_pool: Array = lexicon.get(gender_prefix, ["Terry" if is_male else "Sharon"])
	return str(base_pool[rng.randi() % base_pool.size()]).strip_edges().replace("'", "''")

## Logs an audit breakdown of tied accommodation occupancy
static func _log_tied_housing_audit(available_tied: Dictionary, local_count: int, external_count: int) -> void:
	SystemLogger.log_info("\n==========================================================================")
	SystemLogger.log_info("                  TIED ACCOMMODATION OCCUPANCY AUDIT                      ")
	SystemLogger.log_info("==========================================================================")
	SystemLogger.log_info("  Local Youth Relocated (Preserved Family Roots): %d" % local_count)
	SystemLogger.log_info("  External Migrants Influxed (Solo Intake Cohorts): %d" % external_count)
	SystemLogger.log_info("  Total Occupied Work-Tied Homes:                %d" % (local_count + external_count))
	SystemLogger.log_info("  ------------------------------------------------------------------------")
	SystemLogger.log_info("  Remaining Vacant Tied Units by Category:")
	for res_type in available_tied.keys():
		SystemLogger.log_info("    • %-24s: %d units vacant" % [res_type, available_tied[res_type].size()])
	SystemLogger.log_info("==========================================================================\n")

## -----------------------------------------------------------------------------
## GENERATIVE HOUSEHOLD COMPOSITION ENGINE
## -----------------------------------------------------------------------------

static func _generate_household_composition(demographics: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var legal_cfg: Dictionary = demographics.get("legal_and_pension_thresholds", {})
	var min_head_age: int = int(legal_cfg.get("majority_head_of_household_age", 18))

	var head_sample: Dictionary = _sample_from_population_pyramid(demographics, rng, min_head_age)
	var head_age: int = int(head_sample["age"])
	var head_is_male: bool = bool(head_sample["is_male"])

	var typology_model: Dictionary = demographics.get("household_typology_model", {})
	var archetype_str: String = _sample_typology(typology_model, head_age, rng)

	var is_married: bool = false
	if archetype_str in ["COUPLE_WITHOUT_DEP", "COUPLE_WITH_DEP"]:
		is_married = true
	else:
		is_married = _sample_marital_status(typology_model, head_age, rng) == "MARRIED"

	members.append({
		"role_in_home": "HEAD",
		"age": head_age,
		"is_male": head_is_male,
		"is_head": true,
		"is_married": is_married
	})

	match archetype_str:
		"SINGLE_PERSON":
			return members

		"FLATSHARE_SHARED":
			var shared_rules: Dictionary = typology_model.get("shared_household_rules", {})
			var min_peers: int = int(shared_rules.get("min_peers", 1))
			var max_peers: int = int(shared_rules.get("max_peers", 3))
			var max_diff: int = int(shared_rules.get("max_age_difference", 4))
			var peer_count: int = rng.randi_range(min_peers, max_peers)

			for _i in range(peer_count):
				var p_age: int = maxi(min_head_age, head_age + rng.randi_range(-max_diff, max_diff))
				var p_male: bool = rng.randf() > 0.5
				members.append({
					"role_in_home": "PEER",
					"age": p_age,
					"is_male": p_male,
					"is_head": false,
					"is_married": false
				})

		"COUPLE_WITHOUT_DEP":
			var sp_age: int = _calculate_spouse_age(typology_model, head_age, head_is_male, rng)
			members.append({
				"role_in_home": "SPOUSE",
				"age": sp_age,
				"is_male": not head_is_male,
				"is_head": false,
				"is_married": true
			})

		"COUPLE_WITH_DEP":
			var sp_age: int = _calculate_spouse_age(typology_model, head_age, head_is_male, rng)
			var spouse_is_male: bool = not head_is_male
			members.append({
				"role_in_home": "SPOUSE",
				"age": sp_age,
				"is_male": spouse_is_male,
				"is_head": false,
				"is_married": true
			})

			var mother_age: int = head_age if not head_is_male else sp_age
			var children: Array[Dictionary] = _generate_children(demographics, mother_age, rng)
			members.append_array(children)

		"LONE_PARENT":
			var lone_parent_is_female: bool = rng.randf() < float(typology_model.get("lone_parent_gender_split", {}).get("female_parent_prob", 0.88))
			members[0]["is_male"] = not lone_parent_is_female
			members[0]["is_married"] = false

			var p_mother_age: int = head_age if lone_parent_is_female else maxi(18, head_age - 2)
			var lone_children: Array[Dictionary] = _generate_children(demographics, p_mother_age, rng)
			members.append_array(lone_children)

	return members

static func _sample_from_population_pyramid(demographics: Dictionary, rng: RandomNumberGenerator, min_allowed_age: int = 0) -> Dictionary:
	var pyramid: Array = demographics.get("population_pyramid", [])
	var eligible: Array = []
	var total_weight: float = 0.0

	for bracket in pyramid:
		var max_a: int = int(bracket["max_age"])
		if max_a < min_allowed_age:
			continue
		eligible.append(bracket)
		total_weight += float(bracket.get("male_pct", 0.0)) + float(bracket.get("female_pct", 0.0))

	if eligible.is_empty():
		return { "age": maxi(min_allowed_age, 25), "is_male": true }

	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	var chosen: Dictionary = eligible[0]

	for b in eligible:
		var b_weight: float = float(b.get("male_pct", 0.0)) + float(b.get("female_pct", 0.0))
		cumulative += b_weight
		if roll <= cumulative:
			chosen = b
			break

	var b_min: int = maxi(int(chosen["min_age"]), min_allowed_age)
	var b_max: int = int(chosen["max_age"])
	var resolved_age: int = rng.randi_range(b_min, b_max)

	var male_pct: float = float(chosen.get("male_pct", 50.0))
	var female_pct: float = float(chosen.get("female_pct", 50.0))
	var is_male: bool = rng.randf() < (male_pct / maxf(0.001, male_pct + female_pct))

	return { "age": resolved_age, "is_male": is_male }

static func _sample_typology(typology_model: Dictionary, head_age: int, rng: RandomNumberGenerator) -> String:
	var table: Array = typology_model.get("types_by_head_age", [])
	var chosen_row: Dictionary = {}

	for row in table:
		if head_age >= int(row["age_min"]) and head_age <= int(row["age_max"]):
			chosen_row = row
			break

	if chosen_row.is_empty() and not table.is_empty():
		chosen_row = table[-1]

	var weights: Dictionary = chosen_row.get("weights", { "SINGLE_PERSON": 1.0 })
	var total_w: float = 0.0
	for k in weights.keys():
		total_w += float(weights[k])

	var roll: float = rng.randf() * total_w
	var cum: float = 0.0
	for k in weights.keys():
		cum += float(weights[k])
		if roll <= cum:
			return str(k)

	return "SINGLE_PERSON"

static func _sample_marital_status(typology_model: Dictionary, head_age: int, rng: RandomNumberGenerator) -> String:
	var rows: Array = typology_model.get("marital_status_by_head_age", [])
	for row in rows:
		if head_age >= int(row["age_min"]) and head_age <= int(row["age_max"]):
			var r: float = rng.randf()
			var m_p: float = float(row.get("married", 0.7))
			var nm_p: float = float(row.get("never_married", 0.2))
			var d_p: float = float(row.get("divorced", 0.1))
			if r < m_p:
				return "MARRIED"
			elif r < m_p + nm_p:
				return "NEVER_MARRIED"
			elif r < m_p + nm_p + d_p:
				return "DIVORCED"
			else:
				return "WIDOWED"
	return "NEVER_MARRIED"

static func _calculate_spouse_age(typology_model: Dictionary, head_age: int, head_is_male: bool, rng: RandomNumberGenerator) -> int:
	var sp_cfg: Dictionary = typology_model.get("spousal_age_difference", {})
	var mean_diff: float = float(sp_cfg.get("husband_older_mean", 2.2))
	var std_dev: float = float(sp_cfg.get("husband_older_std_dev", 3.0))

	var u1: float = maxf(0.0001, rng.randf())
	var u2: float = rng.randf()
	var z: float = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
	var sampled_diff: float = mean_diff + (z * std_dev)

	var sp_age: int = head_age
	if head_is_male:
		sp_age = int(round(float(head_age) - sampled_diff))
	else:
		sp_age = int(round(float(head_age) + sampled_diff))

	return clampi(sp_age, 16, 95)

static func _generate_children(demographics: Dictionary, mother_age: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var children: Array[Dictionary] = []
	var fert_model: Dictionary = demographics.get("fertility_and_family_model", {})
	var parity_cfg: Dictionary = fert_model.get("parity_distribution", {})
	var base_weights: Dictionary = parity_cfg.get("base_weights", { "1": 0.42, "2": 0.36, "3": 0.14, "4": 0.05 })
	var continuation_p: float = float(parity_cfg.get("continuation_probability_beyond_4", 0.35))
	var abs_max: int = int(parity_cfg.get("absolute_max_children", 10))

	var target_children: int = 1
	var total_w: float = 0.0
	for k in base_weights.keys():
		total_w += float(base_weights[k])

	var roll: float = rng.randf() * total_w
	var cum: float = 0.0
	for k in base_weights.keys():
		cum += float(base_weights[k])
		if roll <= cum:
			target_children = int(k)
			break

	if target_children == 4:
		while target_children < abs_max and rng.randf() < continuation_p:
			target_children += 1

	var maternal_rules: Dictionary = fert_model.get("maternal_age_rules", {})
	var min_m_age: int = int(maternal_rules.get("min_mother_age_at_birth", 16))
	var max_m_age: int = int(maternal_rules.get("max_mother_age_at_birth", 44))
	var first_birth_dist: Array = maternal_rules.get("maternal_age_first_birth_distribution", [])

	var fb_total_w: float = 0.0
	for row in first_birth_dist:
		fb_total_w += float(row.get("weight", 0.0))

	var fb_roll: float = rng.randf() * fb_total_w
	var fb_cum: float = 0.0
	var first_birth_age: int = 24

	for row in first_birth_dist:
		fb_cum += float(row.get("weight", 0.0))
		if fb_roll <= fb_cum:
			first_birth_age = rng.randi_range(int(row["min_age"]), int(row["max_age"]))
			break

	first_birth_age = mini(first_birth_age, mother_age)
	if mother_age < min_m_age:
		return children

	var twin_p: float = float(fert_model.get("multiple_birth_rates", {}).get("twin_probability", 0.0115))
	var spacing_cfg: Dictionary = fert_model.get("birth_spacing", {})
	var min_spacing: int = int(spacing_cfg.get("min_spacing_years", 1))
	var max_spacing: int = int(spacing_cfg.get("max_spacing_years", 4))

	var current_m_age_at_birth: int = first_birth_age
	var spawned_count: int = 0

	var retention_cfg: Dictionary = fert_model.get("cohabiting_adult_offspring_retention", {})
	var stay_18_21: float = float(retention_cfg.get("age_18_to_21_stay_rate", 0.45))
	var stay_22_25: float = float(retention_cfg.get("age_22_to_25_stay_rate", 0.15))
	var stay_26_plus: float = float(retention_cfg.get("age_26_plus_stay_rate", 0.03))

	while spawned_count < target_children and current_m_age_at_birth <= max_m_age and current_m_age_at_birth <= mother_age:
		var is_twin: bool = (rng.randf() < twin_p) and (spawned_count + 1 < target_children)
		var birth_size: int = 2 if is_twin else 1
		var c_age: int = mother_age - current_m_age_at_birth

		for _b in range(birth_size):
			var retain_in_home: bool = true
			if c_age >= 26:
				retain_in_home = (rng.randf() < stay_26_plus)
			elif c_age >= 22:
				retain_in_home = (rng.randf() < stay_22_25)
			elif c_age >= 18:
				retain_in_home = (rng.randf() < stay_18_21)

			if retain_in_home:
				children.append({
					"role_in_home": "CHILD",
					"age": c_age,
					"is_male": (rng.randf() > 0.5),
					"is_head": false,
					"is_married": false
				})
			spawned_count += 1

		current_m_age_at_birth += rng.randi_range(min_spacing, max_spacing)

	return children

## -----------------------------------------------------------------------------
## DEMOGRAPHIC PROFILE, EDUCATION & CONTRACT RESOLUTION
## -----------------------------------------------------------------------------

static func resolve_citizen_demographics(
	demographics: Dictionary,
	rng: RandomNumberGenerator,
	age_years: int,
	is_male: bool,
	unemp_rate: float,
	edu_code: String,
	is_married: bool,
	has_child_under_5: bool,
	has_child_5_to_15: bool
) -> Dictionary:
	var cohorts: Array = demographics.get("cohort_profiles", [])
	var thresholds: Dictionary = demographics.get("legal_and_pension_thresholds", {})
	var pen_age: int = int(thresholds["pension_age_male"] if is_male else thresholds["pension_age_female"])

	var chosen_cohort: Dictionary = cohorts[0]
	for c in cohorts:
		var c_min: int = int(c.get("age_min", 0))
		if c.has("age_min_dynamic") and c["age_min_dynamic"] == "pension_age":
			c_min = pen_age

		var c_max: int = int(c.get("age_max", 95))
		if c.has("age_max_dynamic") and c["age_max_dynamic"] == "pension_age":
			c_max = pen_age - 1

		if age_years >= c_min and age_years <= c_max:
			chosen_cohort = c
			break

	var strategy: String = chosen_cohort.get("strategy", "FIXED")
	var profile_data: Dictionary = {}

	match strategy:
		"FIXED":
			profile_data = chosen_cohort
		"PROBABILISTIC":
			var prob: float = float(chosen_cohort.get("condition_probability", 0.5))
			profile_data = chosen_cohort["if_true"] if (rng.randf() < prob) else chosen_cohort["if_false"]
		"LABOR_MARKET":
			var participates_in_formal_labor: bool = true
			if not is_male:
				var part_mods: Dictionary = demographics.get("fertility_and_family_model", {}).get("female_labor_participation_modifiers", {})
				var base_rate: float = float(part_mods.get("base_married_rate", 0.68) if is_married else part_mods.get("base_unmarried_rate", 0.74))

				if has_child_under_5:
					base_rate *= float(part_mods.get("has_infant_under_5_multiplier", 0.44))
				elif has_child_5_to_15:
					base_rate *= float(part_mods.get("has_school_child_5_to_15_multiplier", 0.86))

				var edu_boosts: Dictionary = part_mods.get("education_boost", {})
				base_rate *= float(edu_boosts.get(edu_code, 1.0))

				if rng.randf() > base_rate:
					participates_in_formal_labor = false

			if not participates_in_formal_labor:
				profile_data = {
					"role": "HOME_MAKER",
					"anchor_category": "RESIDENTIAL_UNIT",
					"contract_class": "INFORMAL_GREY",
					"weekly_hours": 0.0,
					"compensation_rate": 0.0
				}
			elif rng.randf() < unemp_rate:
				profile_data = chosen_cohort["unemployed_branch"]
			else:
				profile_data = {
					"role": "WORKER_SEEKER",
					"anchor_category": "COMMERCIAL",
					"contract_class": "FORMAL_LEGAL",
					"weekly_hours": 37.5,
					"compensation_rate": 3.75
				}

	return {
		"age": age_years,
		"occupation": str(profile_data.get("role", "COMMERCIAL_SERVICE")),
		"anchor_category": str(profile_data.get("anchor_category", "COMMERCIAL")),
		"contract_class": str(profile_data.get("contract_class", "FORMAL_LEGAL")),
		"weekly_hours": float(profile_data.get("weekly_hours", 37.5)),
		"compensation_rate": float(profile_data.get("compensation_rate", 3.50))
	}

static func resolve_citizen_education(
	demographics: Dictionary,
	rng: RandomNumberGenerator,
	age_years: int,
	is_male: bool,
	is_high_density: bool
) -> String:
	var edu_model: Dictionary = demographics.get("education_attainment_model", {})
	var default_code: String = str(edu_model.get("default_code", "NO_FORMAL"))
	var rates: Array = edu_model.get("cohort_attainment_rates", [])

	if age_years < 16:
		return default_code

	var matched_row: Dictionary = {}
	for row in rates:
		if age_years >= int(row["age_min"]) and age_years <= int(row["age_max"]):
			matched_row = row
			break

	if matched_row.is_empty():
		return default_code

	var penalty: float = float(matched_row.get("high_density_penalty", 0.0)) if is_high_density else 0.0
	var prob_dict: Dictionary = matched_row.get("male_probabilities", {}) if is_male else matched_row.get("female_probabilities", {})

	for tier_code in ["UNIVERSITY_DEGREE", "POLYTECHNIC_DIPLOMA", "A_LEVELS", "O_LEVELS_CSE"]:
		if prob_dict.has(tier_code):
			var p: float = maxf(0.01, float(prob_dict[tier_code]) - penalty)
			if rng.randf() < p:
				return tier_code

	return default_code

## -----------------------------------------------------------------------------
## ANCHORS & CIVIC ROUTING
## -----------------------------------------------------------------------------

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

## -----------------------------------------------------------------------------
## CENSUS & LABOR AUDIT
## -----------------------------------------------------------------------------

static func audit_generated_jobs_by_education() -> void:
	SystemLogger.log_info("\n==========================================================================")
	SystemLogger.log_info("               SOCIETY LABOR & EDUCATION AUDIT REPORT                     ")
	SystemLogger.log_info("==========================================================================")

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
		SystemLogger.log_info("  [Audit] No contract records found.")
		SystemLogger.log_info("==========================================================================\n")
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
			SystemLogger.log_info("\n▶ [Education Tier: %s]" % current_edu)
			SystemLogger.log_info("  %-24s | %-16s | %-6s | %-9s | %-8s" % ["Role Title", "Class", "Count", "Avg Rate", "Avg Hrs"])
			SystemLogger.log_info("  ------------------------------------------------------------------------")

		SystemLogger.log_info("  %-24s | %-16s | %-6d | £%-8.2f | %-5.1f hrs" % [role, cls, count, rate, hours])

	var summary_query := """
		SELECT 
			edu.code AS education_level,
			COUNT(r.resident_id) AS citizen_count,
			SUM(CASE WHEN c_cls.code = 'FORMAL_LEGAL' THEN 1 ELSE 0 END) AS formal_workers,
			SUM(CASE WHEN c_cls.code = 'ENCLAVE_STUDENT' THEN 1 ELSE 0 END) AS students_pupils,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code = 'PENSIONER' THEN 1 ELSE 0 END) AS pensioners,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code = 'HOME_MAKER' THEN 1 ELSE 0 END) AS homemakers,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code NOT IN ('PENSIONER', 'HOME_MAKER') THEN 1 ELSE 0 END) AS unemployed_or_informal
		FROM residents r
		JOIN system_labels edu ON r.education_level_id = edu.label_id
		LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id
		LEFT JOIN system_labels c_cls ON c.contract_class_id = c_cls.label_id
		LEFT JOIN system_labels role ON c.role_title_id = role.label_id
		GROUP BY edu.code
		ORDER BY citizen_count DESC;
	"""
	var summary_results: Array = DB_MANAGER.query_rows(summary_query)

	SystemLogger.log_info("\n------------------------------------------------------------------------------------------------")
	SystemLogger.log_info("                                SUMMARY BY EDUCATION LEVEL                                      ")
	SystemLogger.log_info("------------------------------------------------------------------------------------------------")
	SystemLogger.log_info("  %-20s | %-8s | %-14s | %-10s | %-12s | %-16s | %-10s" % [
		"Education Level", "Pop", "Formal Workers", "Students", "Homemakers", "Unemployed/Other", "Pensioners"
	])
	SystemLogger.log_info("  ------------------------------------------------------------------------------------------------")
	for s_row in summary_results:
		SystemLogger.log_info("  %-20s | %-8d | %-14d | %-10d | %-12d | %-16d | %-10d" % [
			str(s_row["education_level"]),
			int(s_row["citizen_count"]),
			int(s_row["formal_workers"]),
			int(s_row["students_pupils"]),
			int(s_row["homemakers"]),
			int(s_row["unemployed_or_informal"]),
			int(s_row["pensioners"])
		])

	SystemLogger.log_info("================================================================================================")
	SystemLogger.log_info("  Total Contracted Citizens: %d" % total_city_jobs)
	SystemLogger.log_info("================================================================================================\n")