# res://data_modules/core/impacts/worker_fatigue/sink_fatigue.gd
extends ImpactSinkBase
class_name SinkFatigue

static func get_metric_key() -> String:
	return "WORKER_FATIGUE"

static func apply_delta(world_state: Dictionary, _target_id: String, delta: float) -> void:
	if not world_state.has("operations"):
		world_state["operations"] = {"fatigue": 0.0}
	
	var current: float = float(world_state["operations"].get("fatigue", 0.0))
	world_state["operations"]["fatigue"] = clamp(current + delta, 0.0, 100.0)

static func process_ambient(world_state: Dictionary) -> void:
	# Passive recovery: -5.0 fatigue per quiet week tick
	if world_state.has("operations"):
		var current: float = float(world_state["operations"].get("fatigue", 0.0))
		world_state["operations"]["fatigue"] = max(0.0, current - 5.0)