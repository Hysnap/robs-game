# res://systems/dev_authoring/dev_authoring_controller.gd
class_name DevAuthoringController
extends RefCounted

const ValidatorScript = preload("res://systems/dev_authoring/dev_authoring_validator.gd")
const WriterScript = preload("res://systems/dev_authoring/dev_authoring_writer.gd")
const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")

const DATA_MODULES_ROOT := "res://data_modules/"

# =====================================================================
# 1. WORKBENCH CATALOG & WHITELIST SNAPSHOTS (FOR VIEW BINDING)
# =====================================================================

## Returns a complete snapshot of all whitelisted impacts, commodities, verbs, and operators for UI dropdowns
static func get_workbench_catalog_snapshot() -> Dictionary:
	return {
		"modules": ValidatorScript.get_data_modules(),
		"impacts": ValidatorScript.get_registered_impacts(),
		"commodities": ValidatorScript.get_registered_commodities(),
		"verbs": ValidatorScript.get_registered_verbs(),
		"recipes": get_registered_recipes(),
		"primitives": ValidatorScript.ALLOWED_PRIMITIVES.duplicate(),
		"logic_gates": ValidatorScript.ALLOWED_LOGIC_GATES.duplicate(),
		"operators": ValidatorScript.ALLOWED_OPERATORS.duplicate(),
		"require_domains": ValidatorScript.ALLOWED_REQUIRE_DOMAINS.duplicate(),
		"calc_models": ValidatorScript.ALLOWED_CALC_MODELS.duplicate()
	}

## Discovers all authored recipe IDs (both live and WIP drafts)
static func get_registered_recipes() -> Array[String]:
	var recipes: Array[String] = []
	var files: Array[String] = FileSystemCrawlerScript.find_files_recursive(DATA_MODULES_ROOT, "recipe_profile.json")
	for path in files:
		var parsed: Dictionary = _read_json_dict(path)
		var rid: String = str(parsed.get("recipe_id", path.get_base_dir().get_file())).strip_edges().to_lower()
		if not rid.is_empty() and not recipes.has(rid):
			recipes.append(rid)
	recipes.sort()
	return recipes

# =====================================================================
# 2. LOAD EXISTING DEFINITIONS & WIP DRAFTS FOR RESUMING WORK
# =====================================================================

## Loads an existing commodity (live or WIP draft) into a workbench-editable spec Dictionary
static func load_existing_commodity(commodity_id: String) -> Dictionary:
	var target_id: String = commodity_id.strip_edges().to_upper()
	var files: Array[String] = FileSystemCrawlerScript.find_files_recursive(DATA_MODULES_ROOT, "item_profile.json")

	for path in files:
		var parsed: Dictionary = _read_json_dict(path)
		if str(parsed.get("id", "")).strip_edges().to_upper() == target_id:
			var item_dir: String = path.get_base_dir()
			var impacts: Array = _load_commodity_impacts_from_dir(item_dir)
			var meta: Dictionary = parsed.get("_meta", {})
			return {
				"module": str(meta.get("module", "core")).to_lower(),
				"id": target_id,
				"display_name_token": str(parsed.get("display_name_token", "ITEM_" + target_id)),
				"category": str(parsed.get("category", "consumables")).to_lower(),
				"subcategory": str(parsed.get("subcategory", "")).to_lower(),
				"tier": int(parsed.get("tier", 1)),
				"unit_mass_kg": float(parsed.get("unit_mass_kg", 0.0)),
				"unit_volume_l": float(parsed.get("unit_volume_l", 0.0)),
				"base_cost": float(parsed.get("base_cost", 0.0)),
				"legal_status": str(parsed.get("legal_status", "LEGAL")),
				"is_live": bool(meta.get("is_live", true)),
				"impacts": impacts
			}

	return {}

