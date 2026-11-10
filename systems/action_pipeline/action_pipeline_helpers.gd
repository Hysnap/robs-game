# res://systems/action_pipeline/action_pipeline_helpers.gd
class_name ActionPipelineHelpers
extends RefCounted

const EngineResultScript = preload("res://systems/engine_result.gd")
const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")

## Resolves the primary actor ID responsible for the directive
static func resolve_actor_id(directive: Dictionary) -> String:
	return str(directive.get("assigned_to", directive.get("initiator_id", "PLAYER")))

## Dynamic symbol resolver for directive arguments and mathematical aliases
static func resolve_param_value(raw_val: Variant, directive: Dictionary, world_state: Dictionary) -> Variant:
	if typeof(raw_val) != TYPE_STRING:
		return raw_val

	var s_val: String = str(raw_val).strip_edges()

	if s_val == "ORDER_ACTOR" or s_val == "INITIATOR":
		return resolve_actor_id(directive)
	if s_val == "TARGET_NODE" or s_val == "LOCATION":
		return str(directive.get("target_node_id", ""))
	if s_val.begins_with("PARAM."):
		var key: String = s_val.substr(6)
		return directive.get(key, "")
	if s_val == "CALCULATED_TOTAL_COST":
		var qty: float = float(directive.get("amount", 1.0))
		var unit_cost: float = float(directive.get("unit_cost", 0.0))
		return qty * unit_cost

	return raw_val

## Explicitly checks physical commodity quantity with tri-state status reporting
## Returns: { "passed": bool, "status": String, "message": String, "held": float, "required": float }
static func evaluate_commodity_gate(world_state: Dictionary, entity_id: String, commodity_token: String, required_qty: float, op: String = ">=") -> Dictionary:
	var clean_item: String = commodity_token.to_upper().strip_edges()
	var inv_result: Dictionary = get_entity_inventory_safe(world_state, entity_id)

	if not bool(inv_result.get("exists", false)):
		return {
			"passed": false,
			"status": "ENTITY_NOT_FOUND",
			"message": "FAIL_LOUD: Entity '%s' not found in world state." % entity_id,
			"held": 0.0,
			"required": required_qty
		}

	var inv: Dictionary = inv_result.get("inventory", {})
	if not inv.has(clean_item):
		return {
			"passed": false,
			"status": "COMMODITY_NOT_HELD",
			"message": "Entity '%s' does not hold '%s' in inventory." % [entity_id, clean_item],
			"held": 0.0,
			"required": required_qty
		}

	var held: float = float(inv[clean_item])
	var satisfied: bool = ConditionEvaluatorScript.evaluate(held, required_qty, op)

	if not satisfied:
		return {
			"passed": false,
			"status": "INSUFFICIENT_QUANTITY",
			"message": "Entity '%s' has insufficient '%s' (Held: %.2f, Required: %.2f)" % [entity_id, clean_item, held, required_qty],
			"held": held,
			"required": required_qty
		}

	return {
		"passed": true,
		"status": "SATISFIED",
		"message": "",
		"held": held,
		"required": required_qty
	}

## Explicit Query 2: Entity State Attribute (Strictly record fields only, no inventory fallback)
static func get_entity_attribute(world_state: Dictionary, entity_id: String, attribute_key: String) -> float:
	var clean_attr: String = attribute_key.to_lower().strip_edges()

	# 1. Staff Members
	var staff_dict: Dictionary = world_state.get("staff", {})
	if staff_dict.has(entity_id):
		var staff_record: Dictionary = staff_dict[entity_id]
		if staff_record.has(clean_attr):
			return float(staff_record[clean_attr])
		push_error("[ActionPipelineHelpers] FAIL_LOUD: Attribute '%s' does not exist on staff '%s'" % [clean_attr, entity_id])
		return -INF

	# 2. Player / Operations
	if entity_id in ["PLAYER", "", "HQ"]:
		var ops: Dictionary = world_state.get("operations", {})
		if ops.has(clean_attr):
			return float(ops[clean_attr])
		push_error("[ActionPipelineHelpers] FAIL_LOUD: Attribute '%s' does not exist in operations for '%s'" % [clean_attr, entity_id])
		return -INF

	# 3. Counterparties / NPCs
	var cp_dict: Dictionary = world_state.get("counterparties", world_state.get("npcs", {}))
	if cp_dict.has(entity_id):
		var cp_record: Dictionary = cp_dict[entity_id]
		if cp_record.has(clean_attr):
			return float(cp_record[clean_attr])
		push_error("[ActionPipelineHelpers] FAIL_LOUD: Attribute '%s' does not exist on counterparty '%s'" % [clean_attr, entity_id])
		return -INF

	push_error("[ActionPipelineHelpers] FAIL_LOUD: Cannot query attribute '%s' on unknown entity '%s'" % [clean_attr, entity_id])
	return -INF

