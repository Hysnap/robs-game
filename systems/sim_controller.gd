# res://systems/sim_controller.gd
class_name SimController
extends RefCounted

const _VerbRouter = preload("res://systems/verb_router.gd")
const _ImpactRouter = preload("res://systems/impacts/impact_router.gd")

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	var result: Dictionary = _VerbRouter.dispatch(world_state, action_directive)
	
	if result.get("success", false):
		var initiator_id: String = action_directive.get("initiator_id", "PLAYER")
		var target_node_id: String = result.get("target_node_id", "")
		var deltas: Dictionary = result.get("impact_deltas", {})
		
		for metric_key in deltas.keys():
			var delta_val: float = float(deltas[metric_key])
			
			# Scope Routing:
			# Personal/Actor metrics route to the initiator.
			# Environmental/Spatial metrics route to the target location.
			var recipient_id: String = target_node_id
			if metric_key in ["CASH", "WORKER_FATIGUE", "OPERATIONAL_TIME", "INTOXICATION"]:
				recipient_id = initiator_id
				
			_ImpactRouter.dispatch_delta(world_state, recipient_id, metric_key, delta_val)
		
	return result

## Processes complete operational cycle: resolves directives, advances time, 
## triggers ambient drift, and returns structured feedback slips for the UI.
static func process_turn_cycle(world_state: Dictionary, staged_directives: Array) -> Array:
	var meta: Dictionary = world_state.get("metadata", {})
	var current_day: int = int(meta.get("current_day_tick", 1))
	var current_week: int = int(meta.get("current_week_tick", 1))
	var horizon: String = meta.get("time_horizon", "day").to_lower()
	var incoming_slips: Array = []

	# 1. Execute Staged Directives strictly in Array order (Top to Bottom)
	if not staged_directives.is_empty():
		for i in range(staged_directives.size()):
			var directive: Dictionary = staged_directives[i]
			var res: Dictionary = execute_directive(world_state, directive)
			incoming_slips.append({
				"tick": current_day,
				"week": current_week,
				"verb": directive.get("verb", "TASK"),
				"text": res.get("message", "Task completed."),
				"author": directive.get("counterparty_id", "Street Runner"),
				"destination": "DIARY",
				"staged_index": int(directive.get("staged_index", i)),
				"completion_index": i,
				"directive_snapshot": directive.duplicate(true)
			})
	else:
		incoming_slips.append({
			"tick": current_day,
			"week": current_week,
			"verb": "IDLE",
			"text": "Cycle complete. Operations quiet; balances and stock held steady.",
			"author": "Station Log",
			"destination": "DIARY",
			"staged_index": 0,
			"completion_index": 0
		})

	# 2. Advance Temporal Horizon Clock
	match horizon:
		"day":
			current_day += 1
			if current_day > 7:
				current_day = 1
				current_week += 1
				meta["current_week_tick"] = current_week
				process_ambient_heartbeat(world_state)
			meta["current_day_tick"] = current_day
		"week":
			current_week += 1
			meta["current_week_tick"] = current_week
			process_ambient_heartbeat(world_state)
		_:
			current_day += 1
			meta["current_day_tick"] = current_day

	world_state["metadata"] = meta

	# 3. Inform GameState safely if running inside tree (No raw GameState identifier reference)
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var root = (main_loop as SceneTree).root
		if root:
			var gs_node = root.get_node_or_null("GameState")
			if gs_node and gs_node.has_signal("turn_advanced"):
				gs_node.emit_signal("turn_advanced", current_day)

	return incoming_slips

## Global Weekly/Tick Heartbeat
static func process_ambient_heartbeat(world_state: Dictionary) -> void:
	if world_state.has("metadata"):
		world_state["metadata"]["current_week_tick"] = world_state["metadata"].get("current_week_tick", 0) + 1
	_ImpactRouter.dispatch_ambient_tick(world_state)