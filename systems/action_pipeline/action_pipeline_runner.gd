# res://systems/action_pipeline/action_pipeline_runner.gd
class_name ActionPipelineRunner
extends RefCounted

const EngineResultScript = preload("res://systems/engine_result.gd")
const ActionPipelineHelpersScript = preload("res://systems/action_pipeline/action_pipeline_helpers.gd")
const ActionPrimitivesScript = preload("res://systems/action_pipeline/action_primitives.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")

## Primary headless entry point for executing a declarative composite action pipeline
static func run_action_pipeline(world_state: Dictionary, directive: Dictionary, verb_def: Dictionary, impacts_dir: String = "") -> Dictionary:
	var verb_token: String = str(verb_def.get("_meta", {}).get("verb_token", directive.get("verb", "UNKNOWN"))).to_upper()
	var steps: Array = verb_def.get("steps", [])
	var target_node: String = str(directive.get("target_node_id", ""))
	var actor_id: String = ActionPipelineHelpersScript.resolve_actor_id(directive)

	if steps.is_empty():
		return EngineResultScript.fail(
			EngineResultScript.ErrorCode.INVALID_PARAMETER,
			verb_token,
			"FAIL_LOUD: Pipeline definition for '%s' contains no executable steps." % verb_token,
			target_node
		).to_dict()

	var step_map: Dictionary = {}
	for i in range(steps.size()):
		var step: Dictionary = steps[i]
		var s_id: String = str(step.get("step_id", str(i)))
		step_map[s_id] = step

	var current_step_id: String = str(steps[0].get("step_id", "0"))
	var accumulated_time: float = 0.0
	var accumulated_fatigue: float = 0.0
	var executed_step_ids: Array[String] = []
	var visited_step_count: int = 0
	var max_steps: int = steps.size() * 4 # Infinite loop / cycle breaker

	while not current_step_id.is_empty() and visited_step_count < max_steps:
		visited_step_count += 1
		if not step_map.has(current_step_id):
			return EngineResultScript.fail(
				EngineResultScript.ErrorCode.INTERNAL_SIM_ERROR,
				verb_token,
				"FAIL_LOUD: Pipeline jump to unknown step ID: '%s'" % current_step_id,
				target_node
			).to_dict()

		var step_def: Dictionary = step_map[current_step_id]
		executed_step_ids.append(current_step_id)

		# Execute atomic primitive dynamically via ActionPrimitives registry
		var step_outcome: Dictionary = _dispatch_primitive(world_state, directive, step_def, impacts_dir)
		var nominal_cost: Dictionary = step_def.get("nominal_cost", {})
		var step_time: float = float(step_outcome.get("time_spent", nominal_cost.get("time_spent", 0.0)))
		var step_fatigue: float = float(step_outcome.get("fatigue", nominal_cost.get("fatigue", 0.0)))

		# Commit accumulated time and fatigue to operative
		accumulated_time += step_time
		accumulated_fatigue += step_fatigue
		ActionPipelineHelpersScript.apply_time_and_fatigue(world_state, actor_id, step_time, step_fatigue)

		# Evaluate success / failure
		if not bool(step_outcome.get("success", false)):
			var on_failure: Dictionary = step_def.get("on_failure", {})
			var penalties: Dictionary = on_failure.get("penalties", {})

			# Asymmetric verification delay
			var penalty_time: float = float(penalties.get("extra_time_spent", 0.0))
			var penalty_fatigue: float = float(penalties.get("extra_fatigue", 0.0))
			accumulated_time += penalty_time
			accumulated_fatigue += penalty_fatigue
			ActionPipelineHelpersScript.apply_time_and_fatigue(world_state, actor_id, penalty_time, penalty_fatigue)

			# Route contextual failure penalties (e.g. reputation loss)
			for p_key in penalties.keys():
				if p_key not in ["extra_time_spent", "extra_fatigue"]:
					ImpactRouterScript.dispatch_delta(world_state, target_node, str(p_key).to_upper(), float(penalties[p_key]))

			var err_code_str: String = str(on_failure.get("error_code", "GENERIC_FAILURE"))
			var err_enum: int = ActionPipelineHelpersScript.resolve_error_code(err_code_str)
			var reason_msg: String = str(step_outcome.get("message", "Step '%s' halted." % current_step_id))

			return EngineResultScript.fail(
				err_enum,
				verb_token,
				reason_msg,
				target_node,
				{
					"halted_step": current_step_id,
					"time_spent": accumulated_time,
					"fatigue_accrued": accumulated_fatigue,
					"steps_completed": executed_step_ids
				}
			).to_dict()

		# Branching / sequential progression
		if step_def.has("next_step"):
			var nxt = step_def.get("next_step")
			current_step_id = str(nxt) if nxt != null else ""
		else:
			# Implicit sequential fallthrough
			var curr_idx: int = -1
			for i in range(steps.size()):
				if str(steps[i].get("step_id", str(i))) == current_step_id:
					curr_idx = i
					break
			if curr_idx >= 0 and curr_idx + 1 < steps.size():
				current_step_id = str(steps[curr_idx + 1].get("step_id", str(curr_idx + 1)))
			else:
				current_step_id = ""

	return EngineResultScript.ok(
		verb_token,
		"Action completed successfully.",
		{},
		float(directive.get("amount", 1.0)),
		target_node,
		{
			"time_spent": accumulated_time,
			"fatigue_accrued": accumulated_fatigue,
			"steps_completed": executed_step_ids
		}
	).to_dict()

## Resolves and executes a single micro-verb primitive dynamically via ActionPrimitives registry
static func _dispatch_primitive(world_state: Dictionary, directive: Dictionary, step_def: Dictionary, impacts_dir: String) -> Dictionary:
	var primitive: String = str(step_def.get("primitive", "")).to_upper()
	var params: Dictionary = step_def.get("params", {})
	var step_id: String = str(step_def.get("step_id", "unknown_step"))

	return ActionPrimitivesScript.dispatch(primitive, world_state, directive, params, step_id, impacts_dir)