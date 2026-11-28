# res://systems/sim_controller.gd
class_name SimController
extends RefCounted

const _VerbRouter = preload("res://systems/verb_router.gd")
const _ImpactRouter = preload("res://systems/impacts/impact_router.gd")
const _ConditionEvaluator = preload("res://systems/condition_evaluator.gd")
const _ActionPipelineHelpers = preload("res://systems/action_pipeline/action_pipeline_helpers.gd")
const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _IntelManager = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const _FileSystemCrawler = preload("res://systems/file_system_crawler.gd")
const _StandingOrderProcessor = preload("res://systems/standing_order_processor.gd")
const _OrgMandateManager = preload("res://systems/economy/org_mandate_manager.gd")
const _ManagerAIResolver = preload("res://systems/economy/manager_ai_resolver.gd")
const BUSINESS_RULES_PATH: String = "res://data_modules/core/business_rules.cfg"
const _DBManager = preload("res://systems/db_manager.gd")
const _ObligationLedger = preload("res://systems/economy/obligation_ledger.gd")
const _MacroEconomyProcessor = preload("res://systems/economy/macro_economy_processor.gd")
const _LifeCycleProcessor = preload("res://systems/life_cycle_processor.gd")

const WINDOW_ANCHOR_HOURS := {
	"EARLY_MORNING": 6.0,
	"MORNING": 8.0,
	"DAYTIME": 9.0,
	"MIDDAY": 12.0,
	"AFTERNOON": 13.0,
	"EVENING": 18.0,
	"NIGHT": 22.0,
	"LATE_NIGHT": 23.0
}

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	var verb_token: String = str(action_directive.get("verb", action_directive.get("type", ""))).to_upper().strip_edges()
	SystemLogger.log_debug("[SimController] Executing directive: %s" % verb_token)
	_apply_mandate_intervention_guard(world_state, action_directive, verb_token)
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

		var verb_impacts_meta: Dictionary = _dispatch_verb_impacts(world_state, action_directive, verb_token, initiator_id, target_node_id)
		if not verb_impacts_meta.is_empty():
			result["verb_impacts"] = verb_impacts_meta

	SystemLogger.log_info("[SimController] Directive completed: success=%s" % result.get("success", false))
	return result

## Evaluates declarative "when" key-value guards and compound "conditions" gates on an impact JSON
static func _matches_impact_conditions(world_state: Dictionary, directive: Dictionary, impact_cfg: Dictionary) -> bool:
	if impact_cfg.has("when") and impact_cfg["when"] is Dictionary:
		var when_map: Dictionary = impact_cfg["when"]
		for raw_key in when_map.keys():
			var key_str: String = str(raw_key)
			var lookup_token: String = key_str if key_str.begins_with("PARAM.") else ("PARAM." + key_str)
			var current_val: Variant = _ActionPipelineHelpers.resolve_param_value(lookup_token, directive, world_state)
			var expected_val: Variant = when_map[raw_key]
			if expected_val is Array:
				var matched_any := false
				for candidate in expected_val:
					if _ConditionEvaluator.evaluate_gate({ "current": current_val, "target": candidate, "operator": "==" }):
						matched_any = true
						break
				if not matched_any:
					return false
			elif not _ConditionEvaluator.evaluate_gate({ "current": current_val, "target": expected_val, "operator": "==" }):
				return false

	if impact_cfg.has("conditions") and impact_cfg["conditions"] is Array:
		var logic_gate: String = str(impact_cfg.get("logic_gate", "AND"))
		var gates: Array = []
		for cond in impact_cfg["conditions"]:
			if cond is Dictionary:
				var metric_expr: String = str(cond.get("metric", ""))
				var curr: Variant = _ActionPipelineHelpers.resolve_param_value(metric_expr, directive, world_state)
				var targ: Variant = _ActionPipelineHelpers.resolve_param_value(cond.get("value", ""), directive, world_state)
				gates.append({
					"current": curr,
					"target": targ,
					"operator": str(cond.get("operator", "=="))
				})
		if not _ConditionEvaluator.evaluate_logic_block(logic_gate, gates):
			return false

	return true

## Loads and executes declarative JSON impact configs from the verb's mounted core + active flavour impacts_dirs
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

	var impacts_dirs: Array[String] = _VerbRouter.get_impacts_dirs(verb_token)
	if impacts_dirs.is_empty():
		return applied

	var impact_files: Array[String] = []
	for dir_path in impacts_dirs:
		var found: Array[String] = _FileSystemCrawler.find_files_recursive(dir_path, "", ".json")
		impact_files.append_array(found)

	for full_path in impact_files:
		var parsed: Dictionary = ScenarioManifestManager.load_json_file(full_path)
		if parsed.is_empty():
			continue
		if not _matches_impact_conditions(world_state, directive, parsed):
			continue

		var metric_id: String = str(parsed.get("metric_id", full_path.get_file().get_basename())).to_upper().strip_edges()
		if metric_id == "OBLIGATION":
			var obl_outcome: Dictionary = _ObligationLedger.process_verb_impact(world_state, directive, parsed)
			if not obl_outcome.is_empty():
				applied[metric_id] = obl_outcome
				if obl_outcome.has("impacts") and obl_outcome["impacts"] is Array:
					_apply_calendar_event_impacts(world_state, obl_outcome["impacts"], target_node_id, actor_id)
		elif parsed.has("rules_module") or parsed.has("model"):
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
			var target_role: String = str(parsed.get("target_role", "ACTOR")).to_upper().strip_edges()
			var recipient_id: String = target_node_id
			if scope == "ACTOR" or scope == "RESIDENT":
				if target_role == "COUNTERPARTY":
					recipient_id = str(directive.get("target_resident_id", directive.get("counterparty_id", directive.get("source_id", actor_id))))
				else:
					recipient_id = actor_id
			elif scope == "OPERATIONS_STAMP" and target_node_id.is_empty():
				recipient_id = actor_id
			_ImpactRouter.dispatch_delta(world_state, recipient_id, metric_id, delta_val)
			applied[metric_id] = float(applied.get(metric_id, 0.0)) + delta_val
	return applied

## Applies N-actor / multi-target declarative impacts attached to a calendar_events row
static func _apply_calendar_event_impacts(
	world_state: Dictionary,
	impacts: Array,
	default_location_id: String,
	default_actor_id: String = ""
) -> void:
	for entry in impacts:
		if not (entry is Dictionary):
			continue
		var metric_id := str(entry.get("metric_id", "")).to_upper().strip_edges()
		if metric_id.is_empty() or not entry.has("delta"):
			continue
		var delta_val := float(entry["delta"])
		var scope := str(entry.get("target_scope", _ImpactRouter.get_metric_scope(metric_id))).to_upper().strip_edges()
		var recipient_id := str(entry.get("target_id", "")).strip_edges()
		if recipient_id.is_empty():
			recipient_id = default_actor_id if (scope == "ACTOR" and not default_actor_id.is_empty()) else default_location_id
		if not recipient_id.is_empty():
			_ImpactRouter.dispatch_delta(world_state, recipient_id, metric_id, delta_val)

