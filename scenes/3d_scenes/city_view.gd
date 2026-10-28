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
const SimControllerScript = preload("res://systems/sim_controller.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")
const FeedbackShellScene = preload("res://scenes/ui/shell_host/feedback_shell.tscn")

var view_host: ViewHost = null
var shell_customizer: Control = null
var feedback_shell: FeedbackShell = null
var directive_modal: Control = null

func _ready() -> void:
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

	# 4. Synchronize Seed & Visual Layout
	var active_seed: String = str(GameState.world_state.get("metadata", {}).get("active_seed", "default-city"))
	if "seed_id" in city_crafter:
		city_crafter.seed_id = active_seed

	var saved_layout: Dictionary = GameState.world_state.get("city_layout", {})
	if not saved_layout.is_empty() and city_crafter.has_method("load_visual_layout"):
		city_crafter.load_visual_layout(saved_layout)

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

	# D. Mount Interactive Action Planner into ACTION slot
	var action_planner_view: Control = null
	var planner_class = load("res://generated/ui/gen_action_planner.gd")
	if planner_class and outer_shell:
		action_planner_view = planner_class.new()
		outer_shell.mount_view("ACTION", action_planner_view)

	# E. Mount Feedback Inbox Shell onto Canvas
	if workspace_canvas and feedback_shell == null:
		feedback_shell = FeedbackShellScene.instantiate() as FeedbackShell
		feedback_shell.visible = false
		feedback_shell.z_index = 15
		workspace_canvas.add_child(feedback_shell)

	# F. Query active spread for its era-specific composer modal (duck-typed)
	var era_modal: Control = outer_shell.get_slot("MODAL")

	# G. Connect all three systems to ViewHost
	if view_host and action_planner_view:
		view_host.attach_action_system(action_planner_view, feedback_shell, era_modal)

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_workspace_visibility()
			get_viewport().set_input_as_handled()

func _on_district_clicked(block_id: String) -> void:
	print("[CityView] District clicked on 3D map: %s" % block_id)
	
	if GameState.has_method("set_selected_district"):
		GameState.set_selected_district(block_id)
	else:
		GameState.world_state["selected_district_id"] = block_id

	# Fetch ground-truth SQLite and in-memory district telemetry
	var district_data: Dictionary = GameState.get_district_view(block_id)

	# Reveal Filofax and present Docket
	if workspace_canvas != null and view_host != null:
		workspace_canvas.visible = true
		view_host.switch_to_domain("DOSSIER")
		view_host.update_active_view_data(district_data)

func _toggle_workspace_visibility() -> void:
	if workspace_canvas == null:
		return

	workspace_canvas.visible = not workspace_canvas.visible
	if workspace_canvas.visible and view_host != null:
		var active_id: String = str(GameState.world_state.get("selected_district_id", ""))
		if not active_id.is_empty():
			var district_data: Dictionary = GameState.get_district_view(active_id)
			view_host.update_active_view_data(district_data)
