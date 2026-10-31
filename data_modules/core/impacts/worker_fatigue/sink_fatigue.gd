# res://data_modules/core/impacts/worker_fatigue/sink_fatigue.gd
extends ImpactSinkBase
class_name SinkFatigue

static func get_metric_key() -> String:
	return "WORKER_FATIGUE"

static func get_target_scope() -> String:
	return "ACTOR"

## Applies fatigue delta to individual staff member or the player operations pool
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	var staff_table: Dictionary = world_state.get("staff", {})
	if not target_id.is_empty() and staff_table.has(target_id):
		var staff_member: Dictionary = staff_table[target_id]
		var cur: float = float(staff_member.get("fatigue", 0.0))
		staff_member["fatigue"] = clampf(cur + delta, 0.0, 100.0)
		return

	# Fallback to player / operations fatigue pool
	if not world_state.has("operations"):
		world_state["operations"] = {}
	var cur_ops: float = float(world_state["operations"].get("fatigue", 0.0))
	world_state["operations"]["fatigue"] = clampf(cur_ops + delta, 0.0, 100.0)

## Ambient recovery: passive rest per quiet week tick
static func process_ambient(world_state: Dictionary) -> void:
	# 1. Recover player operations fatigue
	if world_state.has("operations"):
		var cur_ops: float = float(world_state["operations"].get("fatigue", 0.0))
		if cur_ops > 0.0:
			world_state["operations"]["fatigue"] = maxf(0.0, cur_ops - 5.0)

	# 2. Recover rostered staff fatigue
	var staff_table: Dictionary = world_state.get("staff", {})
	for s_id in staff_table.keys():
		var staff_member: Dictionary = staff_table[s_id]
		var cur: float = float(staff_member.get("fatigue", 0.0))
		if cur > 0.0:
			staff_member["fatigue"] = maxf(0.0, cur - 5.0)