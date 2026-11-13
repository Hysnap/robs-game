# res://systems/sim_controller.gd
class_name SimController
extends RefCounted

const _VerbRouter = preload("res://systems/verb_router.gd")
const _ImpactRouter = preload("res://systems/impacts/impact_router.gd")
const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _IntelManager = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const BUSINESS_RULES_PATH: String = "res://data_modules/core/business_rules.cfg"
const _DBManager = preload("res://systems/db_manager.gd")

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	var verb_token: String = str(action_directive.get("verb", action_directive.get("type", ""))).to_upper().strip_edges()
	SystemLogger.log_debug("[SimController] Executing directive: %s" % verb_token)
	var result: Dictionary = _VerbRouter.dispatch(world_state, action_directive)
	
	if result.get("success", false):
		var initiator_id: String = str(action_directive.get("assigned_to", action_directive.get("assigned_agent", action_directive.get("initiator_id", "PLAYER"))))
		var target_node_id: String = str(result.get("target_node_id", action_directive.get("target_node_id", "")))
		var deltas: Dictionary = result.get("impact_deltas", {})
		
		for metric_key in deltas.keys():
			var delta_val: float = float(deltas[metric_key])
			var scope: String = _ImpactRouter.get_metric_scope(metric_key)
			var recipient_id: String = initiator_id if scope == "ACTOR" else target_node_id
			_ImpactRouter.dispatch_delta(world_state, recipient_id, metric_key, delta_val)

		# Dispatch declarative verb impacts from data_modules/core/verbs/<verb_slug>/impacts/
		var verb_impacts_meta: Dictionary = _dispatch_verb_impacts(world_state, action_directive, verb_token, initiator_id, target_node_id)
		if not verb_impacts_meta.is_empty():
			result["verb_impacts"] = verb_impacts_meta
		
	SystemLogger.log_info("[SimController] Directive completed: success=%s" % result.get("success", false))
	return result

## Loads and executes declarative JSON impact configs from a verb's impacts/ folder
static func _dispatch_verb_impacts(
	world_state: Dictionary,
	directive: Dictionary,
	verb_token: String,
	actor_id: String,
	target_node_id: String
) -> Dictionary:
	var applied: Dictionary = {}
	if verb_token.is_empty():
		return applied

	var impacts_dir := "res://data_modules/core/verbs/%s/impacts/" % verb_token.to_lower()
	if not DirAccess.dir_exists_absolute(impacts_dir):
		return applied

	var dir := DirAccess.open(impacts_dir)
	if dir == null:
		return applied

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var f := FileAccess.open(impacts_dir.path_join(file_name), FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary:
					var metric_id: String = str(parsed.get("metric_id", file_name.get_basename())).to_upper().strip_edges()
					if parsed.has("rules_module") or parsed.has("model"):
						var target_scope: String = str(parsed.get("target_scope", directive.get("target_scope", "DISTRICT"))).to_upper().strip_edges()
						var resolved_target_id: String = target_node_id
						if target_scope == "RESIDENT":
							resolved_target_id = str(directive.get("target_resident_id", directive.get("counterparty_id", target_node_id)))
						elif target_scope == "ESTABLISHMENT" and directive.has("target_entity_id"):
							resolved_target_id = str(directive.get("target_entity_id"))

						var impact_params: Dictionary = {
							"observer_scope": "RESIDENT",
							"observer_id": actor_id,
							"target_scope": target_scope,
							"target_id": resolved_target_id,
							"recipient_scope": str(parsed.get("recipient_scope", "RESIDENT")),
							"recipient_id": str(directive.get("target_resident_id", directive.get("counterparty_id", ""))),
							"subject_scope": str(directive.get("subject_scope", "DISTRICT")),
							"subject_id": str(directive.get("subject_id", target_node_id)),
							"multiplier": float(directive.get("duration_ticks", directive.get("amount", 1.0))),
							"context": directive.get("impact_context", {}),
							"secondary_targets": directive.get("secondary_targets", [])
						}
						var outcome: Dictionary = _IntelManager.process_verb_impact(world_state, impact_params, parsed)
						if not outcome.is_empty():
							applied[metric_id] = outcome
					elif parsed.has("delta"):
						var delta_val: float = float(parsed["delta"])
						var scope: String = _ImpactRouter.get_metric_scope(metric_id)
						var recipient_id: String = actor_id if scope == "ACTOR" else target_node_id
						_ImpactRouter.dispatch_delta(world_state, recipient_id, metric_id, delta_val)
						applied[metric_id] = delta_val
		file_name = dir.get_next()
	dir.list_dir_end()
	return applied

## Processes complete operational cycle: resolves directives, advances time via CalendarHelper,
## triggers ambient drift, and returns structured cycle report.
static func process_turn_cycle(world_state: Dictionary, staged_directives: Array) -> Dictionary:
	SystemLogger.log_info("[SimController] Processing turn cycle with %d staged directives." % staged_directives.size())
	var meta: Dictionary = world_state.get("metadata", {})
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

	var crossed_boundary := _CalendarHelper.crosses_week_boundary(current_day, days_to_advance)
	current_day += days_to_advance

	if crossed_boundary:
		_ImpactRouter.dispatch_ambient_tick(world_state)

	var dow := _CalendarHelper.day_of_week(current_day)
	meta["current_sim_day"] = current_day
	meta["current_week_tick"] = _CalendarHelper.day_to_week(current_day)
	meta["current_day_tick"] = dow
	meta["current_day_of_week"] = dow
	world_state["metadata"] = meta

	# 3. Synchronize Sim Day into SQLite Database in Lockstep
	_DBManager.execute_batch([
		"INSERT OR REPLACE INTO world_metadata (key, value) VALUES ('current_sim_day', '%d');" % current_day
	])

	# 4. Auto-Save Non-Ironman Granular Turn Snapshot
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

	var residents: Dictionary = world_state.get("residents", {})
	if residents.has(agent_id):
		var record = residents[agent_id]
		if record is Dictionary and record.has("name"):
			return str(record["name"])

	return agent_id