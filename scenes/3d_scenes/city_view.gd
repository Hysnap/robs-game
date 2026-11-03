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
	if nav_class:
		view_host.set_navigation_component(nav_class.new())

	# C. Register Compiled Content Views
	var docket_class = load("res://generated/ui/gen_district_docket.gd")
	if docket_class:
		view_host.register_view("DOSSIER", docket_class.new())

	var cashbook_class = load("res://generated/ui/gen_cashbook_ledger.gd")
	if cashbook_class:
		view_host.register_view("FINANCE", cashbook_class.new())

	var diary_class = load("res://generated/ui/gen_diary_log.gd")
	if diary_class:
		view_host.register_view("DIARY", diary_class.new())

	# Sub-Docket Inspection Views (Option A - Driven dynamically by schema route)
	var estab_class = load("res://generated/ui/gen_establishment_docket.gd")
	if estab_class:
		view_host.register_view("ESTABLISHMENT_DOCKET", estab_class.new())

	var res_class = load("res://generated/ui/gen_residential_docket.gd")
	if res_class:
		view_host.register_view("RESIDENTIAL_DOCKET", res_class.new())

	# D. Mount Interactive Action Planner into ACTION slot
	var action_planner_view: Control = null
	var planner_class = load("res://generated/ui/gen_action_planner.gd")
	if planner_class and outer_shell:
		action_planner_view = planner_class.new()
		outer_shell.mount_view("ACTION", action_planner_view)

	# E. Mount Feedback Inbox Shell onto Canvas
	if workspace_canvas and feedback_inbox == null:
		feedback_inbox = DesktopSlipStackScene.instantiate() as Control
		feedback_inbox.visible = false
		feedback_inbox.z_index = 15
		workspace_canvas.add_child(feedback_inbox)

		if view_host != null and feedback_inbox != null:
			view_host.set_desk_inbox(feedback_inbox)

	# F. Query active spread for its era-specific composer modal (duck-typed)
	var era_modal: Control = outer_shell.get_slot("MODAL")

	# G. Connect ViewHost signals
	if view_host:
		if action_planner_view:
			view_host.attach_action_system(action_planner_view, feedback_inbox, era_modal)
		view_host.action_requested.connect(_on_view_host_action_requested)
		view_host.triage_slip_action.connect(_on_view_host_slip_triage)
		view_host.item_selected.connect(_on_view_host_item_selected)

	view_host.switch_to_domain("DOSSIER")

func _setup_shell_customizer() -> void:
	var customizer_res = load("res://scenes/ui/shell_host/shell_customizer.tscn")
	if customizer_res and workspace_canvas:
		shell_customizer = customizer_res.instantiate()
		
		# Set filter directly from registry without hardcoded checks
		var active_shell_id: String = ShellRegistryScript.get_configured_shell_id()
		if "target_shell" in shell_customizer:
			shell_customizer.target_shell = active_shell_id
			
		shell_customizer.visible = false
		shell_customizer.z_index = 20
		workspace_canvas.add_child(shell_customizer)

		view_host.route_changed.connect(func(domain_key: String):
			if domain_key == "STYLES":
				shell_customizer.visible = not shell_customizer.visible
				if shell_customizer.visible:
					shell_customizer.move_to_front()
		)

func _on_view_host_action_requested(action_code: String, _payload: Dictionary) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	var target_district: String = ""
	if gs != null and "world_state" in gs:
		target_district = str(gs.world_state.get("selected_district_id", ""))

	match action_code:
		"OPEN_PAD", "NEW_ORDER", "OPEN_COMPOSER":
			view_host.open_composer({"target_district_id": target_district})
		"COMMIT_SHIFT", "EXECUTE_TURN", "END_DAY":
			_on_end_turn_requested()

func _on_view_host_slip_triage(action_id: String, card_payload: Dictionary) -> void:
	if action_id == "FILE":
		OperationsControllerScript.file_card_slip(card_payload, view_host)
	else:
		SystemLogger.log_info("[CityView] Discarded slip: %s" % card_payload.get("display_text"))

func _on_view_host_item_selected(target_route: String, filter_key: Variant) -> void:
	var estab_id: int = int(filter_key)
	var docket_data: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id)
	if view_host != null:
		view_host.switch_to_domain(target_route)
		view_host.update_active_view_data(docket_data)

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
		# Anti-lost protection: ensure outer_shell is on-screen and accessible below the HUD
		if outer_shell != null:
			outer_shell.move_to_front()
			var vp_size: Vector2 = get_viewport().get_visible_rect().size
			var shell_size: Vector2 = outer_shell.size
			
			# If unpositioned or dragged off-screen / under HUD, clamp safely
			var min_y: float = 60.0 # Clear HUD top-bar margin
			var max_x: float = maxf(20.0, vp_size.x - shell_size.x - 20.0)
			var max_y: float = maxf(min_y, vp_size.y - 80.0)
			
			if outer_shell.global_position.x < 0.0 or outer_shell.global_position.x > max_x \
			or outer_shell.global_position.y < min_y or outer_shell.global_position.y > max_y:
				# Recenter on screen if lost
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
	if view_host != null:
		if view_host.has_method("consume_selected_staged_directives"):
			staged = view_host.consume_selected_staged_directives()
		elif view_host.has_method("get_staged_directives"):
			staged = view_host.get_staged_directives()
	OperationsControllerScript.execute_staged_cycle(staged, view_host)