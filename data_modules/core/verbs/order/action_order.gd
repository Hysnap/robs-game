# res://data_modules/core/verbs/order/action_order.gd
extends ActionBase
class_name ActionOrder
const ORDER_MGR = preload("res://systems/order_manager.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var params: Dictionary = action.get("config", {})
	var item_key: String = action.get("target_item", "")
	var amount: float = float(action.get("amount", 0.0))
	var unit_cost: float = float(params.get("unit_price", params.get("unit_cost", 0.0)))
	var buyer_id: String = action.get("initiator_id", "PLAYER")
	var seller_id: String = action.get("counterparty_id", "")
	var target_node: String = action.get("target_node_id", "HQ")
	

	# 1. Assert Commodity Exists
	var commodity = world_state.get("commodity_registry", {}).get(item_key, {})
	if commodity.is_empty():
		return EngineResult.fail(EngineResult.ErrorCode.UNKNOWN_COMMODITY, "ORDER", "Commodity '%s' missing from catalog." % item_key, target_node).to_dict()

	# 2. Assert Buyer and Seller Entities Exist
	if ConditionEvaluator.get_state_metric(world_state, buyer_id, "CASH") == -INF:
		return EngineResult.fail(EngineResult.ErrorCode.ENTITY_NOT_FOUND, "ORDER", "Buyer entity '%s' does not exist." % buyer_id, target_node).to_dict()

	if ConditionEvaluator.get_actor_inventory(world_state, seller_id).is_empty():
		return EngineResult.fail(EngineResult.ErrorCode.ENTITY_NOT_FOUND, "ORDER", "Seller entity '%s' does not exist or has no inventory." % seller_id, target_node).to_dict()

	if unit_cost <= 0.0:
		unit_cost = float(commodity.get("base_cost", 1.0))
	var total_cost: float = amount * unit_cost

	# 3. Assert Financial Solvency
	if not ConditionEvaluator.has_sufficient(world_state, buyer_id, "CASH", total_cost):
		var avail = ConditionEvaluator.get_state_metric(world_state, buyer_id, "CASH")
		return EngineResult.fail(EngineResult.ErrorCode.INSUFFICIENT_RESOURCE, "ORDER", "Buyer '%s' lacks funds: £%.2f available, £%.2f needed." % [buyer_id, avail, total_cost], target_node).to_dict()

	# 4. Assert Seller Stock Availability
	if not ConditionEvaluator.has_sufficient(world_state, seller_id, item_key, amount):
		var stock = ConditionEvaluator.get_state_metric(world_state, seller_id, item_key)
		return EngineResult.fail(EngineResult.ErrorCode.INSUFFICIENT_RESOURCE, "ORDER", "Seller '%s' lacks stock: %.0f available, %.0f requested." % [seller_id, stock, amount], target_node).to_dict()
	# 5. Commit Ephemeral Verbal Order
	var order_id = ORDER_MGR.create_order(world_state, buyer_id, seller_id, item_key, amount, unit_cost)

	var res = EngineResult.ok("ORDER", "Order %s registered: %.0f of %s for £%.2f." % [order_id, amount, item_key, total_cost], {}, amount, target_node)
	var dict = res.to_dict()
	dict["order_id"] = order_id
	return dict