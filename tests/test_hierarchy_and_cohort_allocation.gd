# res://tests/test_hierarchy_and_cohort_allocation.gd
extends SceneTree

const HierarchyTreeProjectorScript = preload("res://systems/multilayer_info_loop/hierarchy_tree_projector.gd")
const HierarchyNavigatorScript = preload("res://scenes/ui/components/hierarchy_navigator.gd")
const MandateCohortCatalogScript = preload("res://systems/economy/mandate_cohort_catalog.gd")
const MandateAllocatorPanelScript = preload("res://scenes/ui/components/mandate_allocator_panel.gd")
const ManagerAIResolverScript = preload("res://systems/economy/manager_ai_resolver.gd")
const OrgMandateManagerScript = preload("res://systems/economy/org_mandate_manager.gd")
const CmdInvestigateBridgeScript = preload("res://systems/ui_commands/cmd_investigate_bridge.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const DBManagerScript = preload("res://systems/db_manager.gd")

func _init() -> void:
	print("=== RUNNING HEADLESS TEST: HIERARCHY NAVIGATOR & COHORT ALLOCATION ===")
	var start_day: int = CalendarHelperScript.get_simulation_start_day()
	var ws: Dictionary = _build_fixture_world_state(start_day)

	_test_player_org_rollup_and_stale_collapse(ws, start_day)
	_test_external_org_tbc_bridge_and_recon(ws)
	_test_cohort_allocation_planning_with_hope(ws, start_day)

	print("=== ALL HIERARCHY & COHORT ALLOCATION TESTS PASSED ===")
	quit(0)

func _build_fixture_world_state(start_day: int) -> Dictionary:
	return {
		"metadata": {
			"current_sim_day": start_day,
			"current_day_tick": 1,
			"time_horizon": "DAY"
		},
		"operations": {
			"home_district_id": "DIST_NORTH",
			"crew_org_id": "ORG:CREW_ENTERPRISE",
			"enterprise_name": "Midlands Syndicate"
		},
		"districts": {
			"DIST_NORTH": {"display_name": "North Quarter"},
			"DIST_UNSCOUTED": {"display_name": "Outer Docks"}
		},
		"organizations": {
			"ORG:CREW_ENTERPRISE": {
				"display_name": "Midlands Syndicate",
				"autonomy_mode": "DIRECT",
				"loyalty": 0.92,
				"police_heat": 0.15
			},
			"ORG:RIVAL_RING": {
				"display_name": "Ironbridge Combine",
				"autonomy_mode": "ARMS_LENGTH",
				"loyalty": 0.65,
				"police_heat": 0.30
			}
		},
		"residents": {
			101: {
				"resident_id": 101,
				"name": "Arthur Boss",
				"is_crew": true,
				"org_id": "ORG:CREW_ENTERPRISE",
				"org_role": "BOSS",
				"reports_to_resident_id": 0,
				"current_district_id": "DIST_NORTH",
				"loyalty": 0.95,
				"fatigue": 0.10,
				"inventory": {"CASH": 500.0}
			},
			102: {
				"resident_id": 102,
				"name": "Clara Foreman",
				"is_crew": true,
				"org_id": "ORG:CREW_ENTERPRISE",
				"org_role": "MANAGER",
				"reports_to_resident_id": 101,
				"current_district_id": "DIST_NORTH",
				"loyalty": 0.80,
				"fatigue": 0.25,
				"inventory": {"CASH": 200.0}
			},
			103: {
				"resident_id": 103,
				"name": "Danny Runner",
				"is_crew": true,
				"org_id": "ORG:CREW_ENTERPRISE",
				"org_role": "OPERATIVE",
				"reports_to_resident_id": 102,
				"current_district_id": "DIST_NORTH",
				"loyalty": 0.70,
				"fatigue": 0.40,
				"inventory": {"CASH": 50.0}
			},
			201: {
				"resident_id": 201,
				"name": "Victor Kingpin",
				"is_crew": false,
				"org_id": "ORG:RIVAL_RING",
				"org_role": "BOSS",
				"reports_to_resident_id": 0,
				"current_district_id": "DIST_NORTH",
				"loyalty": 0.90,
				"fatigue": 0.10
			},
			202: {
				"resident_id": 202,
				"name": "Hidden Lieutenant",
				"is_crew": false,
				"org_id": "ORG:RIVAL_RING",
				"org_role": "LIEUTENANT",
				"reports_to_resident_id": 201,
				"current_district_id": "DIST_NORTH",
				"loyalty": 0.85,
				"fatigue": 0.15
			},
			203: {
				"resident_id": 203,
				"name": "Street Collector",
				"is_crew": false,
				"org_id": "ORG:RIVAL_RING",
				"org_role": "COLLECTOR",
				"reports_to_resident_id": 202,
				"current_district_id": "DIST_NORTH",
				"loyalty": 0.60,
				"fatigue": 0.30
			}
		},
		"org_mandates": {
			1: {
				"mandate_id": 1,
				"org_id": "ORG:CREW_ENTERPRISE",
				"manager_resident_id": 102,
				"title": "North Supply Mandate",
				"mandate_mode": "SUPPLY",
				"planning_horizon": "MONTH",
				"is_active": true,
				"heat_ceiling": 0.65,
				"target_metrics": {
					"remittance_target": 300.0,
					"operating_float": 120.0
				},
				"scope_filter": {
					"spatial": ["DIST_NORTH"],
					"premises": ["*"],
					"commodities": ["*"],
					"verbs": ["*"]
				}
			}
		},
		"commodity_registry": {
			"BEER_KEG": {"name": "Beer Keg"},
			"CIGARETTE_PACK": {"name": "Cigarette Pack"}
		},
		"knowledge_pools": {
			"RESIDENT": {
				"101": {
					"ORG:RIVAL_RING": {"score": 80.0, "last_updated_day": start_day},
					"DISTRICT:DIST_NORTH": {"score": 85.0, "last_updated_day": start_day},
					"RESIDENT:101": {"score": 100.0, "last_updated_day": start_day},
					"RESIDENT:102": {"score": 85.0, "last_updated_day": start_day},
					"RESIDENT:103": {"score": 85.0, "last_updated_day": start_day},
					"RESIDENT:201": {"score": 80.0, "last_updated_day": start_day},
					"RESIDENT:203": {"score": 75.0, "last_updated_day": start_day}
				}
			}
		}
	}

func _test_player_org_rollup_and_stale_collapse(ws: Dictionary, start_day: int) -> void:
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)
	var tree_fresh: Dictionary = HierarchyTreeProjectorScript.project_player_org_tree(ws, intel_ctx, "ORG:CREW_ENTERPRISE")
	var metrics: Dictionary = tree_fresh.get("metrics", {})
	assert(int(metrics.get("headcount", 0)) == 3, "Expected 3 total personnel in org roll-up.")

	var fresh_children: Array = tree_fresh.get("children", [])
	var found_mgr_102: bool = false
	for child in fresh_children:
		if str(child.get("entity_id", "")) == "102":
			found_mgr_102 = true
			var mgr_metrics: Dictionary = child.get("metrics", {})
			assert(is_equal_approx(float(mgr_metrics.get("remittance_target", 0.0)), 300.0),
				"Expected manager branch remittance target 300.0.")
	assert(found_mgr_102, "Expected manager branch node 102 under root.")

	var nav: HierarchyNavigator = HierarchyNavigatorScript.new()
	root.add_child(nav)
	nav.set_tree_root(tree_fresh)
	assert(nav.get_selected_node_id() == str(tree_fresh.get("node_id", "")), "Expected root node selected by default.")

	# Age Clara Foreman's report beyond stale threshold so subordinate Danny collapses into TBC_LEAF
	ws["knowledge_pools"]["RESIDENT"]["101"]["RESIDENT:102"]["last_updated_day"] = start_day - 45
	var tree_stale: Dictionary = HierarchyTreeProjectorScript.project_player_org_tree(ws, intel_ctx, "ORG:CREW_ENTERPRISE")
	var clara_node: Dictionary = {}
	for child in tree_stale.get("children", []):
		if str(child.get("entity_id", "")) == "102":
			clara_node = child
			break
	assert(not clara_node.is_empty(), "Expected Clara Foreman under Arthur Boss.")
	assert(str(clara_node.get("node_type", "")) == "STALE", "Expected stale node_type on aged branch.")
	var clara_children: Array = clara_node.get("children", [])
	assert(clara_children.size() == 1 and str(clara_children[0].get("node_type", "")) == "TBC_LEAF",
		"Expected aged subordinate branch to collapse into single TBC_LEAF cohort node.")

	root.remove_child(nav)
	nav.free()
	print("[PASS] Player org roll-up, HierarchyNavigator rendering, and aged TBC_LEAF collapse verified.")

