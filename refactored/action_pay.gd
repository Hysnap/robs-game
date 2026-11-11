# res://data_modules/core/verbs/pay/action_pay.gd
extends ActionBase
class_name ActionPay

const ORDER_MGR = preload("res://systems/order_manager.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var order_id: String = action.get("order_id", "")
	var target_node: String = action.get("target_node_id", "HQ")

	var order: Dictionary = ORDER_MGR.get_order(world_state, order_id)
	if order.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.ENTITY_NOT_FOUND, 
			"PAY", 
			"Order ticket '%s' not found." % order_id, 
			target_node
		).to_dict()

	var total_cost: float = float(order.get("total_cost", 0.0))
	var buyer_id: String = order.get("buyer_id", "PLAYER")
	var seller_id: String = order.get("seller_id", "")

	# 1. Assert Buyer Solvency
	if not ConditionEvaluator.has_sufficient(world_state, buyer_id, "CASH", total_cost):
		return EngineResult.fail(
			EngineResult.ErrorCode.INSUFFICIENT_RESOURCE,
			"PAY",
			"Buyer '%s' lacks funds (£%.2f required)." % [buyer_id, total_cost],
			target_node
		).to_dict()

	# 2. Update Order Lifecycle via OrderManager
	ORDER_MGR.update_order_status(world_state, order_id, "PAID")

	# 3. Emit Impact Delta: Let SinkCash handle the transfer cleanly!
	# Buyer loses funds (-total_cost); if player is selling, seller gains funds (+total_cost)
	var cash_flow: float = total_cost if (seller_id in ["PLAYER", ""]) else -total_cost
	var deltas: Dictionary = {"CASH": cash_flow}

	return EngineResult.ok(
		"PAY", 
		"Settled payment of £%.2f for Order %s." % [total_cost, order_id], 
		deltas, 
		total_cost, 
		target_node,
		{"order_id": order_id, "total_cost": total_cost, "buyer": buyer_id, "seller": seller_id}
	).to_dict()