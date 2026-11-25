# res://scenes/menus/map_menu/map_menu.gd
extends Control

signal generate_city_requested(settings: Dictionary)

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const SHELL_REGISTRY = preload("res://scenes/ui/shell_host/shell_registry.gd")
const GAME_STATE_SCRIPT = preload("res://systems/game_state.gd")

@onready var radius_slider: HSlider = $BackGround/CenterMargin/CardPanel/VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/HSlider
@onready var radius_label: Label = $BackGround/CenterMargin/CardPanel/VBoxControlsContainer/VBoxCitySize/HBoxCityGrid/RadiusValueLabel

var _density_profiles: Array[Dictionary] = []
var _default_density_index: int = 0
var _selected_flavours: Array[String] = []
var _flavour_warning_label: Label = null

const DEFAULT_SETTINGS := {
	"city_name": "New City",
	"seed_id": "default-city",
	"city_radius": 14,
	"grid_width": 28,
	"grid_height": 39,
	"block_size": 200.0,
	"street_width": 25.0,
	"empty_block_chance": 5,
	"enable_multi_size_blocks": true,
	"large_block_chance": 0.20,
	"wide_block_chance": 0.2,
	"tall_block_chance": 0.2,
	"enable_edge_variations": true,
	"edge_variation_chance": 0.3,
	"max_edge_variation": 3,
	"enable_random_extensions": true,
	"random_extensions_count": 5,
	"extension_spawn_chance": 0.4,
	"district_mode": 1,
	"residential_ratio": 55,
	"commercial_ratio": 15,
	"industrial_ratio": 30,
	"noise_scale": 0.1,
	"enable_residential_subdivisions": false,
	"subdivision_mode": 0,
	"subdivision_layout": 0,
	"subdivision_street_width": 8,
	"residential_buildings_min": 6,
	"residential_buildings_max": 12,
	"residential_spacing": 10.0,
	"residential_border_margin": 10.0,
	"commercial_buildings_min": 6,
	"commercial_buildings_max": 12,
	"commercial_spacing": 10.0,
	"commercial_border_margin": 10,
	"industrial_buildings_min": 6,
	"industrial_buildings_max": 12,
	"industrial_spacing": 20.0,
	"industrial_border_margin": 5,
	"rotation_mode": 1,
	"scale_variation": 0.3,
	"generate_roads": true,
	"generate_intersections": true,
	"intersection_height_offset": 0.01,
	"generate_subdivision_roads": true,
	"generate_ground": true,
	"ground_height_offset": -0.1
}

func _ready() -> void:
	if RETRO_THEME.active_profile_id.is_empty():
		var active_shell: String = SHELL_REGISTRY.get_configured_shell_id()
		RETRO_THEME.load_all_catalog_profiles(active_shell)
	theme = RETRO_THEME.create_godot_theme()

	var bg := get_node_or_null("BackGround") as PanelContainer
	if bg:
		bg.add_theme_stylebox_override("panel", RETRO_THEME.create_cover_style())
	var card_panel := get_node_or_null("BackGround/CenterMargin/CardPanel") as PanelContainer
	if card_panel:
		card_panel.add_theme_stylebox_override("panel", RETRO_THEME.create_page_style())

	_build_flavour_pack_selector()
	_apply_localized_labels()
	_load_density_profiles_from_archetypes()
	apply_default_settings()

	var root_vbox := $BackGround/CenterMargin/CardPanel/VBoxControlsContainer
	root_vbox.get_node("Generate_Reload/HBoxContainer/ButtonGenerateCity").pressed.connect(_on_generate_city_pressed)
	root_vbox.get_node("Generate_Reload/HBoxContainer/ButtonBack").pressed.connect(_on_back_pressed)

	if radius_slider:
		radius_slider.value_changed.connect(_on_radius_slider_changed)
		_on_radius_slider_changed(radius_slider.value)

