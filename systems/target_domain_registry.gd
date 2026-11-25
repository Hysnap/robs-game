# res://systems/target_domain_registry.gd
class_name TargetDomainRegistry
extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const VERBS_BASE_DIR := "res://data_modules/core/verbs/"
const RESOLVERS_BASE_DIR := "res://systems/target_resolvers/"

static var _cached_scopes: Dictionary = {} # "VERB_CODE" -> Dictionary
static var _cached_resolvers: Dictionary = {} # "DOMAIN_TOKEN" -> GDScript
static var _active_variant: String = ""
static var _initialized: bool = false

## Clears in-memory cached scopes and resolvers (useful during testing or live-reloading)
static func clear_cache() -> void:
	_cached_scopes.clear()
	_cached_resolvers.clear()
	_active_variant = ""
	_initialized = false

## Initializes scopes from core and optional active flavour overlay (mirrors VerbRouter.initialize)
static func initialize(active_variant: String = "") -> void:
	clear_cache()
	_active_variant = active_variant.strip_edges()
	_ensure_initialized()

## Eagerly scans and indexes all target_scope.json definitions (core + active flavour overlay) and pluggable resolvers
static func _ensure_initialized() -> void:
	if _initialized:
		return

	# 1. Mount baseline canonical verb scopes from core
	_scan_and_mount_scopes(VERBS_BASE_DIR)

	# 2. Merge flavour pack target_scope.json overlays if active
	if not _active_variant.is_empty() and _active_variant != "core":
		var variant_verbs: String = "res://data_modules/%s/verbs/" % _active_variant
		if DirAccess.dir_exists_absolute(variant_verbs):
			_scan_and_mount_scopes(variant_verbs)

	var resolver_files := FileSystemCrawlerScript.find_files_recursive(RESOLVERS_BASE_DIR, "", ".gd")
	for res_path in resolver_files:
		var res_script = load(res_path)
		if res_script == null:
			push_error("[TargetDomainRegistry FATAL] Failed to load target resolver script: %s" % res_path)
			continue
		var const_map: Dictionary = res_script.get_script_constant_map()
		var primary_token: String = str(const_map.get("DOMAIN_TOKEN", "")).strip_edges().to_upper()
		if not primary_token.is_empty():
			_cached_resolvers[primary_token] = res_script
		var aliases = const_map.get("ALIASES", [])
		if aliases is Array:
			for alias in aliases:
				var clean_alias := str(alias).strip_edges().to_upper()
				if not clean_alias.is_empty():
					_cached_resolvers[clean_alias] = res_script

	_initialized = true

