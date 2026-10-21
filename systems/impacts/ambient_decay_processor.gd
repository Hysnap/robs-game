# res://systems/impacts/ambient_decay_processor.gd
class_name AmbientDecayProcessor extends RefCounted

const CALCULATOR = preload("res://systems/impacts/impact_calculator.gd")
const ROUTER = preload("res://systems/impacts/impact_router.gd")

## Evaluates natural commodity decay across all inventory lanes on ambient tick
static func process_inventory_decay(world_state: Dictionary) -> void:
	var inventory = world_state.get("inventory_registry", {})
	var commodity_registry = world_state.get("commodity_registry", {})
	var container_registry = world_state.get("container_registry", {})

	for item_key in inventory.keys():
		var lane_data = inventory[item_key]
		var current_qty: float = float(lane_data.get("STOCK", 0.0))
		if current_qty <= 0.0:
			continue

		var commodity_id: String = lane_data.get("commodity_id", item_key)
		var commodity = commodity_registry.get(commodity_id, {})
		var decay_def = commodity.get("decay_properties", {})
		
		# 1. Non-perishables skip evaluation
		var shelf_life: int = int(decay_def.get("shelf_life_ticks", 0))
		if shelf_life <= 0 or not decay_def.has("impact"):
			continue

		# 2. Track ticks past shelf life
		var age_ticks: int = int(lane_data.get("age_ticks", 0)) + 1
		lane_data["age_ticks"] = age_ticks
		if age_ticks <= shelf_life:
			continue # Still within stable shelf life

		# 3. Pull Base Impact Definition
		var impact_def: Dictionary = decay_def.get("impact", {})
		var model: String = impact_def.get("model", "LINEAR_PER_UNIT")
		var factor: float = float(impact_def.get("factor", 0.0))
		var params: Dictionary = impact_def.get("params", {}).duplicate()

		# 4. Filter Through Container Modifiers (if packaged)
		var container_id: String = lane_data.get("container_id", "NONE")
		if container_id != "NONE" and container_registry.has(container_id):
			var container = container_registry[container_id]
			var mods = container.get("decay_modifiers", {})
			factor *= float(mods.get("factor_multiplier", 1.0))
			if mods.get("override_model", "") != "":
				model = mods["override_model"]

		# 5. REUSE IMPACT CALCULATOR (Zero duplicate math)
		# Evaluates the exact delta lost (negative float)
		var delta_lost: float = CALCULATOR.calculate(model, current_qty, factor, params)

		# 6. REUSE IMPACT ROUTER
		if delta_lost != 0.0:
			# Routes negative delta into the inventory sink
			ROUTER.dispatch_delta(world_state, item_key, "INVENTORY", delta_lost)
			
			# Handle transformation if degraded item converts into another commodity
			var degrades_to: String = decay_def.get("degrades_to", "")
			if degrades_to != "":
				var spoiled_yield = abs(delta_lost)
				ROUTER.dispatch_delta(world_state, degrades_to, "INVENTORY", spoiled_yield)