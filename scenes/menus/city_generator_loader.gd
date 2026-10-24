# res://scenes/menus/city_generator_loader.gd
extends Control

@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var city_crafter: Node3D = null
var monitor: ProgressMonitor = null

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

	# 2. Setup Reusable Progress Monitor
	monitor = ProgressMonitor.new()
	monitor.progress_updated.connect(_on_monitor_progress_updated)

	monitor.configure_stages([
		{ "id": "STREETS",   "title": "Mapping Arterial Infrastructure", "weight": 30.0 },
		{ "id": "DISTRICTS", "title": "Classifying Urban Wards",         "weight": 10.0 },
		{ "id": "SOCIETY",   "title": "Seeding Living Population & Ties","weight": 50.0 },
		{ "id": "SAVE",      "title": "Finalizing Municipal Dossier",    "weight": 10.0 }
	])

	# 3. Extract settings passed from MapMenu
	var settings: Dictionary = {}
	if get_tree().has_meta("pending_city_settings"):
		settings = get_tree().get_meta("pending_city_settings")
		get_tree().remove_meta("pending_city_settings")
	
	var gen_seed := "midlands-1984"
	if not settings.is_empty():
		gen_seed = str(settings.get("seed_id", settings.get("seed", "midlands-1984"))).strip_edges()
		_apply_settings_to_crafter(settings)

	# 4 Connect citycrafter's raw progress signal into our  monitor	
	if city_crafter.has_signal("generation_progress"):
		city_crafter.generation_progress.connect(func(curr, tot, stage_name):
			monitor.update_sub_progress(float(curr), float(tot), stage_name)
		)

	_start_pipeline(gen_seed)

func _on_monitor_progress_updated(percent: float, stage_title: String, detail_text: String) -> void:
	progress_bar.value = percent
	status_label.text = "%s: %s" % [stage_title, detail_text] if detail_text != "" else stage_title

func _start_pipeline(gen_seed: String) -> void:
	# Step 1: Spatial Mesh/Grid Generation
	monitor.begin_stage("STREETS", "Laying street grid...")
	await city_crafter.generate_city_async(gen_seed)
	
	# Step 2: Classify Districts into GameState
	monitor.begin_stage("DISTRICTS", "Parsing block topology...")
	await get_tree().process_frame
	
	GameState.initialize_fresh_state()
	GameState.world_state["metadata"]["active_seed"] = gen_seed
	CitySpatialAdapter.ingest_citycrafter_generation(city_crafter, GameState.world_state, gen_seed)
	
	# Step 3: SQLite Society Pipeline
	monitor.begin_stage("SOCIETY", "Generating establishments, households & Dunbar network...")
	await get_tree().process_frame
	
	# Execute society generation pass
	await SocialNetworkGenerator.generate_city_society(GameState.world_state,
														gen_seed,
														true,
														func(c, t, d): monitor.update_sub_progress(c, t, d)
														)
	
	# Step 4: Cache visual layout into GameState & Save
	monitor.begin_stage("SAVE", "Writing game save slot_01...")
	await get_tree().process_frame
	
	if city_crafter.has_method("export_visual_layout"):
		GameState.world_state["city_layout"] = city_crafter.export_visual_layout()
	
	SaveManager.save_game("slot_01", city_crafter)
	
	monitor.complete("City Ready")
	await get_tree().create_timer(0.3).timeout
	
	# Step 5: Transition to Scene Viewer
	get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")

func _apply_settings_to_crafter(settings: Dictionary) -> void:
	var configuration = city_crafter.get("city_configuration")
	if configuration == null:
		return
	for key in settings.keys():
		if key in configuration:
			configuration.set(key, settings[key])
