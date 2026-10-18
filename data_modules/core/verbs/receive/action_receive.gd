# res://data_modules/core/verbs/receive/action_receive.gd
extends ActionBase
class_name ActionReceive

const CALCULATOR = preload("res://systems/impacts/impact_calculator.gd")
const EVALUATOR = preload("res://systems/condition_evaluator.gd")
const ORDER_MGR = preload("res://systems/order_manager.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var order_id: String = action.get("order_id", "")
	var orders: Dictionary = world_state.get("pending_orders", {})
	var target_node: String = action.get("target_node_id", "HQ")

	if not orders.has(order_id):
		return EngineResult.fail(EngineResult.ErrorCode.ENTITY_NOT_FOUND, "RECEIVE", "Order %s not found." % order_id, target_node).to_dict()

	var order = ORDER_MGR.get_order(world_state, order_id)
	var buyer_id: String = order.get("buyer_id", "PLAYER")
	var seller_id: String = order.get("seller_id", "")
	var item_key: String = order.get("item_key", "")
	var amount: float = float(order.get("amount", 0.0))

	var buyer_inv: Dictionary = EVALUATOR.get_actor_inventory(world_state, buyer_id)
	var seller_inv: Dictionary = EVALUATOR.get_actor_inventory(world_state, seller_id)

	# Mutate Physical Stocks
	seller_inv[item_key]["STOCK"] = max(0.0, float(seller_inv[item_key].get("STOCK", 0.0)) - amount)
	buyer_inv[item_key]["STOCK"] = float(buyer_inv[item_key].get("STOCK", 0.0)) + amount

	# Evaluate Commodity Impacts (BUY vs SELL)
	var is_player_selling: bool = (seller_id == "PLAYER" or seller_id == "")
	var activation_verb: String = "SELL" if is_player_selling else "BUY"
	
	var commodity = world_state.get("commodity_registry", {}).get(item_key, {})
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
	return EngineResult.ok("RECEIVE", "Physical delivery completed for %s." % item_key, deltas, amount, target_node).to_dict()