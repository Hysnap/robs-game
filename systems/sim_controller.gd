# res://systems/sim_controller.gd
class_name SimController extends RefCounted

const VERB_ROUTER = preload("res://systems/verb_router.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	var result: Dictionary = VERB_ROUTER.dispatch(world_state, action_directive)
	
	if result.get("success", false):
		var initiator_id: String = action_directive.get("initiator_id", "")
		var target_node_id: String = result.get("target_node_id", "")
		var deltas: Dictionary = result.get("impact_deltas", {})
		
		for metric_key in deltas.keys():
			var delta_val: float = float(deltas[metric_key])
			
			# Route based on the natural scope of the metric:
			# Personal/Actor metrics route to the initiator.
			# Environmental/Spatial metrics route to the target location.
			var recipient_id: String = target_node_id
			if metric_key in ["CASH", "WORKER_FATIGUE", "OPERATIONAL_TIME", "INTOXICATION"]:
				recipient_id = initiator_id
				
			IMPACT_ROUTER.dispatch_delta(world_state, recipient_id, metric_key, delta_val)

	return result

## Global Weekly/Tick Heartbeat
static func process_ambient_heartbeat(world_state: Dictionary) -> void:
	# Advance clock
	if world_state.has("metadata"):
		world_state["metadata"]["current_week_tick"] = world_state["metadata"].get("current_week_tick", 0) + 1
	
	# Delegate ambient drift, threshold checks, and passive decay to registered sinks
	IMPACT_ROUTER.dispatch_ambient_tick(world_state)