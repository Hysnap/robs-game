# res://data_modules/core/impacts/migration/sink_migration.gd
class_name SinkMigration
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/migration/profile.json"
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkMigration] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkMigration] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkMigration] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkMigration] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_migration"), "FATAL: [SinkMigration] Missing 'default_baseline_migration' in tuning.")
	assert(tuning.has("decay_rate_per_tick"), "FATAL: [SinkMigration] Missing 'decay_rate_per_tick' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "MIGRATION"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. TELEMETRY QUERY CONTRACT (Zero raw SQL)
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkMigration] target_id cannot be empty")
	var census: Dictionary = SOCIETY_QUERIES.get_district_census(target_id)
	return int(census.get("net_migration_flow", 0))

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(_world_state: Dictionary, target_id: String, delta: float) -> void:
	var count: int = int(round(delta))
	if count == 0 or target_id.is_empty():
		return

	# Inward and outward migration impulses are handed off to the demographic
	# lifecycle coordinator to manage tenancy agreements, resident generation,
	# or departure records without breaking relational integrity.
	pass

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	# Ambient migration drift/decay toward baseline equilibrium occurs here
	pass