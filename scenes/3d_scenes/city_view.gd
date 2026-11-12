# res://scenes/3d_scenes/city_view.gd
extends Node3D

@onready var city_crafter: Node3D = $CityCrafter
@onready var rts_camera: RTSCamera3D = $RTSCamera3D
@onready var game_hud: GameHUD = $GameHUD
@onready var workspace_canvas: CanvasLayer = $FilofaxCanvas
@onready var outer_shell: OuterShell = $FilofaxCanvas/OuterShell

const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const UIActionCommandScript = preload("res://scenes/ui/shell_host/ui_action_command.gd")
const RetroThemeScript = preload("res://scenes/ui/shell_host/retro_theme.gd")
const ShellRegistryScript = preload("res://scenes/ui/shell_host/shell_registry.gd")
const OperationsControllerScript = preload("res://systems/operations_controller.gd")
const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const DesktopSlipStackScene = preload("res://scenes/ui/feedback/desktop_slip_stack.tscn")
const IndicatorScene: PackedScene = preload("res://scenes/3d_scenes/indicators/district_indicator.tscn")

var view_host: ViewHost = null
var shell_customizer: Control = null
var feedback_inbox: Control = null
var directive_modal: Control = null

# Spatial indicators state
var _district_ground_nodes: Dictionary = {} # block_id -> MeshInstance3D
var _district_indicators: Dictionary = {}   # block_id -> Node3D (holder)
var _color_verified: Color
var _color_stale: Color
var _marker_elevation: float = 1.5
var _landmark_elevation: float = 4.0

func _ready() -> void:
	SystemLogger.log_info("[CityView] Initializing city view.")
	_load_spatial_indicator_rules()

	# 1. Mount Presenter Host inside OuterShell
	if outer_shell != null:
		view_host = ViewHostScript.new()
		view_host.shell_node = outer_shell
		outer_shell.add_child(view_host)

		_setup_compiled_shell_host_views()
		_setup_shell_customizer()

		if outer_shell.has_signal("close_requested"):
			outer_shell.close_requested.connect(func(): workspace_canvas.visible = false)
		elif outer_shell.close_btn != null:
			outer_shell.close_btn.pressed.connect(func(): workspace_canvas.visible = false)

	# 2. Camera & 3D Picking
	if rts_camera != null:
		rts_camera.district_clicked.connect(_on_district_clicked)
		rts_camera.focus_on(city_crafter.global_position)

	# 3. HUD wiring
	if game_hud != null:
		game_hud.toggle_filofax_requested.connect(_toggle_workspace_visibility)
		game_hud.end_turn_requested.connect(_on_end_turn_requested)
		if game_hud.has_signal("toggle_messages_inbox_requested"):
			game_hud.toggle_messages_inbox_requested.connect(_toggle_feedback_inbox_visibility)

	# 4. Synchronize Seed & Visual Layout
	var gs = ScenarioManifestManager.get_game_state()
	var active_seed: String = "default-city"
	var saved_layout: Dictionary = {}
	if gs != null and "world_state" in gs:
		active_seed = str(gs.world_state.get("metadata", {}).get("active_seed", "default-city"))
		saved_layout = gs.world_state.get("city_layout", {})

		if gs.has_signal("turn_advanced"):
			gs.turn_advanced.connect(func(_current_tick: int):
				refresh_all_district_indicators()
				SystemLogger.log_info("[CityView] Mounted %d district ground indicators." % _district_ground_nodes.size())
			)

	if "seed_id" in city_crafter:
		city_crafter.seed_id = active_seed

	if not saved_layout.is_empty() and city_crafter.has_method("load_visual_layout"):
		city_crafter.load_visual_layout(saved_layout)

	# 5. Index District Nodes and Mount Visual Indicators
	call_deferred("_initialize_spatial_ground_indicators")

func _exit_tree() -> void:
	if is_instance_valid(view_host):
		view_host.cleanup()
	for indicator in _district_indicators.values():
		if is_instance_valid(indicator):
			indicator.queue_free()
	_district_indicators.clear()
	_district_ground_nodes.clear()

