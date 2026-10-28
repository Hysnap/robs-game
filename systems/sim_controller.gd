# res://systems/sim_controller.gd
class_name SimController
extends RefCounted

const _VerbRouter = preload("res://systems/verb_router.gd")
const _ImpactRouter = preload("res://systems/impacts/impact_router.gd")
const _CalendarHelper = preload("res://systems/calendar_helper.gd")

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	var result: Dictionary = _VerbRouter.dispatch(world_state, action_directive)
	
	if result.get("success", false):
		var initiator_id: String = action_directive.get("initiator_id", "PLAYER")
		var target_node_id: String = result.get("target_node_id", "")
		var deltas: Dictionary = result.get("impact_deltas", {})
		
		for metric_key in deltas.keys():
			var delta_val: float = float(deltas[metric_key])
			var scope: String = _ImpactRouter.get_metric_scope(metric_key)
			# Scope Routing:# Personal/Actor metrics route to the initiator.
			# Environmental/Spatial metrics route to the target location.
			var recipient_id: String = target_node_id
			if scope == "ACTOR":
				recipient_id = initiator_id
				
			_ImpactRouter.dispatch_delta(world_state, recipient_id, metric_key, delta_val)
		
	return result

## Processes complete operational cycle: resolves directives, advances time via CalendarHelper,
## triggers ambient drift, and returns structured cycle report.
static func process_turn_cycle(world_state: Dictionary, staged_directives: Array) -> Dictionary:
	var meta: Dictionary = world_state.get("metadata", {})
	# Current time is anchored by a single monotonic day offset
	var current_day: int = int(meta.get("current_sim_day", _CalendarHelper.get_simulation_start_day()))
	var current_week: int = _CalendarHelper.day_to_week(current_day)
	var horizon: String = meta.get("time_horizon", "day").to_lower()
	var executed_events: Array = []
	var diary_memos: Array[String] = []

	# 1. Execute Staged Directives strictly in Array order (Top to Bottom)
	if not staged_directives.is_empty():
		for i in range(staged_directives.size()):
			var directive: Dictionary = staged_directives[i]
			var res: Dictionary = execute_directive(world_state, directive)
			
			var event_record := {
				"trigger_type": "ACTION_RESOLUTION",
				"day_offset": current_day,
				"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
				"week": current_week,
				"day_of_week": _CalendarHelper.day_of_week(current_day),
				"verb": directive.get("verb", "TASK"),
				"target_item": directive.get("target_item", ""),
				"success": res.get("success", false),
				"message": res.get("message", "Task completed."),
				"author": directive.get("counterparty_id", "Street Runner"),
				"target_node_id": directive.get("target_node_id", ""),
				"staged_index": i,
				"directive_snapshot": directive.duplicate(true)
			}
			executed_events.append(event_record)
			diary_memos.append(res.get("message", "Task completed."))
	else:
		executed_events.append({
			"trigger_type": "IDLE",
			"day_offset": current_day,
			"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
			"week": current_week,
			"day_of_week": _CalendarHelper.day_of_week(current_day),
			"verb": "IDLE",
			"message": "Operations quiet; stock and balances steady.",
			"author": "Station Log",
			"success": true
		})
		diary_memos.append("Quiet shift on the patch.")

	# 2. Advance Temporal Offset via CalendarHelper
	var days_to_advance := 1
	match horizon:
		"day", "shift":
			days_to_advance = 1
		"week":
			days_to_advance = _CalendarHelper.get_days_per_tick()

	# Check if this step crosses a full cycle boundary
	var crossed_boundary := _CalendarHelper.crosses_week_boundary(current_day, days_to_advance)
	current_day += days_to_advance

	if crossed_boundary:
		_ImpactRouter.dispatch_ambient_tick(world_state)

	# Store the single canonical time offset
	meta["current_sim_day"] = current_day
	meta["current_calendar_date"] = _CalendarHelper.day_to_calendar_date(current_day)
	meta["current_week_tick"] = _CalendarHelper.day_to_week(current_day)
	meta["current_day_of_week"] = _CalendarHelper.day_of_week(current_day)
	meta["current_day_tick"] = _CalendarHelper.day_of_week(current_day)
	world_state["metadata"] = meta

	# 3. Inform GameState (Observer Pattern)
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var root = (main_loop as SceneTree).root
		if root:
			var gs_node = root.get_node_or_null("GameState")
			if gs_node and gs_node.has_signal("turn_advanced"):
				gs_node.emit_signal("turn_advanced", current_day)

	return {
		"current_sim_day": current_day,
		"calendar_date": meta["current_calendar_date"],
		"week": meta["current_week_tick"],
		"day_of_week": meta["current_day_of_week"],
		"week_rollover": crossed_boundary,
		"executed_events": executed_events,
		"diary_memos": diary_memos
	}

## Global Weekly/Tick Heartbeat
static func process_ambient_heartbeat(world_state: Dictionary) -> void:
	if world_state.has("metadata"):
		world_state["metadata"]["current_week_tick"] = world_state["metadata"].get("current_week_tick", 0) + 1
	_ImpactRouter.dispatch_ambient_tick(world_state)