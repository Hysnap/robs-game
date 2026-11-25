# res://systems/action_pipeline/action_primitives.gd
class_name ActionPrimitives
extends RefCounted

const ActionPipelineHelpersScript = preload("res://systems/action_pipeline/action_pipeline_helpers.gd")
const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")
const SpatialRoutePlannerScript = preload("res://systems/spatial_route_planner.gd")

static var _registry: Dictionary = {
	"REQUIRE": execute_require,
	"MOVE_ACTOR": execute_move_actor,
	"TRANSFER_ITEM": execute_transfer_item,
	"DEDUCT_ITEM": execute_deduct_item,
	"CREDIT_ITEM": execute_credit_item
}

## Registers a new primitive execution function into the switchboard
static func register_primitive(token: String, fn: Callable) -> void:
	_registry[token.to_upper().strip_edges()] = fn

## Universal dispatch entry point
static func dispatch(primitive_token: String, world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var clean_token: String = primitive_token.to_upper().strip_edges()
	if not _registry.has(clean_token):
		push_error("[ActionPrimitives] FAIL_LOUD: Unregistered primitive '%s' at step '%s'" % [primitive_token, step_id])
		return { "success": false }

	var fn: Callable = _registry[clean_token]
	return fn.call(world_state, directive, params, step_id)

# -----------------------------------------------------------------------------
# Micro-Verb Primitives (Pure Mechanical Execution)
# -----------------------------------------------------------------------------

## Primitive 1: REQUIRE (Explicit Gate - Single or Compound Logic Gate across COMMODITY, LOCATION, ATTRIBUTE, or PARAM)
static func execute_require(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	if params.has("conditions") and params["conditions"] is Array:
		var logic_gate: String = str(params.get("logic_gate", "AND"))
		var resolved_gates: Array = []
		for cond in params["conditions"]:
			if cond is Dictionary:
				var gate_res: Dictionary = _evaluate_single_require(world_state, directive, cond, step_id)
				resolved_gates.append({
					"current": 1.0 if bool(gate_res.get("success", false)) else 0.0,
					"target": 1.0,
					"operator": "=="
				})
		return { "success": ConditionEvaluatorScript.evaluate_logic_block(logic_gate, resolved_gates) }

	return _evaluate_single_require(world_state, directive, params, step_id)

static func _evaluate_single_require(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var op: String = str(params.get("operator", "=="))
	var domain: String = str(params.get("domain", "COMMODITY")).to_upper().strip_edges()

	if domain == "PARAM":
		var current_param: Variant = ActionPipelineHelpersScript.resolve_param_value(params.get("metric", ""), directive, world_state)
		var expected_param: Variant = ActionPipelineHelpersScript.resolve_param_value(params.get("value", ""), directive, world_state)
		var passed: bool = ConditionEvaluatorScript.evaluate_gate({
			"current": current_param,
			"target": expected_param,
			"operator": op
		})
		return { "success": passed }

	var raw_actor: Variant = ActionPipelineHelpersScript.resolve_param_value(params.get("actor", ""), directive, world_state)
	var actor_key: Variant = ActionPipelineHelpersScript.normalize_entity_key(raw_actor)

	match domain:
		"COMMODITY":
			var metric_token: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("metric", ""), directive, world_state))
			var threshold: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("value", 0.0), directive, world_state))
			var passed: bool = ActionPipelineHelpersScript.evaluate_commodity_gate(world_state, actor_key, metric_token, threshold, op)
			return { "success": passed }

		"LOCATION":
			var expected_loc: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("value", ""), directive, world_state)).strip_edges()
			
			var residents_dict: Dictionary = world_state.get("residents", {})
			if not residents_dict.has(actor_key):
				push_error("[ActionPrimitives] FAIL_LOUD: Actor '%s' not found in canonical residents registry at step '%s'" % [str(actor_key), step_id])
				return { "success": false }
				
			var current_loc: String = str(residents_dict[actor_key].get("current_district_id", "")).strip_edges()
			var passed: bool = ConditionEvaluatorScript.evaluate_string(current_loc, expected_loc, op)
			return { "success": passed }

		"ATTRIBUTE":
			var metric_token: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("metric", ""), directive, world_state))
			var threshold: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("value", 0.0), directive, world_state))
			var current_val: float = ActionPipelineHelpersScript.get_entity_attribute(world_state, actor_key, metric_token)
			if current_val == -INF:
				return { "success": false }
			return { "success": ConditionEvaluatorScript.evaluate(current_val, threshold, op) }

		_:
			push_error("[ActionPrimitives] FAIL_LOUD: Unknown REQUIRE domain '%s' at step '%s'" % [domain, step_id])
			return { "success": false }