func _apply_localized_labels() -> void:
	var v := $BackGround/CenterMargin/CardPanel/VBoxControlsContainer
	v.get_node("Label").text = tr("UI_HDR_CITY_CREATOR")
	v.get_node("HBoxCityName/Label2").text = tr("UI_LBL_CITY_NAME")
	v.get_node("HBoxCityName/LineEditCityName").placeholder_text = tr("UI_HINT_CITY_NAME")
	v.get_node("HBoxSeedID/Label").text = tr("UI_LBL_SEED_ID")
	v.get_node("HBoxSeedID/seed_text").placeholder_text = tr("UI_HINT_SEED_ID")
	v.get_node("VBoxCitySize/Label3").text = tr("UI_HDR_CITY_SIZE")
	v.get_node("VBoxCitySize/HBoxCityGrid/RadiusSliderLabel").text = tr("UI_LBL_CITY_RADIUS")
	v.get_node("HBoxContainer6/Label").text = tr("UI_LBL_VACANT_BLOCK_CHANCE")
	v.get_node("Vbox2/Label2").text = tr("UI_HDR_ZONE_RATIOS")
	v.get_node("Vbox2/HBoxContainer/HBoxContainer7/Label").text = tr("UI_LBL_ZONE_RES")
	v.get_node("Vbox2/HBoxContainer/HBoxContainer2/Label").text = tr("UI_LBL_ZONE_COM")
	v.get_node("Vbox2/HBoxContainer/HBoxContainer9/Label").text = tr("UI_LBL_ZONE_IND")
	v.get_node("Vbox2/HBoxResidentialDensity/Label").text = tr("UI_LBL_RESIDENTIAL_DENSITY")
	v.get_node("Generate_Reload/HBoxContainer/ButtonGenerateCity").text = tr("UI_BTN_GENERATE_CITY")
	v.get_node("Generate_Reload/HBoxContainer/ButtonBack").text = tr("MENU_BACK")
	var flavour_box := v.get_node_or_null("VBoxFlavourPacks")
	if flavour_box:
		var hdr := flavour_box.get_node_or_null("FlavourHeaderLabel") as Label
		if hdr:
			hdr.text = tr("UI_HDR_FLAVOUR_PACKS")
		var sub := flavour_box.get_node_or_null("FlavourPromptLabel") as Label
		if sub:
			sub.text = tr("UI_LBL_FLAVOUR_PACKS")
	if _flavour_warning_label:
		_flavour_warning_label.text = tr("UI_WARN_MULTI_FLAVOUR_UNVERIFIED")

func _build_flavour_pack_selector() -> void:
	var v := $BackGround/CenterMargin/CardPanel/VBoxControlsContainer
	if v.has_node("VBoxFlavourPacks"):
		return
	var installed: Array[String] = GAME_STATE_SCRIPT.discover_installed_flavours()
	if installed.is_empty():
		return

	var box := VBoxContainer.new()
	box.name = "VBoxFlavourPacks"

	var hdr := Label.new()
	hdr.name = "FlavourHeaderLabel"
	box.add_child(hdr)

	var prompt := Label.new()
	prompt.name = "FlavourPromptLabel"
	box.add_child(prompt)

	var checks_flow := HFlowContainer.new()
	checks_flow.name = "FlavourCheckFlow"
	for slug in installed:
		var cb := CheckBox.new()
		cb.name = "FlavourCheck_%s" % slug
		var token := "UI_FLAVOUR_%s" % slug.to_upper()
		var translated := tr(token)
		cb.text = translated if translated != token else slug.capitalize().replace("_", " ")
		cb.toggled.connect(_on_flavour_toggled.bind(slug))
		checks_flow.add_child(cb)
	box.add_child(checks_flow)

	_flavour_warning_label = Label.new()
	_flavour_warning_label.name = "FlavourWarningLabel"
	_flavour_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flavour_warning_label.add_theme_color_override("font_color", RETRO_THEME.color_ink_warning)
	_flavour_warning_label.visible = false
	box.add_child(_flavour_warning_label)

	var gen_row := v.get_node_or_null("Generate_Reload")
	v.add_child(box)
	if gen_row != null:
		v.move_child(box, gen_row.get_index())

func _on_flavour_toggled(pressed: bool, slug: String) -> void:
	if pressed:
		if not _selected_flavours.has(slug):
			_selected_flavours.append(slug)
	else:
		_selected_flavours.erase(slug)
	if _flavour_warning_label:
		_flavour_warning_label.visible = _selected_flavours.size() > 1

func _on_radius_slider_changed(val: float) -> void:
	if radius_label:
		radius_label.text = str(int(val))

