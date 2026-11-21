# res://systems/docket_manager.gd
class_name DocketManager extends RefCounted

const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")
const MEMO_GEN = preload("res://systems/memo_generator.gd")
const STANDING_ORDER_PROCESSOR = preload("res://systems/standing_order_processor.gd")

## Clones any task (from history or active docket) into a fresh, mutable directive
static func duplicate_task(source_task: Dictionary) -> Dictionary:
	var cloned = source_task.duplicate(true)
	cloned["id"] = "TASK_%d_%d" % [Time.get_ticks_msec(), randi() % 1000]
	cloned["status"] = "STAGED"
	# Remove past execution timestamps, keeping operational intent
	cloned.erase("executed_tick")
	cloned.erase("execution_result")
	return cloned

## Adds an intention to the general To-Do Backlog
static func add_to_backlog(world_state: Dictionary, directive: Dictionary) -> void:
	if not world_state.has("todo_backlog"):
		world_state["todo_backlog"] = []
	world_state["todo_backlog"].append(directive)

## Assigns a task from backlog (or directly) into an operational time slot
static func schedule_to_slot(world_state: Dictionary, task: Dictionary, slot_id: String) -> bool:
	if not world_state.has("active_docket"):
		world_state["active_docket"] = {}

	# Allows any user-defined slot granularity (e.g. "TICK_12", "DAY_2_SHIFT_1", "OCT_WK1")
	world_state["active_docket"][slot_id] = task
	return true

## Delegates standing-order day hydration to StandingOrderProcessor
static func hydrate_standing_orders_for_day(world_state: Dictionary, sim_day: int, resident_filter: Variant = null) -> Array[Dictionary]:
	return STANDING_ORDER_PROCESSOR.hydrate_for_day(world_state, sim_day, duplicate_task, resident_filter)

## Delegates planning-fat and OCEAN conflict queue resolution to StandingOrderProcessor
static func resolve_operative_shift_plan(
	world_state: Dictionary,
	resident_id: Variant,
	adhoc_tasks: Array,
	standing_tasks: Array
) -> Dictionary:
	return STANDING_ORDER_PROCESSOR.resolve_operative_shift_plan(world_state, resident_id, adhoc_tasks, standing_tasks)

## Executes a task at its scheduled time, handling 'planning on margin' (bounces)
static func execute_scheduled_task(world_state: Dictionary, task: Dictionary) -> Dictionary:
	var verb: String = task.get("verb", "")
	var result: Dictionary = SIM_CONTROLLER.execute_directive(world_state, task)

	if not result.get("success", false):
		_penalize_aborted_attempt(world_state, task, result.get("message", "Insufficient Assets"))
		task["status"] = "BOUNCED"
		return {
			"status": "BOUNCED",
			"success": false,
			"message": "⚠️ Bounced [%s]: %s" % [verb, result.get("message", "Conditions unmet")]
		}

	task["status"] = "COMPLETED"
	return {
		"status": "COMPLETED",
		"success": true,
		"message": result.get("message", "Done")
	}

static func _penalize_aborted_attempt(world_state: Dictionary, task: Dictionary, reason: String) -> void:
	var target_node = task.get("target_node_id", "HQ")
	var delta_fatigue = 5.0
	IMPACT_ROUTER.dispatch_delta(world_state, target_node, "FATIGUE", delta_fatigue)

## Evaluates whether a task is eligible to run right now
static func is_task_runnable(world_state: Dictionary, task: Dictionary, current_time_tick: int) -> Dictionary:
	if task.get("status", "PENDING") == "COMPLETED":
		return {"runnable": false, "reason": "Already completed"}

	var earliest_tick: int = task.get("earliest_tick", 0)
	if current_time_tick < earliest_tick:
		return {
			"runnable": false,
			"reason": "Time locked (Unlocks at Tick %d, Current is %d)" % [earliest_tick, current_time_tick]
		}

	var completed_tasks: Array = world_state.get("completed_task_ids", [])
	var dependencies: Array = task.get("depends_on", [])
	for dep_id in dependencies:
		if not completed_tasks.has(dep_id):
			return {
				"runnable": false,
				"reason": "Waiting on prerequisite task: %s" % dep_id
			}

	return {"runnable": true, "reason": "Ready"}

