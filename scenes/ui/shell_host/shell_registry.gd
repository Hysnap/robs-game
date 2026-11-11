# res://scenes/ui/shell_host/shell_registry.gd
class_name ShellRegistry
extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")

const SHELLS_DIR := "res://scenes/ui/shells/"
const FLAVOUR_DATA_DIR := "res://data_modules/"
const BUSINESS_RULES_PATH := "res://data_modules/core/business_rules.cfg"

static var _manifests: Dictionary = {} # "shell_id" -> Dictionary

## Scans shells directory and flavour modules across N-tiers for all shell_manifest.json files
static func initialize() -> void:
	if not _manifests.is_empty():
		return

	var manifest_paths: Array[String] = FileSystemCrawlerScript.find_files_recursive(SHELLS_DIR, "shell_manifest.json")
	
	# Also gather any shell manifests embedded within flavour data modules
	if DirAccess.dir_exists_absolute(FLAVOUR_DATA_DIR):
		var flavour_paths: Array[String] = FileSystemCrawlerScript.find_files_recursive(FLAVOUR_DATA_DIR, "shell_manifest.json")
		manifest_paths.append_array(flavour_paths)

	for manifest_path in manifest_paths:
		var f := FileAccess.open(manifest_path, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and parsed.has("id"):
				_manifests[str(parsed["id"]).to_lower()] = parsed

	assert(not _manifests.is_empty(), "FATAL: [ShellRegistry] No valid shell manifests discovered across %s or %s" % [SHELLS_DIR, FLAVOUR_DATA_DIR])

## Returns the active shell ID configured in business_rules.cfg
static func get_configured_shell_id() -> String:
	assert(FileAccess.file_exists(BUSINESS_RULES_PATH), "FATAL: [ShellRegistry] Missing configuration file: %s" % BUSINESS_RULES_PATH)
	
	var cfg := ConfigFile.new()
	var err := cfg.load(BUSINESS_RULES_PATH)
	assert(err == OK, "FATAL: [ShellRegistry] Failed to load config at %s" % BUSINESS_RULES_PATH)
	
	var target_shell: String = str(cfg.get_value("workspace_device", "active_shell", ""))
	assert(not target_shell.is_empty(), "FATAL: [ShellRegistry] 'active_shell' is missing or empty in business_rules.cfg")
	
	return target_shell.to_lower()

## Returns the manifest for a given shell, asserting it exists in the registry
static func get_shell_manifest(shell_id: String) -> Dictionary:
	initialize()
	var lower_id := shell_id.to_lower()
	assert(_manifests.has(lower_id), "FATAL: [ShellRegistry] Requested shell manifest '%s' does not exist in registry." % lower_id)
	return _manifests[lower_id]

## Returns the path to the active inbox stationery manifest declared in the active shell manifest
static func get_active_inbox_manifest_path() -> String:
	var shell_id := get_configured_shell_id()
	var manifest := get_shell_manifest(shell_id)
	var inbox_path: String = str(manifest.get("inbox_manifest", ""))
	assert(not inbox_path.is_empty(), "FATAL: [ShellRegistry] Shell '%s' manifest missing 'inbox_manifest'." % shell_id)
	return inbox_path

## Returns the path to the active order compilation manifest declared in the active shell manifest
static func get_active_order_composer_manifest_path() -> String:
	var shell_id := get_configured_shell_id()
	var manifest := get_shell_manifest(shell_id)
	var composer_path: String = str(manifest.get("order_composer_manifest", ""))
	assert(not composer_path.is_empty(), "FATAL: [ShellRegistry] Shell '%s' manifest missing 'order_composer_manifest'." % shell_id)
	return composer_path

## Instantiates and returns the spread wrapper scene for the active shell
static func instantiate_active_spread() -> Control:
	var shell_id := get_configured_shell_id()
	var manifest := get_shell_manifest(shell_id)
	var scene_path: String = manifest.get("spread_scene", "")

	assert(not scene_path.is_empty() and ResourceLoader.exists(scene_path), 
		"FATAL: Shell manifest '%s' points to invalid scene: '%s'" % [shell_id, scene_path])

	var scene: PackedScene = load(scene_path)
	return scene.instantiate() as Control