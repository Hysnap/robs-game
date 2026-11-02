# res://systems/target_domain_registry.gd
class_name TargetDomainRegistry
extends RefCounted

const VERBS_BASE_DIR := "res://data_modules/core/verbs/"

static var _cached_scopes: Dictionary = {} # "VERB_CODE" -> Dictionary

## Clears in-memory cached scopes (useful during testing or live-reloading)
static func clear_cache() -> void:
	_cached_scopes.clear()

## Loads and validates the colocated target_scope.json for a given verb
static func get_verb_scope_definition(verb_code: String) -> Dictionary:
	var clean_code: String = verb_code.strip_edges().to_upper()
	if _cached_scopes.has(clean_code):
		return _cached_scopes[clean_code]

	var file_path := VERBS_BASE_DIR.path_join(clean_code.to_lower()).path_join("target_scope.json")
	if not FileAccess.file_exists(file_path):
		push_error("[TargetDomainRegistry FATAL] Missing target_scope.json for verb '%s' at: %s" % [clean_code, file_path])
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[TargetDomainRegistry FATAL] Unable to open target_scope.json at: %s" % file_path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if not (parsed is Dictionary):
		push_error("[TargetDomainRegistry FATAL] Malformed JSON in target_scope.json at: %s" % file_path)
		return {}

	_cached_scopes[clean_code] = parsed
	return parsed

## Returns the array of allowed spatial/entity scopes (e.g. ["DISTRICT", "ESTABLISHMENT"])
static func get_allowed_scopes(verb_code: String) -> Array[String]:
	var def: Dictionary = get_verb_scope_definition(verb_code)
	var raw_scopes: Array = def.get("target_scopes", [])
	var scopes: Array[String] = []
	for s in raw_scopes:
		scopes.append(str(s).to_upper())
	return scopes

## Returns the declared target categories for a given verb
static func get_target_categories(verb_code: String) -> Array[Dictionary]:
	var def: Dictionary = get_verb_scope_definition(verb_code)
	var raw_cats: Array = def.get("target_categories", [])
	var categories: Array[Dictionary] = []
	for c in raw_cats:
		if c is Dictionary:
			categories.append(c)
	return categories

## Resolves a normalized list of target candidates [{ "id": String, "label_token": String, "unit_cost": float }]
## Emits pure semantic tokens; translation via tr() is deferred to the presentation layer.
static func resolve_targets(verb_code: String, world_state: Dictionary, category_id: String = "") -> Array[Dictionary]:
	var categories: Array[Dictionary] = get_target_categories(verb_code)
	if categories.is_empty():
		return []

	# If category_id is specified, locate that category; otherwise use the first category
	var target_cat: Dictionary = {}
	if not category_id.is_empty():
		for cat in categories:
			if str(cat.get("id", "")).to_upper() == category_id.to_upper():
				target_cat = cat
				break
	else:
		target_cat = categories[0]

	if target_cat.is_empty():
		push_warning("[TargetDomainRegistry] Category '%s' not found for verb '%s'." % [category_id, verb_code])
		return []

	var domain: String = str(target_cat.get("domain", "NONE")).to_upper()
	var catalog_source: String = str(target_cat.get("catalog_source", ""))

	match domain:
		"NONE":
			return [{
				"id": str(target_cat.get("id", "DEFAULT")),
				"label_token": str(target_cat.get("label_token", "UI_TARGET_NONE")),
				"unit_cost": 0.0
			}]

		"COMMODITY", "RECIPE":
			if catalog_source.is_empty():
				push_error("[TargetDomainRegistry] Verb '%s' category '%s' missing required 'catalog_source'." % [verb_code, target_cat.get("id")])
				return []

			var catalog: Dictionary = world_state.get(catalog_source, {})
			if catalog.is_empty():
				push_warning("[TargetDomainRegistry] Catalog '%s' in world_state is empty for verb '%s'." % [catalog_source, verb_code])
				return []

			var results: Array[Dictionary] = []
			var sorted_keys: Array = catalog.keys()
			sorted_keys.sort()
			for item_id in sorted_keys:
				var item_data = catalog[item_id]
				var token: String = str(item_id)
				var cost: float = 0.0
				if item_data is Dictionary:
					token = str(item_data.get("display_name", item_id))
					cost = float(item_data.get("base_cost", 0.0))
				results.append({
					"id": str(item_id),
					"label_token": token,
					"unit_cost": cost
				})
			return results

		"CONTACT":
			return [{
				"id": "CONTACT_SELECTED",
				"label_token": str(target_cat.get("label_token", "UI_TARGET_CONTACT")),
				"unit_cost": 0.0
			}]

		_:
			push_warning("[TargetDomainRegistry] Unhandled domain '%s' on verb '%s'." % [domain, verb_code])
			return []