## Processes complete operational cycle across adaptive horizons (day/shift/week/month/quarter)
## with 1-hour continuous timeline scheduling and witness/ownership feedback slip filtering.
static func process_turn_cycle(world_state: Dictionary, staged_directives: Array) -> Dictionary:
	SystemLogger.log_info("[SimController] Processing turn cycle with %d staged directives." % staged_directives.size())
	_ImpactRouter.dispatch_cycle_start(world_state)
	var meta: Dictionary = world_state.get("metadata", {})
	var start_day: int = _CalendarHelper.get_current_sim_day(world_state)
	var current_day: int = start_day
	var current_week: int = _CalendarHelper.day_to_week(current_day)
	var horizon: String = str(meta.get("time_horizon", "day")).to_lower().strip_edges()
	var executed_events: Array = []
	var diary_memos: Array[String] = []

	var strict_halt := false
	if FileAccess.file_exists(BUSINESS_RULES_PATH):
		var cfg := ConfigFile.new()
		if cfg.load(BUSINESS_RULES_PATH) == OK:
			strict_halt = bool(cfg.get_value("turn_execution", "strict_fifo_halt_on_failure", false))
	
	var horizon_preview: Dictionary = _resolve_horizon_step(meta, horizon)
	_evaluate_cascade_impacts(
		world_state,
		start_day,
		horizon,
		int(horizon_preview.get("days", 1)),
		executed_events,
		diary_memos
	)

	var day_queue: Array[Dictionary] = _build_day_execution_queue(world_state, staged_directives, start_day, diary_memos)
	var halted_agents: Dictionary = {}

	if not day_queue.is_empty():
		for i in range(day_queue.size()):
			var directive: Dictionary = day_queue[i]
			var author_str: String = _resolve_directive_author(world_state, directive)
			var agent_key: String = str(directive.get("assigned_to", directive.get("assigned_agent", directive.get("initiator_id", "PLAYER"))))
			var sched_hour: float = float(directive.get("scheduled_hour", 9.0))

			if strict_halt and halted_agents.has(agent_key):
				executed_events.append({
					"trigger_type": "ACTION_ABORTED",
					"day_offset": current_day,
					"hour_of_day": sched_hour,
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
				"hour_of_day": sched_hour,
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
			"hour_of_day": 9.0,
			"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
			"week": current_week,
			"day_of_week": _CalendarHelper.day_of_week(current_day),
			"verb": "IDLE",
			"message": TranslationServer.translate("FEEDBACK_IDLE_DETAIL"),
			"author": "Station Log",
			"success": true
		})
		diary_memos.append(TranslationServer.translate("FEEDBACK_CYCLE_IDLE"))

	# 1b. Per-Operative Auto Return-to-Base (runs regardless of shift directive failures/halts)
	var default_base_id: String = str(world_state.get("operations", {}).get("home_district_id", "")).strip_edges()
	var residents_dict: Dictionary = world_state.get("residents", {})
	var seen_return_ids: Dictionary = {}

	for res_key in residents_dict.keys():
		var rec = residents_dict[res_key]
		if not (rec is Dictionary) or not bool(rec.get("is_crew", true)):
			continue
		if not bool(rec.get("auto_return_to_base", false)):
			continue

		var canonical_id: Variant = rec.get("resident_id", res_key)
		var agent_str: String = str(canonical_id)
		if seen_return_ids.has(agent_str):
			continue
		seen_return_ids[agent_str] = true

		var target_base_id: String = str(rec.get("base_district_id", default_base_id)).strip_edges()
		if target_base_id.is_empty():
			target_base_id = default_base_id

		var current_loc: String = str(rec.get("current_district_id", "")).strip_edges()
		if target_base_id.is_empty() or current_loc == target_base_id:
			continue

		var base_name: String = str(world_state.get("districts", {}).get(target_base_id, {}).get("display_name", target_base_id))
		var return_directive: Dictionary = {
			"verb": "TRAVEL",
			"initiator_id": canonical_id,
			"assigned_to": canonical_id,
			"destination_district_id": target_base_id,
			"target_node_id": target_base_id,
			"target_node_name": base_name,
			"target_scope": "DISTRICT",
			"service_id": "AUTO",
			"auto_generated_return": true
		}

		var author_str: String = _resolve_directive_author(world_state, return_directive)
		var ret_res: Dictionary = execute_directive(world_state, return_directive)
		var ret_success: bool = bool(ret_res.get("success", false))

		executed_events.append({
			"trigger_type": "ACTION_RESOLUTION",
			"day_offset": current_day,
			"hour_of_day": 18.0,
			"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
			"week": current_week,
			"day_of_week": _CalendarHelper.day_of_week(current_day),
			"verb": "TRAVEL",
			"target_item": "",
			"success": ret_success,
			"message": ret_res.get("message", TranslationServer.translate("FEEDBACK_TASK_GENERIC_SUCCESS")),
			"author": author_str,
			"target_node_id": target_base_id,
			"directive_snapshot": return_directive.duplicate(true)
		})
		diary_memos.append(ret_res.get("message", TranslationServer.translate("FEEDBACK_TASK_GENERIC_SUCCESS")))

	# 2. Resolve Adaptive Horizon Span (with 4-week staggered checkpoints for 'month') & Partition Districts
	var horizon_step: Dictionary = _resolve_horizon_step(meta, horizon)
	var days_to_advance: int = int(horizon_step["days"])
	var is_month_close: bool = bool(horizon_step["is_month_close"])
	var month_checkpoint: int = int(horizon_step["month_checkpoint"])
	var district_partition: Dictionary = _partition_districts_by_horizon(world_state, staged_directives)
	meta["active_districts_in_horizon"] = district_partition["active_districts"]
	meta["background_district_count"] = district_partition["background_count"]

	var crossed_boundary := _CalendarHelper.crosses_week_boundary(start_day, days_to_advance)
	var economy_rollover: Dictionary = {}
	var life_cycle_rollover := {
		"scheduled_births": 0,
		"scheduled_deaths": 0,
		"scheduled_illnesses": 0,
		"scheduled_outbreaks": 0,
		"births_resolved": 0,
		"deaths_resolved": 0,
		"illnesses_started": 0,
		"illnesses_recovered": 0,
		"health_records_in_memory": 0
	}
	var obligation_rollover := {
		"delivered_mail": [],
		"cleared_settlements": [],
		"dishonoured_settlements": [],
		"accrued_obligations": [],
		"overdue_obligations": [],
		"dispatched_statements": [],
		"activated_events": [],
		"completed_events": []
	}

	for step in range(1, days_to_advance + 1):
		var day_tick: int = start_day + step
		var tick_month_meta: Dictionary = _CalendarHelper.get_month_grid_meta(day_tick, 0)
		var tick_month_key: String = "%04d-%02d" % [int(tick_month_meta["year"]), int(tick_month_meta["month"])]
		if str(meta.get("lifecycle_last_scheduled_month", "")) != tick_month_key:
			var sched_res: Dictionary = _LifeCycleProcessor.schedule_upcoming_month_events(world_state, day_tick)
			life_cycle_rollover["scheduled_births"] += int(sched_res.get("scheduled_births", 0))
			life_cycle_rollover["scheduled_deaths"] += int(sched_res.get("scheduled_deaths", 0))
			life_cycle_rollover["scheduled_illnesses"] += int(sched_res.get("scheduled_illnesses", 0))
			life_cycle_rollover["scheduled_outbreaks"] += int(sched_res.get("scheduled_outbreaks", 0))
			meta["lifecycle_last_scheduled_month"] = tick_month_key
		if step > 1:
			_execute_standing_orders_for_rollover_day(world_state, day_tick, executed_events, diary_memos)
		var daily_res: Dictionary = _ObligationLedger.process_daily_tick(day_tick)
		var lc_daily: Dictionary = _LifeCycleProcessor.process_daily_resolution(
			world_state,
			day_tick,
			daily_res.get("activated_events", [])
		)
		life_cycle_rollover["births_resolved"] += int(lc_daily.get("births_resolved", 0))
		life_cycle_rollover["deaths_resolved"] += int(lc_daily.get("deaths_resolved", 0))
		life_cycle_rollover["illnesses_started"] += int(lc_daily.get("illnesses_started", 0))
		life_cycle_rollover["illnesses_recovered"] += int(lc_daily.get("illnesses_recovered", 0))
		life_cycle_rollover["health_records_in_memory"] = int(lc_daily.get("health_records_in_memory", 0))
		obligation_rollover["delivered_mail"].append_array(daily_res.get("delivered_mail", []))
		obligation_rollover["cleared_settlements"].append_array(daily_res.get("cleared_settlements", []))
		obligation_rollover["dishonoured_settlements"].append_array(daily_res.get("dishonoured_settlements", []))
		obligation_rollover["accrued_obligations"].append_array(daily_res.get("accrued_obligations", []))
		obligation_rollover["dispatched_statements"].append_array(daily_res.get("dispatched_statements", []))
		obligation_rollover["activated_events"].append_array(daily_res.get("activated_events", []))
		var ended_evs: Array = daily_res.get("completed_events", [])
		obligation_rollover["completed_events"].append_array(ended_evs)
		for ev in ended_evs:
			if ev is Dictionary:
				var parsed_imp = JSON.parse_string(str(ev.get("impacts_json", "[]")))
				if parsed_imp is Array and not parsed_imp.is_empty():
					_apply_calendar_event_impacts(world_state, parsed_imp, str(ev.get("location_id", "")))
		if step == days_to_advance:
			obligation_rollover["overdue_obligations"] = daily_res.get("overdue_obligations", [])

	current_day = start_day + days_to_advance

	if crossed_boundary:
		_ImpactRouter.dispatch_ambient_tick(world_state)
		economy_rollover = _MacroEconomyProcessor.process_cycle(
			world_state,
			current_day,
			district_partition["active_districts"],
			is_month_close
		)
		_evaluate_active_mandates_and_collisions(world_state, current_day, horizon, is_month_close, executed_events, diary_memos)

	_append_ledger_rollover_events(obligation_rollover, current_day, executed_events, diary_memos)

	var dow := _CalendarHelper.day_of_week(current_day)
	meta["current_sim_day"] = current_day
	meta["current_week_tick"] = _CalendarHelper.day_to_week(current_day)
	meta["current_day_tick"] = dow
	meta["current_day_of_week"] = dow
	meta["month_checkpoint"] = month_checkpoint
	world_state["metadata"] = meta

	_DBManager.execute_batch([
		"INSERT OR REPLACE INTO world_metadata (key, value) VALUES ('current_sim_day', '%d');" % current_day
	])

	var witnessed_events: Array = _filter_witnessed_events(world_state, executed_events)

	var active_slot := str(meta.get("active_slot_id", "slot_01"))
	SaveManager.save_turn_snapshot(active_slot, current_day, world_state)
	SystemLogger.log_info("[SimController] Turn cycle advanced to day %d (horizon=%s, active_districts=%d, background_districts=%d, week_rollover=%s, witnessed_slips=%d/%d)." % [
		current_day, horizon, district_partition["active_districts"].size(), district_partition["background_count"], crossed_boundary, witnessed_events.size(), executed_events.size()
	])

	return {
		"current_sim_day": current_day,
		"calendar_date": _CalendarHelper.day_to_calendar_date(current_day),
		"week": meta["current_week_tick"],
		"day_of_week": dow,
		"time_horizon": horizon,
		"active_districts": district_partition["active_districts"],
		"background_district_count": district_partition["background_count"],
		"week_rollover": crossed_boundary,
		"economy_rollover": economy_rollover,
		"life_cycle_rollover": life_cycle_rollover,
		"obligation_rollover": obligation_rollover,
		"executed_events": witnessed_events,
		"all_executed_events": executed_events,
		"diary_memos": diary_memos
	}

