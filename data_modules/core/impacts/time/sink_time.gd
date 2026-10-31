# res://data_modules/core/impacts/time/sink_time.gd
extends ImpactSinkBase
class_name SinkTime

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "OPERATIONAL_TIME"

static func get_target_scope() -> String:
	return "ACTOR"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	# 1. Route to specific Staff Member if specified
	if target_id != "" and target_id != "PLAYER" and world_state.get("staff", {}).has(target_id):
		var worker: Dictionary = world_state["staff"][target_id]
		var current_used: float = float(worker.get("shift_time_spent", 0.0))
		worker["shift_time_spent"] = maxf(0.0, current_used + delta)
	else:
		# 2. Otherwise route to Player's active operations pool
		if not world_state.has("operations"):
			world_state["operations"] = {}
		var ops: Dictionary = world_state["operations"]
		var current_time_spent: float = float(ops.get("shift_time_spent", 0.0))
		ops["shift_time_spent"] = maxf(0.0, current_time_spent + delta)

## 3. AMBIENT SHIFT RESET
static func process_ambient(world_state: Dictionary) -> void:
	# Resets daily shift counters at the boundary of a new day tick
	if world_state.has("operations"):
		world_state["operations"]["shift_time_spent"] = 0.0

	var staff_table: Dictionary = world_state.get("staff", {})
	for s_id in staff_table.keys():
		if staff_table[s_id] is Dictionary:
			staff_table[s_id]["shift_time_spent"] = 0.0