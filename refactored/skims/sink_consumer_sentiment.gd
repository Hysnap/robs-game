# res://data_modules/core/impacts/consumer_sentiment/sink_consumer_sentiment.gd
class_name SinkConsumerSentiment
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/consumer_sentiment/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkConsumerSentiment] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkConsumerSentiment] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkConsumerSentiment] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkConsumerSentiment] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_sentiment"), "FATAL: [SinkConsumerSentiment] Missing 'default_baseline_sentiment' in tuning.")
	assert(tuning.has("passive_drift_per_tick"), "FATAL: [SinkConsumerSentiment] Missing 'passive_drift_per_tick' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "CONSUMER_SENTIMENT"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. TELEMETRY QUERY CONTRACT
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkConsumerSentiment] target_id cannot be empty")
	var tuning := _get_tuning()
	return float(tuning["default_baseline_sentiment"])

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(target_id):
		return

	var tuning := _get_tuning()
	var baseline: float = float(tuning["default_baseline_sentiment"])
	var current_val: float = float(districts[target_id].get("consumer_sentiment", baseline))
	var new_val: float = maxf(0.0, current_val + delta)
	districts[target_id]["consumer_sentiment"] = new_val

	# Synchronize legacy index for backward compatibility
	districts[target_id]["consumer_desperation_index"] = clampf(1.0 - new_val, 0.0, 1.0)

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(world_state: Dictionary) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var tuning := _get_tuning()
	var baseline: float = float(tuning["default_baseline_sentiment"])
	var drift: float = float(tuning["passive_drift_per_tick"])

	for dist_id in districts.keys():
		var dist: Dictionary = districts[dist_id]
		var current_val: float = float(dist.get("consumer_sentiment", baseline))
		if current_val > baseline:
			dist["consumer_sentiment"] = maxf(baseline, current_val - drift)
		elif current_val < baseline:
			dist["consumer_sentiment"] = minf(baseline, current_val + drift)

		dist["consumer_desperation_index"] = clampf(1.0 - float(dist["consumer_sentiment"]), 0.0, 1.0)