## Merges staged ad-hoc directives with due standing orders and schedules them onto a continuous 1-hour timeline
static func _build_day_execution_queue(
	world_state: Dictionary,
	staged_directives: Array,
	sim_day: int,
	diary_memos: Array[String]
) -> Array[Dictionary]:
	var adhoc_by_agent: Dictionary = {}
	var unassigned_adhoc: Array[Dictionary] = []

	for d in staged_directives:
		if not (d is Dictionary):
			continue
		var agent_raw: Variant = d.get("assigned_to", d.get("assigned_agent", d.get("initiator_id", "")))
		var agent_key: String = str(agent_raw).strip_edges()
		if agent_key.is_empty() or agent_key == "PLAYER":
			unassigned_adhoc.append(d)
		else:
			if not adhoc_by_agent.has(agent_key):
				adhoc_by_agent[agent_key] = []
			adhoc_by_agent[agent_key].append(d)

	var hydrated_standing: Array[Dictionary] = _StandingOrderProcessor.hydrate_for_day(
		world_state,
		sim_day,
		func(t): return t.duplicate(true)
	)

	var standing_by_agent: Dictionary = {}
	for st in hydrated_standing:
		var s_key: String = str(st.get("assigned_to", "")).strip_edges()
		if not s_key.is_empty():
			if not standing_by_agent.has(s_key):
				standing_by_agent[s_key] = []
			standing_by_agent[s_key].append(st)

	var all_agent_keys: Dictionary = {}
	for k in adhoc_by_agent.keys():
		all_agent_keys[k] = true
	for k in standing_by_agent.keys():
		all_agent_keys[k] = true

	var timed_entries: Array[Dictionary] = []
	var seq_counter: int = 0

	var player_clock: float = 9.0
	for u_task in unassigned_adhoc:
		var start_hr: float = _resolve_task_start_hour(u_task, player_clock)
		var dur_hrs: float = maxf(0.25, float(u_task.get("estimated_hours", u_task.get("duration_hours", 1.0))))
		u_task["scheduled_hour"] = start_hr
		timed_entries.append({
			"scheduled_hour": start_hr,
			"priority": int(u_task.get("priority", 60)),
			"agent_key": "PLAYER",
			"seq": seq_counter,
			"task": u_task
		})
		player_clock = start_hr + dur_hrs
		seq_counter += 1

	var sorted_agents: Array = all_agent_keys.keys()
	sorted_agents.sort()

	for agent_key in sorted_agents:
		var a_list: Array = adhoc_by_agent.get(agent_key, [])
		var s_list: Array = standing_by_agent.get(agent_key, [])
		var plan: Dictionary = _StandingOrderProcessor.resolve_operative_shift_plan(world_state, agent_key, a_list, s_list)
		var actor_clock: float = 8.0
		for q_item in plan.get("queue", []):
			if not (q_item is Dictionary):
				continue
			var start_hr: float = _resolve_task_start_hour(q_item, actor_clock)
			var dur_hrs: float = maxf(0.25, float(q_item.get("estimated_hours", q_item.get("duration_hours", 1.0))))
			q_item["scheduled_hour"] = start_hr
			timed_entries.append({
				"scheduled_hour": start_hr,
				"priority": int(q_item.get("priority", 50)),
				"agent_key": str(agent_key),
				"seq": seq_counter,
				"task": q_item
			})
			actor_clock = start_hr + dur_hrs
			seq_counter += 1

		for m_txt in plan.get("memos", []):
			var memo_str: String = str(m_txt)
			diary_memos.append(memo_str)
			if not world_state.has("memo_backlog") or not (world_state["memo_backlog"] is Array):
				world_state["memo_backlog"] = []
			world_state["memo_backlog"].append({
				"tick": sim_day,
				"text": memo_str
			})

	# Sort chronologically by 1-hour timeline position (snapped to 1.0 hr buckets for concurrent meeting detection,
	# then exact scheduled_hour, priority, and deterministic actor/sequence tie-breaker)
	timed_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var bucket_a: int = int(floor(float(a["scheduled_hour"])))
		var bucket_b: int = int(floor(float(b["scheduled_hour"])))
		if bucket_a != bucket_b:
			return bucket_a < bucket_b
		var ha: float = float(a["scheduled_hour"])
		var hb: float = float(b["scheduled_hour"])
		if not is_equal_approx(ha, hb):
			return ha < hb
		var pa: int = int(a["priority"])
		var pb: int = int(b["priority"])
		if pa != pb:
			return pa > pb
		return int(a["seq"]) < int(b["seq"])
	)

	var final_queue: Array[Dictionary] = []
	for entry in timed_entries:
		final_queue.append(entry["task"])
	return final_queue

