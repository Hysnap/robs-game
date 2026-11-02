# res://data_modules/crime/impacts/police_heat/sink_heat.gd
class_name SinkPoliceHeat
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/police_heat/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkPoliceHeat] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkPoliceHeat] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkPoliceHeat] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkPoliceHeat] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("passive_cooling_per_week"), "FATAL: [SinkPoliceHeat] Missing 'passive_cooling_per_week' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "POLICE_HEAT"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, district_id: String, delta: float) -> void:
	if delta == 0.0 or district_id.is_empty():
		return

	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(district_id):
		return

	var dist: Dictionary = districts[district_id]
	var current_heat: float = float(dist.get("actual_police_heat", 0.0))
	dist["actual_police_heat"] = clampf(current_heat + delta, 0.0, 1.0)

## 3. AMBIENT DISSIPATION CONTRACT
static func process_ambient(world_state: Dictionary) -> void:
	var tuning: Dictionary = _get_tuning()
	var passive_cooling: float = float(tuning["passive_cooling_per_week"])

	var districts: Dictionary = world_state.get("districts", {})
	for dist_id in districts.keys():
		var dist: Dictionary = districts[dist_id]
		var cur: float = float(dist.get("actual_police_heat", 0.0))
		if cur > 0.0:
			dist["actual_police_heat"] = maxf(0.0, cur - passive_cooling)