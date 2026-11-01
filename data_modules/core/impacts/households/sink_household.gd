# res://data_modules/core/impacts/households/sink_households.gd
class_name SinkHouseholds
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/households/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkHouseholds] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkHouseholds] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkHouseholds] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkHouseholds] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_households"), "FATAL: [SinkHouseholds] Missing 'default_baseline_households' in tuning.")
	assert(tuning.has("passive_growth_rate_per_tick"), "FATAL: [SinkHouseholds] Missing 'passive_growth_rate_per_tick' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "HOUSEHOLDS"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. TELEMETRY QUERY CONTRACT
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkHouseholds] target_id cannot be empty")
	var census: Dictionary = SocietyQueries.get_district_census(target_id)
	if census.has("total_households"):
		return int(census["total_households"])
	var tuning := _get_tuning()
	return int(tuning["default_baseline_households"])

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(target_id):
		return

	var dist: Dictionary = districts[target_id]
	var current_delta: float = float(dist.get("household_impulse_delta", 0.0))
	dist["household_impulse_delta"] = current_delta + delta

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	# Passive family consolidation, household splitting, or natural lifecycle drift
	pass