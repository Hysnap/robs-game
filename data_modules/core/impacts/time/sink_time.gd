# res://data_modules/core/impacts/time/sink_time.gd
extends ImpactSinkBase
class_name SinkTime

static func get_metric_key() -> String:
	return "OPERATIONAL_TIME"

static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return
		
	# 1. Route to specific Staff Member if specified
	if target_id != "" and target_id != "PLAYER" and world_state.get("staff", {}).has(target_id):
		var worker = world_state["staff"][target_id]
		var current_used: float = float(worker.get("shift_time_spent", 0.0))
		worker["shift_time_spent"] = current_used + delta
	else:
		# 2. Otherwise route to Player's active operations pool
		var ops = world_state.get("operations", {})
		var current_time_spent: float = float(ops.get("shift_time_spent", 0.0))
		ops["shift_time_spent"] = current_time_spent + delta