func _load_spatial_indicator_rules() -> void:
	assert(ScenarioManifestManager.has_module("fog_of_war"),
		"FATAL: [CityView] Active scenario manifest missing 'fog_of_war' registration.")

	var fow_rules: Dictionary = ScenarioManifestManager.load_module("fog_of_war")
	assert(not fow_rules.is_empty(), "FATAL: [CityView] Loaded 'fog_of_war' module is empty.")
	assert(fow_rules.has("spatial_indicators"), "FATAL: [CityView] Missing 'spatial_indicators' in fog_of_war rules.")

	var spatial_cfg: Dictionary = fow_rules["spatial_indicators"]
	var hex_v: String = str(spatial_cfg.get("color_verified", "#2ecc71"))
	var hex_s: String = str(spatial_cfg.get("color_stale", "#e67e22"))
	_color_verified = Color.from_string(hex_v, Color.GREEN)
	_color_stale = Color.from_string(hex_s, Color.ORANGE)
	_marker_elevation = float(spatial_cfg.get("marker_elevation", 1.5))
	_landmark_elevation = float(spatial_cfg.get("landmark_elevation", 4.0))

func _initialize_spatial_ground_indicators() -> void:
	_district_ground_nodes.clear()
	for child in city_crafter.get_children():
		if child is MeshInstance3D and child.has_meta("block_id"):
			var b_id: String = child.get_meta("block_id")
			_district_ground_nodes[b_id] = child

	refresh_all_district_indicators()

func refresh_all_district_indicators() -> void:
	for b_id in _district_ground_nodes.keys():
		refresh_district_indicator(b_id)

func refresh_district_indicator(block_id: String) -> void:
	if not _district_ground_nodes.has(block_id):
		return

	var ground_mesh: MeshInstance3D = _district_ground_nodes[block_id]
	var gs = ScenarioManifestManager.get_game_state()
	var view_data: Dictionary = {}
	if gs != null and gs.has_method("get_district_view"):
		view_data = gs.get_district_view(block_id)

	var indicator: DistrictIndicator = _district_indicators.get(block_id, null)
	if indicator == null or not is_instance_valid(indicator):
		indicator = IndicatorScene.instantiate() as DistrictIndicator
		indicator.position = ground_mesh.position
		city_crafter.add_child(indicator)
		_district_indicators[block_id] = indicator

	indicator.update_from_view_data(view_data)

func _get_active_calendar_year() -> int:
	var gs = ScenarioManifestManager.get_game_state()
	if gs != null and "world_state" in gs:
		return int(gs.world_state.get("metadata", {}).get("calendar_year", 0))
	return 0

func _setup_compiled_shell_host_views() -> void:
	_mount_shell_and_views("DOSSIER", [])

	if view_host != null and not view_host.ui_command_dispatched.is_connected(_on_ui_command_dispatched):
		view_host.ui_command_dispatched.connect(_on_ui_command_dispatched)

