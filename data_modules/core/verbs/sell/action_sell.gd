# res://data_modules/core/verbs/sell/action_sell.gd
extends ActionBase
class_name ActionSell

static var _impacts: Array = []
static var _loaded: bool = false

static func _init_impacts() -> void:
	if not _loaded:
		_impacts = load_subfolder_impacts("res://data_modules/core/verbs/sell/impacts")
		_loaded = true

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	_init_impacts()
	
	var params = action.get("config", {})
	var item_key = action.get("target_item", "")
	var amount = float(action.get("amount", 0.0))
	var unit_price = float(params.get("unit_price", 2.0))
	var target_node = action.get("target_node_id", "DIST_01")
	
	# Fetch commodity profile from registry
	var registry = world_state.get("commodity_registry", {})
	var commodity = registry.get(item_key, {})
	
	# Primary Economic Transaction
	var gross_cash = amount * unit_price
	world_state["finances"]["liquid_cash"] += gross_cash[cite: 1]
	
	var summary = {
		"units_transacted": amount,
		"gross_cash": gross_cash,
		"target_node_id": target_node
	}
	
	# Compile impacts calculated through the commodity's velocity metrics
	var deltas = compile_impact_deltas(_impacts, params, summary, commodity)
	
	return {
		"success": true,
		"verb": "SELL",
		"target_node_id": target_node,
		"units_transacted": amount,
		"gross_cash": gross_cash,
		"impact_deltas": deltas,
		"message": "Sold %.0f of %s for £%.2f" % [amount, item_key, gross_cash]
	}