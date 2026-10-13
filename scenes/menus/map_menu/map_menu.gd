extends Control

signal generate_city_requested(settings: Dictionary)
signal recall_city_requested(city_name: String)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	apply_default_settings()

	$VBoxControlsContainer/Generate_Reload/HBoxContainer/ButtonGenerateCity.pressed.connect(
		_on_generate_city_pressed
	)
	$VBoxControlsContainer/Generate_Reload/HBoxContainer/ButtonRecallCity.pressed.connect(
		_on_recall_city_pressed
	)

const DEFAULT_SETTINGS := {
	"city_name": "New City",
	"seed_text": "default-city",
	"grid_width": 10,
	"grid_height": 10,
	"block_size": 200.0,
	"street_width": 25.0,
	"empty_block_chance": 0.01,
	"enable_multi_size_blocks": false,
	"large_block_chance": 0.15,
	"wide_block_chance": 0.1,
	"tall_block_chance": 0.1,
	"enable_edge_variations": true,
	"edge_variation_chance": 0.3,
	"max_edge_variation": 2,
	"enable_random_extensions": true,
	"random_extensions_count": 5,
	"extension_spawn_chance": 0.4,
	"district_mode": 0, ## ("Noise Based", "Zoned Areas", "Random Mix")
	"residential_ratio": 0.4,
	"commercial_ratio": 0.4,
	"industrial_ratio": 0.2,
	"noise_scale": 0.1,
	"enable_residential_subdivisions": true,
	"subdivision_mode": 1, # ("Fixed Layout", "Random Layout")
	"subdivision_layout": 0, # ("2X2", "2X3", "3x3")
	"subdivision_street_width": 8,
	"residential_buildings_min": 3,
	"residential_buildings_max": 6,
	"residential_spacing": 20.0,
	"residential_border_margin": 15.0,
	"commercial_buildings_min": 8,
	"commercial_buildings_max": 10,
	"commercial_spacing": 50.0,
	"commercial_border_margin": 25,
	"industrial_buildings_min": 25,
	"industrial_buildings_max": 30,
	"industrial_spacing": 35.0,
	"industrial_border_margin": 25.0,
	"rotation_mode": 1, # ("Free", "90 Degrees", "No Rotation")
	"scale_variation": 0.3,
	"generate_roads": true,
	"generate_intersections": true,
	"intersection_height_offset": 0.01,
	"generate_subdivision_roads": true,
	"generate_ground": true,
	"ground_height_offset": -0.1
}

func apply_default_settings() -> void:
	$VBoxControlsContainer/HBoxCityName/LineEditCityName.text = DEFAULT_SETTINGS["city_name"]
	$VBoxControlsContainer/HBoxSeedID/seed_text.text = DEFAULT_SETTINGS["seed_text"]

	$VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/HSliderGridWidth.value = DEFAULT_SETTINGS["grid_width"]
	$VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/HSliderGridHeight.value = DEFAULT_SETTINGS["grid_height"]
	$VBoxControlsContainer/HBoxContainer5/HSliderBlockSize.value = DEFAULT_SETTINGS["block_size"]
	$VBoxControlsContainer/HBoxContainer6/HSliderVacantBlockChance.value = DEFAULT_SETTINGS["empty_block_chance"]

	$VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer7/HSliderResidentialRatio.value = DEFAULT_SETTINGS["residential_ratio"]
	$VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer2/HSliderCommercialRatio.value = DEFAULT_SETTINGS["commercial_ratio"]
	$VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer9/HSliderIndustrialRatio.value = DEFAULT_SETTINGS["industrial_ratio"]

	$VBoxControlsContainer/Vbox2/HBoxContainer11/CheckButtonResidentialSubdivs.button_pressed = DEFAULT_SETTINGS["enable_residential_subdivisions"]

func _on_generate_city_pressed() -> void:
	var user_settings : Dictionary = read_settings()
	if user_settings.is_empty():
		return

	var settings := DEFAULT_SETTINGS.duplicate()
	settings.merge(user_settings)
	if not save_city_settings(settings):
		return

	get_tree().set_meta("pending_city_settings", settings)
	generate_city_requested.emit(settings)
	var error := get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")
	if error != OK:
		push_error("Could not open generated city. Error code: %s" % error)

