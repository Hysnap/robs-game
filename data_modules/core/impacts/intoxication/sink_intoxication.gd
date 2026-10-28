# res://data_modules/core/impacts/intoxication/sink_intoxication.gd
extends ImpactSinkBase
class_name SinkIntoxication

static func get_metric_key() -> String:
	return "INTOXICATION"

static func get_target_scope() -> String:
	return "ACTOR"

static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if target_id != "" and target_id != "PLAYER" and world_state.get("staff", {}).has(target_id):
		var worker = world_state["staff"][target_id]
		var cur = float(worker.get("intoxication", 0.0))
		worker["intoxication"] = clamp(cur + delta, 0.0, 100.0)
	else:
		var ops = world_state.get("operations", {})
		var cur = float(ops.get("intoxication", 0.0))
		ops["intoxication"] = clamp(cur + delta, 0.0, 100.0)

## Ambient Heartbeat: Workers sober up naturally over time
static func process_ambient(world_state: Dictionary) -> void:
	# Sober up player
	var ops = world_state.get("operations", {})
	if ops.has("intoxication"):
		ops["intoxication"] = max(0.0, float(ops["intoxication"]) - 15.0)
		
	# Sober up staff roster
	var staff_table = world_state.get("staff", {})
	for staff_id in staff_table.keys():
		var worker = staff_table[staff_id]
		if worker.has("intoxication"):
			worker["intoxication"] = max(0.0, float(worker["intoxication"]) - 15.0)