func _test_external_org_tbc_bridge_and_recon(ws: Dictionary) -> void:
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)
	var rival_records: Array[Dictionary] = [
		{"id": "201", "parent_id": "", "scope": "RESIDENT", "entity_id": "201", "role": "BOSS", "name": "Victor Kingpin"},
		{"id": "202", "parent_id": "201", "scope": "RESIDENT", "entity_id": "202", "role": "LIEUTENANT", "name": "Hidden Lieutenant"},
		{"id": "203", "parent_id": "202", "scope": "RESIDENT", "entity_id": "203", "role": "COLLECTOR", "name": "Street Collector"}
	]
	var ext_tree: Dictionary = HierarchyTreeProjectorScript.project_external_org_tree(ws, intel_ctx, "ORG:RIVAL_RING", rival_records)
	# Resident 201 (known) -> TBC_BRIDGE (across unknown 202) -> Resident 203 (known)
	var root_children: Array = ext_tree.get("children", [])
	assert(root_children.size() == 1 and str(root_children[0].get("entity_id", "")) == "201",
		"Expected known boss 201 directly under rival org root.")
	var boss_children: Array = root_children[0].get("children", [])
	assert(boss_children.size() == 1, "Expected 1 TBC_BRIDGE node under boss 201.")
	var bridge_node: Dictionary = boss_children[0]
	assert(str(bridge_node.get("node_type", "")) == "TBC_BRIDGE", "Expected TBC_BRIDGE node for unknown intermediary.")
	var bridged_kids: Array = bridge_node.get("children", [])
	assert(bridged_kids.size() == 1 and str(bridged_kids[0].get("entity_id", "")) == "203",
		"Expected known lower-tier actor 203 nested under TBC_BRIDGE.")

	var gs = ScenarioManifestManager.get_game_state()
	if gs != null and "world_state" in gs:
		gs.world_state = ws
		CmdInvestigateBridgeScript.execute(bridge_node, null, {})
		var staged: Array = ws.get("staged_directives", [])
		assert(staged.size() == 1 and str(staged[0].get("verb", "")) == "INVESTIGATE",
			"Expected CmdInvestigateBridge to stage an INVESTIGATE directive.")

	print("[PASS] External org TBC_BRIDGE contraction and bridge recon staging verified.")

