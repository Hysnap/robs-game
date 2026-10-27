# res://systems/condition_evaluator.gd
class_name ConditionEvaluator extends RefCounted

const _Calculator = preload("res://systems/impacts/impact_calculator.gd")

# =====================================================================
# 1. ATOMIC COMPARISON OPERATOR ENGINE
# =====================================================================

## Evaluates whether a value breaches a threshold using a string operator
static func evaluate(current_val: float, threshold_val: float, operator: String = ">=") -> bool:
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

# =====================================================================
# 2. UNIVERSAL REQUIREMENT GATES (SINGLE & COMPOUND)
# =====================================================================

## Universal Requirement Check: Gating cash, commodities, fatigue, time, or social standing
static func has_sufficient(
	world_state: Dictionary, 
	actor_id: String, 
	metric: String, 
	target_val: float, 
	operator: String = ">=", 
	context: Dictionary = {}
) -> bool:
	# 1. CASH & LIQUIDITY
	if metric.to_upper() in ["CASH", "LIQUID_CASH"]:
		if _is_infinite_mode_active(actor_id, "third_party_funds_mode", "INFINITE_FUNDS"):
			return true

		var current_cash: float = get_state_metric(world_state, actor_id, "CASH", context)
		if current_cash == -INF:
			return false
		return evaluate(current_cash, target_val, operator)

	# 2. PHYSICAL INVENTORY / COMMODITY STOCK
	if _is_infinite_mode_active(actor_id, "supplier_stock_mode", "INFINITE_SUPPLY"):
		return true

	var current_stock: float = get_state_metric(world_state, actor_id, metric, context)
	if current_stock == -INF:
		return false
	return evaluate(current_stock, target_val, operator)

## Evaluates a compound list of condition rules where ALL must pass ("AND" gate / Tolerance Band)
static func has_all(world_state: Dictionary, actor_id: String, gate_list: Array, context: Dictionary = {}) -> bool:
	for gate in gate_list:
		var metric: String = gate.get("metric", "")
		var required_qty: float = float(gate.get("amount", gate.get("required_qty", 0.0)))
		var op: String = gate.get("operator", ">=")
		
		if not has_sufficient(world_state, actor_id, metric, required_qty, op, context):
			return false
	return true

## Evaluates whether AT LEAST ONE condition in an array is met ("OR" gate / Bifurcated Exclusion Zone)
static func has_any(world_state: Dictionary, actor_id: String, gate_list: Array, context: Dictionary = {}) -> bool:
	if gate_list.is_empty():
		return true
		
	for gate in gate_list:
		var metric: String = gate.get("metric", "")
		var required_qty: float = float(gate.get("amount", gate.get("required_qty", 0.0)))
		var op: String = gate.get("operator", ">=")
		
		if has_sufficient(world_state, actor_id, metric, required_qty, op, context):
			return true
	return false

# =====================================================================
# 3. NON-LINEAR CURVE GATE EVALUATION
# =====================================================================

## Transforms an input value through a chosen curve (EXP, LOG, STEPPED, LINEAR, INVERTED_U_CURVE)
## via ImpactCalculator and tests if the scaled output satisfies the threshold
static func evaluate_curve_gate(
	raw_input_value: float, 
	model_type: String, 
	factor: float, 
	params: Dictionary, 
	threshold_val: float, 
	operator: String = ">="
) -> bool:
	var transformed_val: float = _Calculator.calculate(model_type, raw_input_value, factor, params)
	return evaluate(transformed_val, threshold_val, operator)

## Evaluates a declarative gate dictionary loaded from JSON or config files
static func evaluate_gate_dict(world_state: Dictionary, gate_def: Dictionary, context: Dictionary = {}) -> bool:
	if gate_def.is_empty():
		return true

	var actor_id: String = gate_def.get("actor_id", "PLAYER")
	var metric: String = gate_def.get("metric", gate_def.get("resource", "CASH"))
	var op: String = gate_def.get("operator", ">=")
	var target_val: float = float(gate_def.get("target_value", gate_def.get("amount", 0.0)))

	if gate_def.get("gate_type", "FLAT") == "CURVE":
		var raw_val: float = get_state_metric(world_state, actor_id, metric, context)
		if raw_val == -INF:
			return false
		return evaluate_curve_gate(
			raw_val,
			gate_def.get("model", "LINEAR_PER_UNIT"),
			float(gate_def.get("factor", 1.0)),
			gate_def.get("params", {}),
			target_val,
			op
		)
	else:
		return has_sufficient(world_state, actor_id, metric, target_val, op, context)

# =====================================================================
# 4. UNIVERSAL STATE METRIC RESOLVER
# =====================================================================

