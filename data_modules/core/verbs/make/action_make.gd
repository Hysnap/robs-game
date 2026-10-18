# res://data_modules/core/verbs/make/action_make.gd
extends ActionBase
class_name ActionMake

const CALCULATOR = preload("res://systems/impacts/impact_calculator.gd")
const EVALUATOR = preload("res://systems/condition_evaluator.gd")

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var params: Dictionary = action.get("config", {})
	var recipe_id: String = action.get("recipe_id", action.get("target_item", ""))
	var batch_multiplier: int = int(params.get("batch_multiplier", action.get("amount", 1)))
	var target_node: String = action.get("target_node_id", "HQ")
	var actor_id: String = action.get("initiator_id", "PLAYER")

	if batch_multiplier <= 0:
		batch_multiplier = 1

	# 1. ASSERT RECIPE EXISTS
	var recipe_registry: Dictionary = world_state.get("recipe_registry", {})
	var recipe: Dictionary = recipe_registry.get(recipe_id, {})
	if recipe.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.UNKNOWN_COMMODITY,
			"MAKE",
			"Recipe '%s' not registered in catalog." % recipe_id,
			target_node
		).to_dict()

	var output_item: String = recipe.get("output_item", "")
	var base_yield: float = float(recipe.get("output_yield_units", 1.0))
	var total_yield: float = base_yield * batch_multiplier
	var inputs: Dictionary = recipe.get("inputs", {})

	# 2. ASSERT ACTOR EXISTS & VERIFY INPUT INVENTORY LANES
	var actor_inv: Dictionary = EVALUATOR.get_actor_inventory(world_state, actor_id)
	if actor_inv.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.ENTITY_NOT_FOUND,
			"MAKE",
			"Actor '%s' has no registered inventory." % actor_id,
			target_node
		).to_dict()

	for ingredient_key in inputs.keys():
		var required_qty: float = float(inputs[ingredient_key]) * batch_multiplier
		if not EVALUATOR.has_sufficient_resource(world_state, actor_id, ingredient_key, required_qty):
			var available: float = EVALUATOR.get_resource_balance(world_state, actor_id, ingredient_key)
			return EngineResult.fail(
				EngineResult.ErrorCode.INSUFFICIENT_RESOURCE,
				"MAKE",
				"Shortage of raw material '%s': %.1f required, %.1f available." % [ingredient_key, required_qty, available],
				target_node
			).to_dict()

	# 3. CONSUME RAW MATERIALS (STOCK LANE)
	for ingredient_key in inputs.keys():
		var required_qty: float = float(inputs[ingredient_key]) * batch_multiplier
		actor_inv[ingredient_key]["STOCK"] = float(actor_inv[ingredient_key].get("STOCK", 0.0)) - required_qty

	# 4. DEPOSIT FINISHED PORTIONS (PREPPED LANE)
	if not actor_inv.has(output_item):
		actor_inv[output_item] = {"STOCK": 0.0, "PREPPED": 0.0}
	actor_inv[output_item]["PREPPED"] = float(actor_inv[output_item].get("PREPPED", 0.0)) + total_yield

	# 5. COMPILE DUAL-TIER IMPACT DELTAS
	var consolidated_deltas: Dictionary = {}

	# Tier A: Process-Level Impacts (from the Recipe itself: tool wear, vat fatigue)
	var recipe_activations: Array = recipe.get("impact_activations", {}).get("MAKE", [])
	for entry in recipe_activations:
		var metric: String = entry.get("metric", "")
		var model: String = entry.get("model", "LINEAR_PER_UNIT")
		var factor: float = float(entry.get("factor", 0.0))
		var model_params: Dictionary = entry.get("params", {}).duplicate()

		var delta_val: float = CALCULATOR.calculate(model, batch_multiplier, factor, model_params)
		if metric != "" and delta_val != 0.0:
			consolidated_deltas[metric] = consolidated_deltas.get(metric, 0.0) + delta_val

	# Tier B: Ingredient-Level Impacts (from each Commodity: fumes, handling hazard, toxicity)
	var commodity_registry: Dictionary = world_state.get("commodity_registry", {})
	for ingredient_key in inputs.keys():
		var ingredient_profile: Dictionary = commodity_registry.get(ingredient_key, {})
		var consumed_qty: float = float(inputs[ingredient_key]) * batch_multiplier
		var ing_activations: Array = ingredient_profile.get("impact_activations", {}).get("MAKE", [])

		for entry in ing_activations:
			var metric: String = entry.get("metric", "")
			var model: String = entry.get("model", "LINEAR_PER_UNIT")
			var factor: float = float(entry.get("factor", 0.0))
			var model_params: Dictionary = entry.get("params", {}).duplicate()

			var delta_val: float = CALCULATOR.calculate(model, consumed_qty, factor, model_params)
			if metric != "" and delta_val != 0.0:
				consolidated_deltas[metric] = consolidated_deltas.get(metric, 0.0) + delta_val

	return EngineResult.ok(
		"MAKE",
		"Processed %d batch(es) of %s. Yielded +%.0f prepped units into staging." % [batch_multiplier, recipe_id, total_yield],
		consolidated_deltas,
		total_yield,
		target_node
	).to_dict()