# res://systems/action_pipeline/action_primitives.gd
class_name ActionPrimitives
extends RefCounted

const ActionPipelineHelpersScript = preload("res://systems/action_pipeline/action_pipeline_helpers.gd")
const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")

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

## Primitive 1: REQUIRE (Explicit Gate - COMMODITY, LOCATION, or ATTRIBUTE)
static func execute_require(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var actor_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("actor", ""), directive, world_state))
	var op: String = str(params.get("operator", "=="))
	var domain: String = str(params.get("domain", "COMMODITY")).to_upper().strip_edges()

	match domain:
		"COMMODITY":
			var metric_token: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("metric", ""), directive, world_state))
			var threshold: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("value", 0.0), directive, world_state))
			var passed: bool = ActionPipelineHelpersScript.evaluate_commodity_gate(world_state, actor_id, metric_token, threshold, op)
			return { "success": passed }

		"LOCATION":
			var expected_loc: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("value", ""), directive, world_state)).strip_edges()
			
			var residents_dict: Dictionary = world_state.get("residents", {})
			if not residents_dict.has(actor_id):
				push_error("[ActionPrimitives] FAIL_LOUD: Actor '%s' not found in canonical residents registry at step '%s'" % [actor_id, step_id])
				return { "success": false }
				
			var current_loc: String = str(residents_dict[actor_id].get("current_district_id", "")).strip_edges()
			var passed: bool = (current_loc == expected_loc) if op == "==" else (current_loc != expected_loc)
			return { "success": passed }

		"ATTRIBUTE":
			var metric_token: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("metric", ""), directive, world_state))
			var threshold: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("value", 0.0), directive, world_state))
			var current_val: float = ActionPipelineHelpersScript.get_entity_attribute(world_state, actor_id, metric_token)
			if current_val == -INF:
				return { "success": false }
			return { "success": ConditionEvaluatorScript.evaluate(current_val, threshold, op) }

		_:
			push_error("[ActionPrimitives] FAIL_LOUD: Unknown REQUIRE domain '%s' at step '%s'" % [domain, step_id])
			return { "success": false }

## Primitive 2: MOVE_ACTOR (Pure Spatial Migration)
static func execute_move_actor(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var actor_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("actor", ""), directive, world_state))
	var dest_district: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("destination", ""), directive, world_state))

	var staff_dict: Dictionary = world_state.get("staff", {})
	if not staff_dict.has(actor_id):
		push_error("[ActionPrimitives] FAIL_LOUD: MOVE_ACTOR cannot find staff '%s' at step '%s'" % [actor_id, step_id])
		return { "success": false }

	var staff_entry: Dictionary = staff_dict[actor_id]
	var origin_district: String = str(staff_entry.get("current_district_id", ""))
	if origin_district != dest_district and not dest_district.is_empty():
		staff_entry["current_district_id"] = dest_district

	return { "success": true }

## Primitive 3: TRANSFER_ITEM (Pure Physical Commodity Handover)
static func execute_transfer_item(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var from_entity: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("from", ""), directive, world_state))
	var to_entity: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("to", ""), directive, world_state))
	var item_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("item_id", ""), directive, world_state)).to_upper().strip_edges()
	var quantity: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("quantity", 0.0), directive, world_state))

	if from_entity.is_empty() or to_entity.is_empty() or item_id.is_empty() or quantity <= 0.0:
		push_error("[ActionPrimitives] FAIL_LOUD: TRANSFER_ITEM invalid arguments at step '%s' (from: '%s', to: '%s', item: '%s', qty: %f)" % [step_id, from_entity, to_entity, item_id, quantity])
		return { "success": false }

	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, from_entity, item_id, -quantity)
	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, to_entity, item_id, quantity)

	return { "success": true }

## Primitive 4: DEDUCT_ITEM (Unilateral Commodity Deduction / Disposal / Consumption)
static func execute_deduct_item(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var from_entity: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("from", ""), directive, world_state)).strip_edges()
	var item_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("item_id", ""), directive, world_state)).to_upper().strip_edges()
	var quantity: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("quantity", 0.0), directive, world_state))

	if from_entity.is_empty() or item_id.is_empty() or quantity <= 0.0:
		push_error("[ActionPrimitives] FAIL_LOUD: DEDUCT_ITEM invalid arguments at step '%s' (from: '%s', item: '%s', qty: %f)" % [step_id, from_entity, item_id, quantity])
		return { "success": false }

	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, from_entity, item_id, -quantity)

	return { "success": true }

## Primitive 5: CREDIT_ITEM (Unilateral Commodity Credit / Production Yield / Grant)
static func execute_credit_item(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	var to_entity: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("to", ""), directive, world_state)).strip_edges()
	var item_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params.get("item_id", ""), directive, world_state)).to_upper().strip_edges()
	var quantity: float = float(ActionPipelineHelpersScript.resolve_param_value(params.get("quantity", 0.0), directive, world_state))

	if to_entity.is_empty() or item_id.is_empty() or quantity <= 0.0:
		push_error("[ActionPrimitives] FAIL_LOUD: CREDIT_ITEM invalid arguments at step '%s' (to: '%s', item: '%s', qty: %f)" % [step_id, to_entity, item_id, quantity])
		return { "success": false }

	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, to_entity, item_id, quantity)

	return { "success": true }