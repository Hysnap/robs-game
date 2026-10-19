# res://systems/catalog_validator.gd
class_name CatalogValidator extends RefCounted

const VALID_CATEGORIES = ["CONSUMABLE", "DURABLE", "SERVICE"]
const VALID_MODELS = ["LINEAR_PER_UNIT", "WEIGHTED_PER_UNIT", "EXP_PER_UNIT", "LOG_PER_UNIT", "STEPPED_PER_UNIT"]

## Audits registries, writes logs, and returns ONLY 100% playable items/recipes
static func sanitize_and_audit(world_state: Dictionary, write_to_disk: bool = true) -> Dictionary:
	var raw_commodities: Dictionary = world_state.get("commodity_registry", {})
	var raw_recipes: Dictionary = world_state.get("recipe_registry", {})
	
	var valid_commodities: Dictionary = {}
	var valid_recipes: Dictionary = {}
	
	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"is_clean": true,
		"errors": [],
		"warnings": [],
		"raw_commodity_count": raw_commodities.size(),
		"raw_recipe_count": raw_recipes.size(),
		"sanitized_commodity_count": 0,
		"sanitized_recipe_count": 0
	}

	# -------------------------------------------------------------
	# 1. AUDIT & SANITIZE COMMODITIES
	# -------------------------------------------------------------
	for item_id in raw_commodities.keys():
		var item: Dictionary = raw_commodities[item_id]
		var is_item_valid = true
		
		# Category check
		var cat: String = item.get("category", "")
		if not VALID_CATEGORIES.has(cat):
			report["errors"].append("Commodity '%s' omitted: invalid/missing category '%s'" % [item_id, cat])
			is_item_valid = false
			
		# Impact model check
		var activations: Dictionary = item.get("impact_activations", {})
		for verb_key in activations.keys():
			for impact in activations[verb_key]:
				var model: String = impact.get("model", "")
				if not VALID_MODELS.has(model):
					report["errors"].append("Commodity '%s' omitted: unknown impact model '%s'" % [item_id, model])
					is_item_valid = false

		if is_item_valid:
			valid_commodities[item_id] = item
		else:
			report["is_clean"] = false

	# -------------------------------------------------------------
	# 2. AUDIT & SANITIZE RECIPES (Must match valid commodities)
	# -------------------------------------------------------------
	for recipe_id in raw_recipes.keys():
		var recipe: Dictionary = raw_recipes[recipe_id]
		var is_recipe_valid = true
		
		# Output Item Check
		var output_item: String = recipe.get("output_item", "")
		if output_item == "" or not valid_commodities.has(output_item):
			report["errors"].append("Recipe '%s' omitted: output '%s' does not exist in valid commodities." % [recipe_id, output_item])
			is_recipe_valid = false

		# Yield Check
		if float(recipe.get("output_yield_units", 0.0)) <= 0.0:
			report["errors"].append("Recipe '%s' omitted: non-positive yield." % recipe_id)
			is_recipe_valid = false

		# Inputs Check
		var inputs: Dictionary = recipe.get("inputs", {})
		if inputs.is_empty():
			report["warnings"].append("Recipe '%s' has no inputs." % recipe_id)
		else:
			for ing_id in inputs.keys():
				if not valid_commodities.has(ing_id):
					report["errors"].append("Recipe '%s' omitted: input '%s' is not in valid commodities." % [recipe_id, ing_id])
					is_recipe_valid = false
				elif float(inputs[ing_id]) <= 0.0:
					report["errors"].append("Recipe '%s' omitted: non-positive quantity for '%s'." % [recipe_id, ing_id])
					is_recipe_valid = false

		if is_recipe_valid:
			valid_recipes[recipe_id] = recipe
		else:
			report["is_clean"] = false

	report["sanitized_commodity_count"] = valid_commodities.size()
	report["sanitized_recipe_count"] = valid_recipes.size()

	# -------------------------------------------------------------
	# 3. APPLY SANITIZED DATA TO ACTIVE WORLD STATE
	# -------------------------------------------------------------
	world_state["commodity_registry"] = valid_commodities
	world_state["recipe_registry"] = valid_recipes

	_print_summary(report)
	if write_to_disk:
		_write_log_to_disk(report)

	return report

static func _print_summary(report: Dictionary) -> void:
	print("\n=======================================================")
	print("       SYSTEM CATALOG AUDIT & SANITIZATION             ")
	print("=======================================================")
	print("  Commodities: %d on disk  ->  %d surfaced to player" % [report["raw_commodity_count"], report["sanitized_commodity_count"]])
	print("  Recipes:     %d on disk  ->  %d surfaced to player" % [report["raw_recipe_count"], report["sanitized_recipe_count"]])
	print("  Status:      ", "100% CLEAN" if report["is_clean"] else "ISSUES DETECTED & ISOLATED")
	
	if not report["errors"].is_empty():
		print("\n  [!] ISOLATED ITEMS (Hidden from player):")
		for err in report["errors"]:
			print("    ⚠️  ", err)
			
	print("=======================================================\n")

static func _write_log_to_disk(report: Dictionary) -> void:
	var file = FileAccess.open("user://catalog_audit.log", FileAccess.WRITE)
	if file:
		file.store_line("CATALOG INTEGRITY AUDIT - " + report["timestamp"])
		file.store_line("Clean: " + str(report["is_clean"]))
		file.store_line("Commodities Surfaced: %d / %d" % [report["sanitized_commodity_count"], report["raw_commodity_count"]])
		file.store_line("Recipes Surfaced: %d / %d" % [report["sanitized_recipe_count"], report["raw_recipe_count"]])
		file.store_line("\nISOLATED DEFECTS:")
		for err in report["errors"]:
			file.store_line("- " + err)
		file.close()