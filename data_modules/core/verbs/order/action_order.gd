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
	var contact_id: String = str(action.get("counterparty_id", "")).strip_edges()
	var target_node: String = str(action.get("target_node_id", "HQ")).strip_edges()

	# 1. Assert Commodity Exists
	var commodity = world_state.get("commodity_registry", {}).get(item_key, {})
	if commodity.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.UNKNOWN_COMMODITY, 
			"ORDER", 
			"Commodity '%s' missing from catalog." % item_key, 
			target_node
		).to_dict()

	# 2. Assert Buyer Exists and Verify Solvency
	if ConditionEvaluator.get_state_metric(world_state, buyer_id, "CASH") == -INF:
		return EngineResult.fail(
			EngineResult.ErrorCode.ENTITY_NOT_FOUND, 
			"ORDER", 
			"Buyer entity '%s' does not exist." % buyer_id, 
			target_node
		).to_dict()

	if unit_cost <= 0.0:
		unit_cost = float(commodity.get("base_cost", 1.0))
	var total_cost: float = amount * unit_cost

	if not ConditionEvaluator.has_sufficient(world_state, buyer_id, "CASH", total_cost):
		var avail = ConditionEvaluator.get_state_metric(world_state, buyer_id, "CASH")
		return EngineResult.fail(
			EngineResult.ErrorCode.INSUFFICIENT_RESOURCE, 
			"ORDER", 
			"Buyer '%s' lacks funds: £%.2f available, £%.2f needed." % [buyer_id, avail, total_cost], 
			target_node
		).to_dict()

	# 3. Resolve Stocking Entity (Contact Personal Stash -> Venue/Establishment Inventory)
	var resolved_seller_id: String = ""
	
	# Priority A: Check specific individual/operative's personal stash
	if not contact_id.is_empty():
		if ConditionEvaluator.has_sufficient(world_state, contact_id, item_key, amount):
			resolved_seller_id = contact_id

	# Priority B: Check physical venue/establishment stock
	if resolved_seller_id.is_empty() and not target_node.is_empty() and target_node != "HQ":
		if ConditionEvaluator.has_sufficient(world_state, target_node, item_key, amount):
			resolved_seller_id = target_node

	# 4. Noisy Failure: If neither contact nor venue holds stock, fail explicitly
	if resolved_seller_id.is_empty():
		var venue_label: String = target_node if not target_node.is_empty() else "Unknown Venue"
		if not contact_id.is_empty():
			return EngineResult.fail(
				EngineResult.ErrorCode.INSUFFICIENT_RESOURCE, 
				"ORDER", 
				"Order failed: Neither venue '%s' nor contact '%s' has stock of '%s' (%.0f requested)." % [
					venue_label, contact_id, item_key, amount
				], 
				target_node
			).to_dict()
		else:
			var stock_avail = ConditionEvaluator.get_state_metric(world_state, target_node, item_key)
			return EngineResult.fail(
				EngineResult.ErrorCode.INSUFFICIENT_RESOURCE, 
				"ORDER", 
				"Order failed: Venue '%s' lacks stock of '%s': %.0f available, %.0f requested." % [
					venue_label, item_key, maxf(0.0, stock_avail), amount
				], 
				target_node
			).to_dict()

	# 5. Commit Ephemeral Verbal Order with the Verified Stocking Entity
	var order_id = ORDER_MGR.create_order(world_state, buyer_id, resolved_seller_id, item_key, amount, unit_cost)

	var res = EngineResult.ok(
		"ORDER", 
		"Order %s registered: %.0f of %s for £%.2f from %s." % [order_id, amount, item_key, total_cost, resolved_seller_id], 
		{}, 
		amount, 
		target_node
	)
	var dict = res.to_dict()
	dict["order_id"] = order_id
	return dict