func _mount_shell_and_views(initial_domain: String, preserved_directives: Array) -> void:
	var current_year: int = _get_active_calendar_year()
	var active_shell_id: String = ShellRegistryScript.get_configured_shell_id(current_year)
	var active_manifest: Dictionary = ShellRegistryScript.get_shell_manifest(active_shell_id)
	var unlocked_shells: Array[Dictionary] = ShellRegistryScript.get_available_shells_for_year(current_year)

	if outer_shell != null and outer_shell.has_method("apply_shell_window_size"):
		outer_shell.apply_shell_window_size(active_manifest)

	if view_host != null:
		view_host.sync_shell_selector(unlocked_shells, active_shell_id)

	# A. Mount Era Presentation Spread resolved dynamically via Shell Manifest
	var spread_instance := ShellRegistryScript.instantiate_active_spread(current_year)
	if spread_instance and outer_shell:
		outer_shell.set_spread_wrapper(spread_instance)

	# B. Mount Navigation Spine
	var nav_view: Control = ShellRegistryScript.instantiate_generated_view("gen_navigation_bar.gd", current_year)
	view_host.set_navigation_component(nav_view)

	# C. Register Compiled Content Views
	view_host.register_view("DOSSIER", ShellRegistryScript.instantiate_generated_view("gen_district_docket.gd", current_year))
	view_host.register_view("FINANCE", ShellRegistryScript.instantiate_generated_view("gen_cashbook_ledger.gd", current_year))
	view_host.register_view("DIARY", ShellRegistryScript.instantiate_generated_view("gen_diary_log.gd", current_year))
	view_host.register_view("ROSTER", ShellRegistryScript.instantiate_generated_view("gen_roster_docket.gd", current_year))

	# Sub-Docket Inspection Views
	view_host.register_view("ESTABLISHMENT_DOCKET", ShellRegistryScript.instantiate_generated_view("gen_establishment_docket.gd", current_year))
	view_host.register_view("RESIDENTIAL_DOCKET", ShellRegistryScript.instantiate_generated_view("gen_residential_docket.gd", current_year))

	# D. Mount Interactive Action Planner into ACTION slot
	var action_planner_view: Control = ShellRegistryScript.instantiate_generated_view("gen_action_planner.gd", current_year)
	if outer_shell:
		outer_shell.mount_view("ACTION", action_planner_view)
		view_host.set_action_component(action_planner_view)

	for dir_item in preserved_directives:
		if action_planner_view != null and action_planner_view.has_method("add_directive"):
			action_planner_view.add_directive(dir_item)

	# E. Mount Feedback Inbox Shell onto Canvas
	if workspace_canvas and feedback_inbox == null:
		feedback_inbox = DesktopSlipStackScene.instantiate() as Control
		feedback_inbox.visible = false
		feedback_inbox.z_index = 15
		workspace_canvas.add_child(feedback_inbox)

		if game_hud != null and feedback_inbox.has_signal("stack_count_changed"):
			feedback_inbox.stack_count_changed.connect(game_hud.update_unread_message_count)

		if view_host != null:
			view_host.set_desk_inbox(feedback_inbox)

	# F. Query active spread for its era-specific composer modal and bind to action planner
	directive_modal = outer_shell.get_slot("MODAL")
	assert(directive_modal != null, "FATAL: [CityView] Active spread did not supply a MODAL slot.")
	assert(directive_modal.has_signal("directive_committed"), "FATAL: [CityView] Modal slot does not expose 'directive_committed' signal.")
	assert(action_planner_view != null and action_planner_view.has_method("add_directive"), "FATAL: [CityView] Action planner view is missing 'add_directive' contract.")

	if not directive_modal.directive_committed.is_connected(action_planner_view.add_directive):
		directive_modal.directive_committed.connect(action_planner_view.add_directive)

	if shell_customizer != null and "target_shell" in shell_customizer:
		shell_customizer.target_shell = active_shell_id

	view_host.switch_to_domain(initial_domain)
	_handle_route_request(initial_domain)

func _handle_shell_switch(target_shell_id: String) -> void:
	var current_year: int = _get_active_calendar_year()
	var current_shell: String = ShellRegistryScript.get_configured_shell_id(current_year)
	if target_shell_id.is_empty() or target_shell_id == current_shell:
		return

	var preserved_directives: Array = []
	var planner_node: Control = outer_shell.get_slot("ACTION")
	if planner_node != null and planner_node.get_child_count() > 0:
		var active_planner = planner_node.get_child(0)
		if active_planner.has_method("get_staged_directives"):
			preserved_directives = active_planner.get_staged_directives().duplicate(true)

	var current_domain: String = "DOSSIER"
	if view_host != null and not view_host.get_active_domain().is_empty():
		current_domain = view_host.get_active_domain()

	ShellRegistryScript.set_active_shell(target_shell_id)
	if view_host != null and view_host.has_method("clear_registered_views"):
		view_host.clear_registered_views()

	_mount_shell_and_views(current_domain, preserved_directives)

func _setup_shell_customizer() -> void:
	var customizer_res = load("res://scenes/ui/shell_host/shell_customizer.tscn")
	if customizer_res and workspace_canvas:
		shell_customizer = customizer_res.instantiate()

		var active_shell_id: String = ShellRegistryScript.get_configured_shell_id(_get_active_calendar_year())
		if "target_shell" in shell_customizer:
			shell_customizer.target_shell = active_shell_id

		shell_customizer.visible = false
		shell_customizer.z_index = 20
		workspace_canvas.add_child(shell_customizer)

