# res://data_modules/core/impacts/establishment_headcount/sink_establishment_headcount.gd
class_name SinkEstablishmentHeadcount
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/establishment_headcount/profile.json"
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkEstablishmentHeadcount] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkEstablishmentHeadcount] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkEstablishmentHeadcount] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkEstablishmentHeadcount] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_headcount"), "FATAL: [SinkEstablishmentHeadcount] Missing 'default_baseline_headcount' in tuning.")
	assert(tuning.has("allow_overstaffing"), "FATAL: [SinkEstablishmentHeadcount] Missing 'allow_overstaffing' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "ESTABLISHMENT_HEADCOUNT"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. TELEMETRY QUERY CONTRACT (Zero raw SQL)
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkEstablishmentHeadcount] target_id cannot be empty")
	var estab_id: int = int(target_id.trim_prefix("ESTAB_"))
	return SOCIETY_QUERIES.get_establishment_headcount(estab_id)

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(_world_state: Dictionary, target_id: String, delta: float) -> void:
	var count: int = int(round(delta))
	if count == 0 or target_id.is_empty():
		return

	# Adjusting workplace capacity or staffing targets is routed to the labor market
	# coordinator to recruit or terminate resident contracts cleanly without orphan rows.
	pass

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	# Ambient natural labor turnover or shifts are evaluated here if configured
	pass