## Resolves the single best task to execute from a candidate pool
static func get_next_executable_task(world_state: Dictionary, task_pool: Array, current_time_tick: int) -> Dictionary:
	var runnable_candidates: Array = []

	for task in task_pool:
		var check = is_task_runnable(world_state, task, current_time_tick)
		if check["runnable"]:
			runnable_candidates.append(task)

	if runnable_candidates.is_empty():
		return {}

	runnable_candidates.sort_custom(func(a, b):
		return a.get("priority", 0) > b.get("priority", 0)
	)

	return runnable_candidates[0]

## Marks a task complete and logs its ID into world_state
static func mark_task_completed(world_state: Dictionary, task: Dictionary) -> void:
	task["status"] = "COMPLETED"
	if not world_state.has("completed_task_ids"):
		world_state["completed_task_ids"] = []

	var task_id = task.get("id", "")
	if task_id != "" and not world_state["completed_task_ids"].has(task_id):
		world_state["completed_task_ids"].append(task_id)

## Resolves the next executable task, strictly bounded by the assigned staff member's cognitive limits
static func get_next_task_for_staff(world_state: Dictionary, task_pool: Array, current_time_tick: int, staff_profile: Dictionary) -> Dictionary:
	if task_pool.is_empty():
		return {}

	var horizon_limit: int = staff_profile.get("planning_horizon_limit", 3)
	var max_prereqs: int = staff_profile.get("max_dependency_depth", 1)
	var can_scan_opportunistically: bool = staff_profile.get("opportunity_scanning", false)

	var sorted_pool: Array = task_pool.duplicate(true)
	sorted_pool.sort_custom(func(a, b):
		return a.get("priority", 0) > b.get("priority", 0)
	)

	var visible_tasks: Array = sorted_pool.slice(0, horizon_limit)

	for i in range(visible_tasks.size()):
		var task: Dictionary = visible_tasks[i]
		var prereqs: Array = task.get("depends_on", [])
		if prereqs.size() > max_prereqs:
			continue

		var check = is_task_runnable(world_state, task, current_time_tick)
		if check["runnable"]:
			return task
		else:
			if not can_scan_opportunistically:
				return {}

	return {}

static func execute_staff_shift(world_state: Dictionary, staff: Dictionary, assigned_tasks: Array, current_day_tick: int) -> Dictionary:
	var shift_report = {
		"staff_id": staff.get("id", ""),
		"idle_ticks_waiting": 0,
		"overtime_worked": false,
		"fatigue_added": 0.0,
		"missed_tasks": [],
		"completed_tasks": []
	}

	var task_pool = assigned_tasks.duplicate(true)
	var current_time = 9

	while not task_pool.is_empty() and current_time <= 22:
		var task = get_next_task_for_staff(world_state, task_pool, current_time, staff)

		if task.is_empty():
			shift_report["idle_ticks_waiting"] += 1
			current_time += 1
			continue

		task_pool.erase(task)

		var closing_tick = task.get("closing_tick", 24)
		if current_time >= closing_tick:
			shift_report["missed_tasks"].append({
				"task_name": task.get("name", task.get("verb", "")),
				"reason": "SHOP_CLOSED"
			})
			continue

		var result = SIM_CONTROLLER.execute_directive(world_state, task)
		if result.get("success", false):
			mark_task_completed(world_state, task)
			shift_report["completed_tasks"].append(task)
		else:
			shift_report["missed_tasks"].append({
				"task_name": task.get("name", task.get("verb", "")),
				"reason": "INSUFFICIENT_FUNDS"
			})

		current_time += 2

		if current_time > 18:
			shift_report["overtime_worked"] = true
			shift_report["fatigue_added"] += 15.0

	var note_text = MEMO_GEN.generate_shift_feedback(staff, shift_report)

	if not world_state.has("memo_backlog"):
		world_state["memo_backlog"] = []
	world_state["memo_backlog"].append({
		"tick": current_day_tick,
		"text": note_text
	})

	return shift_report