## Dynamically extracts numerical values across all architectural categories:
## Finances, Personal Attributes, Relational Standing, and Physical Stock
static func get_state_metric(world_state: Dictionary, actor_id: String, metric_key: String, context: Dictionary = {}) -> float:
	var upper_key: String = metric_key.to_upper()
	
	# --- A. LIQUID CASH & FINANCES ---
	if upper_key in ["CASH", "LIQUID_CASH"]:
		if _is_infinite_mode_active(actor_id, "third_party_funds_mode", "INFINITE_FUNDS"):
			return INF
		if actor_id in ["PLAYER", "", "HQ"]:
			return float(world_state.get("finances", {}).get("liquid_cash", 0.0))
		var staff_member: Dictionary = world_state.get("staff", {}).get(actor_id, {})
		if not staff_member.is_empty():
			return float(staff_member.get("cash", 0.0))
		var counterparty: Dictionary = world_state.get("counterparties", world_state.get("npcs", {})).get(actor_id, {})
		if not counterparty.is_empty():
			return float(counterparty.get("cash", 0.0))
		return -INF

	# --- B. PERSONAL ATTRIBUTES (Fatigue, Loyalty, Intoxication, Shift Time) ---
	if upper_key in ["FATIGUE", "WORKER_FATIGUE", "LOYALTY", "INTOXICATION", "SHIFT_TIME_SPENT", "OPERATIONAL_TIME"]:
		var attr_key: String = upper_key.to_lower()
		if attr_key == "worker_fatigue": attr_key = "fatigue"
		if attr_key == "operational_time": attr_key = "shift_time_spent"
		
		if actor_id in ["PLAYER", "", "HQ"]:
			return float(world_state.get("operations", {}).get(attr_key, 0.0))
		var staff: Dictionary = world_state.get("staff", {}).get(actor_id, {})
		if not staff.is_empty():
			return float(staff.get(attr_key, 0.0))
		return -INF

	# --- C. RELATIONAL STANDING (Reputation / Influence / Trust) ---
	if upper_key in ["REPUTATION", "PERSONAL_REPUTATION", "INFLUENCE", "PERSONAL_INFLUENCE", "TRUST"]:
		var target_entity: String = context.get("target_entity_id", context.get("target_node_id", context.get("venue_id", "")))
		return _resolve_relational_metric(world_state, actor_id, target_entity, upper_key)

	# --- D. PHYSICAL COMMODITIES (Stock Balance) ---
	var inventory: Dictionary = get_actor_inventory(world_state, actor_id)
	if inventory.has(metric_key):
		if _is_infinite_mode_active(actor_id, "supplier_stock_mode", "INFINITE_SUPPLY"):
			return INF
		return float(inventory[metric_key].get("STOCK", 0.0))

	return 0.0

## Universal inventory accessor (internal & external tool)
static func get_actor_inventory(world_state: Dictionary, actor_id: String) -> Dictionary:
	if actor_id in ["PLAYER", "", "HQ"]:
		return world_state.get("inventory_registry", {})
	if actor_id in ["WHOLESALER", "MARKET_CONSUMERS"]:
		return {}

	var staff_record: Dictionary = world_state.get("staff", {}).get(actor_id, {})
	if not staff_record.is_empty():
		return staff_record.get("inventory", {})

	var cp_record: Dictionary = world_state.get("counterparties", world_state.get("npcs", {})).get(actor_id, {})
	if not cp_record.is_empty():
		return cp_record.get("inventory", {})

	return {}

## Internal helper: Resolves social/relational capital across Venues, Counterparties, or Districts
static func _resolve_relational_metric(world_state: Dictionary, actor_id: String, target_entity: String, metric_type: String) -> float:
	if target_entity.is_empty():
		return 0.0
		
	# 1. Check if target is a Venue (Pub / Taproom)
	for dist_id in world_state.get("districts", {}).keys():
		var venues = world_state["districts"][dist_id].get("venues", {})
		if venues.has(target_entity):
			var staff_rep = venues[target_entity].get("staff_reputation", {})
			var personal = staff_rep.get(actor_id, {})
			if metric_type in ["REPUTATION", "PERSONAL_REPUTATION"]:
				return float(personal.get("personal_reputation", 0.0))
			else:
				return float(personal.get("personal_influence", 0.0))

	# 2. Check if target is an NPC / Counterparty / Faction
	var counterparties = world_state.get("counterparties", world_state.get("npcs", {}))
	if counterparties.has(target_entity):
		return float(counterparties[target_entity].get("trust_network", {}).get(actor_id, 0.0))

	# 3. Check if target is a Macro District
	if world_state.get("districts", {}).has(target_entity):
		if metric_type in ["REPUTATION", "PERSONAL_REPUTATION"]:
			return float(world_state["districts"][target_entity].get("local_reputation", 0.0))
		else:
			return float(world_state["districts"][target_entity].get("local_influence", 0.0))

	return 0.0

## Universal check: inspects if a third-party actor has infinite capacity for a given rule
static func _is_infinite_mode_active(actor_id: String, rule_key: String, bypass_value: String) -> bool:
	if actor_id in ["PLAYER", "", "HQ"]:
		return false

	var manifest: Dictionary = {}
	if ClassDB.class_exists("ScenarioManifestManager"):
		manifest = ScenarioManifestManager.get_manifest()

	var mode: String = manifest.get("market_rules", {}).get(rule_key, "").to_upper()
	return mode == bypass_value