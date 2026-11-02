# res://data_modules/core/impacts/intoxication/sink_intoxication.gd
class_name SinkIntoxication
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/intoxication/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkIntoxication] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkIntoxication] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkIntoxication] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkIntoxication] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("ambient_sober_rate"), "FATAL: [SinkIntoxication] Missing 'ambient_sober_rate' in tuning.")
	assert(tuning.has("min_intoxication"), "FATAL: [SinkIntoxication] Missing 'min_intoxication' in tuning.")
	assert(tuning.has("max_intoxication"), "FATAL: [SinkIntoxication] Missing 'max_intoxication' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "INTOXICATION"

static func get_target_scope() -> String:
	return "ACTOR"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	var tuning: Dictionary = _get_tuning()
	var min_val: float = float(tuning["min_intoxication"])
	var max_val: float = float(tuning["max_intoxication"])

	# Parse compound target format: "ACTOR_ID:SUBSTANCE" or standalone "ACTOR_ID" / "SUBSTANCE"
	var actor_id: String = target_id
	var substance_id: String = ""

	if target_id.contains(":"):
		var parts := target_id.split(":")
		actor_id = parts[0]
		substance_id = parts[1]

	# Resolve actor container
	var actor_record: Dictionary = {}
	if actor_id == "PLAYER" or actor_id.is_empty():
		if not world_state.has("operations"):
			world_state["operations"] = {}
		actor_record = world_state["operations"]
	elif world_state.get("staff", {}).has(actor_id):
		actor_record = world_state["staff"][actor_id]
	elif world_state.get("counterparties", {}).has(actor_id):
		actor_record = world_state["counterparties"][actor_id]
	else:
		# If target_id was passed purely as a substance name, default actor to PLAYER operations
		if not world_state.has("operations"):
			world_state["operations"] = {}
		actor_record = world_state["operations"]
		substance_id = actor_id

	# 1. Update overall composite intoxication
	var cur_intox: float = float(actor_record.get("intoxication", 0.0))
	actor_record["intoxication"] = clampf(cur_intox + delta, min_val, max_val)

	# 2. Update specific substance serum level if specified
	if not substance_id.is_empty():
		if not actor_record.has("substance_levels"):
			actor_record["substance_levels"] = {}
		var sub_map: Dictionary = actor_record["substance_levels"]
		var cur_sub: float = float(sub_map.get(substance_id, 0.0))
		sub_map[substance_id] = clampf(cur_sub + delta, min_val, max_val)

## 3. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(world_state: Dictionary) -> void:
	var tuning: Dictionary = _get_tuning()
	var sober_step: float = float(tuning["ambient_sober_rate"])

	# 1. Sober up Player operations
	if world_state.has("operations"):
		_sober_actor(world_state["operations"], sober_step)

	# 2. Sober up Staff roster
	var staff_table: Dictionary = world_state.get("staff", {})
	for s_id in staff_table.keys():
		if staff_table[s_id] is Dictionary:
			_sober_actor(staff_table[s_id], sober_step)

	# 3. Sober up Active Counterparties
	var counterparty_table: Dictionary = world_state.get("counterparties", {})
	for c_id in counterparty_table.keys():
		if counterparty_table[c_id] is Dictionary:
			_sober_actor(counterparty_table[c_id], sober_step)

static func _sober_actor(actor: Dictionary, sober_step: float) -> void:
	if actor.has("intoxication"):
		var cur: float = float(actor["intoxication"])
		actor["intoxication"] = maxf(0.0, cur - sober_step)

	if actor.has("substance_levels"):
		var sub_map: Dictionary = actor["substance_levels"]
		var keys_to_remove: Array = []
		for sub_id in sub_map.keys():
			var sub_val: float = maxf(0.0, float(sub_map[sub_id]) - sober_step)
			if sub_val <= 0.0:
				keys_to_remove.append(sub_id)
			else:
				sub_map[sub_id] = sub_val
		for rem_id in keys_to_remove:
			sub_map.erase(rem_id)