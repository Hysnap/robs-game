# res://systems/target_domain_registry.gd
class_name TargetDomainRegistry
extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const VERBS_BASE_DIR := "res://data_modules/core/verbs/"

static var _cached_scopes: Dictionary = {} # "VERB_CODE" -> Dictionary
static var _initialized: bool = false

## Clears in-memory cached scopes (useful during testing or live-reloading)
static func clear_cache() -> void:
	_cached_scopes.clear()
	_initialized = false

## Eagerly scans and indexes all target_scope.json definitions across N-tiers
static func _ensure_initialized() -> void:
	if _initialized:
		return

	var scope_files := FileSystemCrawlerScript.find_files_recursive(VERBS_BASE_DIR, "target_scope.json")
	for file_path in scope_files:
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			push_warning("[TargetDomainRegistry] Unable to open target_scope.json at: %s" % file_path)
			continue

		var parsed = JSON.parse_string(file.get_as_text())
		file.close()

		if not (parsed is Dictionary):
			push_error("[TargetDomainRegistry FATAL] Malformed JSON in target_scope.json at: %s" % file_path)
			continue

		var verb_token: String = ""
		if parsed.has("_meta") and parsed["_meta"] is Dictionary:
			verb_token = str(parsed["_meta"].get("verb_token", "")).strip_edges().to_upper()

		if verb_token.is_empty():
			# Fallback: derive verb token from directory name
			verb_token = file_path.get_base_dir().get_file().strip_edges().to_upper()

		_cached_scopes[verb_token] = parsed

	_initialized = true

## Allows runtime registration of dynamic or player-created macro verb scopes
static func register_scope_definition(verb_token: String, scope_def: Dictionary) -> void:
	var clean_code := verb_token.strip_edges().to_upper()
	assert(not clean_code.is_empty(), "[TargetDomainRegistry FATAL] Cannot register scope for empty verb token.")
	_cached_scopes[clean_code] = scope_def

## Returns the cached target_scope dictionary for a given verb token (O(1) memory lookup)
static func get_verb_scope_definition(verb_code: String) -> Dictionary:
	_ensure_initialized()
	var clean_code: String = verb_code.strip_edges().to_upper()
	return _cached_scopes.get(clean_code, {})

## Returns the array of allowed spatial/entity scopes (e.g. ["DISTRICT", "ESTABLISHMENT", "STAFF"])
static func get_allowed_scopes(verb_code: String) -> Array[String]:
	var def: Dictionary = get_verb_scope_definition(verb_code)
	var raw_scopes: Array = def.get("allowed_scopes", def.get("target_scopes", []))
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

## Resolves a normalized list of target candidates [{ "id": String, "label_token": String, "unit_cost": float, ... }]
## Emits pure semantic tokens; translation via tr() is deferred to the presentation layer.
static func resolve_targets(verb_code: String, world_state: Dictionary, category_id: String = "") -> Array[Dictionary]:
	var categories: Array[Dictionary] = get_target_categories(verb_code)
	if categories.is_empty():
		return []

	var requested_cat := category_id.strip_edges().to_upper()
	var cats_to_process: Array[Dictionary] = []

	if not requested_cat.is_empty() and requested_cat != "ALL":
		for cat in categories:
			if str(cat.get("id", "")).to_upper() == requested_cat:
				cats_to_process.append(cat)
				break
		if cats_to_process.is_empty():
			push_warning("[TargetDomainRegistry] Category '%s' not found for verb '%s'." % [category_id, verb_code])
			return []
	else:
		cats_to_process = categories

	var aggregated_results: Array[Dictionary] = []
	for target_cat in cats_to_process:
		var domain: String = str(target_cat.get("domain", target_cat.get("id", "NONE"))).to_upper()
		var catalog_source: String = str(target_cat.get("catalog_source", "commodities"))

		match domain:
			"CURRENCY":
				aggregated_results.append({
					"id": "CASH",
					"label_token": str(target_cat.get("label_token", "UI_CAT_CURRENCY")),
					"unit_cost": 1.0,
					"category": "CURRENCY",
					"sub_category": "CASH",
					"taxonomy_path": []
				})

			"NONE":
				assert(target_cat.has("id") and not str(target_cat["id"]).is_empty(),
					"FATAL: [TargetDomainRegistry] Category in verb '%s' with domain 'NONE' must define an 'id'." % verb_code)
				assert(target_cat.has("label_token") and not str(target_cat["label_token"]).is_empty(),
					"FATAL: [TargetDomainRegistry] Category '%s' in verb '%s' must define a 'label_token'." % [target_cat.get("id"), verb_code])

				aggregated_results.append({
					"id": str(target_cat["id"]),
					"label_token": str(target_cat["label_token"]),
					"unit_cost": float(target_cat.get("unit_cost", 0.0)),
					"category": str(target_cat.get("id", "")).to_upper(),
					"sub_category": "",
					"taxonomy_path": []
				})

			"COMMODITY", "RECIPE":
				var catalog: Dictionary = world_state.get(catalog_source, {})
				if catalog.is_empty():
					push_warning("[TargetDomainRegistry] Catalog '%s' in world_state is empty for verb '%s'." % [catalog_source, verb_code])
					continue

				var sorted_keys: Array = catalog.keys()
				sorted_keys.sort()
				for item_id in sorted_keys:
					var item_data = catalog[item_id]
					var token: String = str(item_id)
					var cost: float = 0.0
					var cat: String = ""
					var subcat: String = ""
					var tax_path: Array = []

					if item_data is Dictionary:
						token = str(item_data.get("display_name", item_id))
						cost = float(item_data.get("base_cost", item_data.get("unit_cost", 0.0)))
						cat = str(item_data.get("category", "GENERAL")).strip_edges().to_upper()
						assert(not cat.is_empty(),
							"FATAL: [TargetDomainRegistry] Item '%s' in catalog '%s' has an empty category!" % [item_id, catalog_source])
						subcat = str(item_data.get("sub_category", "")).strip_edges().to_upper()
						tax_path = item_data.get("taxonomy_path", [])

					aggregated_results.append({
						"id": str(item_id),
						"label_token": token,
						"unit_cost": cost,
						"category": cat,
						"sub_category": subcat,
						"taxonomy_path": tax_path
					})

			"CONTACT":
				aggregated_results.append({
					"id": "CONTACT_SELECTED",
					"label_token": str(target_cat.get("label_token", "UI_TARGET_CONTACT")),
					"unit_cost": 0.0,
					"category": "CONTACT",
					"sub_category": "",
					"taxonomy_path": []
				})

			_:
				push_warning("[TargetDomainRegistry] Unhandled domain '%s' on verb '%s'." % [domain, verb_code])

	return aggregated_results