func apply_default_settings() -> void:
	var v := $BackGround/CenterMargin/CardPanel/VBoxControlsContainer
	v.get_node("HBoxCityName/LineEditCityName").text = DEFAULT_SETTINGS["city_name"]
	v.get_node("HBoxSeedID/seed_text").text = DEFAULT_SETTINGS["seed_id"]
	v.get_node("VBoxCitySize/HBoxCityGrid/GridWidth").value = DEFAULT_SETTINGS["grid_width"]
	v.get_node("VBoxCitySize/HBoxCityGrid/GridHeight").value = DEFAULT_SETTINGS["grid_height"]
	v.get_node("HBoxContainer5/BlockSize").value = DEFAULT_SETTINGS["block_size"]
	v.get_node("HBoxContainer6/VacantBlockChance").value = DEFAULT_SETTINGS["empty_block_chance"]
	v.get_node("Vbox2/HBoxContainer/HBoxContainer7/ResidentialRatio").value = DEFAULT_SETTINGS["residential_ratio"]
	v.get_node("Vbox2/HBoxContainer/HBoxContainer2/CommercialRatio").value = DEFAULT_SETTINGS["commercial_ratio"]
	v.get_node("Vbox2/HBoxContainer/HBoxContainer9/IndustrialRatio").value = DEFAULT_SETTINGS["industrial_ratio"]
	v.get_node("Vbox2/HBoxContainer11/ResidentialSubdivs").button_pressed = DEFAULT_SETTINGS["enable_residential_subdivisions"]
	var default_r: int = int(DEFAULT_SETTINGS["city_radius"])

	if radius_slider:
		radius_slider.value = default_r
	if radius_label:
		radius_label.text = str(default_r)

func _on_generate_city_pressed() -> void:
	var settings := build_settings_from_form()
	if settings.is_empty():
		return

	SystemLogger.log_info("Saving city settings: city_name=%s seed_id=%s" % [
		settings["city_name"],
		settings["seed_id"]
	])
	if not save_city_settings(settings):
		return

	get_tree().set_meta("pending_city_settings", settings)
	generate_city_requested.emit(settings)
	var error := get_tree().change_scene_to_file("res://scenes/menus/city_generator_loader.tscn")
	if error != OK:
		SystemLogger.log_error("Could not open generated city. Error code: %s" % error)
		push_error("Could not open generated city. Error code: %s" % error)

func _on_back_pressed() -> void:
	var main_scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert(not main_scene_path.is_empty(), "FATAL: [MapMenu] 'application/run/main_scene' is not configured in ProjectSettings.")
	var error := get_tree().change_scene_to_file(main_scene_path)
	if error != OK:
		SystemLogger.log_error("[MapMenu] Could not open main scene '%s': %s" % [main_scene_path, error])
		push_error("[MapMenu] Could not open main scene '%s': %s" % [main_scene_path, error])

func seed_text_to_int(seed_text: String) -> int:
	return seed_text.strip_edges().hash()

func save_city_settings(settings: Dictionary) -> bool:
	var directory := DirAccess.open("user://")
	if directory == null:
		SystemLogger.log_error("Could not access the user data directory.")
		push_error("Could not access the user data directory.")
		return false

	var directory_error := DirAccess.make_dir_recursive_absolute("user://cities")
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		SystemLogger.log_error("Could not create city save directory. Error code: %s" % directory_error)
		push_error("Could not create city save directory. Error code: %s" % directory_error)
		return false

	var city_name: String = sanitize_city_name(str(settings["city_name"]))
	var seed_id: String = sanitize_city_name(str(settings["seed_id"]))
	if city_name.is_empty() or seed_id.is_empty():
		SystemLogger.log_error("City name must contain at least one valid character.")
		push_error("City name must contain at least one valid character.")
		return false

	var file_name := "%s_%s" % [city_name, seed_id]
	if not write_json_file("user://cities/%s.json" % file_name, settings):
		return false
	return write_json_file("user://cities/last_generated.json", settings)

