# res://scenes/3d_scenes/city_view.gd
extends Node3D

@onready var city_crafter: Node3D = $CityCrafter
@onready var filofax_canvas: CanvasLayer = $FilofaxCanvas
@onready var filofax_ui: FilofaxUI = get_node_or_null("FilofaxCanvas/FilofaxBinder")

## Camera settings
var camera: Camera3D
var camera_target := Vector3.ZERO
var camera_distance := 1000.0
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(45.0)

var orbiting := false
var panning := false

func _ready() -> void:
	setup_navigation()
	setup_view()

	# Retrieve active seed
	var active_seed: String = str(GameState.world_state.get("metadata", {}).get("active_seed", "default-city"))
	if "seed_id" in city_crafter:
		city_crafter.seed_id = active_seed

	# Build visuals strictly from saved layout or GameState
	var saved_layout: Dictionary = GameState.world_state.get("city_layout", {})
	if not saved_layout.is_empty() and city_crafter.has_method("load_visual_layout"):
		set_status(tr("CITY_VIEW_STATUS_RENDERING"))
		city_crafter.load_visual_layout(saved_layout)
	
	set_status(tr("CITY_VIEW_STATUS_READY"))

	if not GameState.world_state.get("districts", {}).is_empty():
		run_district_sense_check(GameState.world_state)

func setup_view() -> void:
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)

	var light := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = "DirectionalLight3D"
		add_child(light)

	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		add_child(world_environment)
		
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.12, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.75)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment

	var configuration = city_crafter.get("city_configuration")
	var block_size: float = float(configuration.block_size) if configuration and "block_size" in configuration else 40.0
	var street_width: float = float(configuration.street_width) if configuration and "street_width" in configuration else 8.0
	var cell_extent := block_size + street_width
	
	var city_extent: float = 800.0
	
	if configuration and "city_radius" in configuration:
		var radius: float = float(configuration.city_radius)
		camera_target = city_crafter.global_position
		city_extent = radius * 2.0 * cell_extent
	else:
		var grid_width: float = float(configuration.grid_width)
		var grid_height: float = float(configuration.grid_height)
		camera_target = city_crafter.global_position + Vector3(
			grid_width * cell_extent * 0.5,
			0.0,
			grid_height * cell_extent * 0.5
		)
		city_extent = max(grid_width * cell_extent, grid_height * cell_extent)

	camera_distance = max(city_extent * 1.3, 100.0)
	camera_yaw = 0.0
	camera_pitch = deg_to_rad(45.0)

	camera.fov = 55.0
	camera.current = true
	update_camera_transform()

	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = 1.2
	light.shadow_enabled = true
	light.shadow_opacity = 0.7

func update_camera_transform() -> void:
	if camera == null:
		return

	var horizontal_distance := camera_distance * cos(camera_pitch)
	var height := camera_distance * sin(camera_pitch)

	camera.global_position = camera_target + Vector3(
		sin(camera_yaw) * horizontal_distance,
		height,
		cos(camera_yaw) * horizontal_distance
	)
	camera.look_at(camera_target)

func _unhandled_input(event: InputEvent) -> void:
	# 1. Hotkey Toggle for Filofax Binder (Tab Key)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_filofax_visibility()
			get_viewport().set_input_as_handled()
			return

	# 2. 3D Ground Raycast on Left Click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam == null:
			return

		var from: Vector3 = cam.project_ray_origin(event.position)
		var to: Vector3 = from + cam.project_ray_normal(event.position) * 2000.0
		var space_state = get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(from, to)
		var result := space_state.intersect_ray(query)

		if result and result.collider:
			var col = result.collider
			if col.has_meta("block_id"):
				var clicked_block_id: String = col.get_meta("block_id")
				_on_district_clicked(clicked_block_id)
				get_viewport().set_input_as_handled()

func setup_navigation() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CityNavigation"
	add_child(canvas_layer)

	var return_button := Button.new()
	return_button.name = "ReturnToMainMenu"
	return_button.text = tr("CITY_VIEW_BTN_MAIN_MENU")
	return_button.position = Vector2(20.0, 20.0)
	return_button.custom_minimum_size = Vector2(180.0, 44.0)
	return_button.pressed.connect(_on_return_to_main_menu_pressed)
	canvas_layer.add_child(return_button)

	var status_label := Label.new()
	status_label.name = "GenerationStatus"
	status_label.position = Vector2(20.0, 72.0)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	canvas_layer.add_child(status_label)

func set_status(status: String) -> void:
	var status_label := get_node_or_null("CityNavigation/GenerationStatus") as Label
	if status_label:
		status_label.text = status

func _on_return_to_main_menu_pressed() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/menus/main_menu/main.tscn")
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)

func _process(delta: float) -> void:
	var movement := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): movement.z -= 1.0
	if Input.is_key_pressed(KEY_S): movement.z += 1.0
	if Input.is_key_pressed(KEY_A): movement.x -= 1.0
	if Input.is_key_pressed(KEY_D): movement.x += 1.0

	if movement != Vector3.ZERO:
		var speed := camera_distance * 0.75
		camera_target += movement.normalized() * speed * delta
		update_camera_transform()

func _on_district_clicked(block_id: String) -> void:
	print("[CityView] District clicked: %s" % block_id)
	
	if filofax_canvas != null and filofax_ui != null:
		filofax_canvas.visible = true
		filofax_ui.visible = true
		filofax_ui.display_district_docket(block_id)

func _toggle_filofax_visibility() -> void:
	if filofax_canvas != null:
		filofax_canvas.visible = not filofax_canvas.visible
		if filofax_ui != null:
			filofax_ui.visible = filofax_canvas.visible

func run_district_sense_check(world_state: Dictionary) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		push_error("[AUDIT FAILED] No districts were ingested into world_state!")
		return

	var total_population: int = 0
	for dist_id in districts.keys():
		total_population += int(districts[dist_id].get("population", 0))

	print("[CityView] Loaded city with %d active districts. Total population: ~%d" % [districts.size(), total_population])