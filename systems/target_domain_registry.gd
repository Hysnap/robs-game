# res://systems/target_domain_registry.gd
class_name TargetDomainRegistry
extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const VERBS_BASE_DIR := "res://data_modules/core/verbs/"
const RESOLVERS_BASE_DIR := "res://systems/target_resolvers/"

static var _cached_scopes: Dictionary = {} # "VERB_CODE" -> Dictionary
static var _cached_resolvers: Dictionary = {} # "DOMAIN_TOKEN" -> GDScript
static var _initialized: bool = false

## Clears in-memory cached scopes and resolvers (useful during testing or live-reloading)
static func clear_cache() -> void:
	_cached_scopes.clear()
	_cached_resolvers.clear()
	_initialized = false

## Eagerly scans and indexes all target_scope.json definitions and pluggable target domain resolvers
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
			verb_token = file_path.get_base_dir().get_file().strip_edges().to_upper()

		_cached_scopes[verb_token] = parsed

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