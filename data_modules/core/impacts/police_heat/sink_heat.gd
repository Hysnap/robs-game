# res://data_modules/crime/impacts/police_heat/sink_heat.gd
extends ImpactSinkBase
class_name SinkPoliceHeat

static func get_metric_key() -> String:
	return "POLICE_HEAT"

# Implements the Action Impulse: Clamps heat between 0.0 (Cold) and 1.0 (Raid)
static func apply_delta(world_state: Dictionary, district_id: String, delta: float) -> void:
	if not world_state.get("districts", {}).has(district_id):
		return
	var dist = world_state["districts"][district_id]
	var current_heat: float = dist.get("actual_police_heat", 0.0)
	dist["actual_police_heat"] = clamp(current_heat + delta, 0.0, 1.0)

# Implements the Ambient Heartbeat: Heat dissipates passively by 0.03/week
static func process_ambient(world_state: Dictionary) -> void:
	for dist_id in world_state.get("districts", {}).keys():
		var dist = world_state["districts"][dist_id]
		dist["actual_police_heat"] = max(0.0, dist.get("actual_police_heat", 0.0) - 0.03)