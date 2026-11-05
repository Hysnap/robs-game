# res://systems/sim_controller.gd
class_name SimController
extends RefCounted

const _VerbRouter = preload("res://systems/verb_router.gd")
const _ImpactRouter = preload("res://systems/impacts/impact_router.gd")
const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const BUSINESS_RULES_PATH: String = "res://data_modules/core/business_rules.cfg"

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	SystemLogger.log_debug("[SimController] Executing directive: %s" % action_directive.get("verb", action_directive.get("type", "")))
	var result: Dictionary = _VerbRouter.dispatch(world_state, action_directive)
	
	if result.get("success", false):
		var initiator_id: String = action_directive.get("initiator_id", "PLAYER")
		var target_node_id: String = result.get("target_node_id", "")
		var deltas: Dictionary = result.get("impact_deltas", {})
		
		for metric_key in deltas.keys():
			var delta_val: float = float(deltas[metric_key])
			var scope: String = _ImpactRouter.get_metric_scope(metric_key)
			# Scope Routing:
			# Personal/Actor metrics route to the initiator.
			# Environmental/Spatial metrics route to the target location.
			var recipient_id: String = target_node_id
			if scope == "ACTOR":
				recipient_id = initiator_id
				
			_ImpactRouter.dispatch_delta(world_state, recipient_id, metric_key, delta_val)
		
	SystemLogger.log_info("[SimController] Directive completed: success=%s" % result.get("success", false))
	return result

## Processes complete operational cycle: resolves directives, advances time via CalendarHelper,
## triggers ambient drift, and returns structured cycle report.
static func process_turn_cycle(world_state: Dictionary, staged_directives: Array) -> Dictionary:
	SystemLogger.log_info("[SimController] Processing turn cycle with %d staged directives." % staged_directives.size())
	var meta: Dictionary = world_state.get("metadata", {})
	# Current time is anchored by a single monotonic day offset
	var current_day: int = int(meta.get("current_sim_day", _CalendarHelper.get_simulation_start_day()))
	var current_week: int = _CalendarHelper.day_to_week(current_day)
	var horizon: String = meta.get("time_horizon", "day").to_lower()
	var executed_events: Array = []
	var diary_memos: Array[String] = []

	# 1. Execute Staged Directives strictly in Array order (Top to Bottom)
	var strict_halt := false
	if FileAccess.file_exists(BUSINESS_RULES_PATH):
		var cfg := ConfigFile.new()
		if cfg.load(BUSINESS_RULES_PATH) == OK:
			strict_halt = bool(cfg.get_value("turn_execution", "strict_fifo_halt_on_failure", false))

	var halted_agents: Dictionary = {}

	if not staged_directives.is_empty():
		for i in range(staged_directives.size()):
			var directive: Dictionary = staged_directives[i]
			var author_str: String = _resolve_directive_author(world_state, directive)
			var agent_key: String = str(directive.get("assigned_to", directive.get("assigned_agent", directive.get("initiator_id", "PLAYER"))))

			# Check if this specific agent's pipeline is already halted due to prior failure
			if strict_halt and halted_agents.has(agent_key):
				executed_events.append({
					"trigger_type": "ACTION_ABORTED",
					"day_offset": current_day,
					"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
					"week": current_week,
					"day_of_week": _CalendarHelper.day_of_week(current_day),
					"verb": directive.get("verb", TranslationServer.translate("DEFAULT_VERB_TOKEN")),
					"target_item": directive.get("target_item", ""),
					"success": false,
					"message": TranslationServer.translate("FEEDBACK_TASK_ABORTED_PIPELINE_HALTED"),
					"author": author_str,
					"target_node_id": directive.get("target_node_id", ""),
					"staged_index": i,
					"directive_snapshot": directive.duplicate(true)
				})
				diary_memos.append(TranslationServer.translate("DIARY_TASK_ABORTED_PIPELINE_HALTED"))
				continue

			var res: Dictionary = execute_directive(world_state, directive)
			var success: bool = res.get("success", false)

			var event_record := {
				"trigger_type": "ACTION_RESOLUTION",
				"day_offset": current_day,
				"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
				"week": current_week,
				"day_of_week": _CalendarHelper.day_of_week(current_day),
				"verb": directive.get("verb", TranslationServer.translate("DEFAULT_VERB_TOKEN")),
				"target_item": directive.get("target_item", ""),
				"success": success,
				"message": res.get("message", TranslationServer.translate("FEEDBACK_TASK_GENERIC_SUCCESS")),
				"author": author_str,
				"target_node_id": directive.get("target_node_id", ""),
				"staged_index": i,
				"directive_snapshot": directive.duplicate(true)
			}
			executed_events.append(event_record)
			diary_memos.append(res.get("message", TranslationServer.translate("DIARY_TASK_GENERIC_SUCCESS_MESSAGE")))

			# If this directive failed, halt subsequent tasks ONLY for this agent
			if not success and strict_halt:
				halted_agents[agent_key] = true
	else:
		executed_events.append({
			"trigger_type": "IDLE",
			"day_offset": current_day,
			"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
			"week": current_week,
			"day_of_week": _CalendarHelper.day_of_week(current_day),
			"verb": "IDLE",
			"message": TranslationServer.translate("FEEDBACK_IDLE_DETAIL"),
			"author": "Station Log",
			"success": true
		})
		diary_memos.append(TranslationServer.translate("FEEDBACK_CYCLE_IDLE"))

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
	var dow := _CalendarHelper.day_of_week(current_day)
	meta["current_sim_day"] = current_day
	meta["current_week_tick"] = _CalendarHelper.day_to_week(current_day)
	meta["current_day_tick"] = dow
	meta["current_day_of_week"] = dow
	world_state["metadata"] = meta

	# 3. Auto-Save Non-Ironman Granular Turn Snapshot
	var active_slot := str(meta.get("active_slot_id", "slot_01"))
	SaveManager.save_turn_snapshot(active_slot, current_day, world_state)
	SystemLogger.log_info("[SimController] Turn cycle advanced to day %d (week rollover=%s)." % [current_day, crossed_boundary])

	return {
		"current_sim_day": current_day,
		"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
		"week": meta["current_week_tick"],
		"day_of_week": dow,
		"week_rollover": crossed_boundary,
		"executed_events": executed_events,
		"diary_memos": diary_memos
	}

static func _resolve_directive_author(world_state: Dictionary, directive: Dictionary) -> String:
	var agent_id: String = str(directive.get("assigned_to", directive.get("assigned_agent", directive.get("initiator_id", directive.get("counterparty_id", "")))))
	if agent_id.is_empty() or agent_id == "PLAYER":
		return TranslationServer.translate("DEFAULT_OPERATIVE_TITLE")

	# Check roster or staff table if mounted in world_state
	var roster: Dictionary = world_state.get("roster", world_state.get("staff", {}))
	if roster.has(agent_id):
		var record = roster[agent_id]
		if record is Dictionary and record.has("name"):
			return str(record["name"])

	return agent_id