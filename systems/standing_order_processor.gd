# res://systems/standing_order_processor.gd
class_name StandingOrderProcessor
extends RefCounted

const MEMO_GEN = preload("res://systems/memo_generator.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

## Returns true if the operative's recurring orders are explicitly paused for sim_day
static func is_paused_for_day(world_state: Dictionary, resident_id: Variant, sim_day: int) -> bool:
	var ops: Dictionary = world_state.get("operations", {})
	var paused_map: Dictionary = ops.get("paused_standing_orders_day", {})
	var key_str: String = str(resident_id)
	if paused_map.has(key_str) and int(paused_map[key_str]) == sim_day:
		return true
	if paused_map.has(resident_id) and int(paused_map[resident_id]) == sim_day:
		return true
	return false

## Sets or clears a single-day pause on recurring standing orders for an operative
static func set_paused_for_day(world_state: Dictionary, resident_id: Variant, sim_day: int, paused: bool) -> void:
	if not world_state.has("operations") or not (world_state["operations"] is Dictionary):
		world_state["operations"] = {}
	var ops: Dictionary = world_state["operations"]
	if not ops.has("paused_standing_orders_day") or not (ops["paused_standing_orders_day"] is Dictionary):
		ops["paused_standing_orders_day"] = {}
	var paused_map: Dictionary = ops["paused_standing_orders_day"]
	var key_str: String = str(resident_id)
	if paused:
		paused_map[key_str] = sim_day
	else:
		paused_map.erase(key_str)

## Evaluates whether a single standing order rule triggers on sim_day
static func is_order_due_on_day(world_state: Dictionary, order: Dictionary, sim_day: int) -> bool:
	if not bool(order.get("is_active", true)):
		return false

	var cadence: String = str(order.get("cadence_rule", "DAILY")).to_upper().strip_edges()
	var params: Dictionary = order.get("cadence_params", {})
	if params.is_empty() and order.has("cadence_params_json"):
		var parsed = JSON.parse_string(str(order["cadence_params_json"]))
		if parsed is Dictionary:
			params = parsed

	match cadence:
		"DAILY":
			return true
		"WEEKDAYS":
			var dow: int = CALENDAR_HELPER.day_of_week(sim_day)
			var allowed_days: Array = params.get("weekdays", [1, 2, 3, 4, 5])
			for d in allowed_days:
				if int(d) == dow:
					return true
			return false
		"SPECIFIC_DAYS":
			var target_days: Array = params.get("days", [])
			for td in target_days:
				if int(td) == sim_day:
					return true
			var dow_val: int = CALENDAR_HELPER.day_of_week(sim_day)
			for wd in params.get("weekdays", []):
				if int(wd) == dow_val:
					return true
			return false
		"ON_STOCK_BELOW_THRESHOLD":
			var item_id: String = str(params.get("item_id", "")).strip_edges()
			var min_qty: float = float(params.get("min_qty", 0.0))
			if item_id.is_empty():
				return false
			return _resolve_monitored_stock_qty(world_state, params, item_id) < min_qty
		_:
			return false

static func _resolve_monitored_stock_qty(world_state: Dictionary, params: Dictionary, item_id: String) -> float:
	if params.has("cache_id"):
		var cache_id: String = str(params["cache_id"])
		var caches: Dictionary = world_state.get("caches", {})
		if caches.has(cache_id) and caches[cache_id] is Dictionary:
			return float(caches[cache_id].get("inventory", {}).get(item_id, 0.0))
	if params.has("establishment_id"):
		var est_id: Variant = params["establishment_id"]
		var est_key: Variant = int(str(est_id)) if str(est_id).is_valid_int() else est_id
		var estabs: Dictionary = world_state.get("establishments", {})
		if estabs.has(est_key) and estabs[est_key] is Dictionary:
			return float(estabs[est_key].get("inventory", {}).get(item_id, 0.0))
	return 0.0

## Hydrates due standing order tasks for a given day (respecting single-period pauses)
static func hydrate_for_day(
	world_state: Dictionary,
	sim_day: int,
	task_cloner: Callable,
	resident_filter: Variant = null
) -> Array[Dictionary]:
	var hydrated: Array[Dictionary] = []
	var orders: Array = world_state.get("standing_orders", [])
	if orders.is_empty():
		return hydrated

	var filter_active: bool = (resident_filter != null and str(resident_filter) != "")
	var filter_str: String = str(resident_filter)

	for order in orders:
		if not (order is Dictionary):
			continue
		var assigned_id: Variant = order.get("assigned_resident_id", "")
		if filter_active and str(assigned_id) != filter_str:
			continue
		if is_paused_for_day(world_state, assigned_id, sim_day):
			continue
		if not is_order_due_on_day(world_state, order, sim_day):
			continue

		var steps: Array = order.get("steps", [])
		if steps.is_empty() and order.has("steps_json"):
			var parsed_steps = JSON.parse_string(str(order["steps_json"]))
			if parsed_steps is Array:
				steps = parsed_steps

		var order_title: String = str(order.get("title", "STANDING_ORDER"))
		var order_prio: int = int(order.get("priority", 50))
		var est_hrs: float = float(order.get("estimated_hours", 2.0)) / float(maxi(1, steps.size()))

		for raw_step in steps:
			if not (raw_step is Dictionary):
				continue
			var task: Dictionary = task_cloner.call(raw_step)
			task["assigned_to"] = assigned_id
			task["standing_order_id"] = order.get("standing_order_id", 0)
			task["standing_order_title"] = order_title
			task["is_standing_order"] = true
			task["estimated_hours"] = float(task.get("estimated_hours", est_hrs))
			task["priority"] = int(task.get("priority", order_prio))
			hydrated.append(task)

	return hydrated

## Resolves an operative's shift queue when manual ad-hoc orders and due standing orders coexist,
## factoring in organization "planning fat" (available shift hours) and OCEAN/cognitive traits.
static func resolve_operative_shift_plan(
	world_state: Dictionary,
	resident_id: Variant,
	adhoc_tasks: Array,
	standing_tasks: Array
) -> Dictionary:
	var res_key: Variant = int(str(resident_id)) if str(resident_id).is_valid_int() else resident_id
	var res_rec: Dictionary = world_state.get("residents", {}).get(res_key, {})
	if res_rec.is_empty():
		res_rec = world_state.get("residents", {}).get(str(resident_id), {})

	var shift_limit: float = float(res_rec.get("daily_operational_limit_hours", 8.0))
	var standing_hours: float = 0.0
	for st in standing_tasks:
		standing_hours += float(st.get("estimated_hours", 2.0))

	var adhoc_hours: float = 0.0
	for at in adhoc_tasks:
		adhoc_hours += float(at.get("estimated_hours", 2.0))

	var planning_fat: float = shift_limit - standing_hours
	var total_needed: float = standing_hours + adhoc_hours

	var out_queue: Array[Dictionary] = []
	var dropped_standing: Array[Dictionary] = []
	var memos: Array[String] = []
	var resolution_mode: String = "STANDARD_COMBINED"

	# Ample planning fat or no collision: run manual ad-hoc first, then standing orders
	if standing_tasks.is_empty() or adhoc_tasks.is_empty() or total_needed <= shift_limit:
		for at in adhoc_tasks:
			out_queue.append(at)
		for st in standing_tasks:
			out_queue.append(st)
		return {
			"queue": out_queue,
			"dropped_standing": dropped_standing,
			"memos": memos,
			"mode": resolution_mode,
			"planning_fat_hours": planning_fat
		}

	# Lean organization collision: total hours exceed shift limit. Evaluate OCEAN + cognitive traits.
	var traits: Dictionary = res_rec.get("ocean_traits", res_rec)
	var conc: float = float(traits.get("conscientiousness", 0.5))
	var openn: float = float(traits.get("openness", 0.5))
	var agree: float = float(traits.get("agreeableness", 0.5))
	var neur: float = float(traits.get("neuroticism", 0.5))
	var agility: float = float(traits.get("mental_agility", 0.5))

	var has_adhd: bool = false
	var has_autism: bool = false
	for btag in res_rec.get("behavioral_tags", []):
		var code_str: String = str(btag.get("code", btag)) if btag is Dictionary else str(btag)
		if code_str == "ND_ADHD":
			has_adhd = true
		elif code_str == "ND_AUTISM_SPECTRUM":
			has_autism = true

	var staff_name: String = str(res_rec.get("name", res_rec.get("first_name", "Operative")))
	var loyalty: float = float(res_rec.get("loyalty", agree))
	var primary_standing_title: String = str(standing_tasks[0].get("standing_order_title", "STANDING_ORDER"))
	var primary_adhoc_verb: String = str(adhoc_tasks[0].get("verb", adhoc_tasks[0].get("type", "TASK")))
	var hours_over: float = total_needed - shift_limit

	if agility >= 0.65 and conc >= 0.60 and openn >= 0.55:
		resolution_mode = "CAN_MANAGE_BOTH"
		for at in adhoc_tasks:
			out_queue.append(at)
		for st in standing_tasks:
			out_queue.append(st)
	elif has_autism or (conc >= 0.65 and openn <= 0.38) or (neur >= 0.72 and total_needed > shift_limit * 1.15):
		resolution_mode = "RAISE_ISSUE_TO_BOSS"
		for at in adhoc_tasks:
			out_queue.append(at)
		for st in standing_tasks:
			dropped_standing.append(st)
		memos.append(MEMO_GEN.generate_standing_order_escalation_memo(staff_name, primary_standing_title, primary_adhoc_verb, hours_over))
	elif conc > 0.80 and openn < 0.35:
		resolution_mode = "STICK_TO_ROUTINE_WARN"
		for st in standing_tasks:
			out_queue.append(st)
		for at in adhoc_tasks:
			out_queue.append(at)
	elif has_adhd or _is_low_conscientious_pleaser(conc, agree, agility):
		# "The Billy Issue": prioritizes new ad-hoc order and silently drops/starves standing order
		resolution_mode = "PRIORITIZE_NEW_DROP_STANDING"
		for at in adhoc_tasks:
			out_queue.append(at)
		for st in standing_tasks:
			dropped_standing.append(st)
		memos.append(MEMO_GEN.generate_billy_issue_memo(staff_name, primary_standing_title, primary_adhoc_verb, loyalty))
	else:
		resolution_mode = "STANDARD_COMBINED"
		for at in adhoc_tasks:
			out_queue.append(at)
		for st in standing_tasks:
			out_queue.append(st)

	return {
		"queue": out_queue,
		"dropped_standing": dropped_standing,
		"memos": memos,
		"mode": resolution_mode,
		"planning_fat_hours": planning_fat
	}

static func _is_low_conscientious_pleaser(conc: float, agree: float, agility: float) -> bool:
	return (conc <= 0.42 and agree >= 0.58) or (agility <= 0.38 and conc <= 0.48)