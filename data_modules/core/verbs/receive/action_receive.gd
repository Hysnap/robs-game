# res://data_modules/core/verbs/receive/action_receive.gd
extends ActionBase
class_name ActionReceive

const CALCULATOR = preload("res://systems/impacts/impact_calculator.gd")
const EVALUATOR = preload("res://systems/condition_evaluator.gd")
const ORDER_MGR = preload("res://systems/order_manager.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var order_id: String = action.get("order_id", "")
	var target_node: String = action.get("target_node_id", "HQ")

	var order: Dictionary = ORDER_MGR.get_order(world_state, order_id)
	if order.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.ENTITY_NOT_FOUND, 
			"RECEIVE", 
			"Order %s not found." % order_id, 
			target_node
		).to_dict()

	if order.get("status", "") != "PAID" and not action.get("allow_fronted_credit", false):
		return EngineResult.fail(
			EngineResult.ErrorCode.PAYMENT_REQUIRED,
			"RECEIVE",
			"Cannot receive unpaid Order %s." % order_id,
			target_node
		).to_dict()

	var buyer_id: String = order.get("buyer_id", "PLAYER")
	var seller_id: String = order.get("seller_id", "")
	var item_key: String = order.get("item_key", "")
	var amount: float = float(order.get("amount", 0.0))

	var buyer_inv: Dictionary = EVALUATOR.get_actor_inventory(world_state, buyer_id)
	var seller_inv: Dictionary = EVALUATOR.get_actor_inventory(world_state, seller_id)

	# 1. Mutate Physical Stock Lanes safely
	if not seller_inv.is_empty() and seller_inv.has(item_key):
		seller_inv[item_key]["STOCK"] = max(0.0, float(seller_inv[item_key].get("STOCK", 0.0)) - amount)

	if not buyer_inv.is_empty():
		if not buyer_inv.has(item_key):
			buyer_inv[item_key] = {"STOCK": 0.0, "PREPPED": 0.0}
		buyer_inv[item_key]["STOCK"] = float(buyer_inv[item_key].get("STOCK", 0.0)) + amount

	# 2. Evaluate Commodity Impacts (BUY vs SELL)
	var is_player_selling: bool = (seller_id in ["PLAYER", ""])
	var activation_verb: String = "SELL" if is_player_selling else "BUY"
	
	var commodity: Dictionary = world_state.get("commodity_registry", {}).get(item_key, {})
	var deltas: Dictionary = {}
	var activations: Array = commodity.get("impact_activations", {}).get(activation_verb, [])
	
	for entry in activations:
		var metric: String = entry.get("metric", "")
		var model: String = entry.get("model", "LINEAR_PER_UNIT")
		var factor: float = float(entry.get("factor", 0.0))
		var params: Dictionary = entry.get("params", {}).duplicate()
		var delta_val: float = CALCULATOR.calculate(model, amount, factor, params)
		if metric != "" and delta_val != 0.0:
			deltas[metric] = deltas.get(metric, 0.0) + delta_val

	ORDER_MGR.update_order_status(world_state, order_id, "DELIVERED")

	return EngineResult.ok(
		"RECEIVE", 
		"Physical delivery completed for %s." % item_key, 
		deltas, 
		amount, 
		target_node,
		{"item_key": item_key, "amount": amount, "order_id": order_id}
	).to_dict()