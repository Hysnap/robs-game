# res://systems/order_manager.gd
class_name OrderManager extends RefCounted

## Registers an active order slip into pending_orders
static func create_order(world_state: Dictionary, buyer_id: String, seller_id: String, item_key: String, amount: float, unit_cost: float) -> String:
	var order_id: String = "ORD_%d" % randi_range(1000, 9999)
	if not world_state.has("pending_orders"):
		world_state["pending_orders"] = {}

	world_state["pending_orders"][order_id] = {
		"order_id": order_id,
		"buyer_id": buyer_id,
		"seller_id": seller_id,
		"item_key": item_key,
		"amount": amount,
		"unit_cost": unit_cost,
		"total_cost": amount * unit_cost,
		"status": "ORDERED",
		"created_tick": world_state.get("metadata", {}).get("current_week_tick", 1)
	}
	return order_id

## Fetches an active order ticket
static func get_order(world_state: Dictionary, order_id: String) -> Dictionary:
	return world_state.get("pending_orders", {}).get(order_id, {})

## Transitions order status (e.g. to 'PAID' or 'DELIVERED')
static func update_order_status(world_state: Dictionary, order_id: String, new_status: String) -> void:
	var pending: Dictionary = world_state.get("pending_orders", {})
	if pending.has(order_id):
		pending[order_id]["status"] = new_status

## Moves an order from active pending_orders to permanent completed_orders ledger
static func archive_order(world_state: Dictionary, order_id: String) -> void:
	var pending: Dictionary = world_state.get("pending_orders", {})
	if not pending.has(order_id):
		return

	if not world_state.has("completed_orders"):
		world_state["completed_orders"] = {}

	var ticket: Dictionary = pending[order_id]
	ticket["status"] = "COMPLETED"
	ticket["completed_tick"] = world_state.get("metadata", {}).get("current_week_tick", 1)

	world_state["completed_orders"][order_id] = ticket
	pending.erase(order_id)