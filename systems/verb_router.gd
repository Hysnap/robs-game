# res://systems/verb_router.gd
class_name VerbRouter extends RefCounted

static var _registry: Dictionary = {}
static var _verb_mappings: Dictionary = {}
static var _initialized: bool = false

## Initializes and mounts verbs from core and optional active variant overlays
static func initialize(active_variant: String = "") -> void:
	_registry.clear()
	_verb_mappings.clear()
	
	# 1. Mount baseline canonical verbs from core
	_scan_and_mount_verbs("res://data_modules/core/verbs/")
	_load_verb_mappings("res://data_modules/core/verb_mappings.json")
	
	# 2. Overlay variant-specific overrides if active
	if active_variant != "" and active_variant != "core":
		var variant_verbs = "res://data_modules/%s/verbs/" % active_variant
		if DirAccess.dir_exists_absolute(variant_verbs):
			_scan_and_mount_verbs(variant_verbs)
		
		var variant_mappings = "res://data_modules/%s/verb_mappings.json" % active_variant
		if FileAccess.file_exists(variant_mappings):
			_load_verb_mappings(variant_mappings)
			
	_initialized = true
	print("[VERB ROUTER] Mounted %d atomic verbs into execution switchboard." % _registry.size())

## Executes an action directive safely through the registered verb
static func dispatch(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	if not _initialized:
		initialize()
		
	var raw_verb: String = action_directive.get("verb", action_directive.get("type", "")).to_upper()
	var resolved_key: String = _verb_mappings.get(raw_verb, raw_verb)
	
	if not _registry.has(resolved_key):
		push_error("[VERB ROUTER] No action script mounted for verb key: %s (Raw: %s)" % [resolved_key, raw_verb])
		return {"success": false, "message": "Unknown verb: " + raw_verb}
		
	var verb_script: Variant = _registry[resolved_key]
	return verb_script.execute(world_state, action_directive)

## Scans directories for action_*.gd files
static func _scan_and_mount_verbs(verbs_root_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(verbs_root_dir):
		return

	var dir = DirAccess.open(verbs_root_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var full_path = verbs_root_dir.path_join(entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			_scan_and_mount_verbs(full_path) # Recurse into subfolders (e.g. buy/, sell/)
		elif entry.ends_with(".gd") and entry.begins_with("action_"):
			var script_res = load(full_path)
			if script_res and script_res.has_method("execute"):
				var verb_token = entry.replace("action_", "").replace(".gd", "").to_upper()
				_registry[verb_token] = script_res
		entry = dir.get_next()
	dir.list_dir_end()

static func _load_verb_mappings(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_verb_mappings.merge(json.data, true)