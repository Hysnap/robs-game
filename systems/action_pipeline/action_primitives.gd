# res://systems/action_pipeline/action_primitives.gd
class_name ActionPrimitives
extends RefCounted

const ActionPipelineHelpersScript = preload("res://systems/action_pipeline/action_pipeline_helpers.gd")
const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")

static var _registry: Dictionary = {
	"REQUIRE": execute_require,
	"MOVE_ACTOR": execute_move_actor,
	"TRANSFER_ITEM": execute_transfer_item,
	"MUTATE_ACTOR": execute_mutate_actor,
	"DISPATCH_IMPACT": execute_dispatch_impact
}

## Registers a new primitive execution function into the switchboard
static func register_primitive(token: String, fn: Callable) -> void:
	_registry[token.to_upper().strip_edges()] = fn

## Universal dispatch entry point
static func dispatch(primitive_token: String, world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String, impacts_dir: String) -> Dictionary:
	var clean_token: String = primitive_token.to_upper().strip_edges()
	if not _registry.has(clean_token):
		return {
			"success": false,
			"message": "FAIL_LOUD: Unregistered primitive '%s' at step '%s'" % [primitive_token, step_id],
			"time_spent": 0.0,
			"fatigue": 0.0
		}

	var fn: Callable = _registry[clean_token]
	if clean_token == "DISPATCH_IMPACT":
		return fn.call(world_state, directive, params, impacts_dir)
	else:
		return fn.call(world_state, directive, params, step_id)

# -----------------------------------------------------------------------------
# Micro-Verb Primitives
# -----------------------------------------------------------------------------

## Primitive 1: REQUIRE (Explicit Gate - COMMODITY or ATTRIBUTE)
static func execute_require(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	for req_key in ["actor", "metric", "operator", "value"]:
		if not params.has(req_key):
			return {
				"success": false,
				"message": "FAIL_LOUD: REQUIRE step '%s' missing mandatory parameter '%s'" % [step_id, req_key],
				"time_spent": 0.0,
				"fatigue": 0.0
			}

	var actor_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params["actor"], directive, world_state))
	var metric_token: String = str(ActionPipelineHelpersScript.resolve_param_value(params["metric"], directive, world_state))
	var op: String = str(params["operator"])
	var threshold: float = float(ActionPipelineHelpersScript.resolve_param_value(params["value"], directive, world_state))
	
	# Explicit target domain: defaults to COMMODITY unless explicitly set to ATTRIBUTE
	var domain: String = str(params.get("domain", "COMMODITY")).to_upper().strip_edges()

	match domain:
		"COMMODITY":
			var gate_res: Dictionary = ActionPipelineHelpersScript.evaluate_commodity_gate(world_state, actor_id, metric_token, threshold, op)
			var passed: bool = bool(gate_res.get("passed", false))
			return {
				"success": passed,
				"message": "" if passed else str(gate_res.get("message", "Commodity gate failed")),
				"status": gate_res.get("status", "FAILED"),
				"time_spent": 0.0,
				"fatigue": 0.0
			}

		"ATTRIBUTE":
			var current_val: float = ActionPipelineHelpersScript.get_entity_attribute(world_state, actor_id, metric_token)
			if current_val == -INF:
				return {
					"success": false,
					"message": "FAIL_LOUD: Attribute '%s' unresolved on entity '%s' at step '%s'" % [metric_token, actor_id, step_id],
					"time_spent": 0.0,
					"fatigue": 0.0
				}
			var passed: bool = ConditionEvaluatorScript.evaluate(current_val, threshold, op)
			return {
				"success": passed,
				"message": "" if passed else "Attribute gate failed: %s %s %.2f for %s" % [metric_token, op, threshold, actor_id],
				"time_spent": 0.0,
				"fatigue": 0.0
			}

		_:
			return {
				"success": false,
				"message": "FAIL_LOUD: Unknown REQUIRE domain '%s' at step '%s'" % [domain, step_id],
				"time_spent": 0.0,
				"fatigue": 0.0
			}

## Primitive 2: MOVE_ACTOR (Spatial Transit)
static func execute_move_actor(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	for req_key in ["actor", "destination", "travel_time", "travel_fatigue"]:
		if not params.has(req_key):
			return {
				"success": false,
				"message": "FAIL_LOUD: MOVE_ACTOR step '%s' missing mandatory parameter '%s'" % [step_id, req_key],
				"time_spent": 0.0,
				"fatigue": 0.0
			}

	var actor_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params["actor"], directive, world_state))
	var dest_district: String = str(ActionPipelineHelpersScript.resolve_param_value(params["destination"], directive, world_state))
	var t_time: float = float(params["travel_time"])
	var t_fatigue: float = float(params["travel_fatigue"])

	var staff_dict: Dictionary = world_state.get("staff", {})
	if not staff_dict.has(actor_id):
		return { "success": true, "time_spent": t_time, "fatigue": t_fatigue }

	var staff_entry: Dictionary = staff_dict[actor_id]
	var origin_district: String = str(staff_entry.get("current_district_id", ""))
	
	if origin_district == dest_district or dest_district.is_empty():
		return { "success": true, "time_spent": 0.0, "fatigue": 0.0 }

	staff_entry["current_district_id"] = dest_district
	return {
		"success": true,
		"time_spent": t_time,
		"fatigue": t_fatigue
	}

