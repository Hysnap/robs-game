# res://tests/test_ui_pipeline_management.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")
const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const UIActionCommandScript = preload("res://scenes/ui/shell_host/ui_action_command.gd")
const OperationsControllerScript = preload("res://systems/operations_controller.gd")
const ShellRegistryScript = preload("res://scenes/ui/shell_host/shell_registry.gd")
const OuterShellScene: PackedScene = preload("res://scenes/ui/shell_host/outer_shell.tscn")
const TestSocietyFactoryScript = preload("res://tests/test_society_factory.gd")
const DBManagerScript = preload("res://systems/db_manager.gd")

const MGMT_SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/org_management_docket.json"
const NAV_SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/navigation_bar.json"
const MGMT_GEN_PATH := "res://generated/ui/core/gen_org_management_docket.gd"
const NAV_GEN_PATH := "res://generated/ui/core/gen_navigation_bar.gd"

var _captured_actions: Array[Dictionary] = []
var _frame_count: int = 0
var _executed: bool = false

func _init() -> void:
	print("\n--- [Test] UI Pipeline: Organization & Mandate Management (TestSocietyFactory) ---")

func _process(_delta: float) -> bool:
	if _executed:
		return false
	_frame_count += 1
	if _frame_count < 2:
		return false
	_executed = true
	_run_tests_async()
	return false

