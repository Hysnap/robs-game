# res://data_modules/core/verbs/sell/action_sell.gd
extends ActionBase
class_name ActionSell

const ACTION_ORDER = preload("res://data_modules/core/verbs/order/action_order.gd")
const ACTION_PAY = preload("res://data_modules/core/verbs/pay/action_pay.gd")
const ACTION_RECEIVE = preload("res://data_modules/core/verbs/receive/action_receive.gd")
const ORDER_MGR = preload("res://systems/order_manager.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var item_key: String = action.get("target_item", "")
	var amount: float = float(action.get("amount", 0.0))
	var target_node: String = action.get("target_node_id", "DIST_01")
	var seller_id: String = action.get("initiator_id", "PLAYER")
	var buyer_id: String = action.get("counterparty_id", "MARKET_CONSUMERS")

	# -------------------------------------------------------------
	# 1. ORDER (Commitment: Verifies Seller Available Stock)
	# -------------------------------------------------------------
	var order_directive = {
		"initiator_id": buyer_id,
		"counterparty_id": seller_id,
		"target_item": item_key,
		"amount": amount,
		"target_node_id": target_node,
		"config": action.get("config", {})
	}
	var order_res = ACTION_ORDER.execute(world_state, order_directive)
	if not order_res.get("success", false):
		return order_res

	var order_id: String = order_res["order_id"]

	# -------------------------------------------------------------
	# 2. RECEIVE (Goods Transferred to Customer & SELL Impacts Run)
	# -------------------------------------------------------------
	var rec_res = ACTION_RECEIVE.execute(world_state, {
		"order_id": order_id,
		"target_node_id": target_node,
		"allow_fronted_credit": true
	})
	if not rec_res.get("success", false):
		return rec_res

	# -------------------------------------------------------------
	# 3. PAY (Revenue Settlement: Inflow to Seller Vault)
	# -------------------------------------------------------------
	var pay_res = ACTION_PAY.execute(world_state, {"order_id": order_id, "target_node_id": target_node})
	if not pay_res.get("success", false):
		return pay_res

	# -------------------------------------------------------------
	# 4. CONSOLIDATE IMPACT DELTAS (CASH + POLICE_HEAT + ZONE_HEALTH)
	# -------------------------------------------------------------
	var consolidated_deltas: Dictionary = {}
	consolidated_deltas.merge(rec_res.get("impact_deltas", {}))
	
	# For selling, cash flows positive into player metrics/vault
	var revenue: float = abs(pay_res.get("impact_deltas", {}).get("CASH", 0.0))
	consolidated_deltas["CASH"] = revenue
	ORDER_MGR.archive_order(world_state, order_id)

	return EngineResult.ok("SELL", "Sold %.0f of %s to %s for £%.2f." % [amount, item_key, buyer_id, revenue], consolidated_deltas, amount, target_node).to_dict()
