# res://scenes/menus/city_generator_loader.gd
extends Control

@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var city_crafter: Node3D = null

func _ready() -> void:
	# 1. Instantiate the generator directly (cleaner, avoids loading camera/viewer logic)
	city_crafter = CustomCityCrafter.new()
	city_crafter.name = "CityCrafter"
	
	# Load the European configuration resource
	var config_res = load("res://resources/city/default_european_city.tres")
	if config_res:
		city_crafter.city_configuration = config_res.duplicate()
		
	add_child(city_crafter)
	await get_tree().process_frame

	# 2. Extract settings passed from MapMenu
	var settings: Dictionary = {}
	if get_tree().has_meta("pending_city_settings"):
		settings = get_tree().get_meta("pending_city_settings")
		get_tree().remove_meta("pending_city_settings")
	
	var gen_seed := "midlands-1984"
	if not settings.is_empty():
		gen_seed = str(settings.get("seed_id", settings.get("seed", "midlands-1984"))).strip_edges()
		_apply_settings_to_crafter(settings)
	
	progress_bar.value = 0.0
	status_label.text = tr("LOADER_STATUS_INIT")
	
	if city_crafter.has_signal("generation_progress"):
		city_crafter.generation_progress.connect(_on_crafter_progress)
		
	# 3. Start pipeline - exactly once!
	_start_pipeline(gen_seed)

func _on_crafter_progress(current: int, total: int, stage: String) -> void:
	status_label.text = stage
	if total > 0:
		progress_bar.value = (float(current) / float(total)) * 40.0

func _start_pipeline(gen_seed: String) -> void:
	# Step 1: Spatial Mesh/Grid Generation
	status_label.text = tr("LOADER_STATUS_STREETS")
	await city_crafter.generate_city_async(gen_seed)
	
	# Step 2: Classify Districts into GameState
	progress_bar.value = 50.0
	status_label.text = tr("LOADER_STATUS_DISTRICTS")
	await get_tree().process_frame
	
	GameState.initialize_fresh_state()
	GameState.world_state["metadata"]["active_seed"] = gen_seed
	CitySpatialAdapter.ingest_citycrafter_generation(city_crafter, GameState.world_state, gen_seed)
	
	# Step 3: SQLite Society Pipeline
	progress_bar.value = 75.0
	status_label.text = tr("LOADER_STATUS_SOCIETY")
	await get_tree().process_frame
	
	SocialNetworkGenerator.generate_city_society(GameState.world_state, gen_seed, true)
	
	# Step 4: Cache visual layout into GameState & Save
	progress_bar.value = 90.0
	status_label.text = tr("LOADER_STATUS_PERSIST")
	await get_tree().process_frame
	
	if city_crafter.has_method("export_visual_layout"):
		GameState.world_state["city_layout"] = city_crafter.export_visual_layout()
	
	SaveManager.save_game("slot_01", city_crafter)
	
	progress_bar.value = 100.0
	status_label.text = tr("LOADER_STATUS_READY")
	await get_tree().create_timer(0.4).timeout
	
	# Step 5: Transition to Scene Viewer
	get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")

func _apply_settings_to_crafter(settings: Dictionary) -> void:
	var configuration = city_crafter.get("city_configuration")
	if configuration == null:
		return
	for key in settings.keys():
		if key in configuration:
			configuration.set(key, settings[key])
