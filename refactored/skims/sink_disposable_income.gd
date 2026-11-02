# res://data_modules/core/impacts/income/sink_income.gd
class_name SinkIncome
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/income/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkIncome] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkIncome] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkIncome] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkIncome] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_income"), "FATAL: [SinkIncome] Missing 'default_baseline_income' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "INCOME"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(_world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	# Mutates ground-truth SQLite records only (No detached static average writes)
	if target_id.begins_with("HH_"):
		var hh_id: int = int(target_id.trim_prefix("HH_"))
		var sql := "UPDATE households SET weekly_income_modifier = weekly_income_modifier + (%f) WHERE household_id = %d;" % [delta, hh_id]
		DBManager.query_rows(sql)
	else:
		# District or macro catchment wage/expense shift (e.g. factory closure, municipal tax)
		var sql := "UPDATE households SET weekly_income_modifier = weekly_income_modifier + (%f) WHERE district_id = '%s';" % [delta, target_id]
		DBManager.query_rows(sql)

## 3. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	# Mean reversion or macroeconomic inflation drift can be evaluated here if configured
	pass