## Scans a verbs directory recursively and mounts or deep-merges discovered target_scope.json files
static func _scan_and_mount_scopes(verbs_root_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(verbs_root_dir):
		return

	var scope_files := FileSystemCrawlerScript.find_files_recursive(verbs_root_dir, "target_scope.json")
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

		var meta: Dictionary = parsed.get("_meta", {}) if parsed.get("_meta") is Dictionary else {}
		var verb_token: String = str(meta.get("verb_token", "")).strip_edges().to_upper()
		if verb_token.is_empty():
			verb_token = file_path.get_base_dir().get_file().strip_edges().to_upper()

		if not _cached_scopes.has(verb_token) or bool(meta.get("replace_core", false)):
			_cached_scopes[verb_token] = parsed.duplicate(true)
		else:
			_cached_scopes[verb_token] = _merge_scope_overlay(_cached_scopes[verb_token], parsed)

## Deep-merges a flavour pack target_scope.json overlay onto an existing core scope definition
static func _merge_scope_overlay(base_scope: Dictionary, overlay_scope: Dictionary) -> Dictionary:
	var merged: Dictionary = base_scope.duplicate(true)

	# 1. Merge allowed_scopes (unique union)
	if overlay_scope.has("allowed_scopes") and overlay_scope["allowed_scopes"] is Array:
		var base_scopes: Array = merged.get("allowed_scopes", [])
		merged["allowed_scopes"] = _merge_unique_array(base_scopes, overlay_scope["allowed_scopes"])

	# 2. Merge target_categories (keyed by id)
	if overlay_scope.has("target_categories") and overlay_scope["target_categories"] is Array:
		var base_cats: Array = merged.get("target_categories", [])
		merged["target_categories"] = _merge_unique_array(base_cats, overlay_scope["target_categories"])

	# 3. Deep-merge form_layout sections (preserving core fields and appending cascading options/rules)
	if overlay_scope.has("form_layout") and overlay_scope["form_layout"] is Dictionary:
		var merged_layout: Dictionary = merged.get("form_layout", {}).duplicate(true)
		var overlay_layout: Dictionary = overlay_scope["form_layout"]
		for sec_key in overlay_layout.keys():
			var overlay_sec = overlay_layout[sec_key]
			if overlay_sec is Dictionary and merged_layout.has(sec_key) and merged_layout[sec_key] is Dictionary:
				merged_layout[sec_key] = _merge_section_dict(merged_layout[sec_key], overlay_sec)
			else:
				merged_layout[sec_key] = overlay_sec.duplicate(true) if overlay_sec is Dictionary or overlay_sec is Array else overlay_sec
		merged["form_layout"] = merged_layout

	# 4. Merge any remaining top-level keys (excluding _meta and already-merged keys)
	for top_key in overlay_scope.keys():
		if top_key in ["_meta", "allowed_scopes", "target_categories", "form_layout"]:
			continue
		var val = overlay_scope[top_key]
		if val is Dictionary and merged.has(top_key) and merged[top_key] is Dictionary:
			merged[top_key] = _merge_section_dict(merged[top_key], val)
		elif val is Array and merged.has(top_key) and merged[top_key] is Array:
			merged[top_key] = _merge_unique_array(merged[top_key], val)
		else:
			merged[top_key] = val.duplicate(true) if val is Dictionary or val is Array else val

	return merged

## Recursively merges two form_layout section dictionaries, deduplicating option/rule arrays
static func _merge_section_dict(base_sec: Dictionary, overlay_sec: Dictionary) -> Dictionary:
	var result: Dictionary = base_sec.duplicate(true)
	for k in overlay_sec.keys():
		var val = overlay_sec[k]
		if val is Dictionary and result.has(k) and result[k] is Dictionary:
			result[k] = _merge_section_dict(result[k], val)
		elif val is Array and result.has(k) and result[k] is Array:
			result[k] = _merge_unique_array(result[k], val)
		else:
			result[k] = val.duplicate(true) if val is Dictionary or val is Array else val
	return result

## Merges two arrays without duplicates (matching Dictionary elements by 'id' or 'value')
static func _merge_unique_array(base_arr: Array, overlay_arr: Array) -> Array:
	var result: Array = base_arr.duplicate(true)
	var index_by_key: Dictionary = {}
	for i in range(result.size()):
		if result[i] is Dictionary:
			var item_key: String = str(result[i].get("id", result[i].get("value", ""))).strip_edges().to_upper()
			if not item_key.is_empty():
				index_by_key[item_key] = i

	for raw_item in overlay_arr:
		if raw_item is Dictionary:
			var item_key: String = str(raw_item.get("id", raw_item.get("value", ""))).strip_edges().to_upper()
			if not item_key.is_empty() and index_by_key.has(item_key):
				var idx: int = int(index_by_key[item_key])
				result[idx] = _merge_section_dict(result[idx], raw_item)
			else:
				if not item_key.is_empty():
					index_by_key[item_key] = result.size()
				result.append(raw_item.duplicate(true))
		else:
			if not result.has(raw_item):
				result.append(raw_item)
	return result

## Allows runtime registration of dynamic or player-created macro verb scopes
static func register_scope_definition(verb_token: String, scope_def: Dictionary) -> void:
	var clean_code := verb_token.strip_edges().to_upper()
	assert(not clean_code.is_empty(), "[TargetDomainRegistry FATAL] Cannot register scope for empty verb token.")
	_cached_scopes[clean_code] = scope_def

## Allows runtime registration of custom target domain resolver scripts
static func register_domain_resolver(domain_token: String, resolver_script: Script) -> void:
	var clean_domain := domain_token.strip_edges().to_upper()
	assert(not clean_domain.is_empty() and resolver_script != null,
		"[TargetDomainRegistry FATAL] Invalid domain_token or resolver_script.")
	_cached_resolvers[clean_domain] = resolver_script

## Returns the cached target_scope dictionary for a given verb token (O(1) memory lookup)
static func get_verb_scope_definition(verb_code: String) -> Dictionary:
	_ensure_initialized()
	var clean_code: String = verb_code.strip_edges().to_upper()
	return _cached_scopes.get(clean_code, {})

## Returns the array of allowed spatial/entity scopes (e.g. ["DISTRICT", "ESTABLISHMENT"])
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

## Resolves candidates directly from a single mounted domain resolver script
static func resolve_domain(domain_token: String, world_state: Dictionary, config: Dictionary = {}) -> Array[Dictionary]:
	_ensure_initialized()
	var clean_domain := domain_token.strip_edges().to_upper()
	assert(_cached_resolvers.has(clean_domain),
		"[TargetDomainRegistry FATAL] No pluggable target resolver mounted for domain '%s'." % clean_domain)
	var resolver_script = _cached_resolvers[clean_domain]
	return resolver_script.resolve(config, world_state, "")

## Resolves a normalized list of target candidates via pluggable domain resolver scripts
static func resolve_targets(verb_code: String, world_state: Dictionary, category_id: String = "") -> Array[Dictionary]:
	_ensure_initialized()
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
		var domain: String = str(target_cat.get("domain", target_cat.get("id", ""))).strip_edges().to_upper()
		if not _cached_resolvers.has(domain):
			push_error("[TargetDomainRegistry FATAL] No pluggable target resolver mounted for domain '%s' on verb '%s'." % [domain, verb_code])
			continue

		var resolver_script = _cached_resolvers[domain]
		var resolved: Array[Dictionary] = resolver_script.resolve(target_cat, world_state, verb_code)
		aggregated_results.append_array(resolved)

	return aggregated_results