# res://data_modules/core/impacts/corruption_tolerance/sink_corruption_tolerance.gd
class_name SinkCorruptionTolerance
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/corruption_tolerance/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkCorruptionTolerance] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkCorruptionTolerance] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkCorruptionTolerance] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkCorruptionTolerance] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_tolerance"), "FATAL: [SinkCorruptionTolerance] Missing 'default_baseline_tolerance' in tuning.")
	assert(tuning.has("passive_drift_per_tick"), "FATAL: [SinkCorruptionTolerance] Missing 'passive_drift_per_tick' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "CORRUPTION_TOLERANCE"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. TELEMETRY QUERY CONTRACT
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkCorruptionTolerance] target_id cannot be empty")
	# State is held in world_state districts; query_metric_value defaults to baseline if called standalone
	var tuning := _get_tuning()
	return float(tuning["default_baseline_tolerance"])

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(target_id):
		return

	var tuning := _get_tuning()
	var baseline: float = float(tuning["default_baseline_tolerance"])
	var current_val: float = float(districts[target_id].get("corruption_tolerance", baseline))
	districts[target_id]["corruption_tolerance"] = clampf(current_val + delta, 0.0, 1.0)

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(world_state: Dictionary) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var tuning := _get_tuning()
	var baseline: float = float(tuning["default_baseline_tolerance"])
	var drift: float = float(tuning["passive_drift_per_tick"])

	for dist_id in districts.keys():
		var dist: Dictionary = districts[dist_id]
		var current_val: float = float(dist.get("corruption_tolerance", baseline))
		if current_val > baseline:
			dist["corruption_tolerance"] = maxf(baseline, current_val - drift)
		elif current_val < baseline:
			dist["corruption_tolerance"] = minf(baseline, current_val + drift)