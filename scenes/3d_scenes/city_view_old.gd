# res://scenes/3d_scenes/city_view.gd
extends Node3D

@onready var city_crafter: Node3D = $CityCrafter
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
	
	# 1. Retrieve settings from SceneTree metadata (map_menu) or fallback to last_generated.json
	var settings := load_pending_city_settings()
	if settings.is_empty():
		settings = load_last_generated_settings()
		
	# 2. Apply settings (or fall back to defaults)
	var gen_seed := "default-city"
	if not settings.is_empty():
		apply_settings(settings)
		gen_seed = get_seed_from_settings(settings)
	else:
		# Read directly from CityCrafter node export
		if "seed_id" in city_crafter and not str(city_crafter.seed_id).is_empty():
			gen_seed = city_crafter.seed_id
			
	# 3. Setup Camera and Lighting for radial layout
	setup_view()
	
	# 4. Connect progress signal for HUD status text
	if city_crafter.has_signal("generation_progress"):
		city_crafter.generation_progress.connect(func(_c, _t, stage): set_status(stage))
		
	# 5. Await the async generator directly
	var already_generated: bool = city_crafter.get_child_count() > 5 and not GameState.world_state.get("districts", {}).is_empty()

	if not already_generated:
		set_status("Generating city layout...")
		await city_crafter.generate_city_async(gen_seed)
		_on_generation_complete()
	else:
		set_status("City ready.")

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
	var seed_value = settings.get("seed_id", settings.get("seed_text", settings.get("seed", "")))
	return str(seed_value).strip_edges()

