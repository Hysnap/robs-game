# res://scenes/3d_scenes/city_view.gd
extends Node3D

@onready var city_crafter: Node3D = $CityCrafter
@onready var rts_camera: RTSCamera3D = $RTSCamera3D
@onready var game_hud: GameHUD = $GameHUD
@onready var workspace_canvas: CanvasLayer = $FilofaxCanvas
@onready var outer_shell: OuterShell = $FilofaxCanvas/OuterShell

const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
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
			outer_shell.connect("close_requested", func(): workspace_canvas.visible = false)
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

		# Listen reactively for turn completion to update 3D ground markers
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

## Refreshes ground ticks and landmark billboards based on current perception
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

	# Fetch or instantiate the component
	var indicator: DistrictIndicator = _district_indicators.get(block_id, null)
	if indicator == null or not is_instance_valid(indicator):
		indicator = IndicatorScene.instantiate() as DistrictIndicator
		indicator.position = ground_mesh.position
		city_crafter.add_child(indicator)
		_district_indicators[block_id] = indicator

	indicator.update_from_view_data(view_data)

func _setup_compiled_shell_host_views() -> void:
	# A. Mount Era Presentation Spread resolved dynamically via Shell Manifest
	var spread_instance := ShellRegistryScript.instantiate_active_spread()
	if spread_instance and outer_shell:
		outer_shell.set_spread_wrapper(spread_instance)

	# B. Mount Navigation Spine
	var nav_class = load("res://generated/ui/gen_navigation_bar.gd")
	assert(nav_class != null, "FATAL: [CityView] Generated UI missing: gen_navigation_bar.gd")
	view_host.set_navigation_component(nav_class.new())

	# C. Register Compiled Content Views
	var docket_class = load("res://generated/ui/gen_district_docket.gd")
	assert(docket_class != null, "FATAL: [CityView] Generated UI missing: gen_district_docket.gd")
	view_host.register_view("DOSSIER", docket_class.new())

	var cashbook_class = load("res://generated/ui/gen_cashbook_ledger.gd")
	assert(cashbook_class != null, "FATAL: [CityView] Generated UI missing: gen_cashbook_ledger.gd")
	view_host.register_view("FINANCE", cashbook_class.new())

	var diary_class = load("res://generated/ui/gen_diary_log.gd")
	assert(diary_class != null, "FATAL: [CityView] Generated UI missing: gen_diary_log.gd")
	view_host.register_view("DIARY", diary_class.new())

	var roster_class = load("res://generated/ui/gen_roster_docket.gd")
	assert(roster_class != null, "FATAL: [CityView] Generated UI missing: gen_roster_docket.gd")
	view_host.register_view("ROSTER", roster_class.new())

	# Sub-Docket Inspection Views
	var estab_class = load("res://generated/ui/gen_establishment_docket.gd")
	assert(estab_class != null, "FATAL: [CityView] Generated UI missing: gen_establishment_docket.gd")
	view_host.register_view("ESTABLISHMENT_DOCKET", estab_class.new())

	var res_class = load("res://generated/ui/gen_residential_docket.gd")
	assert(res_class != null, "FATAL: [CityView] Generated UI missing: gen_residential_docket.gd")
	view_host.register_view("RESIDENTIAL_DOCKET", res_class.new())

	# D. Mount Interactive Action Planner into ACTION slot
	var action_planner_view: Control = null
	var planner_class = load("res://generated/ui/gen_action_planner.gd")
	assert(planner_class != null, "FATAL: [CityView] Generated UI missing: gen_action_planner.gd")
	if outer_shell:
		action_planner_view = planner_class.new()
		outer_shell.mount_view("ACTION", action_planner_view)
		view_host.set_action_component(action_planner_view)

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

	# F. Query active spread for its era-specific composer modal (duck-typed)
	directive_modal = outer_shell.get_slot("MODAL")
	if directive_modal != null and directive_modal.has_signal("directive_committed"):
		if action_planner_view != null and action_planner_view.has_method("add_directive"):
			directive_modal.directive_committed.connect(action_planner_view.add_directive)

	# G. Connect ViewHost signals
	if view_host:
		view_host.ui_command_dispatched.connect(_on_ui_command_dispatched)

	view_host.switch_to_domain("DOSSIER")

func _on_ui_command_dispatched(command: UIActionCommand) -> void:
	if command.type == UIActionCommand.CommandType.ROUTE_REQUEST \
	and command.domain == "STYLES":
		shell_customizer.visible = not shell_customizer.visible
		if shell_customizer.visible:
			shell_customizer.move_to_front()

	OperationsControllerScript.dispatch_ui_command(
		command,
		view_host,
		{
			"directive_modal": directive_modal,
			"action_planner": view_host.get_action_component()
		}
	)

func _setup_shell_customizer() -> void:
	var customizer_res = load("res://scenes/ui/shell_host/shell_customizer.tscn")
	if customizer_res and workspace_canvas:
		shell_customizer = customizer_res.instantiate()
		
		var active_shell_id: String = ShellRegistryScript.get_configured_shell_id()
		if "target_shell" in shell_customizer:
			shell_customizer.target_shell = active_shell_id
			
		shell_customizer.visible = false
		shell_customizer.z_index = 20
		workspace_canvas.add_child(shell_customizer)

func _on_view_host_slip_triage(action_id: String, card_payload: Dictionary) -> void:
	if action_id == "FILE":
		OperationsControllerScript.file_card_slip(card_payload, view_host)
	else:
		SystemLogger.log_info("[CityView] Discarded slip: %s" % card_payload.get("display_text"))

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