## Resolves an entity's physical inventory dictionary with fail-loud safety verification
static func get_entity_inventory_safe(world_state: Dictionary, entity_id: String) -> Dictionary:
	if entity_id in ["PLAYER", "", "HQ"]:
		if not world_state.has("inventory"):
			world_state["inventory"] = {}
		return { "exists": true, "inventory": world_state["inventory"] }

	# Staff Members
	var staff_dict: Dictionary = world_state.get("staff", {})
	if staff_dict.has(entity_id):
		var staff_record: Dictionary = staff_dict[entity_id]
		if not staff_record.has("inventory"):
			staff_record["inventory"] = {}
		return { "exists": true, "inventory": staff_record["inventory"] }

	# Venues across Districts
	var districts: Dictionary = world_state.get("districts", {})
	for d_id in districts.keys():
		var venues: Dictionary = districts[d_id].get("venues", {})
		if venues.has(entity_id):
			var venue_record: Dictionary = venues[entity_id]
			if not venue_record.has("inventory"):
				venue_record["inventory"] = {}
			return { "exists": true, "inventory": venue_record["inventory"] }

	# Counterparties / NPCs
	var cp_dict: Dictionary = world_state.get("counterparties", world_state.get("npcs", {}))
	if cp_dict.has(entity_id):
		var cp_record: Dictionary = cp_dict[entity_id]
		if not cp_record.has("inventory"):
			cp_record["inventory"] = {}
		return { "exists": true, "inventory": cp_record["inventory"] }

	return { "exists": false, "inventory": {} }

## Convenience helper that returns the raw inventory dictionary directly, failing loud if missing
static func get_entity_inventory(world_state: Dictionary, entity_id: String) -> Dictionary:
	var res: Dictionary = get_entity_inventory_safe(world_state, entity_id)
	if not bool(res.get("exists", false)):
		push_error("[ActionPipelineHelpers] FAIL_LOUD: Entity '%s' not found in world state." % entity_id)
		return {}
	return res.get("inventory", {})

## Safely mutates item inventory quantities across any actor, venue, or vault
static func mutate_inventory_pool(world_state: Dictionary, entity_id: String, item_id: String, delta: float) -> void:
	var clean_item: String = item_id.to_upper().strip_edges()
	var inv: Dictionary = get_entity_inventory(world_state, entity_id)
	
	var current_qty: float = float(inv.get(clean_item, 0.0))
	var new_qty: float = max(0.0, current_qty + delta)
	if new_qty > 0.0:
		inv[clean_item] = new_qty
	else:
		inv.erase(clean_item)

## Advances an operative's operational shift meter and fatigue
static func apply_time_and_fatigue(world_state: Dictionary, actor_id: String, time_delta: float, fatigue_delta: float) -> void:
	var staff_dict: Dictionary = world_state.get("staff", {})
	if staff_dict.has(actor_id):
		var staff_entry: Dictionary = staff_dict[actor_id]
		staff_entry["shift_time_spent"] = float(staff_entry.get("shift_time_spent", 0.0)) + time_delta
		staff_entry["fatigue"] = max(0.0, float(staff_entry.get("fatigue", 0.0)) + fatigue_delta)

## Ingests an authored JSON impact profile and routes the delta to UniversalMetricSink
static func load_and_dispatch_profile(world_state: Dictionary, target_id: String, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json_str: String = file.get_as_text()
	var parsed = JSON.parse_string(json_str)
	if parsed is Dictionary:
		var metric: String = str(parsed.get("metric_key", "")).to_upper()
		var delta_val: float = float(parsed.get("delta", 0.0))
		if not metric.is_empty():
			ImpactRouterScript.dispatch_delta(world_state, target_id, metric, delta_val)

## Maps string failure tokens to normalized EngineResult.ErrorCode enums
static func resolve_error_code(code_str: String) -> int:
	match code_str.to_upper():
		"INSUFFICIENT_RESOURCE", "INSUFFICIENT_FUNDS", "OUT_OF_STOCK", "INSUFFICIENT_QUANTITY", "COMMODITY_NOT_HELD":
			return EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE
		"INVALID_PARAMETER", "ROUTE_UNREACHABLE", "ENTITY_NOT_FOUND":
			return EngineResultScript.ErrorCode.INVALID_PARAMETER
		"UNAUTHORIZED":
			return EngineResultScript.ErrorCode.UNAUTHORIZED
		_:
			return EngineResultScript.ErrorCode.INTERNAL_SIM_ERROR