## Primitive 3: TRANSFER_ITEM (Unified Commodity Handover - Strictly via Inventory)
static func execute_transfer_item(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	for req_key in ["from", "to", "item_id", "quantity", "transfer_time", "transfer_fatigue"]:
		if not params.has(req_key):
			return {
				"success": false,
				"message": "FAIL_LOUD: TRANSFER_ITEM step '%s' missing mandatory parameter '%s'" % [step_id, req_key],
				"time_spent": 0.0,
				"fatigue": 0.0
			}

	var from_entity: String = str(ActionPipelineHelpersScript.resolve_param_value(params["from"], directive, world_state))
	var to_entity: String = str(ActionPipelineHelpersScript.resolve_param_value(params["to"], directive, world_state))
	var item_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params["item_id"], directive, world_state)).to_upper().strip_edges()
	var quantity: float = float(ActionPipelineHelpersScript.resolve_param_value(params["quantity"], directive, world_state))
	var t_time: float = float(params["transfer_time"])
	var t_fatigue: float = float(params["transfer_fatigue"])

	if quantity <= 0.0:
		return {
			"success": false,
			"message": "FAIL_LOUD: Transfer quantity must be > 0.0 at step '%s'" % step_id,
			"time_spent": 0.0,
			"fatigue": 0.0
		}

	# Commodity-agnostic transfer: CASH, goods, and tools move identically
	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, from_entity, item_id, -quantity)
	ActionPipelineHelpersScript.mutate_inventory_pool(world_state, to_entity, item_id, quantity)

	return {
		"success": true,
		"time_spent": t_time,
		"fatigue": t_fatigue
	}

## Primitive 4: MUTATE_ACTOR (Personal State Shifts)
static func execute_mutate_actor(world_state: Dictionary, directive: Dictionary, params: Dictionary, step_id: String) -> Dictionary:
	for req_key in ["actor", "metric", "delta"]:
		if not params.has(req_key):
			return {
				"success": false,
				"message": "FAIL_LOUD: MUTATE_ACTOR step '%s' missing mandatory parameter '%s'" % [step_id, req_key],
				"time_spent": 0.0,
				"fatigue": 0.0
			}

	var actor_id: String = str(ActionPipelineHelpersScript.resolve_param_value(params["actor"], directive, world_state))
	var metric: String = str(params["metric"]).to_lower()
	var delta: float = float(ActionPipelineHelpersScript.resolve_param_value(params["delta"], directive, world_state))

	var staff_dict: Dictionary = world_state.get("staff", {})
	if staff_dict.has(actor_id):
		var staff_entry: Dictionary = staff_dict[actor_id]
		var curr_val: float = float(staff_entry.get(metric, 0.0))
		staff_entry[metric] = max(0.0, curr_val + delta)

	return { "success": true, "time_spent": 0.0, "fatigue": 0.0 }

## Primitive 5: DISPATCH_IMPACT (Folder Impacts & Direct Deltas)
static func execute_dispatch_impact(world_state: Dictionary, directive: Dictionary, params: Dictionary, impacts_dir: String) -> Dictionary:
	var target_node: String = str(directive.get("target_node_id", ""))

	var folder: String = str(params.get("load_from_folder", impacts_dir))
	if not folder.is_empty() and DirAccess.dir_exists_absolute(folder):
		var dir = DirAccess.open(folder)
		if dir != null:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while not file_name.is_empty():
				if not dir.current_is_dir() and file_name.ends_with(".json"):
					var impact_path = folder.path_join(file_name)
					ActionPipelineHelpersScript.load_and_dispatch_profile(world_state, target_node, impact_path)
				file_name = dir.get_next()
			dir.list_dir_end()

	var direct_deltas: Dictionary = params.get("direct_deltas", {})
	for metric_key in direct_deltas.keys():
		var delta_val: float = float(direct_deltas[metric_key])
		ImpactRouterScript.dispatch_delta(world_state, target_node, str(metric_key).to_upper(), delta_val)

	return { "success": true, "time_spent": 0.0, "fatigue": 0.0 }