func _on_ui_command_dispatched(command: UIActionCommand) -> void:
	match command.type:
		UIActionCommand.CommandType.SWITCH_SHELL:
			_handle_shell_switch(str(command.payload.get("shell_id", "")))

		UIActionCommand.CommandType.ROUTE_REQUEST:
			if command.domain == "STYLES":
				if shell_customizer != null:
					shell_customizer.visible = not shell_customizer.visible
					if shell_customizer.visible:
						shell_customizer.move_to_front()
			else:
				_handle_route_request(command.domain)

		UIActionCommand.CommandType.ACTION_CLICKED:
			if command.domain == "INBOX":
				_handle_slip_triage(command.action_code, command.payload)
			else:
				_handle_action_requested(command.action_code, command.payload)

		UIActionCommand.CommandType.ITEM_SELECTED:
			_handle_item_selected(command.domain, command.payload.get("filter_key"))

		UIActionCommand.CommandType.SLIP_FILED:
			pass

func _handle_route_request(domain_key: String) -> void:
	match domain_key:
		"ROSTER":
			_hydrate_roster_view()
		"DOSSIER":
			var gs = ScenarioManifestManager.get_game_state()
			var active_id: String = ""
			if gs != null and "world_state" in gs:
				active_id = str(gs.world_state.get("selected_district_id", ""))
			if not active_id.is_empty() and gs.has_method("get_district_view"):
				view_host.update_active_view_data(gs.get_district_view(active_id))

func _hydrate_roster_view() -> void:
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs or view_host == null:
		return

	var ws: Dictionary = gs.world_state
	var staff_dict: Dictionary = ws.get("staff", {})
	var home_id: String = str(ws.get("operations", {}).get("home_district_id", "block_0_0"))

	var crew_members: Array[Dictionary] = []
	for staff_id in staff_dict.keys():
		var member = staff_dict[staff_id]
		if member is Dictionary:
			var r_id: int = int(member.get("resident_id", 0))
			var name_str: String = str(member.get("name", staff_id))
			var cash_val: float = float(member.get("pocket_cash", 0.0))
			var daily_hrs: float = float(member.get("daily_operational_limit_hours", 8.0))

			var age_val: int = 25
			if r_id > 0:
				var demo: Dictionary = SocietyQueriesScript.get_resident_profile(r_id)
				age_val = int(demo.get("age", 25))

			var summary: String = "Age %d • £%.2f Pocket • %.0fh max" % [age_val, cash_val, daily_hrs]

			crew_members.append({
				"resident_id": r_id if r_id > 0 else staff_id,
				"name": name_str,
				"summary_line": summary,
				"staff_id": staff_id,
				"assigned_district": str(member.get("current_district_id", home_id))
			})

	view_host.update_active_view_data({"crew_roster": crew_members})

func _handle_action_requested(action_code: String, _payload: Dictionary) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	var target_district: String = ""
	if gs != null and "world_state" in gs:
		target_district = str(gs.world_state.get("selected_district_id", ""))

	match action_code:
		"OPEN_PAD", "NEW_ORDER", "OPEN_COMPOSER":
			if directive_modal != null and directive_modal.has_method("open_for_context"):
				directive_modal.open_for_context({"target_district_id": target_district})
		"COMMIT_SHIFT", "EXECUTE_TURN", "END_DAY":
			_on_end_turn_requested()

func _handle_slip_triage(action_id: String, card_payload: Dictionary) -> void:
	if action_id == "FILE":
		OperationsControllerScript.file_card_slip(card_payload, view_host)
	else:
		SystemLogger.log_info("[CityView] Discarded slip: %s" % card_payload.get("display_text"))

