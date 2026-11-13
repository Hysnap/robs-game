# res://tests/test_crew_intel_and_fow.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SOCIAL_GEN = preload("res://systems/social_network_generator.gd")
const CREW_BOOT = preload("res://systems/society/crew_scout_bootstrapper.gd")
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")
const OPS_CTRL = preload("res://systems/operations_controller.gd")
const GEN_ROSTER_SCRIPT = preload("res://generated/ui/core/gen_roster_docket.gd")
const INTEL_MANAGER = preload("res://systems/multilayer_info_loop/intel_manager.gd")

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("\n==========================================================================")
	print("   HEADLESS SUITE: CREW INTELLIGENCE, KINSHIP & FOG OF WAR (ITEMS A-G)    ")
	print("==========================================================================")

	var passed: bool = true

	# 1. Seed a deterministic multi-district world state & populate SQLite society
	var world_state := _build_test_world_state()
	await SOCIAL_GEN.generate_city_society(world_state, "test_seed_crew_intel_fow", true)

	passed = passed and _test_business_naming_and_ethno_names()
	passed = passed and _test_crew_addresses_and_kinship(world_state)
	passed = passed and _test_secondary_relationship_firewall(world_state)
	passed = passed and _test_household_and_workplace_fog_of_war(world_state)
	passed = passed and _test_roster_docket_contract(world_state)

	if passed:
		print("==========================================================================")
		print("   ALL CREW INTELLIGENCE & FOG OF WAR TESTS PASSED (EXIT 0)               ")
		print("==========================================================================\n")
		quit(0)
	else:
		printerr("==========================================================================")
		printerr("   CREW INTELLIGENCE & FOG OF WAR TEST SUITE FAILED (EXIT 1)              ")
		printerr("==========================================================================\n")
		quit(1)

func _build_test_world_state() -> Dictionary:
	return {
		"metadata": {
			"calendar_year": 1980,
			"current_sim_day": 29219,
			"current_day_tick": 1
		},
		"operations": {
			"home_district_id": "block_0_0",
			"enterprise_name": "ASTON FIRM"
		},
		"player_knowledge": {
			"home_district_id": "block_0_0",
			"known_residents": [],
			"scouted_establishments": []
		},
		"knowledge_pools": {},
		"districts": {
			"block_0_0": {
				"district_id": "block_0_0",
				"display_name": "Aston Row",
				"district_type": "high_density_low_rise",
				"grid_coords": Vector2i(0, 0),
				"grid_size": Vector2i(2, 2),
				"spatial_anchor": Vector2(0, 0),
				"estimated_population": 3500.0,
				"expected_pop_min": 3000,
				"expected_pop_max": 4000,
				"unemployment_rate": 0.14,
				"avg_disposable_income": 65.0
			},
			"block_1_0": {
				"district_id": "block_1_0",
				"display_name": "High Parade",
				"district_type": "commercial",
				"grid_coords": Vector2i(2, 0),
				"grid_size": Vector2i(1, 1),
				"spatial_anchor": Vector2(500, 0),
				"estimated_population": 1200.0,
				"expected_pop_min": 900,
				"expected_pop_max": 1500,
				"unemployment_rate": 0.11,
				"avg_disposable_income": 85.0
			},
			"block_0_1": {
				"district_id": "block_0_1",
				"display_name": "Vulcan Works",
				"district_type": "industrial",
				"grid_coords": Vector2i(0, 2),
				"grid_size": Vector2i(1, 1),
				"spatial_anchor": Vector2(0, 500),
				"estimated_population": 600.0,
				"expected_pop_min": 400,
				"expected_pop_max": 800,
				"unemployment_rate": 0.12,
				"avg_disposable_income": 75.0
			},
			"block_1_1": {
				"district_id": "block_1_1",
				"display_name": "Birch Estate",
				"district_type": "high_density_high_rise",
				"grid_coords": Vector2i(2, 2),
				"grid_size": Vector2i(1, 1),
				"spatial_anchor": Vector2(500, 500),
				"estimated_population": 2500.0,
				"expected_pop_min": 2000,
				"expected_pop_max": 3000,
				"unemployment_rate": 0.16,
				"avg_disposable_income": 55.0
			}
		}
	}

