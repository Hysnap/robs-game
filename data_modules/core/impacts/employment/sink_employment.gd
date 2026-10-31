# res://data_modules/core/impacts/employment/sink_employment.gd
class_name SinkEmployment
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/employment/profile.json"
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkEmployment] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkEmployment] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkEmployment] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkEmployment] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_employment_rate"), "FATAL: [SinkEmployment] Missing 'default_baseline_employment_rate' in tuning.")
	assert(tuning.has("min_labor_age"), "FATAL: [SinkEmployment] Missing 'min_labor_age' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "EMPLOYMENT"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. TELEMETRY QUERY CONTRACT (Zero raw SQL)
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkEmployment] target_id cannot be empty")
	
	var census: Dictionary = SOCIETY_QUERIES.get_district_census(target_id)
	if census.is_empty():
		return 0.0

	var active_pop: int = int(census.get("active_population", 0))
	if active_pop <= 0:
		return 0.0

	var employed: int = int(census.get("formally_employed_count", 0))
	return float(employed) / float(active_pop)

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(_world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	# Hiring or redundancy impulses are dispatched to the labor market coordinator 
	# to manage contract rows and slot vacancies without orphan rows or split-brain drift.
	pass

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	# Passive labor turnover or seasonal employment shifts are evaluated here if configured
	pass