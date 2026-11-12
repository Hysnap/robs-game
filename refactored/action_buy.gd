# res://data_modules/core/verbs/buy/action_buy.gd
extends ActionBase
class_name ActionBuy

const ACTION_ORDER = preload("res://data_modules/core/verbs/order/action_order.gd")
const ACTION_PAY = preload("res://data_modules/core/verbs/pay/action_pay.gd")
const ACTION_RECEIVE = preload("res://data_modules/core/verbs/receive/action_receive.gd")
const ORDER_MGR = preload("res://systems/order_manager.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var item_key: String = action.get("target_item", "")
	var amount: float = float(action.get("amount", 0.0))
	var target_node: String = str(action.get("target_node_id", "HQ")).strip_edges()
	var buyer_id: String = str(action.get("initiator_id", "PLAYER")).strip_edges()
	var contact_id: String = str(action.get("counterparty_id", "")).strip_edges()

	# -------------------------------------------------------------
	# 1. ORDER (Commitment & Dual-Entity Stock Verification)
	# -------------------------------------------------------------
	var order_directive := {
		"initiator_id": buyer_id,
		"counterparty_id": contact_id,
		"target_item": item_key,
		"amount": amount,
		"target_node_id": target_node,
		"config": action.get("config", {})
	}
	var order_res: Dictionary = ACTION_ORDER.execute(world_state, order_directive)
	if not order_res.get("success", false):
		return order_res

	var order_id: String = order_res.get("order_id", "")
	var order_ticket: Dictionary = ORDER_MGR.get_order(world_state, order_id)
	var resolved_seller: String = str(order_ticket.get("seller_id", contact_id))

	# -------------------------------------------------------------
	# 2. PAY (Settlement: Cash Transfer)
	# -------------------------------------------------------------
	var pay_res: Dictionary = ACTION_PAY.execute(world_state, {
		"order_id": order_id, 
		"target_node_id": target_node
	})
	if not pay_res.get("success", false):
		return pay_res

	# -------------------------------------------------------------
	# 3. RECEIVE (Physical Stock Sunk to Buyer & BUY Impacts Run)
	# -------------------------------------------------------------
	var rec_res: Dictionary = ACTION_RECEIVE.execute(world_state, {
		"order_id": order_id, 
		"target_node_id": target_node
	})
	if not rec_res.get("success", false):
		return rec_res

	# -------------------------------------------------------------
	# 4. CONSOLIDATE IMPACT DELTAS
	# -------------------------------------------------------------
	var consolidated_deltas: Dictionary = {}
	consolidated_deltas.merge(pay_res.get("impact_deltas", {}))
	consolidated_deltas.merge(rec_res.get("impact_deltas", {}))

	# Archive completed ticket into permanent historical ledger
	ORDER_MGR.archive_order(world_state, order_id)

	var ctx := {
		"target_item": item_key,
		"amount": amount,
		"seller_id": resolved_seller,
		"target_location": target_node
	}
	return EngineResult.ok(
		"BUY", 
		"Purchased %.0f of %s from %s." % [amount, item_key, resolved_seller], 
		consolidated_deltas, 
		amount, 
		target_node, 
		ctx
	).to_dict()