## Test 1 (Item g): Era-aware business names & clean ethno-religious citizen names
func _test_business_naming_and_ethno_names() -> bool:
	var comm_rows: Array = DB_MANAGER.query_rows("""
		SELECT DISTINCT e.name, l.title AS cat_title
		FROM establishments e
		JOIN system_labels l ON e.category_id = l.label_id
		WHERE l.code != 'RESIDENTIAL_UNIT';
	""")

	if comm_rows.size() < 2:
		printerr("FAIL [Test 1]: Expected multiple distinct non-residential establishment names, got %d." % comm_rows.size())
		return false

	var bad_names: Array = DB_MANAGER.query_rows("""
		SELECT resident_id, first_name, current_surname
		FROM residents
		WHERE first_name LIKE ' %%' OR current_surname LIKE ' %%';
	""")
	if not bad_names.is_empty():
		printerr("FAIL [Test 1]: Found citizen names with leading whitespace: ", bad_names[0])
		return false

	print("PASS [Test 1]: Generated %d distinct business/civic names and clean citizen names." % comm_rows.size())
	return true

## Test 2 (Item a): Physical addresses & reciprocal FAMILY kinship edges for starting crew
func _test_crew_addresses_and_kinship(world_state: Dictionary) -> bool:
	var ok: bool = CREW_BOOT.scout_and_bind_starting_crew(world_state, "block_0_0")
	if not ok:
		printerr("FAIL [Test 2]: CrewScoutBootstrapper.scout_and_bind_starting_crew returned false.")
		return false

	var residents: Dictionary = world_state.get("residents", {})
	if residents.is_empty():
		printerr("FAIL [Test 2]: world_state['residents'] was not populated for starting crew.")
		return false

	var leader_estab_id: int = 0
	for slot_id in residents.keys():
		var op: Dictionary = residents[slot_id]
		var r_id: int = int(op.get("resident_id", 0))
		var hh_id: int = int(op.get("household_id", 0))
		var est_id: int = int(op.get("home_establishment_id", 0))
		if r_id <= 0 or hh_id <= 0 or est_id <= 0:
			printerr("FAIL [Test 2]: Operative '%s' missing physical address or resident_id: %s" % [slot_id, str(op)])
			return false
		if leader_estab_id == 0 or bool(op.get("is_leader", false)):
			leader_estab_id = est_id

		# Seed starting home district score into sparse knowledge_pools for this operative
		INTEL_MANAGER.apply_effort_impulse(
			world_state, "RESIDENT", str(r_id), "DISTRICT", "block_0_0", 85.0,
			{"distance": 0.0, "access_permeability": 1.0}
		)

		var hh_members: Array = DB_MANAGER.query_rows("SELECT resident_id FROM residents WHERE household_id = %d AND dod IS NULL;" % hh_id)
		if hh_members.size() > 1:
			var family_edges: Array = DB_MANAGER.query_rows("""
				SELECT sr.to_resident_id
				FROM social_relationships sr
				JOIN system_labels l ON sr.relationship_type_id = l.label_id
				WHERE sr.from_resident_id = %d AND l.code = 'FAMILY' AND sr.valid_to IS NULL;
			""" % r_id)
			if family_edges.is_empty():
				printerr("FAIL [Test 2]: Operative %d shares household %d but has no FAMILY edges." % [r_id, hh_id])
				return false

	var leader_est_dict: Dictionary = world_state.get("establishments", {}).get(str(leader_estab_id), {})
	var stash_cash: float = float(leader_est_dict.get("inventory", {}).get("CASH", 0.0))
	if stash_cash <= 0.0:
		printerr("FAIL [Test 2]: Starting stash was not anchored to leader home establishment %d." % leader_estab_id)
		return false

	print("PASS [Test 2]: All %d crew operatives anchored to physical homes, kinship edges verified, £%.2f stash anchored." % [residents.size(), stash_cash])
	return true