## Resolves a task's start hour on the 24-hour clock, anchored by explicit start_hour or role time_window,
## while advancing smoothly past any prior travel/delay spillover on the actor's clock.
static func _resolve_task_start_hour(task: Dictionary, actor_clock: float) -> float:
	if task.has("start_hour"):
		return maxf(actor_clock, float(task["start_hour"]))
	var win_token: String = str(task.get("time_window", "")).to_upper().strip_edges()
	if not win_token.is_empty() and WINDOW_ANCHOR_HOURS.has(win_token):
		return maxf(actor_clock, float(WINDOW_ANCHOR_HOURS[win_token]))
	return actor_clock

## Executes standing orders automatically on subsequent days during multi-day horizons (week/month/quarter)
static func _execute_standing_orders_for_rollover_day(
	world_state: Dictionary,
	day_tick: int,
	executed_events: Array,
	diary_memos: Array[String]
) -> void:
	var due_tasks: Array[Dictionary] = _StandingOrderProcessor.hydrate_for_day(
		world_state,
		day_tick,
		func(t): return t.duplicate(true)
	)
	if due_tasks.is_empty():
		return

	var w_num: int = _CalendarHelper.day_to_week(day_tick)
	var cal_d: String = _CalendarHelper.day_to_calendar_date(day_tick)
	var d_of_w: int = _CalendarHelper.day_of_week(day_tick)

	var timed_rollover: Array[Dictionary] = []
	var agent_clocks: Dictionary = {}
	for idx in range(due_tasks.size()):
		var t: Dictionary = due_tasks[idx]
		var a_key: String = str(t.get("assigned_to", "PLAYER"))
		var clk: float = float(agent_clocks.get(a_key, 8.0))
		var s_hr: float = _resolve_task_start_hour(t, clk)
		var dur: float = maxf(0.25, float(t.get("estimated_hours", 1.0)))
		t["scheduled_hour"] = s_hr
		agent_clocks[a_key] = s_hr + dur
		timed_rollover.append({ "hour": s_hr, "seq": idx, "task": t })

	timed_rollover.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ba: int = int(floor(float(a["hour"])))
		var bb: int = int(floor(float(b["hour"])))
		if ba != bb:
			return ba < bb
		return int(a["seq"]) < int(b["seq"])
	)

	for item in timed_rollover:
		var task: Dictionary = item["task"]
		var res: Dictionary = execute_directive(world_state, task)
		var ok: bool = bool(res.get("success", false))
		var msg: String = str(res.get("message", TranslationServer.translate("FEEDBACK_TASK_GENERIC_SUCCESS")))
		executed_events.append({
			"trigger_type": "STANDING_ORDER_EXECUTION",
			"day_offset": day_tick,
			"hour_of_day": float(task.get("scheduled_hour", 9.0)),
			"calendar_date": cal_d,
			"week": w_num,
			"day_of_week": d_of_w,
			"verb": str(task.get("verb", "STANDING_ORDER")),
			"target_item": str(task.get("target_item", "")),
			"success": ok,
			"message": msg,
			"author": _resolve_directive_author(world_state, task),
			"target_node_id": str(task.get("target_node_id", "")),
			"directive_snapshot": task.duplicate(true)
		})
		diary_memos.append(msg)

## Resolves step length and staggered 4-week checkpoint state for 'month' horizons
static func _resolve_horizon_step(meta: Dictionary, horizon: String) -> Dictionary:
	var week_days: int = _CalendarHelper.get_days_per_tick()
	match horizon:
		"day", "shift":
			return { "days": 1, "is_month_close": false, "month_checkpoint": 0 }
		"week":
			return { "days": week_days, "is_month_close": false, "month_checkpoint": 0 }
		"month":
			var prev_cp: int = int(meta.get("month_checkpoint", 0))
			var next_cp: int = prev_cp + 1
			var closes: bool = next_cp >= 4
			return {
				"days": week_days,
				"is_month_close": closes,
				"month_checkpoint": 0 if closes else next_cp
			}
		"quarter":
			return { "days": week_days * 12, "is_month_close": true, "month_checkpoint": 0 }
		_:
			return { "days": 1, "is_month_close": false, "month_checkpoint": 0 }

## Checks whether a direct player order intrudes on a locked manager mandate or ARMS_LENGTH subsidiary
static func _apply_mandate_intervention_guard(world_state: Dictionary, directive: Dictionary, verb_token: String) -> void:
	if bool(directive.get("is_standing_order", false)) or bool(directive.get("auto_generated_return", false)):
		return
	var mandates: Dictionary = world_state.get("org_mandates", {})
	if mandates.is_empty():
		return

	var current_day: int = _CalendarHelper.get_current_sim_day(world_state)
	var actor_id: int = int(directive.get("assigned_to", directive.get("initiator_id", 0)))
	var target_node: String = str(directive.get("target_node_id", "")).strip_edges()
	var ctx: Dictionary = {
		"district_id": target_node,
		"establishment_id": int(directive.get("target_entity_id", 0)),
		"item_id": str(directive.get("target_item", "")),
		"verb": verb_token
	}

	var residents: Dictionary = world_state.get("residents", {})
	var orgs: Dictionary = world_state.get("organizations", {})

	for m_id in mandates.keys():
		var m = mandates[m_id]
		if not (m is Dictionary) or not bool(m.get("is_active", true)):
			continue
		var mgr_id: int = int(m.get("manager_resident_id", 0))
		var target_org: String = str(m.get("target_org_id", "")).strip_edges()
		var is_arms_length: bool = not target_org.is_empty() and str(orgs.get(target_org, {}).get("autonomy_mode", "DIRECT")).to_upper() == "ARMS_LENGTH"

		var covers_actor: bool = actor_id > 0 and mgr_id > 0 and actor_id != mgr_id and int(residents.get(str(actor_id), {}).get("reports_to_resident_id", 0)) == mgr_id
		var covers_scope: bool = _OrgMandateManager.matches_scope(m.get("scope_filter", {}), ctx)
		if not covers_actor and not covers_scope:
			continue

		var auth: Dictionary = _OrgMandateManager.evaluate_intervention_authorization(m, current_day, is_arms_length)
		if not bool(auth.get("authorized", true)):
			var delta: float = float(auth.get("loyalty_delta", -0.10))
			if mgr_id > 0 and residents.has(str(mgr_id)):
				residents[str(mgr_id)]["loyalty"] = clampf(float(residents[str(mgr_id)].get("loyalty", 0.75)) + delta, 0.0, 1.0)
			if is_arms_length and orgs.has(target_org):
				orgs[target_org]["loyalty"] = clampf(float(orgs[target_org].get("loyalty", 0.75)) + delta, 0.0, 1.0)
			m["accountability_excuse"] = true

