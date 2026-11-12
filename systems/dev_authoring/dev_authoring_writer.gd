# res://systems/dev_authoring/dev_authoring_writer.gd
class_name DevAuthoringWriter
extends RefCounted

const ValidatorScript = preload("res://systems/dev_authoring/dev_authoring_validator.gd")
const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")

const DATA_MODULES_ROOT := "res://data_modules/"

# =====================================================================
# 1. COMMODITY DISK WRITER
# =====================================================================

## Validates and writes a Commodity definition and its whitelisted verb impacts to disk
static func write_commodity(spec: Dictionary, request_make_live: bool = false) -> Dictionary:
	var allowed_impacts: Array[String] = ValidatorScript.get_registered_impacts()
	var validation: Dictionary = ValidatorScript.validate_commodity_spec(spec, allowed_impacts)

	if not bool(validation.get("can_save_draft", false)):
		return {
			"success": false,
			"is_live": false,
			"path": "",
			"validation": validation
		}

	var is_live: bool = request_make_live and bool(validation.get("can_make_live", false))
	var module_slug: String = str(spec.get("module", "core")).strip_edges().to_lower()
	var category_slug: String = str(spec.get("category", "consumables")).strip_edges().to_lower()
	var subcategory_slug: String = str(spec.get("subcategory", "")).strip_edges().to_lower()
	var item_id: String = str(spec.get("id", "")).strip_edges().to_upper()
	var item_slug: String = item_id.to_lower()

	var base_dir: String = DATA_MODULES_ROOT.path_join(module_slug).path_join("commodities").path_join(category_slug)
	if not subcategory_slug.is_empty():
		base_dir = base_dir.path_join(subcategory_slug)
	var item_dir: String = base_dir.path_join(item_slug)

	if not _ensure_dir(item_dir):
		return _io_error_response("Failed to create commodity directory: %s" % item_dir, validation)

	var profile_payload: Dictionary = {
		"_meta": {
			"id": item_id,
			"module": module_slug,
			"is_live": is_live,
			"status": "LIVE" if is_live else "WIP_DRAFT"
		},
		"id": item_id,
		"display_name_token": str(spec.get("display_name_token", "ITEM_" + item_id)),
		"category": category_slug.to_upper(),
		"subcategory": subcategory_slug.to_upper(),
		"tier": int(spec.get("tier", 1)),
		"unit_mass_kg": float(spec.get("unit_mass_kg", 0.0)),
		"unit_volume_l": float(spec.get("unit_volume_l", 0.0)),
		"base_cost": float(spec.get("base_cost", 0.0)),
		"legal_status": str(spec.get("legal_status", "LEGAL")).to_upper()
	}

	var profile_path: String = item_dir.path_join("item_profile.json")
	if not _write_json_file(profile_path, profile_payload):
		return _io_error_response("Failed to write item_profile.json at: %s" % profile_path, validation)

	# Write whitelisted impact profiles per verb context
	var impacts: Array = spec.get("impacts", [])
	for imp in impacts:
		if not (imp is Dictionary):
			continue
		var verb_ctx: String = str(imp.get("verb_context", "consume")).strip_edges().to_lower()
		var metric_key: String = str(imp.get("metric_key", "")).strip_edges().to_upper()
		if verb_ctx.is_empty() or metric_key.is_empty():
			continue
		var impact_dir: String = item_dir.path_join(verb_ctx)
		if _ensure_dir(impact_dir):
			var imp_payload: Dictionary = {
				"metric_key": metric_key,
				"model": str(imp.get("model", "LINEAR_PER_UNIT")).to_upper(),
				"factor": float(imp.get("factor", 0.0)),
				"delta": float(imp.get("delta", imp.get("factor", 0.0)))
			}
			_write_json_file(impact_dir.path_join(metric_key.to_lower() + ".json"), imp_payload)

	return {
		"success": true,
		"is_live": is_live,
		"path": profile_path,
		"validation": validation
	}

# =====================================================================
# 2. RECIPE DISK WRITER
# =====================================================================