## Primitive 2: MOVE_ACTOR (Spatial Migration + Multi-Modal Route Planning)
static func execute_move_actor(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var raw_actor: Variant = ActionPipelineHelpersScript.resolve_param_value(params.get("actor", ""), directive, world_state)
	var actor_key: Variant = ActionPipelineHelpersScript.normalize_entity_key(raw_actor)
	var dest_district: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("destination", ""), directive, world_state)).strip_edges()
	if dest_district.is_empty():
		dest_district = str(directive.get("target_node_id", "")).strip_edges()

	var residents_dict: Dictionary = world_state.get("residents", {})
	if not residents_dict.has(actor_key):
		push_error("[ActionPrimitives] FAIL_LOUD: MOVE_ACTOR cannot find resident '%s' at step '%s'" % [str(actor_key), step_id])
		return { "success": false }

	var districts_dict: Dictionary = world_state.get("districts", {})
	if dest_district.is_empty() or not districts_dict.has(dest_district):
		push_error("[ActionPrimitives] FAIL_LOUD: MOVE_ACTOR invalid or missing destination district '%s' at step '%s'" % [dest_district, step_id])
		return { "success": false }

	var resident_entry: Dictionary = residents_dict[actor_key]
	var origin_district: String = str(resident_entry.get("current_district_id", "")).strip_edges()
	if origin_district == dest_district:
		return { "success": true }

	var route_options: Dictionary = {
		"actor_id": str(actor_key),
		"service_id": str(directive.get("service_id", params.get("service_id", "AUTO"))),
		"routing_policy": str(directive.get("routing_policy", params.get("routing_policy", "SHORTEST"))),
		"waypoints": directive.get("waypoints", params.get("waypoints", [])),
		"is_off_peak": bool(directive.get("is_off_peak", false))
	}

	var route_plan: Dictionary = SpatialRoutePlannerScript.plan_route(world_state, origin_district, dest_district, route_options)
	if not bool(route_plan.get("reachable", false)):
		push_error("[ActionPrimitives] FAIL_LOUD: MOVE_ACTOR route unreachable from '%s' to '%s' (%s)" % [
			origin_district, dest_district, str(route_plan.get("error_code", "ROUTE_UNREACHABLE"))
		])
		return { "success": false }

	if not directive.has("context") or not (directive["context"] is Dictionary):
		directive["context"] = {}
	directive["context"]["route_plan"] = route_plan
	resident_entry["current_district_id"] = dest_district

	return { "success": true }

## Primitive 3: TRANSFER_ITEM (Pure Physical Commodity Handover)
static func execute_transfer_item(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var from_entity: Variant = ActionPipelineHelpersScript.normalize_entity_key(ActionPipelineHelpersScript.resolve_param_value(params.get("from", ""), directive, world_state))
	var to_entity: Variant = ActionPipelineHelpersScript.normalize_entity_key(ActionPipelineHelpersScript.resolve_param_value(params.get("to", ""), directive, world_state))
	var item_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("item_id", ""), directive, world_state)).to_upper().strip_edges()
	var quantity: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("quantity", 0.0), directive, world_state))

	var from_empty: bool = (from_entity is int and from_entity <= 0) or (from_entity is String and str(from_entity).is_empty())
	var to_empty: bool = (to_entity is int and to_entity <= 0) or (to_entity is String and str(to_entity).is_empty())
	if from_empty or to_empty or item_id.is_empty() or quantity <= 0.0:
		push_error("[ActionPrimitives] FAIL_LOUD: TRANSFER_ITEM invalid arguments at step '%s' (from: '%s', to: '%s', item: '%s', qty: %f)" % [step_id, str(from_entity), str(to_entity), item_id, quantity])
		return { "success": false }

	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, from_entity, item_id, -quantity)
	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, to_entity, item_id, quantity)

	return { "success": true }

## Primitive 4: DEDUCT_ITEM (Unilateral Commodity Deduction / Disposal / Consumption)
static func execute_deduct_item(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var from_entity: Variant = ActionPipelineHelpersScript.normalize_entity_key(ActionPipelineHelpersScript.resolve_param_value(params.get("from", ""), directive, world_state))
	var item_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("item_id", ""), directive, world_state)).to_upper().strip_edges()
	var quantity: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("quantity", 0.0), directive, world_state))

	var from_empty: bool = (from_entity is int and from_entity <= 0) or (from_entity is String and str(from_entity).is_empty())
	if from_empty or item_id.is_empty() or quantity <= 0.0:
		push_error("[ActionPrimitives] FAIL_LOUD: DEDUCT_ITEM invalid arguments at step '%s' (from: '%s', item: '%s', qty: %f)" % [step_id, str(from_entity), item_id, quantity])
		return { "success": false }

	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, from_entity, item_id, -quantity)

	return { "success": true }

## Primitive 5: CREDIT_ITEM (Unilateral Commodity Credit / Production Yield / Grant)
static func execute_credit_item(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var to_entity: Variant = ActionPipelineHelpersScript.normalize_entity_key(ActionPipelineHelpersScript.resolve_param_value(params.get("to", ""), directive, world_state))
	var item_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("item_id", ""), directive, world_state)).to_upper().strip_edges()
	var quantity: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("quantity", 0.0), directive, world_state))

	var to_empty: bool = (to_entity is int and to_entity <= 0) or (to_entity is String and str(to_entity).is_empty())
	if to_empty or item_id.is_empty() or quantity <= 0.0:
		push_error("[ActionPrimitives] FAIL_LOUD: CREDIT_ITEM invalid arguments at step '%s' (to: '%s', item: '%s', qty: %f)" % [step_id, str(to_entity), item_id, quantity])
		return { "success": false }

	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, to_entity, item_id, quantity)

	return { "success": true }