## Evaluates active mandates, dyadic scope collisions, and ARMS_LENGTH subsidiary macro cycles on boundary rollover
static func _evaluate_active_mandates_and_collisions(
	world_state: Dictionary,
	current_day: int,
	horizon: String,
	is_month_close: bool,
	executed_events: Array,
	diary_memos: Array[String]
) -> void:
	var mandates_dict: Dictionary = world_state.get("org_mandates", {})
	if mandates_dict.is_empty():
		return

	var active_list: Array[Dictionary] = []
	for m_id in mandates_dict.keys():
		var m = mandates_dict[m_id]
		if m is Dictionary and bool(m.get("is_active", true)):
			active_list.append(m)
	if active_list.is_empty():
		return

	var residents: Dictionary = world_state.get("residents", {})
	var orgs: Dictionary = world_state.get("organizations", {})
	var week_num: int = _CalendarHelper.day_to_week(current_day)
	var cal_date: String = _CalendarHelper.day_to_calendar_date(current_day)
	var dow: int = _CalendarHelper.day_of_week(current_day)

	# 1. Pairwise dyadic scope collisions
	for i in range(active_list.size()):
		for j in range(i + 1, active_list.size()):
			var ma: Dictionary = active_list[i]
			var mb: Dictionary = active_list[j]
			if str(ma.get("org_id", "")) != str(mb.get("org_id", "")):
				continue
			var res_a: Dictionary = residents.get(str(ma.get("manager_resident_id", 0)), {})
			var res_b: Dictionary = residents.get(str(mb.get("manager_resident_id", 0)), {})
			var col: Dictionary = _ManagerAIResolver.resolve_dyadic_mandate_collision(res_a, ma, res_b, mb)
			if bool(col.get("has_collision", false)):
				var msg := "%s (%s)" % [
					TranslationServer.translate("UI_MEMO_MANDATE_COLLISION"),
					str(col.get("outcome", "FRICTIONAL_OVERLAP"))
				]
				executed_events.append({
					"trigger_type": "MANDATE_COLLISION",
					"day_offset": current_day,
					"calendar_date": cal_date,
					"week": week_num,
					"day_of_week": dow,
					"verb": "MANDATE_COLLISION",
					"target_item": str(col.get("outcome", "")),
					"success": str(col.get("outcome", "")) == "PEER_COOPERATION",
					"message": msg,
					"author": TranslationServer.translate("UI_ORG_OPS_DESK")
				})
				diary_memos.append(msg)

	# 2. Individual manager reports & ARMS_LENGTH subsidiary macro resolution
	for m in active_list:
		var target_org: String = str(m.get("target_org_id", "")).strip_edges()
		var org_rec: Dictionary = orgs.get(target_org, {})
		if not target_org.is_empty() and str(org_rec.get("autonomy_mode", "DIRECT")).to_upper() == "ARMS_LENGTH":
			var m_horizon: String = str(m.get("planning_horizon", "MONTH")).to_upper()
			var due_macro: bool = (m_horizon == "WEEK") or (m_horizon == "MONTH" and is_month_close) or (m_horizon == "QUARTER" and horizon == "quarter")
			if due_macro:
				var macro_res: Dictionary = _OrgMandateManager.resolve_arms_length_macro_cycle(world_state, m, current_day)
				if bool(macro_res.get("requires_exception_alert", false)):
					var exc_msg := "%s (%s)" % [TranslationServer.translate("UI_MEMO_ARMS_LENGTH_EXCEPTION"), target_org]
					executed_events.append({
						"trigger_type": "ARMS_LENGTH_EXCEPTION",
						"day_offset": current_day,
						"calendar_date": cal_date,
						"week": week_num,
						"day_of_week": dow,
						"verb": "ARMS_LENGTH_EXCEPTION",
						"target_item": target_org,
						"success": false,
						"message": exc_msg,
						"author": str(org_rec.get("display_name", target_org))
					})
					diary_memos.append(exc_msg)
			continue

		var mgr_id: String = str(m.get("manager_resident_id", 0))
		var mgr_res: Dictionary = residents.get(mgr_id, {})
		var rep: Dictionary = _ManagerAIResolver.evaluate_reporting_and_escalation(world_state, mgr_res, m, {
			"current_heat": float(m.get("last_observed_heat", 0.0)),
			"target_attainment": float(m.get("last_target_attainment", 1.0)),
			"subordinate_escalations": int(m.get("subordinate_escalations", 0))
		})
		if bool(rep.get("should_emit_report", false)):
			var rep_msg := TranslationServer.translate(str(rep.get("report_token", "UI_MEMO_MGR_ROUTINE_DIGEST")))
			executed_events.append({
				"trigger_type": "MANAGER_REPORT",
				"day_offset": current_day,
				"calendar_date": cal_date,
				"week": week_num,
				"day_of_week": dow,
				"verb": "MANAGER_REPORT",
				"target_item": str(m.get("title", "")),
				"success": not bool(rep.get("crisis_detected", false)),
				"message": rep_msg,
				"author": str(mgr_res.get("name", mgr_id))
			})
			diary_memos.append(rep_msg)

## Partitions districts into fine-resolution active/impacted districts vs. coarse cohort background districts
static func _partition_districts_by_horizon(world_state: Dictionary, staged_directives: Array) -> Dictionary:
	var active_set: Dictionary = {}
	var all_districts: Dictionary = world_state.get("districts", {})
	var home_dist: String = str(world_state.get("operations", {}).get("home_district_id", "")).strip_edges()
	if not home_dist.is_empty() and all_districts.has(home_dist):
		active_set[home_dist] = true

	var residents_dict: Dictionary = world_state.get("residents", {})
	for r_key in residents_dict.keys():
		var rec = residents_dict[r_key]
		if rec is Dictionary:
			var cur_d: String = str(rec.get("current_district_id", "")).strip_edges()
			if not cur_d.is_empty() and all_districts.has(cur_d):
				active_set[cur_d] = true
			var base_d: String = str(rec.get("base_district_id", "")).strip_edges()
			if not base_d.is_empty() and all_districts.has(base_d):
				active_set[base_d] = true

	for d in staged_directives:
		if not (d is Dictionary):
			continue
		for k in ["target_node_id", "destination_district_id", "origin_district_id"]:
			var d_cand: String = str(d.get(k, "")).strip_edges()
			if not d_cand.is_empty() and all_districts.has(d_cand):
				active_set[d_cand] = true

	var active_list: Array[String] = []
	for d_id in active_set.keys():
		active_list.append(str(d_id))
	active_list.sort()

	var bg_count: int = maxi(0, all_districts.size() - active_list.size())
	return {
		"active_districts": active_list,
		"background_count": bg_count
	}

