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

	generate_city_requested.emit(settings)

func _on_recall_city_pressed() -> void:
	var city_name: String = $VBoxControlsContainer/HBoxCityName/LineEditCityName.text.strip_edges()
	if city_name.is_empty():
		push_error("Enter a city name before recalling a city.")
		return

	recall_city_requested.emit(city_name)

func seed_text_to_int(seed_text: String) -> int:
	return seed_text.strip_edges().hash()

func save_city_settings(settings: Dictionary) -> void:
	var directory := DirAccess.open("user://")
	if directory == null:
		push_error("Could not access the user data directory.")
		return

	if not DirAccess.dir_exists_absolute("user://cities"):
		var error := DirAccess.make_dir_absolute("user://cities")
		if error != OK:
			push_error("Could not create city save directory.")
			return

	var city_name: String = str(settings["city_name"]).to_lower().replace(" ", "_")
	var file_path := "user://cities/%s.json" % city_name
	var file := FileAccess.open(file_path, FileAccess.WRITE)

	if file == null:
		push_error("Could not open city save file: %s" % file_path)
		return
	
	file.store_string(JSON.stringify(settings))
	file.close()

func read_settings() -> Dictionary:
	var city_name: String = $VBoxControlsContainer/HBoxCityName/LineEditCityName.text.strip_edges()
	if city_name.is_empty():
		push_error("Enter a city name before generating a city.")
		return {}
	var residential_ratio: float = $VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer7/HSliderResidentialRatio.value
	var commercial_ratio: float = $VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer2/HSliderCommercialRatio.value
	var industrial_ratio: float = $VBoxControlsContainer/Vbox2/HBoxContainer/HBoxContainer9/HSliderIndustrialRatio.value

	var ratio_total := residential_ratio + commercial_ratio + industrial_ratio
	if ratio_total <= 0.0:
		push_error("At least one district ratio must be greater than zero.")
		return {}

	return {
		"city_name": $VBoxControlsContainer/HBoxCityName/LineEditCityName.text.strip_edges(),
		"seed_text": str($VBoxControlsContainer/HBoxSeedID/seed_text.text),
		"seed": seed_text_to_int(
			str($VBoxControlsContainer/HBoxSeedID/seed_text.text)
		),
		"grid_width": int($VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/HSliderGridWidth.value),
		"grid_height": int($VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/HSliderGridHeight.value),
		"block_size": $VBoxControlsContainer/HBoxContainer5/HSliderBlockSize.value,
		"empty_block_chance": $VBoxControlsContainer/HBoxContainer6/HSliderVacantBlockChance.value,
		"residential_ratio": residential_ratio / ratio_total,
		"commercial_ratio": commercial_ratio / ratio_total,
		"industrial_ratio": industrial_ratio / ratio_total,
		"enable_residential_subdivisions": $VBoxControlsContainer/Vbox2/HBoxContainer11/CheckButtonResidentialSubdivs.button_pressed
	}
