# res://tools/compile_recipe_verbs.gd
class_name CompileRecipeVerbs
extends SceneTree

const CommodityManagerScript = preload("res://systems/commodity_manager.gd")
const RECIPES_DIR := "res://data_modules/core/recipes/"
const OUTPUT_BASE_DIR := "res://data_modules/core/verbs/recipes/"

func _init() -> void:
	print("\n--- [CompileRecipeVerbs] Ingesting Existing Recipe Registry ---")
	
	# 1. Load recipes directly using existing CommodityManager loader
	var recipe_registry: Dictionary = CommodityManagerScript.load_hierarchical_commodities(RECIPES_DIR)
	
	if recipe_registry.is_empty():
		push_warning("[CompileRecipeVerbs] No recipes found in '%s'." % RECIPES_DIR)
		quit(0)
		return

	print("[CompileRecipeVerbs] Discovered %d recipes in registry. Compiling to disk..." % recipe_registry.size())
	
	# Ensure base directory exists
	if not DirAccess.dir_exists_absolute(OUTPUT_BASE_DIR):
		DirAccess.make_dir_recursive_absolute(OUTPUT_BASE_DIR)

	var compiled_count: int = 0
	for recipe_id in recipe_registry.keys():
		var recipe_data: Dictionary = recipe_registry[recipe_id]
		if _compile_recipe_to_disk(recipe_data):
			compiled_count += 1

	print("--- [CompileRecipeVerbs] Successfully wrote %d static verb definitions and target scopes to %s ---\n" % [compiled_count, OUTPUT_BASE_DIR])
	quit(0)

static func _compile_recipe_to_disk(recipe: Dictionary) -> bool:
	var recipe_id: String = str(recipe.get("id", "")).strip_edges().to_upper()
	if recipe_id.is_empty():
		return false

	var verb_token: String = "MAKE_" + recipe_id
	var verb_def: Dictionary = build_verb_definition_from_recipe(recipe)

	var target_folder: String = OUTPUT_BASE_DIR.path_join(verb_token.to_lower())
	if not DirAccess.dir_exists_absolute(target_folder):
		DirAccess.make_dir_recursive_absolute(target_folder)

	# 1. Write verb_definition.json
	var def_path: String = target_folder.path_join("verb_definition.json")
	var def_file := FileAccess.open(def_path, FileAccess.WRITE)
	if def_file == null:
		push_error("[CompileRecipeVerbs] Failed to write verb definition at: %s" % def_path)
		return false

	def_file.store_string(JSON.stringify(verb_def, "  "))
	def_file.close()

	# 2. Write co-located target_scope.json with is_recipe_verb: true
	var scope_def: Dictionary = {
		"_meta": {
			"verb_token": verb_token,
			"version": 1,
			"description": "Compiled recipe sub-verb; executed via primary MAKE."
		},
		"is_recipe_verb": true
	}

	var scope_path: String = target_folder.path_join("target_scope.json")
	var scope_file := FileAccess.open(scope_path, FileAccess.WRITE)
	if scope_file == null:
		push_error("[CompileRecipeVerbs] Failed to write target scope at: %s" % scope_path)
		return false

	scope_file.store_string(JSON.stringify(scope_def, "  "))
	scope_file.close()

	print("  • Compiled %-24s -> %s (with target_scope.json)" % [verb_token, target_folder])
	return true

## Pure functional transformation of a recipe dictionary into a declarative verb_definition Dictionary
static func build_verb_definition_from_recipe(recipe: Dictionary) -> Dictionary:
	var recipe_id: String = str(recipe.get("id", "")).strip_edges().to_upper()
	var verb_token: String = "MAKE_" + recipe_id
	var display_name: String = str(recipe.get("display_name", recipe_id))
	var output_item: String = str(recipe.get("output_item", "")).strip_edges().to_upper()
	var output_yield: float = float(recipe.get("output_yield_units", 1.0))
	var inputs: Dictionary = recipe.get("inputs", {})

	var steps: Array[Dictionary] = []

	# 1. Prerequisite Commodity Gates (REQUIRE for each input commodity)
	for input_key in inputs.keys():
		var item_id: String = str(input_key).strip_edges().to_upper()
		var req_qty: float = float(inputs[input_key])
		steps.append({
			"step_id": "gate_input_" + item_id.to_lower(),
			"primitive": "REQUIRE",
			"params": {
				"domain": "COMMODITY",
				"actor": "ORDER_ACTOR",
				"metric": item_id,
				"operator": ">=",
				"value": req_qty
			},
			"on_failure": {
				"error_code": "INSUFFICIENT_RESOURCE"
			}
		})

	# 2. Input Item Consumption (DEDUCT_ITEM directly from ORDER_ACTOR)
	for input_key in inputs.keys():
		var item_id: String = str(input_key).strip_edges().to_upper()
		var req_qty: float = float(inputs[input_key])
		steps.append({
			"step_id": "consume_input_" + item_id.to_lower(),
			"primitive": "DEDUCT_ITEM",
			"params": {
				"from": "ORDER_ACTOR",
				"item_id": item_id,
				"quantity": req_qty
			}
		})

	# 3. Output Item Credit (CREDIT_ITEM directly to ORDER_ACTOR)
	steps.append({
		"step_id": "yield_output_" + output_item.to_lower(),
		"primitive": "CREDIT_ITEM",
		"params": {
			"to": "ORDER_ACTOR",
			"item_id": output_item,
			"quantity": output_yield
		}
	})

	# Link next_step pointers sequentially
	for i in range(steps.size()):
		if i < steps.size() - 1:
			steps[i]["next_step"] = steps[i + 1]["step_id"]
		else:
			steps[i]["next_step"] = null

	return {
		"_meta": {
			"verb_token": verb_token,
			"version": 1,
			"source_recipe": recipe_id,
			"user_creatable": true,
			"description": "Craft %s (%s)" % [display_name, recipe_id]
		},
		"parameters": {
			"target_node_id": { "type": "STRING", "required": false }
		},
		"steps": steps
	}