## Validates and writes a Recipe definition and its whitelisted impacts to disk
static func write_recipe(spec: Dictionary, request_make_live: bool = false) -> Dictionary:
	var allowed_commodities: Array[String] = ValidatorScript.get_registered_commodities()
	var allowed_impacts: Array[String] = ValidatorScript.get_registered_impacts()
	var validation: Dictionary = ValidatorScript.validate_recipe_spec(spec, allowed_commodities, allowed_impacts)

	if not bool(validation.get("can_save_draft", false)):
		return {
			"success": false,
			"is_live": false,
			"path": "",
			"validation": validation
		}

	var is_live: bool = request_make_live and bool(validation.get("can_make_live", false))
	var module_slug: String = str(spec.get("module", "core")).strip_edges().to_lower()
	var category_slug: String = str(spec.get("category", "general")).strip_edges().to_lower()
	var recipe_id: String = str(spec.get("recipe_id", "")).strip_edges().to_lower()

	var recipe_dir: String = DATA_MODULES_ROOT.path_join(module_slug).path_join("recipes").path_join(category_slug).path_join(recipe_id)
	if not _ensure_dir(recipe_dir):
		return _io_error_response("Failed to create recipe directory: %s" % recipe_dir, validation)

	var clean_inputs: Dictionary = {}
	var raw_inputs: Dictionary = spec.get("inputs", {})
	for k in raw_inputs.keys():
		clean_inputs[str(k).strip_edges().to_upper()] = float(raw_inputs[k])

	var recipe_payload: Dictionary = {
		"_meta": {
			"recipe_id": recipe_id.to_upper(),
			"module": module_slug,
			"is_live": is_live,
			"status": "LIVE" if is_live else "WIP_DRAFT"
		},
		"recipe_id": recipe_id.to_upper(),
		"display_name_token": str(spec.get("display_name_token", "RECIPE_" + recipe_id.to_upper())),
		"inputs": clean_inputs,
		"output_commodity": str(spec.get("output_commodity", "")).strip_edges().to_upper(),
		"output_quantity": float(spec.get("output_quantity", 1.0)),
		"required_facility": str(spec.get("required_facility", "")).strip_edges().to_upper(),
		"duration_ticks": float(spec.get("duration_ticks", 1.0))
	}

	var profile_path: String = recipe_dir.path_join("recipe_profile.json")
	if not _write_json_file(profile_path, recipe_payload):
		return _io_error_response("Failed to write recipe_profile.json at: %s" % profile_path, validation)

	var impacts: Array = spec.get("impacts", [])
	if not impacts.is_empty():
		var imp_dir: String = recipe_dir.path_join("impacts")
		if _ensure_dir(imp_dir):
			for imp in impacts:
				if imp is Dictionary:
					var metric_key: String = str(imp.get("metric_key", "")).strip_edges().to_upper()
					if not metric_key.is_empty():
						_write_json_file(imp_dir.path_join(metric_key.to_lower() + ".json"), {
							"metric_key": metric_key,
							"model": str(imp.get("model", "FLAT_DELTA")).to_upper(),
							"factor": float(imp.get("factor", 0.0)),
							"delta": float(imp.get("delta", imp.get("factor", 0.0)))
						})

	return {
		"success": true,
		"is_live": is_live,
		"path": profile_path,
		"validation": validation
	}

# =====================================================================
# 3. MACRO VERB DISK WRITER (WITH SOFT-LOCK COMPOSER GATING)
# =====================================================================

