# res://systems/sim_controller.gd
class_name SimController extends RefCounted

const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	# 1. Dispatch action through VerbRouter (which resolves aliases and mounts scripts)
	var result: Dictionary = VerbRouterScript.dispatch(world_state, action_directive)
	
	# 2. If successful, route all emitted impact deltas to their respective sinks
	if result.get("success", false):
		var target_id: String = result.get("target_node_id", "")
		var deltas: Dictionary = result.get("impact_deltas", {})
		
		for metric_key in deltas.keys():
			var delta_val: float = float(deltas[metric_key])
			ImpactRouter.dispatch_delta(world_state, target_id, metric_key, delta_val)
		
	return result

## Global Weekly/Tick Heartbeat
static func process_ambient_heartbeat(world_state: Dictionary) -> void:
	# Advance clock
	if world_state.has("metadata"):
		world_state["metadata"]["current_week_tick"] = world_state["metadata"].get("current_week_tick", 0) + 1
	
	# Delegate ambient drift, threshold checks, and passive decay to registered sinks
	ImpactRouterScript.dispatch_ambient_tick(world_state)