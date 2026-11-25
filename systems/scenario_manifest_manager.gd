# res://systems/scenario_manifest_manager.gd
class_name ScenarioManifestManager
extends RefCounted

const BUSINESS_RULES_PATH := "res://data_modules/core/business_rules.cfg"
const DATA_MODULES_ROOT := "res://data_modules/"

static var _cached_manifest: Dictionary = {}
static var _cached_modules: Dictionary = {} # "module_key" -> parsed Dictionary
static var _active_manifest_path: String = ""
static var _active_flavours: Array[String] = []
static var _flavour_overlays: Dictionary = {} # "module_key" -> Array[String] of overlay paths

## Sets active flavour slugs (e.g. ["crime"]) and invalidates cached manifest/modules so overlays apply
static func set_active_flavours(flavours: Array) -> void:
	var normalized: Array[String] = []
	for raw_f in flavours:
		var slug: String = str(raw_f).strip_edges().to_lower()
		if not slug.is_empty() and slug != "core" and not normalized.has(slug):
			normalized.append(slug)
	if normalized == _active_flavours and not _cached_manifest.is_empty():
		return
	_active_flavours = normalized
	_cached_manifest.clear()
	_cached_modules.clear()
	_flavour_overlays.clear()

static func get_active_flavours() -> Array[String]:
	return _active_flavours.duplicate()

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
	SystemLogger.log_info("[ScenarioManifestManager] Active manifest resolved: %s" % path)
	return _active_manifest_path

## Parses and caches the root scenario manifest JSON, overlaying any active flavour manifests
static func get_manifest() -> Dictionary:
	if not _cached_manifest.is_empty():
		return _cached_manifest

	var manifest_path: String = get_manifest_path()
	var parsed: Dictionary = load_json_file(manifest_path).duplicate(true)
	
	assert(parsed.has("modules"), "FATAL: Scenario manifest missing 'modules' block: %s" % manifest_path)
	assert(parsed["modules"] is Dictionary, "FATAL: 'modules' in manifest must be a Dictionary: %s" % manifest_path)

	_flavour_overlays.clear()
	var modules: Dictionary = parsed["modules"]

	for flavour_slug in _active_flavours:
		var flavour_manifest_path: String = "%s%s/flavour_manifest.json" % [DATA_MODULES_ROOT, flavour_slug]
		if not FileAccess.file_exists(flavour_manifest_path):
			continue
		var flavour_data: Dictionary = load_json_file(flavour_manifest_path)
		assert(flavour_data.has("modules") and flavour_data["modules"] is Dictionary,
			"FATAL: Flavour manifest missing 'modules' Dictionary: %s" % flavour_manifest_path)
		var f_modules: Dictionary = flavour_data["modules"]
		for mod_key in f_modules.keys():
			var mod_path: String = str(f_modules[mod_key]).strip_edges()
			assert(not mod_path.is_empty(), "FATAL: Empty module path for '%s' in %s" % [mod_key, flavour_manifest_path])
			if not modules.has(mod_key):
				modules[mod_key] = mod_path
			else:
				if not _flavour_overlays.has(mod_key):
					_flavour_overlays[mod_key] = []
				_flavour_overlays[mod_key].append(mod_path)

	_cached_manifest = parsed
	SystemLogger.log_info("[ScenarioManifestManager] Scenario manifest loaded with %d modules (flavours: %s)." % [
		modules.size(), str(_active_flavours)
	])
	return _cached_manifest

## Checks whether a named module key is registered in the active manifest (or active flavour overlays)
static func has_module(module_key: String) -> bool:
	var manifest: Dictionary = get_manifest()
	var modules: Dictionary = manifest.get("modules", {})
	return modules.has(module_key)

## Resolves the file or directory path for a named module declared in the manifest
static func get_module_path(module_key: String) -> String:
	var manifest: Dictionary = get_manifest()
	var modules: Dictionary = manifest.get("modules", {})
	assert(modules.has(module_key), "FATAL: Module '%s' is not registered in manifest: %s" % [module_key, _active_manifest_path])
	
	var path: String = str(modules[module_key]).strip_edges()
	assert(not path.is_empty(), "FATAL: Module path for '%s' is empty in manifest" % module_key)
	var exists_on_disk: bool = FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)
	assert(exists_on_disk, "FATAL: Module path on disk not found for '%s': %s" % [module_key, path])
	
	return path

## Loads and caches a module JSON directly by its registered key, deep-merging any active flavour overlays
static func load_module(module_key: String) -> Dictionary:
	if _cached_modules.has(module_key):
		return _cached_modules[module_key]

	var path: String = get_module_path(module_key)
	var merged: Dictionary = load_json_file(path).duplicate(true)

	if _flavour_overlays.has(module_key):
		for overlay_path in _flavour_overlays[module_key]:
			var overlay_dict: Dictionary = load_json_file(overlay_path)
			_deep_merge_dictionary(merged, overlay_dict)
	
	_cached_modules[module_key] = merged
	SystemLogger.log_debug("[ScenarioManifestManager] Loaded module '%s'." % module_key)
	return _cached_modules[module_key]

static func _deep_merge_dictionary(target: Dictionary, overlay: Dictionary) -> void:
	for key in overlay.keys():
		if key == "_meta":
			continue
		var val = overlay[key]
		if target.has(key) and target[key] is Dictionary and val is Dictionary:
			_deep_merge_dictionary(target[key], val)
		else:
			target[key] = val.duplicate(true) if (val is Dictionary or val is Array) else val

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
		SystemLogger.log_critical("[ScenarioManifestManager CRITICAL] JSON syntax error in %s at line %d: %s" % [
			file_path, json.get_error_line(), json.get_error_message()
		])
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
	_active_flavours.clear()
	_flavour_overlays.clear()

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

## Centralized system accessor: safely resolves the active GameState node
## Works across editor runtime, live play, and headless test harnesses without compile errors
static func get_game_state() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root and main_loop.root.has_node("GameState"):
		return main_loop.root.get_node("GameState")
	return null