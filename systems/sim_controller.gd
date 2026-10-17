# res://systems/sim_controller.gd
class_name SimController extends RefCounted

## Dispatches an action command through its verb script and applies the resulting impacts
static func execute_directive(world_state: Dictionary, verb_script: Variant, action_directive: Dictionary) -> Dictionary:
	var result: Dictionary = verb_script.execute(world_state, action_directive)
	
	if result.get("success", false):
		var target_node: String = result.get("target_node_id", "")
		var deltas: Dictionary = result.get("impact_deltas", {})
		apply_impact_deltas(world_state, target_node, deltas)
		
	return result

## Sinks calculated deltas into the objective state (True Reality)
static func apply_impact_deltas(world_state: Dictionary, target_node_id: String, deltas: Dictionary) -> void:
	# 1. District / Spatial Sinks
	if world_state.get("districts", {}).has(target_node_id):
		var dist = world_state["districts"][target_node_id]
		if deltas.has("POLICE_HEAT"):
			dist["actual_police_heat"] = clamp(dist.get("actual_police_heat", 0.0) + deltas["POLICE_HEAT"], 0.0, 1.0)
		if deltas.has("ZONE_HEALTH"):
			dist["zone_health_index"] = clamp(dist.get("zone_health_index", 100.0) + deltas["ZONE_HEALTH"], 0.0, 100.0)

	# 2. Player Operations Sinks
	var ops = world_state.get("operations", {})
	if deltas.has("WORKER_FATIGUE"):
		ops["fatigue"] = clamp(ops.get("fatigue", 0.0) + deltas["WORKER_FATIGUE"], 0.0, 100.0)[cite: 1]

## Global Weekly/Tick Heartbeat (Resolves Ambient Environmental Pulses)
static func process_ambient_heartbeat(world_state: Dictionary, ambient_impacts: Array) -> void:
	world_state["metadata"]["current_week_tick"] += 1
	
	for dist_id in world_state.get("districts", {}).keys():
		for impact in ambient_impacts:
			var metric = impact.get_target_metric()
			var ambient_delta = impact.process_ambient_tick(world_state, dist_id)
			if ambient_delta != 0.0:
				apply_impact_deltas(world_state, dist_id, {metric: ambient_delta})