func apply_settings(settings: Dictionary) -> bool:
	var configuration = city_crafter.get("city_configuration")
	if configuration == null:
		push_error("CityCrafter has no city configuration.")
		return false

	# Full list of supported parameters including the new European radial parameters
	var property_names := [
		"city_radius", "radial_jitter", "enable_building_spawning",
		"spawn_local_government", "spawn_hospital", "spawn_university",
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
		if settings.has(property_name) and property_name in configuration:
			configuration.set(property_name, settings[property_name])

	# Assign the seed to the CityCrafter node (NOT the configuration resource)
	var saved_seed := get_seed_from_settings(settings)
	if not saved_seed.is_empty():
		city_crafter.set("seed_id", saved_seed)
		
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
	var block_size: float = float(configuration.block_size) if configuration and "block_size" in configuration else 40.0
	var street_width: float = float(configuration.street_width) if configuration and "street_width" in configuration else 8.0
	var cell_extent := block_size + street_width
	
	var city_extent: float = 800.0
	
	# Radial centering: The town center is at (0, 0)
	if configuration and "city_radius" in configuration:
		var radius: float = float(configuration.city_radius)
		camera_target = city_crafter.global_position # Centered on (0,0)
		city_extent = radius * 2.0 * cell_extent
	else:
		# Fallback to legacy rectangular centering if non-radial
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
	# Toggle Filofax on Tab key
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if filofax_ui:
			filofax_ui.visible = not filofax_ui.visible
			if filofax_ui.visible:
				filofax_ui.update_display(GameState.world_state.get("filofax_cache", {}))
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton

		# 1. Camera Orbit (Right Click)
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = mouse_button.pressed
			get_viewport().set_input_as_handled()

		# 2. Camera Pan (Middle Click)
		elif mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mouse_button.pressed
			get_viewport().set_input_as_handled()

		# 3. District Selection Raycast (Left Click)
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			var mouse_pos := get_viewport().get_mouse_position()
			var from := camera.project_ray_origin(mouse_pos)
			var to := from + camera.project_ray_normal(mouse_pos) * 5000.0 # Extended range for zoomed out views
		
			var space_state := get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(from, to)
			var result := space_state.intersect_ray(query)
		
			if result and result.collider:
				var hit_node: Node = result.collider
				# Check both collider and its parent in case collision is nested
				if not hit_node.has_meta("block_id") and hit_node.get_parent() and hit_node.get_parent().has_meta("block_id"):
					hit_node = hit_node.get_parent()

				if hit_node.has_meta("block_id"):
					var block_id: String = hit_node.get_meta("block_id")
					
					# 1. Update GameState selection pointer
					GameState.set_selected_district(block_id)
					
					# 2. Bring up the Filofax and focus the district tab
					if filofax_ui:
						filofax_ui.visible = true
						filofax_ui.display_district_docket(block_id)
						
					get_viewport().set_input_as_handled()

		# 4. Camera Zoom (Mouse Wheel)
		elif mouse_button.pressed:
			if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_distance = max(camera_distance * 0.85, 25.0)
				update_camera_transform()
				get_viewport().set_input_as_handled()

			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_distance = min(camera_distance * 1.15, 10000.0)
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

func _on_generation_complete() -> void:
	var current_seed: String = city_crafter.seed_id
	var stored_seed: String = str(GameState.world_state.get("metadata", {}).get("active_seed", ""))

	var seed_changed: bool = (stored_seed != "" and stored_seed != current_seed)

	# 1. Stamp active seed into the global singleton
	GameState.world_state["metadata"]["active_seed"] = current_seed
	
	# 2. Ingest spatial districts from CityCrafter into GameState.world_state
	CitySpatialAdapter.ingest_citycrafter_generation(city_crafter, GameState.world_state, current_seed)
	
	# 3. Guard: Check if society exists FOR THIS SEED
	if seed_changed or not DBManager.is_society_populated(current_seed):
		set_status("Populating civic establishments & society...")
		SocialNetworkGenerator.generate_city_society(GameState.world_state, current_seed)
	else:
		print("[CityView] Society for seed '%s' already loaded in SQLite. Skipping procedural generation." % current_seed)
	
	set_status("City generated")
	
	# 4. Run our sense-check audit
	run_district_sense_check(GameState.world_state)

func run_district_sense_check(world_state: Dictionary) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	var total_count: int = districts.size()
	
	if total_count == 0:
		push_error("[AUDIT FAILED] No districts were ingested into world_state!")
		return

	var type_counts: Dictionary = {}
	var total_population: int = 0
	var income_samples: Array = []
	var zhi_samples: Array = []
	var sample_dockets: Array = []

	for dist_id in districts.keys():
		var d = districts[dist_id]
		var dtype = d.get("district_type", "unknown")
		
		# Count types
		type_counts[dtype] = type_counts.get(dtype, 0) + 1
		
		# Aggregate demographics
		var pop = d.get("population", 0)
		var inc = d.get("avg_disposable_income", 0.0)
		var zhi = d.get("zone_health_index", 0.0)
		
		total_population += pop
		income_samples.append(inc)
		zhi_samples.append(zhi)
		
		# Save a few sample entries to print
		if sample_dockets.size() < 4:
			sample_dockets.append(d)

	# Calculate averages
	income_samples.sort()
	zhi_samples.sort()
	var mid_income_idx: int = income_samples.size() >> 1
	var mid_zhi_idx: int = zhi_samples.size() >> 1

	var median_income = income_samples[mid_income_idx] if not income_samples.is_empty() else 0.0
	var median_zhi = zhi_samples[mid_zhi_idx] if not zhi_samples.is_empty() else 0.0

	# Print the Executive Sanity Dossier
	print("\n=======================================================")
	print("	   CITY GENERATION STATISTICAL SENSE-CHECK		 ")
	print("=======================================================")
	print("Total Ingested Districts: %d" % total_count)
	print("Total Town Population:	~%d residents" % total_population)
	print("Median Weekly Income:	 £%.2f / week" % median_income)
	print("Median Zone Health (ZHI): %.1f / 100" % median_zhi)
	print("-------------------------------------------------------")
	print("District Breakdown:")
	for dtype in type_counts.keys():
		var pct = (float(type_counts[dtype]) / float(total_count)) * 100.0
		print(" - %-24s: %3d blocks (%.1f%%)" % [dtype, type_counts[dtype], pct])
	print("-------------------------------------------------------")
	print("Sample Ingested District Dockets:")
	for sample in sample_dockets:
		print(" • [%s] \"%s\"" % [sample.get("district_type"), sample.get("display_name")])
		print("	Pop: %d | Unemp: %.1f%% | Income: £%.2f/wk | ZHI: %.1f | Heat: %.2f" % [
			sample.get("population"),
			sample.get("unemployment_rate") * 100.0,
			sample.get("avg_disposable_income"),
			sample.get("zone_health_index"),
			sample.get("actual_police_heat")
		])
	print("=======================================================\n")