static func _append_ledger_rollover_events(
	rollover: Dictionary,
	current_day: int,
	executed_events: Array,
	diary_memos: Array[String]
) -> void:
	var week_num: int = _CalendarHelper.day_to_week(current_day)
	var cal_date: String = _CalendarHelper.day_to_calendar_date(current_day)
	var dow: int = _CalendarHelper.day_of_week(current_day)

	for ev in rollover.get("activated_events", []):
		if not (ev is Dictionary):
			continue
		var title_tok := str(ev.get("title_token", "UI_EVENT_DEFAULT"))
		var msg := "%s: %s" % [TranslationServer.translate("FEEDBACK_CALENDAR_EVENT_ACTIVE"), TranslationServer.translate(title_tok)]
		executed_events.append({
			"trigger_type": "CALENDAR_EVENT_STARTED",
			"day_offset": int(ev.get("start_day", current_day)),
			"calendar_date": cal_date,
			"week": week_num,
			"day_of_week": dow,
			"verb": "CALENDAR_EVENT_STARTED",
			"target_item": str(ev.get("event_type", "")),
			"event_id": int(ev.get("event_id", 0)),
			"visibility_scope": str(ev.get("visibility_scope", "")),
			"success": true,
			"message": msg,
			"author": TranslationServer.translate("UI_CALENDAR_DIARY"),
			"target_node_id": str(ev.get("location_id", ""))
		})
		diary_memos.append(msg)

	for ev in rollover.get("completed_events", []):
		if not (ev is Dictionary):
			continue
		var title_tok := str(ev.get("title_token", "UI_EVENT_DEFAULT"))
		var msg := "%s: %s" % [TranslationServer.translate("FEEDBACK_CALENDAR_EVENT_COMPLETED"), TranslationServer.translate(title_tok)]
		executed_events.append({
			"trigger_type": "CALENDAR_EVENT_COMPLETED",
			"day_offset": int(ev.get("end_day", current_day)),
			"calendar_date": cal_date,
			"week": week_num,
			"day_of_week": dow,
			"verb": "CALENDAR_EVENT_COMPLETED",
			"target_item": str(ev.get("event_type", "")),
			"event_id": int(ev.get("event_id", 0)),
			"visibility_scope": str(ev.get("visibility_scope", "")),
			"success": true,
			"message": msg,
			"author": TranslationServer.translate("UI_CALENDAR_DIARY"),
			"target_node_id": str(ev.get("location_id", ""))
		})
		diary_memos.append(msg)

	for mail in rollover.get("delivered_mail", []):
		if not (mail is Dictionary):
			continue
		var subj_token := str(mail.get("subject_token", "UI_MAIL_SUBJECT_DEFAULT"))
		var item_type := str(mail.get("item_type", "NOTICE"))
		var msg := "%s: %s" % [TranslationServer.translate("FEEDBACK_POSTAL_DELIVERED"), TranslationServer.translate(subj_token)]
		executed_events.append({
			"trigger_type": "POSTAL_DELIVERY",
			"day_offset": int(mail.get("delivery_day", current_day)),
			"calendar_date": cal_date,
			"week": week_num,
			"day_of_week": dow,
			"verb": "POSTAL_DELIVERY",
			"target_item": item_type,
			"mail_id": int(mail.get("mail_id", 0)),
			"success": true,
			"message": msg,
			"author": TranslationServer.translate("UI_POSTAL_SERVICE"),
			"target_node_id": "ESTABLISHMENT:%s" % str(mail.get("destination_estab_id", ""))
		})
		diary_memos.append(msg)

	for cleared in rollover.get("cleared_settlements", []):
		if not (cleared is Dictionary):
			continue
		var msg := "%s (#%d: %.2f)" % [
			TranslationServer.translate("FEEDBACK_SETTLEMENT_CLEARED"),
			int(cleared.get("obligation_id", 0)),
			float(cleared.get("amount", 0.0))
		]
		executed_events.append({
			"trigger_type": "SETTLEMENT_CLEARED",
			"day_offset": current_day,
			"calendar_date": cal_date,
			"week": week_num,
			"day_of_week": dow,
			"verb": "SETTLEMENT_CLEARED",
			"target_item": str(cleared.get("obligation_id", "")),
			"success": true,
			"message": msg,
			"author": TranslationServer.translate("UI_CLEARING_HOUSE")
		})
		diary_memos.append(msg)

	for bounced in rollover.get("dishonoured_settlements", []):
		if not (bounced is Dictionary):
			continue
		var msg := "%s (#%d: %.2f)" % [
			TranslationServer.translate("FEEDBACK_SETTLEMENT_DISHONOURED"),
			int(bounced.get("obligation_id", 0)),
			float(bounced.get("amount", 0.0))
		]
		executed_events.append({
			"trigger_type": "SETTLEMENT_DISHONOURED",
			"day_offset": current_day,
			"calendar_date": cal_date,
			"week": week_num,
			"day_of_week": dow,
			"verb": "SETTLEMENT_DISHONOURED",
			"target_item": str(bounced.get("obligation_id", "")),
			"success": false,
			"message": msg,
			"author": TranslationServer.translate("UI_CLEARING_HOUSE")
		})
		diary_memos.append(msg)

## Filters turn events so player feedback slips include only:
## 1. Active crew actions, direct interactions/outreach, & player-owned establishments
## 2. Co-located events witnessed in districts where crew are present
## 3. Universal public calendar events (bank holidays/major fixtures) OR cohort/personal events involving crew or 1st-degree associates
static func _filter_witnessed_events(world_state: Dictionary, raw_events: Array) -> Array:
	var crew_ids: Dictionary = { "PLAYER": true }
	var crew_int_ids: Array[int] = []
	var witness_districts: Dictionary = {}
	var owned_estab_ids: Dictionary = {}
	var crew_org_id: String = str(world_state.get("operations", {}).get("crew_org_id", "ORG:CREW_ENTERPRISE")).strip_edges()

	var residents: Dictionary = world_state.get("residents", {})
	var estabs: Dictionary = world_state.get("establishments", {})

	for r_key in residents.keys():
		var rec = residents[r_key]
		if rec is Dictionary and (not str(rec.get("slot_id", "")).is_empty() or bool(rec.get("is_crew", false))):
			var cid: String = str(rec.get("resident_id", r_key)).strip_edges()
			if not cid.is_empty():
				crew_ids[cid] = true
				if cid.is_valid_int():
					crew_int_ids.append(int(cid))
			var cur_d: String = str(rec.get("current_district_id", "")).strip_edges()
			if not cur_d.is_empty():
				witness_districts[cur_d] = true

	for e_key in estabs.keys():
		var est = estabs[e_key]
		if est is Dictionary:
			var owner_org: String = str(est.get("owner_org_id", "")).strip_edges()
			var owner_res: String = str(est.get("owner_resident_id", "")).strip_edges()
			if (not crew_org_id.is_empty() and owner_org == crew_org_id) or crew_ids.has(owner_res) or bool(est.get("is_player_owned", false)):
				var eid_str: String = str(est.get("establishment_id", e_key)).strip_edges()
				owned_estab_ids[eid_str] = true
				owned_estab_ids["ESTABLISHMENT:%s" % eid_str] = true

	var relevant_event_ids: Dictionary = _resolve_crew_and_associate_event_ids(crew_int_ids)

	var filtered: Array = []
	for ev in raw_events:
		if not (ev is Dictionary):
			continue
		var trig: String = str(ev.get("trigger_type", "")).to_upper()
		if trig in ["IDLE", "MANDATE_COLLISION", "MANAGER_REPORT", "ARMS_LENGTH_EXCEPTION", "POSTAL_DELIVERY", "SETTLEMENT_CLEARED", "SETTLEMENT_DISHONOURED"]:
			filtered.append(ev)
			continue

		if trig in ["CALENDAR_EVENT_STARTED", "CALENDAR_EVENT_COMPLETED"]:
			var ev_id: int = int(ev.get("event_id", 0))
			var vis_scope: String = str(ev.get("visibility_scope", "")).to_upper().strip_edges()
			var ev_loc: String = str(ev.get("target_node_id", "")).strip_edges()
			if vis_scope in ["PUBLIC", "GLOBAL", "JURISDICTION"]:
				filtered.append(ev)
			elif ev_id > 0 and relevant_event_ids.has(ev_id):
				filtered.append(ev)
			elif not ev_loc.is_empty() and (witness_districts.has(ev_loc) or owned_estab_ids.has(ev_loc)):
				filtered.append(ev)
			continue

		var snap: Dictionary = ev.get("directive_snapshot", {})
		var actor_str: String = str(snap.get("assigned_to", snap.get("assigned_agent", snap.get("initiator_id", "")))).strip_edges()
		if crew_ids.has(actor_str) or owned_estab_ids.has(actor_str):
			filtered.append(ev)
			continue

		var target_res: String = str(snap.get("target_resident_id", snap.get("counterparty_id", ""))).strip_edges()
		if not target_res.is_empty() and crew_ids.has(target_res):
			filtered.append(ev)
			continue

		var loc_raw: String = str(ev.get("target_node_id", snap.get("target_node_id", ""))).strip_edges()
		var target_ent: String = str(snap.get("target_entity_id", "")).strip_edges()
		if owned_estab_ids.has(loc_raw) or (not target_ent.is_empty() and owned_estab_ids.has(target_ent)):
			filtered.append(ev)
			continue

		var resolved_dist: String = loc_raw
		if loc_raw.begins_with("ESTABLISHMENT:"):
			var est_tok: String = loc_raw.trim_prefix("ESTABLISHMENT:")
			var est_rec = estabs.get(int(est_tok) if est_tok.is_valid_int() else est_tok, {})
			if est_rec is Dictionary:
				resolved_dist = str(est_rec.get("district_id", "")).strip_edges()
		elif estabs.has(int(loc_raw) if loc_raw.is_valid_int() else loc_raw):
			var est_rec2 = estabs.get(int(loc_raw) if loc_raw.is_valid_int() else loc_raw, {})
			if est_rec2 is Dictionary:
				resolved_dist = str(est_rec2.get("district_id", "")).strip_edges()

		if not resolved_dist.is_empty() and witness_districts.has(resolved_dist):
			filtered.append(ev)

	return filtered

