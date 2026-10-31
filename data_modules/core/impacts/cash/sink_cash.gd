# res://data_modules/core/impacts/cash/sink_cash.gd
class_name SinkCash
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/cash/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkCash] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkCash] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkCash] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkCash] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_float"), "FATAL: [SinkCash] Missing 'default_baseline_float' in tuning.")
	assert(tuning.has("allow_negative_balance"), "FATAL: [SinkCash] Missing 'allow_negative_balance' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "CASH"

static func get_target_scope() -> String:
	return "ACTOR"

## 2. TELEMETRY QUERY CONTRACT
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkCash] target_id cannot be empty")
	var tuning := _get_tuning()
	return float(tuning["default_baseline_float"])

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	var tuning := _get_tuning()
	var allow_negative: bool = bool(tuning.get("allow_negative_balance", false))

	# 1. Staff registry
	var staff_table: Dictionary = world_state.get("staff", {})
	if staff_table.has(target_id):
		var staff_member: Dictionary = staff_table[target_id]
		var cur_val: float = float(staff_member.get("cash", 0.0))
		var new_val: float = cur_val + delta
		staff_member["cash"] = new_val if allow_negative else maxf(0.0, new_val)
		return

	# 2. Counterparty / NPC registry
	var npcs: Dictionary = world_state.get("counterparties", world_state.get("npcs", {}))
	if npcs.has(target_id):
		var npc: Dictionary = npcs[target_id]
		var cur_val: float = float(npc.get("cash", 0.0))
		var new_val: float = cur_val + delta
		npc["cash"] = new_val if allow_negative else maxf(0.0, new_val)
		return

	# 3. Default Actor: Player Vault / Central Ledger
	var finances: Dictionary = world_state.get("finances", {})
	var current: float = float(finances.get("liquid_cash", 0.0))
	var updated: float = current + delta
	finances["liquid_cash"] = updated if allow_negative else maxf(0.0, updated)

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	# Passive interest, debt decay, or periodic retainer deductions
	pass