## Validates and writes a Macro Verb (verb_definition.json + target_scope.json + impacts)
static func write_macro_verb(spec: Dictionary, request_make_live: bool = false) -> Dictionary:
	var allowed_verbs: Array[String] = ValidatorScript.get_registered_verbs()
	var allowed_impacts: Array[String] = ValidatorScript.get_registered_impacts()
	var validation: Dictionary = ValidatorScript.validate_macro_verb_spec(
		spec,
		ValidatorScript.ALLOWED_PRIMITIVES,
		allowed_verbs,
		allowed_impacts
	)

	if not bool(validation.get("can_save_draft", false)):
		return {
			"success": false,
			"is_live": false,
			"path": "",
			"validation": validation
		}

	var is_live: bool = request_make_live and bool(validation.get("can_make_live", false))
	var module_slug: String = str(spec.get("module", "core")).strip_edges().to_lower()
	var meta: Dictionary = spec.get("_meta", {}).duplicate(true)
	var verb_token: String = str(meta.get("verb_token", spec.get("verb_token", ""))).strip_edges().to_upper()
	var verb_slug: String = verb_token.to_lower()

	var verb_dir: String = DATA_MODULES_ROOT.path_join(module_slug).path_join("verbs").path_join(verb_slug)
	if not _ensure_dir(verb_dir):
		return _io_error_response("Failed to create verb directory: %s" % verb_dir, validation)

	meta["verb_token"] = verb_token
	meta["version"] = int(meta.get("version", 2))
	meta["is_live"] = is_live
	meta["status"] = "LIVE" if is_live else "WIP_DRAFT"
	meta["user_creatable"] = is_live and bool(spec.get("user_creatable", true))

	var sequence: Array = spec.get("sequence", spec.get("steps", []))
	var verb_def_payload: Dictionary = {
		"_meta": meta,
		"parameters": spec.get("parameters", {}),
		"sequence": sequence
	}

	var def_path: String = verb_dir.path_join("verb_definition.json")
	if not _write_json_file(def_path, verb_def_payload):
		return _io_error_response("Failed to write verb_definition.json at: %s" % def_path, validation)

	# Build and write companion target_scope.json (Soft-locked if WIP draft)
	var raw_scope: Dictionary = spec.get("target_scope", {}).duplicate(true)
	var desired_visibility: bool = bool(raw_scope.get("visible_in_composer", spec.get("visible_in_composer", true)))
	var scope_payload: Dictionary = {
		"_meta": {
			"verb_token": verb_token,
			"is_live": is_live,
			"desired_visible_in_composer": desired_visibility
		},
		"visible_in_composer": is_live and desired_visibility,
		"is_recipe_verb": bool(raw_scope.get("is_recipe_verb", false)),
		"allowed_scopes": raw_scope.get("allowed_scopes", ["DISTRICT", "ESTABLISHMENT"]),
		"target_categories": raw_scope.get("target_categories", ["ALL"]),
		"form_layout": raw_scope.get("form_layout", _build_default_form_layout())
	}

	var scope_path: String = verb_dir.path_join("target_scope.json")
	if not _write_json_file(scope_path, scope_payload):
		return _io_error_response("Failed to write target_scope.json at: %s" % scope_path, validation)

	# Register updated scope in TargetDomainRegistry memory cache immediately
	TargetDomainRegistryScript.register_scope_definition(verb_token, scope_payload)

	# Write whitelisted verb-level impacts
	var impacts: Array = spec.get("impacts", [])
	if not impacts.is_empty():
		var imp_dir: String = verb_dir.path_join("impacts")
		if _ensure_dir(imp_dir):
			for imp in impacts:
				if imp is Dictionary:
					var metric_key: String = str(imp.get("metric_key", "")).strip_edges().to_upper()
					if not metric_key.is_empty():
						_write_json_file(imp_dir.path_join(metric_key.to_lower() + ".json"), {
							"metric_key": metric_key,
							"model": str(imp.get("model", "FLAT_DELTA")).to_upper(),
							"factor": float(imp.get("factor", 0.0)),
							"delta": float(imp.get("delta", imp.get("factor", 0.0)))
						})

	return {
		"success": true,
		"is_live": is_live,
		"path": def_path,
		"scope_path": scope_path,
		"validation": validation
	}

# =====================================================================
# 4. INTERNAL ATOMIC FILE HELPERS
# =====================================================================

static func _ensure_dir(dir_path: String) -> bool:
	var global_path: String = ProjectSettings.globalize_path(dir_path)
	if DirAccess.dir_exists_absolute(global_path):
		return true
	var err: Error = DirAccess.make_dir_recursive_absolute(global_path)
	if err != OK:
		push_error("[DevAuthoringWriter] FAIL_LOUD: Cannot create directory '%s' (Error %d)" % [dir_path, err])
		return false
	return true

static func _write_json_file(file_path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		push_error("[DevAuthoringWriter] FAIL_LOUD: Cannot open '%s' for writing." % file_path)
		return false
	f.store_string(JSON.stringify(data, "\t") + "\n")
	f.close()
	return true

static func _io_error_response(msg: String, validation: Dictionary) -> Dictionary:
	var errs: Array = validation.get("blocking_errors", []).duplicate()
	errs.append(msg)
	validation["blocking_errors"] = errs
	validation["can_save_draft"] = false
	validation["can_make_live"] = false
	return {
		"success": false,
		"is_live": false,
		"path": "",
		"validation": validation
	}

static func _build_default_form_layout() -> Dictionary:
	return {
		"target_section": {
			"visible": true,
			"required": true,
			"label_token": "UI_LBL_COMMODITY",
			"mapped_field": "item_id"
		},
		"amount_section": {
			"visible": true,
			"required": true,
			"label_token": "UI_LBL_QUANTITY",
			"default_value": 1.0,
			"min_value": 1.0,
			"max_value": 1000.0,
			"step": 1.0,
			"mapped_field": "amount"
		},
		"location_section": {
			"visible": true,
			"required": true,
			"label_token": "UI_LBL_DISTRICT",
			"mapped_field": "target_node_id"
		},
		"contact_section": {
			"visible": false,
			"required": false,
			"label_token": "UI_LBL_CONTACT",
			"mapped_field": "counterparty_id"
		}
	}