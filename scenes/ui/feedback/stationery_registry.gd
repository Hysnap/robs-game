# res://scenes/ui/feedback/stationery_registry.gd
class_name StationeryRegistry
extends RefCounted

const ShellRegistryScript = preload("res://scenes/ui/shell_host/shell_registry.gd")

static var _cached_definitions: Dictionary = {} # "DEF_ID" -> Dictionary
static var _active_manifest: Dictionary = {}
static var _active_manifest_path: String = ""

## Initializes or re-initializes the registry if the active shell manifest has changed
static func initialize(manifest_path: String = "") -> void:
	# 1. Resolve dynamic inbox manifest from the active shell directly
	if manifest_path.is_empty():
		manifest_path = ShellRegistryScript.get_active_inbox_manifest_path()

	# 2. Prevent redundant loads, but allow dynamic theme/shell switching
	if _active_manifest_path == manifest_path and not _cached_definitions.is_empty():
		return

	assert(FileAccess.file_exists(manifest_path), "FATAL: [StationeryRegistry] Manifest missing at: %s" % manifest_path)

	var f := FileAccess.open(manifest_path, FileAccess.READ)
	var parsed_manifest = JSON.parse_string(f.get_as_text())
	f.close()
	assert(parsed_manifest is Dictionary, "FATAL: [StationeryRegistry] Malformed JSON in inbox manifest: %s" % manifest_path)
	_active_manifest = parsed_manifest

	_cached_definitions.clear()
	_active_manifest_path = manifest_path
	
	var allowed_files: Array = _active_manifest.get("allowed_stationery", [])

	for file_path in allowed_files:
		assert(FileAccess.file_exists(file_path), "FATAL: [StationeryRegistry] Missing stationery definition at: %s" % file_path)
		var def_file := FileAccess.open(file_path, FileAccess.READ)
		var parsed = JSON.parse_string(def_file.get_as_text())
		def_file.close()

		if parsed is Dictionary and parsed.has("_meta"):
			var id: String = str(parsed["_meta"].get("id", "")).to_upper()
			assert(not id.is_empty(), "FATAL: [StationeryRegistry] Stationery definition missing '_meta.id' at: %s" % file_path)
			_cached_definitions[id] = parsed

	assert(not _cached_definitions.is_empty(), "FATAL: [StationeryRegistry] No valid stationery definitions loaded for manifest: %s" % manifest_path)
	SystemLogger.log_info("[StationeryRegistry] Ingested %d stationery definitions for shell manifest: %s" % [_cached_definitions.size(), manifest_path])

static func get_default_definition_id() -> String:
	initialize()
	var bindings: Dictionary = _active_manifest.get("verb_bindings", {})
	var default_binding: Dictionary = bindings.get("DEFAULT", {})
	var def_id: String = str(_active_manifest.get("default_stationery", default_binding.get("default_definition", ""))).to_upper()
	if def_id.is_empty() and not _cached_definitions.is_empty():
		def_id = str(_cached_definitions.keys()[0])
	assert(not def_id.is_empty() and _cached_definitions.has(def_id),
		"FATAL: [StationeryRegistry] Active manifest '%s' has no valid default stationery definition." % _active_manifest_path)
	return def_id

static func get_definition(def_id: String) -> Dictionary:
	initialize()
	return _cached_definitions.get(def_id.to_upper(), {})

static func get_verb_binding(verb: String) -> Dictionary:
	initialize()
	var bindings: Dictionary = _active_manifest.get("verb_bindings", {})
	var upper_verb: String = verb.to_upper()
	if bindings.has(upper_verb):
		return bindings[upper_verb]
	if bindings.has("DEFAULT"):
		return bindings["DEFAULT"]
	return {
		"default_definition": get_default_definition_id(),
		"default_filing_domain": "DIARY"
	}

static func get_stack_rules() -> Dictionary:
	initialize()
	return _active_manifest.get("stack_rules", {})