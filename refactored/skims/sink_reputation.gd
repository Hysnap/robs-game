# res://data_modules/core/impacts/reputation/sink_reputation.gd
class_name SinkReputation
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/reputation/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkReputation] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkReputation] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkReputation] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkReputation] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("default_baseline_reputation"), "FATAL: [SinkReputation] Missing 'default_baseline_reputation' in tuning.")
	assert(tuning.has("passive_decay_rate_per_tick"), "FATAL: [SinkReputation] Missing 'passive_decay_rate_per_tick' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "REPUTATION"

static func get_target_scope() -> String:
	return "ACTOR"

## 2. TELEMETRY QUERY CONTRACT
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkReputation] target_id cannot be empty")
	var tuning := _get_tuning()
	return float(tuning["default_baseline_reputation"])

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	var tuning := _get_tuning()
	var baseline: float = float(tuning["default_baseline_reputation"])

	# 1. Interpersonal: Counterparty / NPC
	var counterparties: Dictionary = world_state.get("counterparties", world_state.get("npcs", {}))
	if counterparties.has(target_id):
		var cur: float = float(counterparties[target_id].get("reputation", baseline))
		counterparties[target_id]["reputation"] = clampf(cur + delta, -1.0, 1.0)
		return

	# 2. Interpersonal: Staff Member
	var staff_table: Dictionary = world_state.get("staff", {})
	if staff_table.has(target_id):
		var cur: float = float(staff_table[target_id].get("reputation", baseline))
		staff_table[target_id]["reputation"] = clampf(cur + delta, -1.0, 1.0)
		return

	# 3. Institutional: Organization / Faction / Church
	var orgs: Dictionary = world_state.get("organizations", world_state.get("factions", {}))
	if orgs.has(target_id):
		var cur: float = float(orgs[target_id].get("reputation", baseline))
		orgs[target_id]["reputation"] = clampf(cur + delta, -1.0, 1.0)
		return

	# 4. Institutional: Individual Establishment
	var establishments: Dictionary = world_state.get("establishments", {})
	if establishments.has(target_id):
		var cur: float = float(establishments[target_id].get("reputation", baseline))
		establishments[target_id]["reputation"] = clampf(cur + delta, -1.0, 1.0)
		return

	# 5. Spatial: District / Neighborhood Public Standing
	var districts: Dictionary = world_state.get("districts", {})
	if districts.has(target_id):
		var cur: float = float(districts[target_id].get("reputation", baseline))
		districts[target_id]["reputation"] = clampf(cur + delta, -1.0, 1.0)
		return

	# 6. Fallback / Dedicated Standings Table
	var standings: Dictionary = world_state.get("standings", {})
	if not world_state.has("standings"):
		world_state["standings"] = standings
	var cur: float = float(standings.get(target_id, baseline))
	standings[target_id] = clampf(cur + delta, -1.0, 1.0)

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(world_state: Dictionary) -> void:
	var tuning := _get_tuning()
	var baseline: float = float(tuning["default_baseline_reputation"])
	var decay: float = float(tuning["passive_decay_rate_per_tick"])

	# Helper to decay entries in an entity table back toward baseline
	var decay_table = func(table: Dictionary) -> void:
		for entity_id in table.keys():
			var entity = table[entity_id]
			if entity is Dictionary and entity.has("reputation"):
				var cur: float = float(entity["reputation"])
				if cur > baseline:
					entity["reputation"] = maxf(baseline, cur - decay)
				elif cur < baseline:
					entity["reputation"] = minf(baseline, cur + decay)

	decay_table.call(world_state.get("counterparties", {}))
	decay_table.call(world_state.get("organizations", {}))
	decay_table.call(world_state.get("establishments", {}))
	decay_table.call(world_state.get("standings", {}))