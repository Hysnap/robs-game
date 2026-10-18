# res://data_modules/core/impacts/cash/sink_cash.gd
extends ImpactSinkBase
class_name SinkCash

static func get_metric_key() -> String:
	return "CASH"

static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if target_id == "PLAYER" or target_id == "":
		var current = float(world_state.get("finances", {}).get("liquid_cash", 0.0))
		world_state["finances"]["liquid_cash"] = max(0.0, current + delta)
	else:
		# Staff or NPC cash pocket
		var actor = world_state.get("staff", {}).get(target_id, world_state.get("npcs", {}).get(target_id, {}))
		actor["cash"] = max(0.0, actor.get("cash", 0.0) + delta)