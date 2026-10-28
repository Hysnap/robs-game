# res://scenes/ui/shell_host/shell_registry.gd
class_name ShellRegistry
extends RefCounted

const SHELLS_DIR := "res://scenes/ui/shells/"
const BUSINESS_RULES_PATH := "res://data_modules/core/business_rules.cfg"

static var _manifests: Dictionary = {} # "shell_id" -> Dictionary

## Scans res://scenes/ui/shells/ for all shell_manifest.json files
static func initialize() -> void:
	if not _manifests.is_empty():
		return

	var dir := DirAccess.open(SHELLS_DIR)
	if not dir:
		push_error("[ShellRegistry] Missing shells directory: %s" % SHELLS_DIR)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var manifest_path := SHELLS_DIR.path_join(entry).path_join("shell_manifest.json")
			if FileAccess.file_exists(manifest_path):
				var f := FileAccess.open(manifest_path, FileAccess.READ)
				if f:
					var parsed = JSON.parse_string(f.get_as_text())
					f.close()
					if parsed is Dictionary and parsed.has("id"):
						_manifests[str(parsed["id"]).to_lower()] = parsed
		entry = dir.get_next()
	dir.list_dir_end()

## Returns the active shell ID configured in business_rules.cfg
static func get_configured_shell_id() -> String:
	var target_shell := "filofax"
	if FileAccess.file_exists(BUSINESS_RULES_PATH):
		var cfg := ConfigFile.new()
		if cfg.load(BUSINESS_RULES_PATH) == OK:
			target_shell = str(cfg.get_value("workspace_device", "active_shell", "filofax")).to_lower()
	return target_shell

## Returns the manifest for a given shell or falls back safely
static func get_shell_manifest(shell_id: String) -> Dictionary:
	initialize()
	if _manifests.has(shell_id.to_lower()):
		return _manifests[shell_id.to_lower()]
	
	# Fallback to filofax if requested ID is missing
	if _manifests.has("filofax"):
		return _manifests["filofax"]
		
	# Fallback to the first available manifest if filofax isn't found
	if not _manifests.is_empty():
		return _manifests[_manifests.keys()[0]]

	push_error("[ShellRegistry FATAL] No valid shell manifests discovered in %s" % SHELLS_DIR)
	return {}

## Instantiates and returns the spread wrapper scene for the active shell
static func instantiate_active_spread() -> Control:
	var shell_id := get_configured_shell_id()
	var manifest := get_shell_manifest(shell_id)
	var scene_path: String = manifest.get("spread_scene", "")
	
	assert(!scene_path.is_empty() and ResourceLoader.exists(scene_path), 
		"FATAL: Shell manifest '%s' points to invalid scene: '%s'" % [shell_id, scene_path])
	
	var scene: PackedScene = load(scene_path)
	return scene.instantiate() as Control