## Loads an existing recipe (live or WIP draft) into a workbench-editable spec Dictionary
static func load_existing_recipe(recipe_id: String) -> Dictionary:
	var target_id: String = recipe_id.strip_edges().to_lower()
	var files: Array[String] = FileSystemCrawlerScript.find_files_recursive(DATA_MODULES_ROOT, "recipe_profile.json")

	for path in files:
		var parsed: Dictionary = _read_json_dict(path)
		var file_rid: String = str(parsed.get("recipe_id", path.get_base_dir().get_file())).strip_edges().to_lower()
		if file_rid == target_id:
			var recipe_dir: String = path.get_base_dir()
			var meta: Dictionary = parsed.get("_meta", {})
			return {
				"module": str(meta.get("module", "core")).to_lower(),
				"category": recipe_dir.get_base_dir().get_file().to_lower(),
				"recipe_id": target_id,
				"display_name_token": str(parsed.get("display_name_token", "RECIPE_" + target_id.to_upper())),
				"inputs": parsed.get("inputs", {}).duplicate(true),
				"output_commodity": str(parsed.get("output_commodity", "")).to_upper(),
				"output_quantity": float(parsed.get("output_quantity", 1.0)),
				"required_facility": str(parsed.get("required_facility", "")),
				"duration_ticks": float(parsed.get("duration_ticks", 1.0)),
				"is_live": bool(meta.get("is_live", true)),
				"impacts": _load_impacts_subfolder(recipe_dir.path_join("impacts"))
			}

	return {}

## Loads an existing Macro Verb (live or WIP draft) so a developer can resume wiring steps/branches
static func load_existing_verb(verb_token: String) -> Dictionary:
	var target_token: String = verb_token.strip_edges().to_upper()
	var files: Array[String] = FileSystemCrawlerScript.find_files_recursive(DATA_MODULES_ROOT, "verb_definition.json")

	for path in files:
		var parsed: Dictionary = _read_json_dict(path)
		var meta: Dictionary = parsed.get("_meta", {})
		var file_token: String = str(meta.get("verb_token", path.get_base_dir().get_file())).strip_edges().to_upper()
		if file_token == target_token:
			var verb_dir: String = path.get_base_dir()
			var scope_dict: Dictionary = _read_json_dict(verb_dir.path_join("target_scope.json"))
			return {
				"module": _extract_module_from_path(path),
				"verb_token": target_token,
				"_meta": meta.duplicate(true),
				"parameters": parsed.get("parameters", {}).duplicate(true),
				"sequence": parsed.get("sequence", parsed.get("steps", [])).duplicate(true),
				"target_scope": scope_dict,
				"is_live": bool(meta.get("is_live", true)),
				"impacts": _load_impacts_subfolder(verb_dir.path_join("impacts"))
			}

	return {}

# =====================================================================
# 3. SAVE / PUBLISH COMMAND DISPATCHERS
# =====================================================================

## Validates and persists a commodity (as WIP draft or Live) and returns updated catalog snapshot
static func save_commodity(spec: Dictionary, make_live: bool = false) -> Dictionary:
	var write_res: Dictionary = WriterScript.write_commodity(spec, make_live)
	write_res["catalog"] = get_workbench_catalog_snapshot()
	return write_res

## Validates and persists a recipe (as WIP draft or Live) and returns updated catalog snapshot
static func save_recipe(spec: Dictionary, make_live: bool = false) -> Dictionary:
	var write_res: Dictionary = WriterScript.write_recipe(spec, make_live)
	write_res["catalog"] = get_workbench_catalog_snapshot()
	return write_res

## Validates and persists a macro verb (as WIP draft or Live) and returns updated catalog snapshot
static func save_macro_verb(spec: Dictionary, make_live: bool = false) -> Dictionary:
	var write_res: Dictionary = WriterScript.write_macro_verb(spec, make_live)
	write_res["catalog"] = get_workbench_catalog_snapshot()
	return write_res

## Dry-run validation check for immediate UI feedback before saving
static func preview_validation(domain: String, spec: Dictionary) -> Dictionary:
	var allowed_impacts: Array[String] = ValidatorScript.get_registered_impacts()
	match domain.strip_edges().to_upper():
		"COMMODITY":
			return ValidatorScript.validate_commodity_spec(spec, allowed_impacts)
		"RECIPE":
			var allowed_comms: Array[String] = ValidatorScript.get_registered_commodities()
			return ValidatorScript.validate_recipe_spec(spec, allowed_comms, allowed_impacts)
		"VERB", "MACRO_VERB":
			var allowed_verbs: Array[String] = ValidatorScript.get_registered_verbs()
			return ValidatorScript.validate_macro_verb_spec(
				spec,
				ValidatorScript.ALLOWED_PRIMITIVES,
				allowed_verbs,
				allowed_impacts
			)
		_:
			return { "valid": false, "can_save_draft": false, "can_make_live": false, "errors": ["Unknown domain: " + domain] }

