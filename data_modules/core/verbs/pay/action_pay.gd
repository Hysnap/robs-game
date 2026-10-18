# res://data_modules/core/verbs/pay/action_pay.gd
extends ActionBase
class_name ActionPay

const ORDER_MGR = preload("res://systems/order_manager.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var order_id: String = action.get("order_id", "")
	var target_node: String = action.get("target_node_id", "HQ")

	var order = ORDER_MGR.get_order(world_state, order_id)
	if order.is_empty():
		return EngineResult.fail(EngineResult.ErrorCode.ENTITY_NOT_FOUND, "PAY", "Order ticket '%s' not found." % order_id, target_node).to_dict()

	var total_cost: float = float(order.get("total_cost", 0.0))
	var buyer_id: String = order.get("buyer_id", "PLAYER")
	var seller_id: String = order.get("seller_id", "")

	# Deduct funds from buyer
	if buyer_id == "PLAYER" or buyer_id == "":
		world_state["finances"]["liquid_cash"] -= total_cost
	else:
		var buyer = world_state.get("counterparties", {}).get(buyer_id, world_state.get("staff", {}).get(buyer_id, {}))
		buyer["cash"] -= total_cost

	# Credit funds to seller
	if seller_id == "PLAYER" or seller_id == "":
		world_state["finances"]["liquid_cash"] += total_cost
	else:
		var seller = world_state.get("counterparties", {}).get(seller_id, world_state.get("staff", {}).get(seller_id, {}))
		seller["cash"] += total_cost

	ORDER_MGR.update_order_status(world_state, order_id, "PAID")
	var deltas: Dictionary = {"CASH": total_cost if (seller_id == "PLAYER") else -total_cost}
	return EngineResult.ok("PAY", "Settled payment of £%.2f for Order %s." % [total_cost, order_id], deltas, 0.0, target_node).to_dict()