# res://scenes/ui/shell_host/shell_registry.gd
class_name ShellRegistry
extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")

const SHELLS_DIR := "res://scenes/ui/shells/"
const FLAVOUR_DATA_DIR := "res://data_modules/"
const GENERATED_UI_ROOT := "res://generated/ui/"
const CORE_VARIANT_SLUG := "core"

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

## Resolves the active shell configuration block from the scenario manifest
static func _get_active_shell_entry(calendar_year: int = 0) -> Dictionary:
	var scenario_manifest: Dictionary = ScenarioManifestManagerScript.get_manifest()
	assert(scenario_manifest.has("ui_shells") and scenario_manifest["ui_shells"] is Dictionary,
		"FATAL: [ShellRegistry] Scenario manifest missing 'ui_shells' configuration block.")

	var ui_shells: Dictionary = scenario_manifest["ui_shells"]
	var target_shell: String = str(ui_shells.get("default_shell", "")).strip_edges().to_lower()
	assert(not target_shell.is_empty(), "FATAL: [ShellRegistry] 'default_shell' is missing or empty in scenario manifest 'ui_shells'.")

	var available: Array = ui_shells.get("available_shells", [])
	for entry in available:
		if entry is Dictionary and str(entry.get("shell_id", "")).to_lower() == target_shell:
			var earliest_year: int = int(entry.get("earliest_year", 0))
			if calendar_year > 0 and earliest_year > 0:
				assert(calendar_year >= earliest_year,
					"FATAL: [ShellRegistry] Shell '%s' is not available until %d (current year: %d)." % [target_shell, earliest_year, calendar_year])
			return entry

	assert(false, "FATAL: [ShellRegistry] Shell '%s' is not registered in manifest 'available_shells'." % target_shell)
	return {}

## Returns the active shell ID configured in the scenario manifest
static func get_configured_shell_id(calendar_year: int = 0) -> String:
	var entry: Dictionary = _get_active_shell_entry(calendar_year)
	return str(entry.get("shell_id", "")).to_lower()

## Returns the active compiled UI view variant directory slug (e.g., 'core' or flavour variant)
static func get_active_view_variant(calendar_year: int = 0) -> String:
	var entry: Dictionary = _get_active_shell_entry(calendar_year)
	var variant: String = str(entry.get("view_variant", CORE_VARIANT_SLUG)).strip_edges()
	return variant if not variant.is_empty() else CORE_VARIANT_SLUG

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
static func instantiate_active_spread(calendar_year: int = 0) -> Control:
	var shell_id := get_configured_shell_id(calendar_year)
	var manifest := get_shell_manifest(shell_id)
	var scene_path: String = manifest.get("spread_scene", "")

	assert(not scene_path.is_empty() and ResourceLoader.exists(scene_path), 
		"FATAL: Shell manifest '%s' points to invalid scene: '%s'" % [shell_id, scene_path])

	var scene: PackedScene = load(scene_path)
	return scene.instantiate() as Control

## Resolves and instantiates a compiled UI view via N-tier variant lookup (<view_variant> -> core), failing visibly if missing
static func instantiate_generated_view(view_filename: String, calendar_year: int = 0) -> Control:
	assert(not view_filename.is_empty(), "FATAL: [ShellRegistry] view_filename cannot be empty.")

	var variant: String = get_active_view_variant(calendar_year)
	var variant_path: String = GENERATED_UI_ROOT.path_join(variant).path_join(view_filename)
	var core_path: String = GENERATED_UI_ROOT.path_join(CORE_VARIANT_SLUG).path_join(view_filename)

	var resolved_path: String = ""
	if ResourceLoader.exists(variant_path):
		resolved_path = variant_path
	elif variant != CORE_VARIANT_SLUG and ResourceLoader.exists(core_path):
		resolved_path = core_path
	else:
		var msg := "FATAL: [ShellRegistry] Compiled UI view '%s' not found in variant '%s' (%s) or core (%s)." % [
			view_filename, variant, variant_path, core_path
		]
		SystemLogger.log_error(msg)
		push_error(msg)
		assert(false, msg)
		return null

	var view_script = load(resolved_path)
	if view_script == null:
		var load_msg := "FATAL: [ShellRegistry] Failed to load compiled UI script at: %s" % resolved_path
		SystemLogger.log_error(load_msg)
		push_error(load_msg)
		assert(false, load_msg)
		return null

	var instance = view_script.new()
	assert(instance is Control, "FATAL: [ShellRegistry] Compiled UI script '%s' did not instantiate as Control." % resolved_path)
	return instance as Control