func _on_recall_city_pressed() -> void:
	var city_name: String = $VBoxControlsContainer/HBoxCityName/LineEditCityName.text.strip_edges()
	if city_name.is_empty():
		push_error("Enter a city name before recalling a city.")
		return

	var settings := load_city_settings(city_name)
	if settings.is_empty():
		return
	if not write_json_file("user://cities/last_generated.json", settings):
		return

	recall_city_requested.emit(city_name)
	var error := get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")
	if error != OK:
		push_error("Could not open recalled city. Error code: %s" % error)

func seed_text_to_int(seed_text: String) -> int:
	return seed_text.strip_edges().hash()

func save_city_settings(settings: Dictionary) -> bool:
	var directory := DirAccess.open("user://")
	if directory == null:
		push_error("Could not access the user data directory.")
		return false

	var directory_error := DirAccess.make_dir_recursive_absolute("user://cities")
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Could not create city save directory. Error code: %s" % directory_error)
		return false

	var city_name: String = sanitize_city_name(str(settings["city_name"]))
	if city_name.is_empty():
		push_error("City name must contain at least one valid character.")
		return false

	if not write_json_file("user://cities/%s.json" % city_name, settings):
		return false
	return write_json_file("user://cities/last_generated.json", settings)

func load_city_settings(city_name: String) -> Dictionary:
	var safe_name := sanitize_city_name(city_name)
	var file_path := "user://cities/%s.json" % safe_name
	return read_json_file(file_path)

func sanitize_city_name(city_name: String) -> String:
	var safe_name := city_name.strip_edges().to_lower()
	safe_name = safe_name.replace(" ", "_")
	return safe_name.validate_filename()

func write_json_file(file_path: String, settings: Dictionary) -> bool:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open city save file: %s. Error code: %s" % [
			file_path,
			FileAccess.get_open_error()
		])
		return false
	file.store_string(JSON.stringify(settings))
	if file.get_error() != OK:
		push_error("Could not write city save file: %s. Error code: %s" % [
			file_path,
			file.get_error()
		])
		file.close()
		return false
	file.close()
	return true

func read_json_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("City save file does not exist: %s" % file_path)
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Could not open city save file: %s" % file_path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("City save file has invalid content: %s" % file_path)
		return {}
	return parsed

func read_settings() -> Dictionary:
	var city_name: String = $VBoxControlsContainer/HBoxCityName/LineEditCityName.text.strip_edges()
	if city_name.is_empty():
		push_error("Enter a city name before generating a city.")
		return {}
	var seed_text: String = $VBoxControlsContainer/HBoxSeedID/seed_text.text.strip_edges()
	if seed_text.is_empty():
		push_error("Enter a seed before generating a city.")
		return {}
	var residential_ratio: float = $VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer7/HSliderResidentialRatio.value
	var commercial_ratio: float = $VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer2/HSliderCommercialRatio.value
	var industrial_ratio: float = $VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer9/HSliderIndustrialRatio.value

	var ratio_total := residential_ratio + commercial_ratio + industrial_ratio
	if ratio_total <= 0.0:
		push_error("At least one district ratio must be greater than zero.")
		return {}

	return {
		"city_name": city_name,
		"seed_text": seed_text,
		"seed": seed_text_to_int(seed_text),
		"grid_width": int($VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/HSliderGridWidth.value),
		"grid_height": int($VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/HSliderGridHeight.value),
		"block_size": $VBoxControlsContainer/HBoxContainer5/HSliderBlockSize.value,
		"empty_block_chance": $VBoxControlsContainer/HBoxContainer6/HSliderVacantBlockChance.value,
		"residential_ratio": residential_ratio / ratio_total,
		"commercial_ratio": commercial_ratio / ratio_total,
		"industrial_ratio": industrial_ratio / ratio_total,
		"enable_residential_subdivisions": $VBoxControlsContainer/Vbox2/HBoxContainer11/CheckButtonResidentialSubdivs.button_pressed
	}