## Test 3 (Item c): Secondary Relationship Firewall blocks 2nd-degree acquaintance leaks
func _test_secondary_relationship_firewall(world_state: Dictionary) -> bool:
	var intel_ctx: Dictionary = OPS_CTRL._build_player_intel_context(world_state)
	var crew_ids: Array = intel_ctx["crew_resident_ids"]
	var op1_id: int = int(crew_ids[0])

	# Pick two non-crew residents in block_1_0: C1 (1st-degree contact) and C2 (2nd-degree friend of C1)
	var outsiders: Array = DB_MANAGER.query_rows("""
		SELECT r.resident_id
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		WHERE e.district_id = 'block_1_0' AND r.is_active_agent = 0 AND r.dod IS NULL
		LIMIT 2;
	""")
	if outsiders.size() < 2:
		printerr("FAIL [Test 3]: Insufficient outsider citizens generated in block_1_0.")
		return false

	var c1_id: int = int(outsiders[0]["resident_id"])
	var c2_id: int = int(outsiders[1]["resident_id"])
	var rel_friend_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "FRIEND")
	if rel_friend_id <= 0:
		rel_friend_id = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CIVIC_PEER")
	var reason_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	# Link op1 -> c1 (1st degree) and c1 -> c2 (2nd degree relative to op1)
	DB_MANAGER.execute_batch([
		"INSERT OR IGNORE INTO social_relationships (from_resident_id, to_resident_id, relationship_type_id, affinity_score, valid_from, change_reason_id) VALUES (%d, %d, %d, 0.80, 29219, %d);" % [op1_id, c1_id, rel_friend_id, reason_id],
		"INSERT OR IGNORE INTO social_relationships (from_resident_id, to_resident_id, relationship_type_id, affinity_score, valid_from, change_reason_id) VALUES (%d, %d, %d, 0.80, 29219, %d);" % [c1_id, c2_id, rel_friend_id, reason_id]
	])

	var contacts_before: Array[Dictionary] = SOCIETY_QUERIES.get_known_contacts_for_crew(crew_ids, [], 29219)
	var found_c1 := false
	var found_c2 := false
	for c in contacts_before:
		var cid: int = int(c["resident_id"])
		if cid == c1_id:
			found_c1 = true
		if cid == c2_id:
			found_c2 = true

	if not found_c1:
		printerr("FAIL [Test 3]: 1st-degree contact %d was not returned by get_known_contacts_for_crew." % c1_id)
		return false
	if found_c2:
		printerr("FAIL [Test 3]: Secondary Relationship Firewall breached! 2nd-degree contact %d leaked through %d." % [c2_id, c1_id])
		return false

	# Explicit introduction (COMMUNICATE / INVESTIGATE) unlocks c2
	var contacts_after: Array[Dictionary] = SOCIETY_QUERIES.get_known_contacts_for_crew(crew_ids, [c2_id], 29219)
	var unlocked_c2 := false
	for c in contacts_after:
		if int(c["resident_id"]) == c2_id:
			unlocked_c2 = true
			break

	if not unlocked_c2:
		printerr("FAIL [Test 3]: Explicitly introduced contact %d failed to appear after revelation." % c2_id)
		return false

	print("PASS [Test 3]: Secondary Relationship Firewall blocked 2nd-degree contact %d until explicit introduction." % c2_id)
	return true

## Test 4 (Items d, e, f): Residential & Workplace Fog-of-War masking before/after investigation
func _test_household_and_workplace_fog_of_war(world_state: Dictionary) -> bool:
	var intel_ctx: Dictionary = OPS_CTRL._build_player_intel_context(world_state)
	var known_res_set: Dictionary = {}
	for k in intel_ctx["crew_resident_ids"]:
		known_res_set[int(k)] = true

	# Find an uninvestigated occupied residential unit in block_1_1
	var res_units: Array = DB_MANAGER.query_rows("""
		SELECT DISTINCT e.establishment_id
		FROM establishments e
		JOIN households h ON e.establishment_id = h.establishment_id
		JOIN residents r ON h.household_id = r.household_id
		JOIN system_labels l ON e.category_id = l.label_id
		WHERE e.district_id = 'block_1_1' AND l.code = 'RESIDENTIAL_UNIT' AND r.is_active_agent = 0 AND r.dod IS NULL
		LIMIT 1;
	""")
	if res_units.is_empty():
		printerr("FAIL [Test 4]: No occupied residential unit found in block_1_1.")
		return false

	var res_estab_id: int = int(res_units[0]["establishment_id"])
	var masked_res_docket: Dictionary = SOCIETY_QUERIES.get_establishment_docket(res_estab_id, 29219, intel_ctx)
	var masked_occupants: Array = masked_res_docket.get("residents", [])
	var saw_masked_occupant := false
	for occ in masked_occupants:
		if bool(occ.get("is_masked", false)) and str(occ.get("full_name", "")) == "UI_MASKED_OCCUPANT":
			saw_masked_occupant = true
			break

	if not saw_masked_occupant:
		printerr("FAIL [Test 4]: Uninvestigated residential unit %d leaked occupant names instead of UI_MASKED_OCCUPANT." % res_estab_id)
		return false

	# Find an uninvestigated staffed workplace
	var known_est_strs: Array[String] = ["0"]
	for est_k in intel_ctx.get("scouted_establishment_ids", []):
		known_est_strs.append(str(int(est_k)))
	for crew_id in intel_ctx.get("crew_resident_ids", []):
		var prof: Dictionary = SOCIETY_QUERIES.get_resident_profile(int(crew_id), 29219)
		var emp_str: String = str(prof.get("employer_entity_id", ""))
		if emp_str.begins_with("ESTAB_"):
			known_est_strs.append(emp_str.trim_prefix("ESTAB_"))

	# Find an uninvestigated staffed workplace where no crew member works
	var workplaces: Array = DB_MANAGER.query_rows("""
		SELECT DISTINCT e.establishment_id
		FROM establishments e
		JOIN livelihood_contracts c ON c.employer_entity_id = 'ESTAB_' || e.establishment_id
		JOIN system_labels l ON e.category_id = l.label_id
		WHERE l.code != 'RESIDENTIAL_UNIT'
		  AND e.establishment_id NOT IN (%s)
		  AND c.valid_to IS NULL
		LIMIT 1;
	""" % ", ".join(known_est_strs))

	var work_estab_id: int = int(workplaces[0]["establishment_id"])
	var masked_work_docket: Dictionary = SOCIETY_QUERIES.get_establishment_docket(work_estab_id, 29219, intel_ctx)
	var masked_staff: Array = masked_work_docket.get("employees", [])
	var saw_masked_staff := false
	for emp in masked_staff:
		if bool(emp.get("is_masked", false)) and str(emp.get("full_name", "")) == "UI_MASKED_STAFF":
			saw_masked_staff = true
			break

	if not saw_masked_staff:
		printerr("FAIL [Test 4]: Uninvestigated workplace %d leaked employee names instead of UI_MASKED_STAFF." % work_estab_id)
		return false

	# Simulate INVESTIGATE/SCOUT on work_estab_id -> true staff names revealed
	var revealed_ctx: Dictionary = intel_ctx.duplicate(true)
	revealed_ctx["scouted_establishment_ids"] = [work_estab_id]
	var revealed_work_docket: Dictionary = SOCIETY_QUERIES.get_establishment_docket(work_estab_id, 29219, revealed_ctx)
	for emp in revealed_work_docket.get("employees", []):
		if bool(emp.get("is_masked", false)) or str(emp.get("full_name", "")) == "UI_MASKED_STAFF":
			printerr("FAIL [Test 4]: Scouted workplace %d remained masked after investigation." % work_estab_id)
			return false

	print("PASS [Test 4]: Residential (UI_MASKED_OCCUPANT) & Workplace (UI_MASKED_STAFF) Fog of War enforced and revealed on scout.")
	return true

