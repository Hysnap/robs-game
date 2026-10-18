# res://data_modules/core/impacts/inventory/sink_inventory.gd
extends ImpactSinkBase
class_name SinkInventory

static func get_metric_key() -> String:
	return "INVENTORY" # Matches keys formatted as "INVENTORY:ITEM_NAME"

static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	# Handled dynamically via payload parameters or compound key (e.g., INVENTORY_STOCK)
	pass