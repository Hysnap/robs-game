# res://scenes/ui/feedback/stationery_registry.gd
class_name StationeryRegistry
extends RefCounted

const ShellRegistryScript = preload("res://scenes/ui/shell_host/shell_registry.gd")

static var _cached_definitions: Dictionary = {} # "STICKY_NOTE" -> Dictionary
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

	if not FileAccess.file_exists(manifest_path):
		SystemLogger.log_error("[StationeryRegistry] Manifest missing at: %s" % manifest_path)
		push_error("[StationeryRegistry] Manifest missing at: %s" % manifest_path)
		return

	var f := FileAccess.open(manifest_path, FileAccess.READ)
	_active_manifest = JSON.parse_string(f.get_as_text())
	f.close()

	_cached_definitions.clear()
	_active_manifest_path = manifest_path
	
	var allowed_files: Array = _active_manifest.get("allowed_stationery", [])
	
	for file_path in allowed_files:
		if FileAccess.file_exists(file_path):
			var def_file := FileAccess.open(file_path, FileAccess.READ)
			var parsed = JSON.parse_string(def_file.get_as_text())
			def_file.close()
			
			if parsed is Dictionary and parsed.has("_meta"):
				var id: String = str(parsed["_meta"].get("id", "")).to_upper()
				_cached_definitions[id] = parsed
				
	SystemLogger.log_info("[StationeryRegistry] Ingested %d stationery definitions for shell manifest: %s" % [_cached_definitions.size(), manifest_path])

static func get_definition(def_id: String) -> Dictionary:
	initialize()
	return _cached_definitions.get(def_id.to_upper(), {})

static func get_verb_binding(verb: String) -> Dictionary:
	initialize()
	var bindings: Dictionary = _active_manifest.get("verb_bindings", {})
	return bindings.get(verb.to_upper(), {
		"default_definition": "STICKY_NOTE",
		"default_filing_domain": "DIARY"
	})

static func get_stack_rules() -> Dictionary:
	initialize()
	return _active_manifest.get("stack_rules", {})