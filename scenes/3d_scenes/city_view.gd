extends Node3D

@onready var city_crafter: Node3D = $ExampleScene/CityCrafter

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
	var status_text: String = "Generating city: %s" % str(settings.get("seed_text", "unknown"))
	set_status(status_text)
	city_crafter.connect("generation_complete", _on_generation_complete)
	city_crafter.call_deferred("generate_city_async")

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

	if not settings.has("seed_text"):
		push_error("The saved city does not contain a seed.")
		return false
	var saved_seed: String = str(settings["seed_text"]).strip_edges()
	if saved_seed.is_empty():
		push_error("The saved city has an empty seed.")
		return false
	city_crafter.call("set_seed_id", saved_seed)
	if str(city_crafter.get("seed_id")) != saved_seed:
		push_error("Could not apply the saved city seed: %s" % saved_seed)
		return false
	return true

func setup_view() -> void:
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)

	var light := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = "DirectionalLight3D"
		add_child(light)

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

	camera.global_position = city_center + Vector3(0.0, city_extent * 0.9, city_extent * 0.9)
	camera.look_at(city_center)
	camera.current = true
	camera.fov = 55.0

	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true

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
