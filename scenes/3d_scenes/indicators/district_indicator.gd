# res://scenes/3d_scenes/indicators/district_indicator.gd
class_name DistrictIndicator
extends Node3D

@onready var survey_tick: MeshInstance3D = $SurveyTick
@onready var civic_billboard: Label3D = $CivicBillboard

@export var color_verified: Color = Color("#2ecc71")
@export var color_stale: Color = Color("#e67e22")

var _tick_material: StandardMaterial3D

func _ready() -> void:
	_tick_material = StandardMaterial3D.new()
	_tick_material.emission_enabled = true
	_tick_material.emission_energy_multiplier = 0.9
	if survey_tick != null:
		survey_tick.material_override = _tick_material

## Applies district intelligence data to update visual presentation
func update_from_view_data(view_data: Dictionary) -> void:
	if survey_tick == null or civic_billboard == null:
		return

	var intel_status: String = str(view_data.get("intel_status", view_data.get("intel_status_token", "INTEL_STATUS_UNEXPLORED")))
	var is_known: bool = bool(view_data.get("is_known", false))
	var is_home: bool = bool(view_data.get("is_home_turf", false))
	var is_landmark: bool = bool(view_data.get("is_public_landmark", false))
	var civic_features: Array = view_data.get("civic_features_list", [])

	# Unexplored non-landmark: completely hidden
	if not is_known and intel_status == "INTEL_STATUS_UNEXPLORED":
		visible = false
		return

	visible = true
	var is_verified: bool = (intel_status == "INTEL_STATUS_VERIFIED" or intel_status == "VERIFIED")

	# 1. Survey Tick Presentation
	if is_home:
		survey_tick.visible = true
		survey_tick.scale = Vector3(1.6, 1.2, 1.6)
		_tick_material.albedo_color = color_verified
		_tick_material.emission = color_verified
		_tick_material.emission_energy_multiplier = 1.3
	elif is_verified:
		survey_tick.visible = true
		survey_tick.scale = Vector3(1.0, 1.0, 1.0)
		_tick_material.albedo_color = color_verified
		_tick_material.emission = color_verified
		_tick_material.emission_energy_multiplier = 0.7
	else:
		survey_tick.visible = true
		survey_tick.scale = Vector3(1.0, 1.0, 1.0)
		_tick_material.albedo_color = color_stale
		_tick_material.emission = color_stale
		_tick_material.emission_energy_multiplier = 0.7

	# 2. Billboard Text Presentation
	if is_home:
		civic_billboard.visible = true
		civic_billboard.text = "★ HOME TURF"
		civic_billboard.modulate = color_verified
	elif is_landmark or not civic_features.is_empty():
		var label_text: String = str(civic_features[0]) if not civic_features.is_empty() else str(view_data.get("type_title", "Landmark"))
		civic_billboard.visible = true
		civic_billboard.text = "🏛 %s" % label_text
		civic_billboard.modulate = Color("#F4EEDB")
	else:
		civic_billboard.visible = false