func _handle_item_selected(target_route: String, filter_key: Variant) -> void:
	match target_route:
		"OPERATIVE_DETAIL":
			var gs = ScenarioManifestManager.get_game_state()
			var ws: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
			var staff_dict: Dictionary = ws.get("staff", {})

			var res_id: int = 0
			var staff_info: Dictionary = {}

			if typeof(filter_key) == TYPE_INT or (typeof(filter_key) == TYPE_STRING and str(filter_key).is_valid_int()):
				res_id = int(filter_key)
			else:
				var s_id: String = str(filter_key)
				if staff_dict.has(s_id):
					staff_info = staff_dict[s_id]
					res_id = int(staff_info.get("resident_id", 0))

			if res_id > 0:
				var demo: Dictionary = SocietyQueriesScript.get_resident_profile(res_id)
				var home_estab: int = int(demo.get("home_establishment_id", demo.get("establishment_id", 0)))
				if home_estab > 0:
					var res_data: Dictionary = SocietyQueriesScript.get_establishment_docket(home_estab)
					view_host.switch_to_domain("RESIDENTIAL_DOCKET")
					view_host.update_active_view_data(res_data)
					return

			var target_district: String = ""
			if not staff_info.is_empty():
				target_district = str(staff_info.get("current_district_id", ""))
			else:
				for s_key in staff_dict.keys():
					var s_entry = staff_dict[s_key]
					if s_entry is Dictionary and int(s_entry.get("resident_id", -1)) == res_id:
						target_district = str(s_entry.get("current_district_id", ""))
						break

			if target_district.is_empty():
				target_district = str(ws.get("player_knowledge", {}).get("home_district_id", ""))

			if not target_district.is_empty() and gs != null and gs.has_method("get_district_view"):
				var district_data: Dictionary = gs.get_district_view(target_district)
				view_host.switch_to_domain("DOSSIER")
				view_host.update_active_view_data(district_data)

		"RESIDENTIAL_DOCKET", "ESTABLISHMENT_DOCKET":
			var estab_id: int = int(filter_key)
			var docket_data: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id)
			view_host.switch_to_domain(target_route)
			view_host.update_active_view_data(docket_data)

		_:
			view_host.switch_to_domain(target_route)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_workspace_visibility()
			get_viewport().set_input_as_handled()

func _on_district_clicked(block_id: String) -> void:
	SystemLogger.log_info("[CityView] District clicked on 3D map: %s" % block_id)

	var gs = ScenarioManifestManager.get_game_state()
	var district_data: Dictionary = {}
	if gs != null:
		if gs.has_method("set_selected_district"):
			gs.set_selected_district(block_id)
		elif "world_state" in gs:
			gs.world_state["selected_district_id"] = block_id

		if gs.has_method("get_district_view"):
			district_data = gs.get_district_view(block_id)

	if workspace_canvas != null and view_host != null:
		workspace_canvas.visible = true
		view_host.switch_to_domain("DOSSIER")
		view_host.update_active_view_data(district_data)

func _toggle_workspace_visibility() -> void:
	if workspace_canvas == null:
		return

	workspace_canvas.visible = not workspace_canvas.visible
	if workspace_canvas.visible:
		if outer_shell != null:
			outer_shell.move_to_front()
			var vp_size: Vector2 = get_viewport().get_visible_rect().size
			var shell_size: Vector2 = outer_shell.size

			var min_y: float = 60.0
			var max_x: float = maxf(20.0, vp_size.x - shell_size.x - 20.0)
			var max_y: float = maxf(min_y, vp_size.y - 80.0)

			if outer_shell.global_position.x < 0.0 or outer_shell.global_position.x > max_x \
			or outer_shell.global_position.y < min_y or outer_shell.global_position.y > max_y:
				outer_shell.global_position = Vector2(
					maxf(20.0, (vp_size.x - shell_size.x) * 0.5),
					maxf(min_y, (vp_size.y - shell_size.y) * 0.5)
				)

		if view_host != null:
			var gs = ScenarioManifestManager.get_game_state()
			var active_id: String = ""
			if gs != null and "world_state" in gs:
				active_id = str(gs.world_state.get("selected_district_id", ""))

			if not active_id.is_empty() and gs != null and gs.has_method("get_district_view"):
				var district_data: Dictionary = gs.get_district_view(active_id)
				view_host.update_active_view_data(district_data)

func _on_end_turn_requested() -> void:
	var staged: Array = []
	var planner_node: Control = outer_shell.get_slot("ACTION")
	if planner_node != null and planner_node.get_child_count() > 0:
		var active_planner = planner_node.get_child(0)
		if active_planner.has_method("consume_selected_directives"):
			staged = active_planner.consume_selected_directives()
		elif active_planner.has_method("get_staged_directives"):
			staged = active_planner.get_staged_directives()

	OperationsControllerScript.execute_staged_cycle(staged, view_host)

func _toggle_feedback_inbox_visibility() -> void:
	if feedback_inbox == null or workspace_canvas == null:
		return

	workspace_canvas.visible = true
	feedback_inbox.visible = not feedback_inbox.visible
	if feedback_inbox.visible:
		feedback_inbox.move_to_front()