## Test 5 (Item b): GenRosterDocket binds crew_members + known_contacts and resets cleanly
func _test_roster_docket_contract(world_state: Dictionary) -> bool:
	var roster_view: Control = GEN_ROSTER_SCRIPT.new()
	var intel_ctx: Dictionary = OPS_CTRL._build_player_intel_context(world_state)
	var contacts: Array[Dictionary] = SOCIETY_QUERIES.get_known_contacts_for_crew(intel_ctx["crew_resident_ids"], [], 29219)

	var crew_list: Array[Dictionary] = []
	for slot_id in world_state.get("residents", {}).keys():
		var op: Dictionary = world_state["residents"][slot_id]
		crew_list.append({
			"resident_id": int(op["resident_id"]),
			"name": str(op["name"]),
			"summary_line": "Age %d" % int(op["age"])
		})

	var contact_list: Array[Dictionary] = []
	for c in contacts:
		contact_list.append({
			"resident_id": int(c["resident_id"]),
			"name": str(c["full_name"]),
			"summary_line": str(c.get("home_address", ""))
		})

	roster_view.bind_data({
		"enterprise_title": "ASTON FIRM",
		"home_district_name": "Aston Row",
		"crew_members": crew_list,
		"known_contacts": contact_list
	})

	var op_box: Node = roster_view.find_child("operative_cards", true, false)
	var contact_box: Node = roster_view.find_child("contact_cards", true, false)
	if op_box == null or contact_box == null:
		printerr("FAIL [Test 5]: GenRosterDocket missing operative_cards or contact_cards containers.")
		roster_view.free()
		return false

	if op_box.get_child_count() != crew_list.size() or contact_box.get_child_count() != contact_list.size():
		printerr("FAIL [Test 5]: GenRosterDocket button counts did not match bound crew/contacts.")
		roster_view.free()
		return false

	# Snapshot reset contract (Rule 9)
	roster_view.bind_data({})
	if op_box.get_child_count() != 0 or contact_box.get_child_count() != 0:
		printerr("FAIL [Test 5]: GenRosterDocket failed to clear list containers on empty snapshot reset.")
		roster_view.free()
		return false

	roster_view.free()
	print("PASS [Test 5]: GenRosterDocket bound %d operatives & %d known contacts and reset cleanly." % [crew_list.size(), contact_list.size()])
	return true