func _test_cohort_allocation_planning_with_hope(ws: Dictionary, start_day: int) -> void:
	var catalog: Dictionary = MandateCohortCatalogScript.build_allocator_catalog(ws)
	if DBManagerScript.is_database_open():
		var reason_id: int = DBManagerScript.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
		var cat_res_id: int = DBManagerScript.get_label_id("ESTABLISHMENT_CATEGORY", "RESIDENTIAL_UNIT")
		var res_type_id: int = int(DBManagerScript.query_rows("SELECT label_id FROM system_labels WHERE domain = 'RESIDENCE_TYPE' LIMIT 1;")[0]["label_id"])
		var eth_id: int = int(DBManagerScript.query_rows("SELECT label_id FROM system_labels WHERE domain = 'ETHNICITY' LIMIT 1;")[0]["label_id"])
		var rel_id: int = int(DBManagerScript.query_rows("SELECT label_id FROM system_labels WHERE domain = 'RELIGION' LIMIT 1;")[0]["label_id"])
		var gen_id: int = int(DBManagerScript.query_rows("SELECT label_id FROM system_labels WHERE domain = 'GENDER' LIMIT 1;")[0]["label_id"])
		var edu_id: int = int(DBManagerScript.query_rows("SELECT label_id FROM system_labels WHERE domain = 'EDUCATION_LEVEL' LIMIT 1;")[0]["label_id"])
		DBManagerScript.query_rows("""
			INSERT OR IGNORE INTO districts (
				district_id, display_name, district_type, grid_x, grid_z, valid_from, valid_to, change_reason_id
			) VALUES ('DIST_NORTH', 'North Quarter', 'INNER_SUBURB', 0, 0, %d, NULL, %d);
			INSERT OR IGNORE INTO organizations (
				org_id, display_name, org_type, legal_status, institution_rail_class, valid_from, valid_to, change_reason_id
			) VALUES ('ORG:CREW_ENTERPRISE', 'Midlands Syndicate', 'CRIMINAL', 'INFORMAL', 'STANDARD', %d, NULL, %d);
			INSERT OR IGNORE INTO establishments (
				establishment_id, district_id, name, category_id, capacity, valid_from, valid_to, change_reason_id
			) VALUES (1, 'DIST_NORTH', 'HQ Flat', %d, 4, %d, NULL, %d);
			INSERT OR IGNORE INTO households (
				household_id, establishment_id, residence_type_id, ethnicity_id, religion_id, valid_from, valid_to, change_reason_id
			) VALUES (1, 1, %d, %d, %d, %d, NULL, %d);
			INSERT OR IGNORE INTO residents (
				resident_id, household_id, first_name, birth_surname, current_surname, dob, gender_id, education_level_id, ethnicity_id, religion_id, valid_from, valid_to, change_reason_id
			) VALUES (101, 1, 'Arthur', 'Boss', 'Boss', 0, %d, %d, %d, %d, %d, NULL, %d);
		""" % [
			start_day, reason_id,
			start_day, reason_id,
			cat_res_id, start_day, reason_id,
			res_type_id, eth_id, rel_id, start_day, reason_id,
			gen_id, edu_id, eth_id, rel_id, start_day, reason_id
		])

	var spatial_opts: Array = catalog.get("spatial", [])
	var found_unscouted: bool = false
	for opt in spatial_opts:
		if opt is Dictionary and str(opt.get("id", "")) == "DIST_UNSCOUTED":
			found_unscouted = bool(opt.get("is_unscouted", false))
	assert(found_unscouted, "Expected unscouted district DIST_UNSCOUTED to remain selectable and flagged is_unscouted=true.")

	var panel: MandateAllocatorPanel = MandateAllocatorPanelScript.new()
	root.add_child(panel)
	panel.set_allocator_catalog(catalog)

	var emitted_actions: Array[Dictionary] = []
	panel.action_clicked.connect(func(code: String, payload: Dictionary) -> void:
		emitted_actions.append({"code": code, "payload": payload})
	)
	panel._toggle_axis_value("spatial", "DIST_UNSCOUTED")
	panel._on_submit_mandate_pressed()

	assert(emitted_actions.size() == 1 and emitted_actions[0]["code"] == "create_org_mandate",
		"Expected MandateAllocatorPanel to emit create_org_mandate without blocking overlapping/unscouted cohorts.")
	var issued_spec: Dictionary = emitted_actions[0]["payload"]
	var created: Dictionary = OrgMandateManagerScript.create_mandate(ws, issued_spec)
	var recon_plan: Dictionary = ManagerAIResolverScript.plan_mandate_reconnaissance(ws, created)
	assert(bool(recon_plan.get("requires_recon_first", false)),
		"Expected ManagerAIResolver to detect unscouted target district and require recon first.")
	assert(recon_plan.get("priority_verbs", []).has("SCOUT"),
		"Expected SCOUT in priority_verbs for unscouted mandate.")

	var review: Dictionary = MandateCohortCatalogScript.build_mandate_review_summary(ws, int(created.get("mandate_id", 0)))
	assert(bool(review.get("requires_recon_first", false)), "Expected review summary to flag unscouted districts.")
	panel.set_selected_mandate_review(review)

	root.remove_child(panel)
	panel.free()
	print("[PASS] 4-axis cohort allocation ('planning with hope') and recon prioritization verified.")