# res://systems/condition_evaluator.gd
class_name ConditionEvaluator extends RefCounted

# Inside ConditionEvaluator (or ImpactCalculator)
enum ModelType {
	LINEAR_PER_UNIT,
	WEIGHTED_PER_UNIT,
	EXP_PER_UNIT,
	LOG_PER_UNIT,
	STEPPED_PER_UNIT
}

static func get_supported_models() -> Array:
	return ModelType.keys()

## Evaluates whether a metric has breached a threshold using standard operators
static func evaluate(current_val: float, threshold_val: float, operator: String) -> bool:
	match operator:
		"<":  return current_val < threshold_val
		"<=": return current_val <= threshold_val
		">":  return current_val > threshold_val
		">=": return current_val >= threshold_val
		"==": return is_equal_approx(current_val, threshold_val)
		"!=": return not is_equal_approx(current_val, threshold_val)
		_:
			push_error("[CONDITION EVALUATOR] Unknown operator: %s" % operator)
			return false

## Universal query: resolves the inventory dictionary lane for ANY actor
static func get_actor_inventory(world_state: Dictionary, actor_id: String) -> Dictionary:
	if actor_id == "PLAYER" or actor_id == "":
		return world_state.get("inventory_registry", {})
		
	# Check staff registry
	var staff_record: Dictionary = world_state.get("staff", {}).get(actor_id, {})
	if not staff_record.is_empty():
		return staff_record.get("inventory", {})
		
	# Check market counterparties (wholesalers, suppliers, market pools)
	var cp_record: Dictionary = world_state.get("counterparties", {}).get(actor_id, {})
	if not cp_record.is_empty():
		return cp_record.get("inventory", {})

	return {}

## Universal Resource Balance Inspector
static func get_resource_balance(world_state: Dictionary, actor_id: String, resource_key: String) -> float:
	if resource_key == "CASH":
		if actor_id == "PLAYER" or actor_id == "":
			return float(world_state.get("finances", {}).get("liquid_cash", 0.0))
		
		# Staff or counterparty cash wallet
		var staff_member = world_state.get("staff", {}).get(actor_id, {})
		if not staff_member.is_empty():
			return float(staff_member.get("cash", 0.0))
			
		var counterparty = world_state.get("counterparties", {}).get(actor_id, {})
		if not counterparty.is_empty():
			return float(counterparty.get("cash", 0.0))
			
		return -1.0 # Signals entity not found!

	var inv = get_actor_inventory(world_state, actor_id)
	if inv.has(resource_key):
		return float(inv[resource_key].get("STOCK", 0.0))
		
	return -1.0 # Signals inventory lane not found!

static func has_sufficient_resource(world_state: Dictionary, actor_id: String, resource_key: String, required_qty: float) -> bool:
	var balance = get_resource_balance(world_state, actor_id, resource_key)
	if balance < 0.0:
		return false # Entity or stock lane does not exist
	return balance >= required_qty