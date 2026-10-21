# res://scripts/world/custom_city_configuration.gd
@tool
class_name CustomCityConfiguration
extends CityConfiguration

# --- RADIAL GROWTH PARAMETERS ---
@export_group("European Layout")
@export_range(3, 40, 1) var city_radius: int = 14
@export_range(0.0, 1.0, 0.05) var radial_jitter: float = 0.35
@export var enable_building_spawning: bool = false

# --- CIVIC ANCHORS ---
@export_group("Civic Facilities")
@export var spawn_local_government: bool = true
@export var spawn_hospital: bool = true
@export var spawn_university: bool = true

# --- DISTRICT GROUND MATERIALS ---
@export_group("District Materials")
@export var high_rise_ground_material: Material
@export var low_rise_ground_material: Material
@export var civic_ground_material: Material

# --- BUILDING ARRAYS (For future visual instantiation) ---
@export_group("Extended Building Pools")
@export var high_rise_buildings: Array[PackedScene] = []
@export var low_rise_buildings: Array[PackedScene] = []
@export var civic_buildings: Array[PackedScene] = []

func _init() -> void:
	load_rules_from_config()

## Ingests baseline defaults from business_rules.cfg without hardcoding literals
func load_rules_from_config(config_path: String = "res://data_modules/core/business_rules.cfg") -> void:
	if not FileAccess.file_exists(config_path):
		return
		
	var cfg := ConfigFile.new()
	if cfg.load(config_path) == OK and cfg.has_section("map_layout"):
		city_radius = int(cfg.get_value("map_layout", "default_city_radius", city_radius))
		radial_jitter = float(cfg.get_value("map_layout", "default_radial_jitter", radial_jitter))
		enable_building_spawning = bool(cfg.get_value("map_layout", "enable_building_spawning", enable_building_spawning))
		
		spawn_local_government = bool(cfg.get_value("map_layout", "spawn_local_government", spawn_local_government))
		spawn_hospital = bool(cfg.get_value("map_layout", "spawn_hospital", spawn_hospital))
		spawn_university = bool(cfg.get_value("map_layout", "spawn_university", spawn_university))

## Validation override: allows generating roads & districts even if building arrays are empty
func is_valid() -> bool:
	if not enable_building_spawning:
		return true
	return super.is_valid()