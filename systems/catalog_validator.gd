# res://systems/catalog_validator.gd
class_name CatalogValidator extends RefCounted

const VALID_CATEGORIES = ["CONSUMABLE", "DURABLE", "SERVICE"]
const VALID_MODELS = ["LINEAR_PER_UNIT", "WEIGHTED_PER_UNIT", "EXP_PER_UNIT", "LOG_PER_UNIT", "STEPPED_PER_UNIT"]

## Runs an end-to-end integrity audit across commodities, recipes, and verbs
static func validate_catalogs(world_state: Dictionary, write_to_disk: bool = true) -> Dictionary:
	var commodities: Dictionary = world_state.get("commodity_registry", {})
	var recipes: Dictionary = world_state.get("recipe_registry", {})
	
	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"is_clean": true,
		"errors": [],
		"warnings": [],
		"commodity_count": commodities.size(),
		"recipe_count": recipes.size(),
		"raw_commodity_count": commodities.size(),
		"sanitized_commodity_count": commodities.size(),
		"raw_recipe_count": recipes.size(),
		"sanitized_recipe_count": recipes.size()
	}

	# -------------------------------------------------------------
	# 1. COMMODITY INTEGRITY AUDIT
	# -------------------------------------------------------------
	for item_id in commodities.keys():
		var item = commodities[item_id]
		if not item is Dictionary:
			report["errors"].append("Commodity '%s' is not a Dictionary." % item_id)
			report["is_clean"] = false
			continue
		
		# Check category validity
		var cat: String = item.get("category", "")
		if not VALID_CATEGORIES.has(cat):
			report["errors"].append("Commodity '%s' has invalid or missing category: '%s'" % [item_id, cat])
			report["is_clean"] = false
			
		# Check base cost (warning only if explicitly present and <= 0.0)
		if item.has("base_cost") and float(item["base_cost"]) <= 0.0:
			report["warnings"].append("Commodity '%s' has zero or negative base_cost." % item_id)
			
		# Check impact activations
		var activations = item.get("impact_activations", {})
		if activations is Dictionary:
			for verb_key in activations.keys():
				var act_list = activations[verb_key]
				if act_list is Array:
					for impact in act_list:
						if impact is Dictionary:
							var model: String = impact.get("model", "")
							if not VALID_MODELS.has(model):
								report["errors"].append("Commodity '%s' [%s] references unknown ImpactCalculator model: '%s'" % [item_id, verb_key, model])
								report["is_clean"] = false

	# -------------------------------------------------------------
	# 2. RECIPE INTEGRITY AUDIT (Cross-Reference Against Commodities)
	# -------------------------------------------------------------
	for recipe_id in recipes.keys():
		var recipe = recipes[recipe_id]
		if not recipe is Dictionary:
			report["errors"].append("Recipe '%s' is not a Dictionary." % recipe_id)
			report["is_clean"] = false
			continue
		
		# Check Output Item Exists
		var output_item: String = recipe.get("output_item", "")
		if output_item == "":
			report["errors"].append("Recipe '%s' defines no output_item." % recipe_id)
			report["is_clean"] = false
		elif not commodities.has(output_item):
			report["errors"].append("Recipe '%s' outputs '%s', which does not exist in commodity_registry!" % [recipe_id, output_item])
			report["is_clean"] = false

		# Check Yield
		if float(recipe.get("output_yield_units", 0.0)) <= 0.0:
			report["errors"].append("Recipe '%s' has zero or negative output_yield_units." % recipe_id)
			report["is_clean"] = false

		# Check All Inputs Exist in Catalog
		var inputs = recipe.get("inputs", {})
		if not inputs is Dictionary or inputs.is_empty():
			report["warnings"].append("Recipe '%s' defines no inputs." % recipe_id)
		else:
			for ing_id in inputs.keys():
				if not commodities.has(ing_id):
					report["errors"].append("Recipe '%s' requires input ingredient '%s', which is NOT in commodity_registry!" % [recipe_id, ing_id])
					report["is_clean"] = false
				elif float(inputs[ing_id]) <= 0.0:
					report["errors"].append("Recipe '%s' requires zero or negative quantity for ingredient '%s'." % [recipe_id, ing_id])
					report["is_clean"] = false

	# -------------------------------------------------------------
	# 3. FORMAT & LOG DUMP
	# -------------------------------------------------------------
	_print_summary(report)
	
	if write_to_disk:
		_write_log_to_disk(report)
		
	return report

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
		"commodity_count": raw_commodities.size(),
		"recipe_count": raw_recipes.size(),
		"raw_commodity_count": raw_commodities.size(),
		"raw_recipe_count": raw_recipes.size(),
		"sanitized_commodity_count": 0,
		"sanitized_recipe_count": 0
	}

	# 1. AUDIT & SANITIZE COMMODITIES
	for item_id in raw_commodities.keys():
		var item = raw_commodities[item_id]
		var is_item_valid = true
		
		var cat: String = item.get("category", "")
		if not VALID_CATEGORIES.has(cat):
			report["errors"].append("Commodity '%s' omitted: invalid/missing category '%s'" % [item_id, cat])
			is_item_valid = false
			
		var activations = item.get("impact_activations", {})
		if activations is Dictionary:
			for verb_key in activations.keys():
				var act_list = activations[verb_key]
				if act_list is Array:
					for impact in act_list:
						if impact is Dictionary:
							var model: String = impact.get("model", "")
							if not VALID_MODELS.has(model):
								report["errors"].append("Commodity '%s' omitted: unknown impact model '%s'" % [item_id, model])
								is_item_valid = false

		if is_item_valid:
			valid_commodities[item_id] = item
		else:
			report["is_clean"] = false

	# 2. AUDIT & SANITIZE RECIPES
	for recipe_id in raw_recipes.keys():
		var recipe = raw_recipes[recipe_id]
		var is_recipe_valid = true
		
		var output_item: String = recipe.get("output_item", "")
		if output_item == "" or not valid_commodities.has(output_item):
			report["errors"].append("Recipe '%s' omitted: output '%s' does not exist in valid commodities." % [recipe_id, output_item])
			is_recipe_valid = false

		if float(recipe.get("output_yield_units", 0.0)) <= 0.0:
			report["errors"].append("Recipe '%s' omitted: non-positive yield." % recipe_id)
			is_recipe_valid = false

		var inputs = recipe.get("inputs", {})
		if not inputs is Dictionary or inputs.is_empty():
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
	var raw_c = report.get("raw_commodity_count", report.get("commodity_count", 0))
	var san_c = report.get("sanitized_commodity_count", raw_c)
	var raw_r = report.get("raw_recipe_count", report.get("recipe_count", 0))
	var san_r = report.get("sanitized_recipe_count", raw_r)
	
	print("  Commodities: %d on disk  ->  %d surfaced to player" % [raw_c, san_c])
	print("  Recipes:     %d on disk  ->  %d surfaced to player" % [raw_r, san_r])
	print("  Status:      ", "100% CLEAN" if report["is_clean"] else "ISSUES DETECTED & ISOLATED")
	
	if not report["errors"].is_empty():
		print("\n  [!] ISOLATED ITEMS (Hidden from player):")
		for err in report["errors"]:
			print("    ⚠️  ", err)
			
	print("=======================================================\n")

static func _write_log_to_disk(report: Dictionary) -> void:
	var file = FileAccess.open("user://catalog_audit.log", FileAccess.WRITE)
	if file:
		var raw_c = report.get("raw_commodity_count", report.get("commodity_count", 0))
		var san_c = report.get("sanitized_commodity_count", raw_c)
		var raw_r = report.get("raw_recipe_count", report.get("recipe_count", 0))
		var san_r = report.get("sanitized_recipe_count", raw_r)
		
		file.store_line("CATALOG INTEGRITY AUDIT - " + report.get("timestamp", ""))
		file.store_line("Clean: " + str(report.get("is_clean", false)))
		file.store_line("Commodities Surfaced: %d / %d" % [san_c, raw_c])
		file.store_line("Recipes Surfaced: %d / %d" % [san_r, raw_r])
		file.store_line("\nISOLATED DEFECTS:")
		for err in report.get("errors", []):
			file.store_line("- " + err)
		file.close()