## Resolves calendar event_ids relevant to crew or their 1st-degree close associates (linked obligations or organizer/subject ties)
static func _resolve_crew_and_associate_event_ids(crew_int_ids: Array[int]) -> Dictionary:
	var out: Dictionary = {}
	if crew_int_ids.is_empty() or not _DBManager.is_database_open():
		return out

	var relevant_residents: Dictionary = {}
	for cid in crew_int_ids:
		relevant_residents[cid] = true

	var id_tokens: Array[String] = []
	for cid in crew_int_ids:
		id_tokens.append(str(cid))
	var id_csv := ", ".join(id_tokens)

	var rel_tbl: Array = _DBManager.query_rows("SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='social_relationships';")
	if not rel_tbl.is_empty() and int(rel_tbl[0].get("cnt", 0)) > 0:
		var rel_rows: Array = _DBManager.query_rows("""
			SELECT to_resident_id FROM social_relationships
			WHERE valid_to IS NULL AND from_resident_id IN (%s);
		""" % id_csv)
		for rr in rel_rows:
			var tid: int = int(rr.get("to_resident_id", 0))
			if tid > 0:
				relevant_residents[tid] = true

	var all_res_tokens: Array[String] = []
	for rid in relevant_residents.keys():
		all_res_tokens.append(str(rid))
	var all_res_csv := ", ".join(all_res_tokens)

	var obl_tbl: Array = _DBManager.query_rows("SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='obligations';")
	if not obl_tbl.is_empty() and int(obl_tbl[0].get("cnt", 0)) > 0:
		var obl_rows: Array = _DBManager.query_rows("""
			SELECT DISTINCT linked_event_id FROM obligations
			WHERE linked_event_id IS NOT NULL
			  AND ((debtor_scope = 'RESIDENT' AND debtor_id IN (%s))
			    OR (creditor_scope = 'RESIDENT' AND creditor_id IN (%s)));
		""" % [all_res_csv, all_res_csv])
		for orow in obl_rows:
			var eid: int = int(orow.get("linked_event_id", 0))
			if eid > 0:
				out[eid] = true

	var ev_tbl: Array = _DBManager.query_rows("SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='calendar_events';")
	if not ev_tbl.is_empty() and int(ev_tbl[0].get("cnt", 0)) > 0:
		var ev_rows: Array = _DBManager.query_rows("""
			SELECT event_id FROM calendar_events
			WHERE organizer_scope = 'RESIDENT' AND organizer_id IN (%s);
		""" % all_res_csv)
		for erow in ev_rows:
			var eid2: int = int(erow.get("event_id", 0))
			if eid2 > 0:
				out[eid2] = true

	return out