# =====================================================================
# 4. STEP & DECISION TREE FACTORY HELPERS
# =====================================================================

## Creates a standardized step block template for the Macro Verb Sequencer
static func create_step_template(step_id: String, primitive: String = "REQUIRE") -> Dictionary:
	var clean_prim: String = primitive.strip_edges().to_upper()
	var step: Dictionary = {
		"step_id": step_id.strip_edges(),
		"primitive": clean_prim,
		"params": {},
		"next_step": "",
		"on_true": "",
		"on_false": "",
		"on_failure": {
			"error_code": "INSUFFICIENT_RESOURCE"
		}
	}

	match clean_prim:
		"REQUIRE":
			step["params"] = {
				"logic_gate": "AND",
				"conditions": [
					create_condition_template()
				]
			}
		"MOVE_ACTOR":
			step["params"] = {
				"actor": "ORDER_ACTOR",
				"destination": "TARGET_NODE"
			}
		"TRANSFER_ITEM":
			step["params"] = {
				"from": "ORDER_ACTOR",
				"to": "PARAM.counterparty_id",
				"item_id": "PARAM.item_id",
				"quantity": "PARAM.amount"
			}
		"DEDUCT_ITEM":
			step["params"] = {
				"from": "ORDER_ACTOR",
				"item_id": "PARAM.item_id",
				"quantity": "PARAM.amount"
			}
		"CREDIT_ITEM":
			step["params"] = {
				"to": "ORDER_ACTOR",
				"item_id": "PARAM.item_id",
				"quantity": "PARAM.amount"
			}
		"CALL_VERB":
			step["params"] = {
				"verb_token": "",
				"actor": "ORDER_ACTOR",
				"target_node_id": "TARGET_NODE"
			}

	return step

## Creates a standardized single condition row for a REQUIRE logic gate block
static func create_condition_template(
	domain: String = "COMMODITY",
	actor: String = "ORDER_ACTOR",
	metric: String = "CASH",
	operator: String = ">=",
	value: Variant = 0.0
) -> Dictionary:
	return {
		"domain": domain.strip_edges().to_upper(),
		"actor": actor.strip_edges(),
		"metric": metric.strip_edges(),
		"operator": operator.strip_edges().to_upper(),
		"value": value,
		"lower": 0.0,
		"upper": 100.0
	}

# =====================================================================
# 5. INTERNAL HELPERS
# =====================================================================

static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

static func _extract_module_from_path(path: String) -> String:
	var rel: String = path.trim_prefix(DATA_MODULES_ROOT)
	var parts: PackedStringArray = rel.split("/", false)
	if parts.size() > 0:
		return parts[0].to_lower()
	return "core"

static func _load_impacts_subfolder(imp_dir: String) -> Array:
	var list: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(imp_dir)):
		return list
	var files: Array[String] = FileSystemCrawlerScript.find_files_recursive(imp_dir, "", ".json")
	for fpath in files:
		var parsed: Dictionary = _read_json_dict(fpath)
		if not parsed.is_empty():
			list.append({
				"metric_key": str(parsed.get("metric_key", fpath.get_file().get_basename())).to_upper(),
				"model": str(parsed.get("model", "FLAT_DELTA")).to_upper(),
				"factor": float(parsed.get("factor", parsed.get("delta", 0.0))),
				"delta": float(parsed.get("delta", parsed.get("factor", 0.0)))
			})
	return list

static func _load_commodity_impacts_from_dir(item_dir: String) -> Array:
	var list: Array = []
	var dir := DirAccess.open(item_dir)
	if dir == null:
		return list
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var sub_path: String = item_dir.path_join(entry)
			var json_files: Array[String] = FileSystemCrawlerScript.find_files_recursive(sub_path, "", ".json")
			for jf in json_files:
				var parsed: Dictionary = _read_json_dict(jf)
				if not parsed.is_empty():
					list.append({
						"verb_context": entry.to_lower(),
						"metric_key": str(parsed.get("metric_key", jf.get_file().get_basename())).to_upper(),
						"model": str(parsed.get("model", "LINEAR_PER_UNIT")).to_upper(),
						"factor": float(parsed.get("factor", parsed.get("delta", 0.0))),
						"delta": float(parsed.get("delta", parsed.get("factor", 0.0)))
					})
		entry = dir.get_next()
	dir.list_dir_end()
	return list