func load_city_settings(city_name: String, seed_id: String) -> Dictionary:
	var safe_name := sanitize_city_name(city_name)
	var safe_seed := sanitize_city_name(seed_id)
	var file_path := "user://cities/%s_%s.json" % [safe_name, safe_seed]
	if FileAccess.file_exists(file_path):
		return read_json_file(file_path)

	var legacy_file_path := "user://cities/%s.json" % safe_name
	return read_json_file(legacy_file_path)

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
		SystemLogger.log_error("City save file does not exist: %s" % file_path)
		push_error("City save file does not exist: %s" % file_path)
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		SystemLogger.log_error("Could not open city save file: %s" % file_path)
		push_error("Could not open city save file: %s" % file_path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		SystemLogger.log_error("City save file has invalid content: %s" % file_path)
		push_error("City save file has invalid content: %s" % file_path)
		return {}
	return parsed

func build_settings_from_form() -> Dictionary:
	var v := $BackGround/CenterMargin/CardPanel/VBoxControlsContainer
	var city_name: String = v.get_node("HBoxCityName/LineEditCityName").text.strip_edges()
	if city_name.is_empty():
		SystemLogger.log_error("Enter a city name before generating a city.")
		push_error("Enter a city name before generating a city.")
		return {}
	var seed_id: String = v.get_node("HBoxSeedID/seed_text").text.strip_edges()
	if seed_id.is_empty():
		SystemLogger.log_error("Enter a seed before generating a city.")
		push_error("Enter a seed before generating a city.")
		return {}
	var residential_percent: int = int(v.get_node("Vbox2/HBoxContainer/HBoxContainer7/ResidentialRatio").value)
	var commercial_percent: int = int(v.get_node("Vbox2/HBoxContainer/HBoxContainer2/CommercialRatio").value)
	var industrial_percent: int = int(v.get_node("Vbox2/HBoxContainer/HBoxContainer9/IndustrialRatio").value)
	var residential_ratio := float(residential_percent) / 100.0
	var commercial_ratio := float(commercial_percent) / 100.0
	var industrial_ratio := float(industrial_percent) / 100.0

	var ratio_total := residential_ratio + commercial_ratio + industrial_ratio
	if ratio_total <= 0.0:
		SystemLogger.log_error("At least one district ratio must be greater than zero.")
		push_error("At least one district ratio must be greater than zero.")
		return {}

	var settings := DEFAULT_SETTINGS.duplicate()
	settings["city_name"] = city_name
	settings["seed_id"] = seed_id
	settings["seed"] = seed_text_to_int(seed_id)
	settings["block_size"] = v.get_node("HBoxContainer5/BlockSize").value
	var vacant_block_percent: int = int(v.get_node("HBoxContainer6/VacantBlockChance").value)
	settings["empty_block_chance"] = float(vacant_block_percent) / 100.0
	var radius_val: int = int(radius_slider.value) if radius_slider else 14
	settings["city_radius"] = radius_val
	settings["grid_width"] = radius_val * 2
	settings["grid_height"] = radius_val * 2
	settings["residential_ratio"] = residential_ratio / ratio_total
	settings["commercial_ratio"] = commercial_ratio / ratio_total
	settings["industrial_ratio"] = industrial_ratio / ratio_total
	settings["enable_residential_subdivisions"] = v.get_node("Vbox2/HBoxContainer11/ResidentialSubdivs").button_pressed
	var density_opt = v.get_node("Vbox2/HBoxResidentialDensity/OptionDensityProfile")
	var profile_id: String = "balanced"
	if density_opt and density_opt.item_count > 0:
		var meta = density_opt.get_selected_metadata()
		if meta != null:
			profile_id = str(meta)
	settings["residential_density_profile"] = profile_id
	settings["active_flavours"] = _selected_flavours.duplicate()
	return settings

func _load_density_profiles_from_archetypes() -> void:
	_density_profiles.clear()

	var parsed: Dictionary = ScenarioManifestManager.load_module("archetypes")
	assert(parsed.has("setup") and parsed["setup"] is Dictionary,
		"FATAL: [MapMenu] Archetypes module missing 'setup' configuration block.")

	var density_cfg: Dictionary = parsed["setup"].get("density_profiles", {})
	var default_key: String = str(density_cfg.get("default_profile", "balanced"))
	var profiles_dict: Dictionary = density_cfg.get("profiles", {})

	var density_opt: OptionButton = $BackGround/CenterMargin/CardPanel/VBoxControlsContainer/Vbox2/HBoxResidentialDensity/OptionDensityProfile
	if density_opt:
		density_opt.clear()

	var idx: int = 0
	for key in profiles_dict.keys():
		var p_data: Dictionary = profiles_dict[key]
		var label_str: String = str(p_data.get("label", key))

		_density_profiles.append({
			"id": key,
			"label": label_str,
			"index": idx
		})

		if density_opt:
			density_opt.add_item(label_str, idx)
			density_opt.set_item_metadata(idx, key)

		if key == default_key:
			_default_density_index = idx

		idx += 1

	if density_opt and density_opt.item_count > 0:
		density_opt.select(_default_density_index)