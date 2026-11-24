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
## and partitions active/impacted districts (fine resolution) from background districts (coarse cohort rollover).
static func process_turn_cycle(world_state: Dictionary, staged_directives: Array) -> Dictionary:
	SystemLogger.log_info("[SimController] Processing turn cycle with %d staged directives." % staged_directives.size())
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

	var day_queue: Array[Dictionary] = _build_day_execution_queue(world_state, staged_directives, start_day, diary_memos)
	var halted_agents: Dictionary = {}

	if not day_queue.is_empty():
		for i in range(day_queue.size()):
			var directive: Dictionary = day_queue[i]
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
		if step > 1:
			_execute_standing_orders_for_rollover_day(world_state, day_tick, executed_events, diary_memos)
		var daily_res: Dictionary = _ObligationLedger.process_daily_tick(day_tick)
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

	var active_slot := str(meta.get("active_slot_id", "slot_01"))
	SaveManager.save_turn_snapshot(active_slot, current_day, world_state)
	SystemLogger.log_info("[SimController] Turn cycle advanced to day %d (horizon=%s, active_districts=%d, background_districts=%d, week_rollover=%s)." % [
		current_day, horizon, district_partition["active_districts"].size(), district_partition["background_count"], crossed_boundary
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
		"obligation_rollover": obligation_rollover,
		"executed_events": executed_events,
		"diary_memos": diary_memos
	}

## Merges staged ad-hoc directives with due standing orders using planning fat and OCEAN/cognitive resolution
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

	var final_queue: Array[Dictionary] = []
	for u_task in unassigned_adhoc:
		final_queue.append(u_task)

	for agent_key in all_agent_keys.keys():
		var a_list: Array = adhoc_by_agent.get(agent_key, [])
		var s_list: Array = standing_by_agent.get(agent_key, [])
		var plan: Dictionary = _StandingOrderProcessor.resolve_operative_shift_plan(world_state, agent_key, a_list, s_list)
		for q_item in plan.get("queue", []):
			if q_item is Dictionary:
				final_queue.append(q_item)
		for m_txt in plan.get("memos", []):
			var memo_str: String = str(m_txt)
			diary_memos.append(memo_str)
			if not world_state.has("memo_backlog") or not (world_state["memo_backlog"] is Array):
				world_state["memo_backlog"] = []
			world_state["memo_backlog"].append({
				"tick": sim_day,
				"text": memo_str
			})

	return final_queue

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

	for task in due_tasks:
		var res: Dictionary = execute_directive(world_state, task)
		var ok: bool = bool(res.get("success", false))
		var msg: String = str(res.get("message", TranslationServer.translate("FEEDBACK_TASK_GENERIC_SUCCESS")))
		executed_events.append({
			"trigger_type": "STANDING_ORDER_EXECUTION",
			"day_offset": day_tick,
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