static func _resolve_directive_author(world_state: Dictionary, directive: Dictionary) -> String:
	var agent_id: String = str(directive.get("assigned_to", directive.get("assigned_agent", directive.get("initiator_id", directive.get("counterparty_id", ""))))).strip_edges()
	if agent_id.is_empty() or agent_id == "PLAYER":
		return str(TranslationServer.translate("DEFAULT_OPERATIVE_TITLE"))

	var residents: Dictionary = world_state.get("residents", {})
	var record: Variant = null
	if residents.has(agent_id):
		record = residents[agent_id]
	elif agent_id.is_valid_int() and residents.has(int(agent_id)):
		record = residents[int(agent_id)]

	if record is Dictionary:
		for name_key in ["name", "full_name", "display_name"]:
			var candidate: String = str(record.get(name_key, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
		var first: String = str(record.get("first_name", "")).strip_edges()
		var last: String = str(record.get("last_name", record.get("surname", ""))).strip_edges()
		var combined: String = ("%s %s" % [first, last]).strip_edges()
		if not combined.is_empty():
			return combined

	return agent_id

## Evaluates cascade_impacts.json rules once at the start of a turn before scheduled/ordered actions run.
## Supports configurable ordering/layers in business_rules.cfg, 0.0 baseline defaults, metric deltas,
## and OCEAN/probability-gated follow-on actions for non-Leader actors.
static func _evaluate_cascade_impacts(
	world_state: Dictionary,
	sim_day: int,
	horizon: String,
	days_to_advance: int,
	executed_events: Array,
	diary_memos: Array[String]
) -> void:
	var order_keys: Array[String] = []
	var layer_keys: Array[String] = ["core"]

	if FileAccess.file_exists(BUSINESS_RULES_PATH):
		var cfg := ConfigFile.new()
		if cfg.load(BUSINESS_RULES_PATH) == OK:
			for raw_k in cfg.get_value("cascade_impacts", "evaluation_order", []):
				var k_str := str(raw_k).strip_edges().to_upper()
				if not k_str.is_empty():
					order_keys.append(k_str)
			var raw_layers: Array = cfg.get_value("cascade_impacts", "module_layers", [])
			if not raw_layers.is_empty():
				layer_keys.clear()
				for raw_l in raw_layers:
					var l_str := str(raw_l).strip_edges().to_lower()
					if not l_str.is_empty() and not layer_keys.has(l_str):
						layer_keys.append(l_str)

	var active_flavours: Array = ScenarioManifestManager.get_active_flavours()
	for flav in active_flavours:
		var f_str := str(flav).strip_edges().to_lower()
		if not f_str.is_empty() and not layer_keys.has(f_str):
			layer_keys.append(f_str)

	var discovered_files: Array[String] = []
	for layer_name in layer_keys:
		var base_impacts_dir := "res://data_modules/%s/impacts" % layer_name
		var found: Array[String] = _FileSystemCrawler.find_files_recursive(base_impacts_dir, "cascade_impacts.json", ".json")
		found.sort()
		for f_path in found:
			if not discovered_files.has(f_path):
				discovered_files.append(f_path)

	if discovered_files.is_empty():
		return

	var ordered_files: Array[String] = []
	if not order_keys.is_empty():
		for ord_key in order_keys:
			for f_path in discovered_files:
				var folder_metric := f_path.get_base_dir().get_file().to_upper()
				if folder_metric == ord_key and not ordered_files.has(f_path):
					ordered_files.append(f_path)
	for f_path in discovered_files:
		if not ordered_files.has(f_path):
			ordered_files.append(f_path)

	var horizon_scale: float = maxf(1.0, float(maxi(1, days_to_advance)))
	var week_num: int = _CalendarHelper.day_to_week(sim_day)
	var cal_date: String = _CalendarHelper.day_to_calendar_date(sim_day)
	var dow: int = _CalendarHelper.day_of_week(sim_day)
	var residents_dict: Dictionary = world_state.get("residents", {})
	var leader_id: String = str(world_state.get("operations", {}).get("leader_resident_id", "PLAYER")).strip_edges()

	for file_path in ordered_files:
		var doc: Dictionary = ScenarioManifestManager.load_json_file(file_path)
		var rules_arr: Array = doc.get("cascades", []) if doc.get("cascades", null) is Array else ([doc] if not doc.is_empty() else [])

		for rule_raw in rules_arr:
			if not (rule_raw is Dictionary):
				continue
			var rule: Dictionary = rule_raw
			var rule_id := str(rule.get("id", file_path.get_base_dir().get_file())).strip_edges()
			var eval_scope := str(rule.get("scope", _ImpactRouter.get_metric_scope(rule_id))).to_upper().strip_edges()

			var candidate_ids: Array[String] = []
			if eval_scope in ["ACTOR", "RESIDENT"]:
				for r_key in residents_dict.keys():
					candidate_ids.append(str(r_key))
			elif eval_scope == "DISTRICT":
				for d_key in world_state.get("districts", {}).keys():
					candidate_ids.append(str(d_key))
			elif eval_scope == "ESTABLISHMENT":
				for e_key in world_state.get("establishments", {}).keys():
					candidate_ids.append(str(e_key))
			else:
				candidate_ids.append(leader_id if not leader_id.is_empty() else "PLAYER")

			for cand_id in candidate_ids:
				var ctx_directive: Dictionary = {
					"target_resident_id": cand_id,
					"assigned_to": cand_id,
					"target_node_id": cand_id,
					"horizon": horizon,
					"days_to_advance": days_to_advance
				}
				if not _matches_cascade_gate(world_state, cand_id, ctx_directive, rule):
					continue

				# 1. Optional follow-on metric delta (clamped 0..100 via ImpactRouter / UniversalMetricSink)
				var target_metric := str(rule.get("target_metric", "")).to_upper().strip_edges()
				if not target_metric.is_empty() and rule.has("delta"):
					var base_delta: float = float(rule["delta"])
					var scale_by_horizon: bool = bool(rule.get("scale_by_horizon", false))
					var applied_delta: float = (base_delta * horizon_scale) if scale_by_horizon else base_delta
					var rec_scope := str(rule.get("target_scope", _ImpactRouter.get_metric_scope(target_metric))).to_upper().strip_edges()
					var rec_id := cand_id if rec_scope in ["ACTOR", "RESIDENT"] else str(rule.get("target_id", cand_id))
					_ImpactRouter.dispatch_delta(world_state, rec_id, target_metric, applied_delta)

				# 2. Optional follow-on action trigger (Leader never forced; non-Leader evaluated via OCEAN/probability)
				if rule.has("follow_on_action") and rule["follow_on_action"] is Dictionary:
					var act_cfg: Dictionary = rule["follow_on_action"]
					var is_leader := (cand_id == leader_id or cand_id == "PLAYER")
					if is_leader:
						continue
					var res_rec: Dictionary = _lookup_resident_record(residents_dict, cand_id)
					if _should_non_leader_act(sim_day, rule_id, cand_id, res_rec, act_cfg):
						var follow_verb := str(act_cfg.get("verb", "")).to_upper().strip_edges()
						if not follow_verb.is_empty():
							var follow_dir: Dictionary = {
								"verb": follow_verb,
								"initiator_id": cand_id,
								"assigned_to": cand_id,
								"target_resident_id": cand_id,
								"target_node_id": str(res_rec.get("current_district_id", "")),
								"cascade_source": rule_id
							}
							var f_res: Dictionary = execute_directive(world_state, follow_dir)
							var f_msg := str(f_res.get("message", follow_verb))
							executed_events.append({
								"trigger_type": "CASCADE_ACTION",
								"day_offset": sim_day,
								"calendar_date": cal_date,
								"week": week_num,
								"day_of_week": dow,
								"verb": follow_verb,
								"target_item": rule_id,
								"success": bool(f_res.get("success", false)),
								"message": f_msg,
								"author": _resolve_directive_author(world_state, follow_dir),
								"target_node_id": str(follow_dir.get("target_node_id", "")),
								"directive_snapshot": follow_dir
							})
							diary_memos.append(f_msg)

static func _matches_cascade_gate(
	world_state: Dictionary,
	entity_id: String,
	directive: Dictionary,
	rule: Dictionary
) -> bool:
	if not _matches_impact_conditions(world_state, directive, rule):
		return false

	var gate: Dictionary = rule.get("metric_gate", {}) if rule.get("metric_gate", null) is Dictionary else {}
	if gate.is_empty():
		return true

	var metric_field := str(gate.get("field", "")).strip_edges()
	if metric_field.is_empty():
		return true

	var curr_val: float = _read_zero_baseline_metric(world_state, entity_id, metric_field)
	var target_val: float = float(gate.get("value", 0.0))
	var op := str(gate.get("operator", ">=")).strip_edges()
	return _ConditionEvaluator.evaluate_gate({
		"current": curr_val,
		"target": target_val,
		"operator": op
	})

static func _read_zero_baseline_metric(world_state: Dictionary, entity_id: String, field_name: String) -> float:
	var residents_dict: Dictionary = world_state.get("residents", {})
	var rec: Dictionary = _lookup_resident_record(residents_dict, entity_id)
	if not rec.is_empty():
		return float(rec.get(field_name, 0.0))

	for pool_key in ["districts", "establishments", "caches"]:
		var pool: Dictionary = world_state.get(pool_key, {})
		if pool.has(entity_id) and pool[entity_id] is Dictionary:
			return float(pool[entity_id].get(field_name, 0.0))
		if entity_id.is_valid_int() and pool.has(int(entity_id)) and pool[int(entity_id)] is Dictionary:
			return float(pool[int(entity_id)].get(field_name, 0.0))

	return 0.0

static func _should_non_leader_act(
	sim_day: int,
	rule_id: String,
	actor_id: String,
	res_rec: Dictionary,
	act_cfg: Dictionary
) -> bool:
	var base_prob: float = float(act_cfg.get("base_probability", 0.5))
	var trait_name := str(act_cfg.get("ocean_trait", "")).to_lower().strip_edges()
	var trait_weight: float = float(act_cfg.get("ocean_weight", 0.0))
	if not trait_name.is_empty() and not res_rec.is_empty():
		var trait_val: float = float(res_rec.get(trait_name, 0.5))
		base_prob += (trait_val - 0.5) * trait_weight

	var clamped_prob: float = clampf(base_prob, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("CASCADE_ACT:%d:%s:%s" % [sim_day, rule_id, actor_id])
	return rng.randf() <= clamped_prob

static func _lookup_resident_record(residents_dict: Dictionary, entity_id: String) -> Dictionary:
	if residents_dict.has(entity_id) and residents_dict[entity_id] is Dictionary:
		return residents_dict[entity_id]
	if entity_id.is_valid_int() and residents_dict.has(int(entity_id)) and residents_dict[int(entity_id)] is Dictionary:
		return residents_dict[int(entity_id)]
	return {}