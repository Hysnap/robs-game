extends Node3D

@onready var city_crafter: Node3D = $CityCrafter

## camera settings
var camera: Camera3D
var camera_target := Vector3.ZERO
var camera_distance := 1000.0
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(45.0)

var orbiting := false
var panning := false

func _ready() -> void:
	var settings := load_pending_city_settings()
	if settings.is_empty():
		settings = load_last_generated_settings()
	if settings.is_empty():
		push_error("No generated city is available to display.")
		return

	if not apply_settings(settings):
		return
	setup_view()
	setup_navigation()
	var status_text: String = "Loading city: %s" % str(get_seed_from_settings(settings))
	set_status(status_text)
	city_crafter.connect("generation_complete", _on_generation_complete)
	city_crafter.call_deferred(
		"generate_city_async",
		get_seed_from_settings(settings)
	)

func load_pending_city_settings() -> Dictionary:
	if not get_tree().has_meta("pending_city_settings"):
		return {}
	var settings = get_tree().get_meta("pending_city_settings")
	get_tree().remove_meta("pending_city_settings")
	if not settings is Dictionary:
		push_error("Pending city settings are invalid.")
		return {}
	return settings

func load_last_generated_settings() -> Dictionary:
	var file_path := "user://cities/last_generated.json"
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Could not open the last generated city save.")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("The last generated city save is invalid.")
		return {}
	return parsed

func get_seed_from_settings(settings: Dictionary) -> String:
	var seed_value = settings.get("seed_id", settings.get("seed_text", ""))
	return str(seed_value).strip_edges()

func apply_settings(settings: Dictionary) -> bool:
	var configuration = city_crafter.get("city_configuration")
	if configuration == null:
		push_error("CityCrafter has no city configuration.")
		return false

	var property_names := [
		"grid_width", "grid_height", "block_size", "street_width",
		"empty_block_chance", "enable_multi_size_blocks", "large_block_chance",
		"wide_block_chance", "tall_block_chance", "enable_edge_variations",
		"edge_variation_chance", "max_edge_variation", "enable_random_extensions",
		"random_extensions_count", "extension_spawn_chance", "district_mode",
		"residential_ratio", "commercial_ratio", "industrial_ratio", "noise_scale",
		"enable_residential_subdivisions", "subdivision_mode", "subdivision_layout",
		"subdivision_street_width", "residential_buildings_min",
		"residential_buildings_max", "residential_spacing", "residential_border_margin",
		"commercial_buildings_min", "commercial_buildings_max", "commercial_spacing",
		"commercial_border_margin", "industrial_buildings_min", "industrial_buildings_max",
		"industrial_spacing", "industrial_border_margin", "rotation_mode",
		"scale_variation", "generate_roads", "generate_intersections",
		"intersection_height_offset", "generate_subdivision_roads", "generate_ground",
		"ground_height_offset"
	]
	for property_name in property_names:
		if settings.has(property_name):
			configuration.set(property_name, settings[property_name])

	var saved_seed := get_seed_from_settings(settings)
	if saved_seed.is_empty():
		push_error("The saved city does not contain a seed.")
		return false
	city_crafter.set("seed_id", saved_seed)
	if str(city_crafter.get("seed_id")) != saved_seed:
		push_error("Could not apply the saved city seed: %s" % saved_seed)
		return false
	var expected_seed: int = saved_seed.hash()
	if int(city_crafter.get("city_seed")) != expected_seed:
		push_error("Could not initialize the saved city seed: %s" % saved_seed)
		return false
	return true

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
	var grid_width: float = float(configuration.grid_width)
	var grid_height: float = float(configuration.grid_height)
	var block_size: float = float(configuration.block_size)
	var street_width: float = float(configuration.street_width)
	var city_center := city_crafter.global_position + Vector3(
		grid_width * (block_size + street_width) * 0.5,
		0.0,
		grid_height * (block_size + street_width) * 0.5
	)
	var city_extent: float = max(
		grid_width * (block_size + street_width),
		grid_height * (block_size + street_width)
	)

	camera_target = city_center
	camera_distance = city_extent * 1.3
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
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton

		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = mouse_button.pressed
			get_viewport().set_input_as_handled()

		elif mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mouse_button.pressed
			get_viewport().set_input_as_handled()

		elif mouse_button.pressed:
			if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_distance = max(camera_distance * 0.85, 25.0)
				update_camera_transform()
				get_viewport().set_input_as_handled()

			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_distance = min(camera_distance * 1.15, 10000.0)
				update_camera_transform()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion

		if orbiting:
			camera_yaw -= mouse_motion.relative.x * 0.01
			camera_pitch = clamp(
				camera_pitch + mouse_motion.relative.y * 0.01,
				deg_to_rad(10.0),
				deg_to_rad(85.0)
			)
			update_camera_transform()
			get_viewport().set_input_as_handled()

		elif panning:
			var camera_right := camera.global_transform.basis.x
			var camera_up := camera.global_transform.basis.y

			camera_right.y = 0.0
			camera_up.y = 0.0

			camera_right = camera_right.normalized()
			camera_up = camera_up.normalized()

			var pan_speed := camera_distance * 0.001
			camera_target -= camera_right * mouse_motion.relative.x * pan_speed
			camera_target += camera_up * mouse_motion.relative.y * pan_speed

			update_camera_transform()
			get_viewport().set_input_as_handled()

func setup_navigation() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CityNavigation"
	add_child(canvas_layer)

	var return_button := Button.new()
	return_button.name = "ReturnToMainMenu"
	return_button.text = "Return to Main Menu"
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

func _on_generation_complete() -> void:
	set_status("City generated")

func _on_return_to_main_menu_pressed() -> void:
	var error := get_tree().change_scene_to_file(
		"res://scenes/menus/main_menu/main.tscn"
	)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)

func _process(delta: float) -> void:
	var movement := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		movement.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		movement.z += 1.0
	if Input.is_key_pressed(KEY_A):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		movement.x += 1.0

	if movement != Vector3.ZERO:
		var speed := camera_distance * 0.75
		camera_target += movement.normalized() * speed * delta
		update_camera_transform()