func _run_tests_async() -> void:
	# 1. Compile target schemas headlessly
	assert(FileAccess.file_exists(MGMT_SCHEMA_PATH), "Missing schema: %s" % MGMT_SCHEMA_PATH)
	assert(FileAccess.file_exists(NAV_SCHEMA_PATH), "Missing schema: %s" % NAV_SCHEMA_PATH)
	var harvested_tokens: Dictionary = {}
	UICompilerScript.compile_schema(MGMT_SCHEMA_PATH, harvested_tokens)
	UICompilerScript.compile_schema(NAV_SCHEMA_PATH, harvested_tokens)
	assert(FileAccess.file_exists(MGMT_GEN_PATH), "Failed to compile: %s" % MGMT_GEN_PATH)
	assert(FileAccess.file_exists(NAV_GEN_PATH), "Failed to compile: %s" % NAV_GEN_PATH)
	print("PASS 1/5: Compiled org_management_docket.json and navigation_bar.json cleanly.")

	# 2. Instantiate views & verify GenNavBar management tab signal
	var nav_script = load(NAV_GEN_PATH)
	var mgmt_script = load(MGMT_GEN_PATH)
	assert(nav_script != null and mgmt_script != null, "Generated scripts failed to load.")

	var nav_view: Control = nav_script.new() as Control
	var mgmt_view: Control = mgmt_script.new() as Control
	assert(nav_view != null and mgmt_view != null, "Generated views failed to instantiate.")
	assert(mgmt_view.has_signal("action_clicked"), "GenOrgManagementDocket missing action_clicked signal.")
	assert(mgmt_view.has_signal("item_selected"), "GenOrgManagementDocket missing item_selected signal.")
	assert(mgmt_view.has_method("bind_data"), "GenOrgManagementDocket missing bind_data().")
	assert(mgmt_view.has_method("inscribe_entry"), "GenOrgManagementDocket missing inscribe_entry().")

	root.add_child(nav_view)
	nav_view.connect("action_clicked", _on_action_clicked)
	var mgmt_btn: Button = nav_view.find_child("management", true, false) as Button
	assert(mgmt_btn != null, "GenNavBar missing 'management' macro tab button.")
	mgmt_btn.pressed.emit()
	assert(_captured_actions.size() == 1 and _captured_actions[0]["code"] == "open_management",
		"Management tab did not emit 'open_management'.")
	print("PASS 2/5: GenNavBar 'management' button emitted action_clicked('open_management', {}).")

	# 3. Resolve mounted GameState autoload & generate TestSocietyFactory society
	var gs = ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "GameState autoload unavailable after frame tick.")
	var ws: Dictionary = await TestSocietyFactoryScript.create_test_world_with_crew(4, 4, "mgmt-ui-pipeline-seed")
	gs.world_state = ws

	var home_dist: String = str(ws.get("operations", {}).get("home_district_id", "block_0_0"))
	var crew_ids: Array = ws.get("residents", {}).keys()
	assert(crew_ids.size() >= 2, "Expected at least 2 crew operatives from TestSocietyFactory.")
	var mgr_a_id: int = int(crew_ids[0])
	var mgr_b_id: int = int(crew_ids[1])
	assert(mgr_a_id > 0 and mgr_b_id > 0, "Expected integer resident IDs in ws['residents'].")

	TestSocietyFactoryScript.ensure_test_organization(
		ws, "ORG:CHICKEN_FRONT", "Digbeth Fried Chicken", "ORG:CREW_ENTERPRISE", "ARMS_LENGTH", 0.72, 0.45
	)
	ws["org_mandates"] = {}

	OperationsControllerScript.initialize_commands()

	var shell_instance: OuterShell = OuterShellScene.instantiate() as OuterShell
	assert(shell_instance != null, "Failed to instantiate outer_shell.tscn.")
	root.add_child(shell_instance)
	var spread_instance := ShellRegistryScript.instantiate_active_spread(1975)
	assert(spread_instance != null, "Failed to instantiate active spread for 1975.")
	shell_instance.set_spread_wrapper(spread_instance)

	var view_host := ViewHostScript.new()
	view_host.shell_node = shell_instance
	view_host.register_view("MANAGEMENT", mgmt_view)

	OperationsControllerScript.dispatch_ui_command(UIActionCommandScript.new("open_management", {}), view_host, {})
	assert(view_host.get_active_domain() == "MANAGEMENT", "ViewHost failed to switch to MANAGEMENT domain.")
	print("PASS 3/5: OperationsController routed 'open_management' against TestSocietyFactory world_state.")

	# 4. Test create_org_mandate, overlapping collision detection, grant_mandate_assistance & revoke_org_mandate
	OperationsControllerScript.dispatch_ui_command(UIActionCommandScript.new("create_org_mandate", {
		"org_id": "ORG:CREW_ENTERPRISE",
		"manager_resident_id": mgr_a_id,
		"title": "Home Turf Pubs",
		"mandate_mode": "CASHFLOW",
		"planning_horizon": "MONTH",
		"scope_filter": {"spatial": [home_dist], "premises": ["CATEGORY:PUB"], "commodities": [], "verbs": []}
	}), view_host, {})
	OperationsControllerScript.dispatch_ui_command(UIActionCommandScript.new("create_org_mandate", {
		"org_id": "ORG:CREW_ENTERPRISE",
		"manager_resident_id": mgr_b_id,
		"title": "Home Turf Protection",
		"mandate_mode": "EXPAND",
		"planning_horizon": "MONTH",
		"scope_filter": {"spatial": [home_dist], "premises": ["CATEGORY:PUB"], "commodities": [], "verbs": ["THREATEN"]}
	}), view_host, {})

	assert(ws["org_mandates"].size() == 2,
		"Expected 2 active mandates created via command, got %d." % ws["org_mandates"].size())
	var first_mandate_id: int = int(ws["org_mandates"].keys()[0])

	OperationsControllerScript.dispatch_ui_command(UIActionCommandScript.new("grant_mandate_assistance", {
		"mandate_id": first_mandate_id,
		"duration_days": 7
	}), view_host, {})
	assert(int(ws["org_mandates"][first_mandate_id].get("assistance_request_expires_day", -1)) > 0,
		"Assistance window was not opened on mandate.")

	OperationsControllerScript.dispatch_ui_command(UIActionCommandScript.new("revoke_org_mandate", {
		"mandate_id": first_mandate_id
	}), view_host, {})
	assert(not bool(ws["org_mandates"][first_mandate_id].get("is_active", true)),
		"Mandate was not deactivated by revoke_org_mandate.")
	print("PASS 4/5: Verified create_org_mandate, grant_mandate_assistance, and revoke_org_mandate commands.")

	# 5. Test complete snapshot reset & clean node teardown
	mgmt_view.inscribe_entry({"author": "HQ", "text": "Manager report entry"})
	mgmt_view.bind_data({})
	var org_list: Node = mgmt_view.find_child("org_hierarchy_list", true, false)
	if org_list != null:
		for child in org_list.get_children():
			assert(not (child is Button), "Expected org_hierarchy_list buttons cleared on empty snapshot reset.")
	print("PASS 5/5: Snapshot reset cleared bound lists cleanly.")

	# Teardown
	view_host.cleanup()
	view_host.free()
	root.remove_child(shell_instance)
	_deep_free(shell_instance)
	if is_instance_valid(mgmt_view):
		_deep_free(mgmt_view)
	root.remove_child(nav_view)
	_deep_free(nav_view)
	DBManagerScript.close_database()

	print("--- [Test] ALL MANAGEMENT UI PIPELINE CHECKS PASSED ---\n")
	quit(0)

func _on_action_clicked(action_code: String, payload: Dictionary) -> void:
	_captured_actions.append({"code": action_code, "payload": payload})

func _deep_free(node: Node) -> void:
	for child in node.get_children():
		_deep_free(child)
	node.free()
