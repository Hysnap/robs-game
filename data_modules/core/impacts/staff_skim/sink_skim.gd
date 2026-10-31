# res://data_modules/crime/impacts/staff_skim/sink_skim.gd
class_name SinkSkim
extends ImpactSinkBase

const CONDITION_EVALUATOR = preload("res://systems/condition_evaluator.gd")
const PROFILE_PATH := "res://data_modules/crime/impacts/staff_skim/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkSkim] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkSkim] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkSkim] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkSkim] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("loyalty_skim_threshold"), "FATAL: [SinkSkim] Missing 'loyalty_skim_threshold' in tuning.")
	assert(tuning.has("loyalty_operator"), "FATAL: [SinkSkim] Missing 'loyalty_operator' in tuning.")
	assert(tuning.has("ambient_skim_increment"), "FATAL: [SinkSkim] Missing 'ambient_skim_increment' in tuning.")
	assert(tuning.has("max_ambient_skim"), "FATAL: [SinkSkim] Missing 'max_ambient_skim' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "STAFF_SKIM"

static func get_target_scope() -> String:
	return "ACTOR"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	var actor_record: Dictionary = {}
	if world_state.get("staff", {}).has(target_id):
		actor_record = world_state["staff"][target_id]
	elif world_state.get("counterparties", {}).has(target_id):
		actor_record = world_state["counterparties"][target_id]

	if actor_record.is_empty():
		return

	var current: float = float(actor_record.get("actual_skim", 0.0))
	actor_record["actual_skim"] = clampf(current + delta, 0.0, 1.0)

## 3. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(world_state: Dictionary) -> void:
	var tuning: Dictionary = _get_tuning()
	var threshold: float = float(tuning["loyalty_skim_threshold"])
	var operator: String = str(tuning["loyalty_operator"])
	var increment: float = float(tuning["ambient_skim_increment"])
	var max_ambient: float = float(tuning["max_ambient_skim"])

	var staff_table: Dictionary = world_state.get("staff", {})
	for staff_id in staff_table.keys():
		var member: Dictionary = staff_table[staff_id]
		if not member is Dictionary:
			continue

		var loyalty: float = float(member.get("loyalty", 1.0))
		var should_creep: bool = CONDITION_EVALUATOR.evaluate(loyalty, threshold, operator)

		if should_creep:
			var current_skim: float = float(member.get("actual_skim", 0.0))
			member["actual_skim"] = clampf(current_skim + increment, 0.0, max_ambient)