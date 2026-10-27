# res://systems/scenario_manifest_manager.gd
class_name ScenarioManifestManager
extends RefCounted

const BUSINESS_RULES_PATH := "res://data_modules/core/business_rules.cfg"


static var _cached_manifest: Dictionary = {}
static var _cached_modules: Dictionary = {} # "module_key" -> parsed Dictionary
static var _active_manifest_path: String = ""

## Resolves the scenario manifest path from business_rules.cfg
static func get_manifest_path() -> String:
	if not _active_manifest_path.is_empty():
		return _active_manifest_path

	assert(FileAccess.file_exists(BUSINESS_RULES_PATH), "FATAL: business_rules.cfg missing at: %s" % BUSINESS_RULES_PATH)
	
	var config := ConfigFile.new()
	var err := config.load(BUSINESS_RULES_PATH)
	assert(err == OK, "FATAL: Failed to parse %s (Error code: %d)" % [BUSINESS_RULES_PATH, err])

	var path: String = str(config.get_value("society", "manifest_path", "")).strip_edges()
	assert(not path.is_empty(), "FATAL: Section [society] 'manifest_path' is missing or empty in %s" % BUSINESS_RULES_PATH)
	assert(FileAccess.file_exists(path), "FATAL: Scenario manifest file declared in business_rules.cfg does not exist: %s" % path)

	_active_manifest_path = path
	return _active_manifest_path

## Parses and caches the root scenario manifest JSON
static func get_manifest() -> Dictionary:
	if not _cached_manifest.is_empty():
		return _cached_manifest

	var manifest_path: String = get_manifest_path()
	var parsed: Dictionary = load_json_file(manifest_path)
	
	assert(parsed.has("modules"), "FATAL: Scenario manifest missing 'modules' block: %s" % manifest_path)
	assert(parsed["modules"] is Dictionary, "FATAL: 'modules' in manifest must be a Dictionary: %s" % manifest_path)

	_cached_manifest = parsed
	return _cached_manifest

## Checks whether a named module key is registered in the active manifest
static func has_module(module_key: String) -> bool:
	var manifest: Dictionary = get_manifest()
	var modules: Dictionary = manifest.get("modules", {})
	return modules.has(module_key)

## Resolves the file path for a named module declared in the manifest
static func get_module_path(module_key: String) -> String:
	var manifest: Dictionary = get_manifest()
	var modules: Dictionary = manifest.get("modules", {})
	assert(modules.has(module_key), "FATAL: Module '%s' is not registered in manifest: %s" % [module_key, _active_manifest_path])
	
	var path: String = str(modules[module_key]).strip_edges()
	assert(not path.is_empty(), "FATAL: Module path for '%s' is empty in manifest" % module_key)
	assert(FileAccess.file_exists(path), "FATAL: Module file on disk not found for '%s': %s" % [module_key, path])
	
	return path

## Loads and caches a module JSON directly by its registered key
static func load_module(module_key: String) -> Dictionary:
	if _cached_modules.has(module_key):
		return _cached_modules[module_key]

	var path: String = get_module_path(module_key)
	var parsed: Dictionary = load_json_file(path)
	
	_cached_modules[module_key] = parsed
	return _cached_modules[module_key]

## Universal JSON Reader enforcing strict syntax validation and hard assertions
static func load_json_file(file_path: String) -> Dictionary:
	assert(FileAccess.file_exists(file_path), "FATAL: JSON file does not exist: %s" % file_path)
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	assert(file != null, "FATAL: Unable to open file for read access: %s" % file_path)
	
	var raw_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(raw_text)
	if parse_err != OK:
		push_error("[ScenarioManifestManager CRITICAL] JSON syntax error in %s at line %d: %s" % [
			file_path, json.get_error_line(), json.get_error_message()
		])
		assert(false, "FATAL: Corrupted JSON at: %s" % file_path)

	assert(json.data is Dictionary, "FATAL: JSON root element must be a Dictionary: %s" % file_path)
	return json.data

## Flushes cached dictionaries (used during testing or when switching scenarios)
static func reset_cache() -> void:
	_cached_manifest.clear()
	_cached_modules.clear()
	_active_manifest_path = ""

## Universal module loader: Dispatches to JSON parser or Engine Resource loader based on extension
static func load_resource_module(module_key: String) -> Resource:
	var path: String = get_module_path(module_key)
	assert(ResourceLoader.exists(path), "FATAL: Engine resource missing on disk: %s" % path)
	var res = load(path)
	assert(res != null, "FATAL: Failed to instantiate engine resource at: %s" % path)
	return res

## Smart loader that detects file extension
static func load_any(module_key: String) -> Variant:
	var path: String = get_module_path(module_key)
	if path.ends_with(".tres") or path.ends_with(".res"):
		return load_resource_module(module_key)
	else:
		return load_module(module_key)

## Typed accessor returning the manifest-selected CustomCityConfiguration / CityConfiguration resource
static func get_city_configuration() -> Resource:
	assert(has_module("city_configuration"), 
		"FATAL: Scenario manifest missing 'city_configuration' registration: %s" % _active_manifest_path)
	var res = load_resource_module("city_configuration")
	assert(res != null, "FATAL: Failed to resolve city_configuration resource.")
	return res