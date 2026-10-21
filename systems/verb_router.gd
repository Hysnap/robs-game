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
		var variant_verbs: String = "res://data_modules/%s/verbs/" % active_variant
		if DirAccess.dir_exists_absolute(variant_verbs):
			_scan_and_mount_verbs(variant_verbs)
		
		var variant_mappings: String = "res://data_modules/%s/verb_mappings.json" % active_variant
		if FileAccess.file_exists(variant_mappings):
			_load_verb_mappings(variant_mappings)
			
	_initialized = true
	print("[VERB ROUTER] Mounted %d atomic verbs into execution switchboard." % _registry.size())

## Executes an action directive safely through the registered verb
static func dispatch(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	if not _initialized:
		initialize()
		
	# 1. Extract raw verb token
	var raw_verb: String = str(action_directive.get("verb", action_directive.get("type", ""))).to_upper()
	if raw_verb.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.INVALID_DIRECTIVE,
			"UNKNOWN",
			"Directive missing required 'verb' or 'type' key."
		).to_dict()

	# 2. Resolve aliases via verb_mappings.json (e.g. RESTOCK -> BUY)
	var resolved_verb: String = _verb_mappings.get(raw_verb, raw_verb)
	
	# 3. Locate mounted script in the registry
	if not _registry.has(resolved_verb):
		push_error("[VERB ROUTER] No action script mounted for verb key: %s (Raw: %s)" % [resolved_verb, raw_verb])
		return EngineResult.fail(
			EngineResult.ErrorCode.ROUTER_UNMAPPED_VERB,
			raw_verb,
			"Unmapped verb: '%s'" % raw_verb
		).to_dict()

	var verb_script: Variant = _registry[resolved_verb]

	# 4. Execute the verb
	var raw_result = verb_script.execute(world_state, action_directive)
	
	# 5. Dual-Type Normalization Bridge:
	# If verb returned an EngineResult object, convert it to Dictionary for caller compatibility
	if raw_result is EngineResult:
		return raw_result.to_dict()
	elif raw_result is Dictionary:
		return raw_result
		
	push_error("[VERB ROUTER] Verb '%s' returned invalid type: %s" % [raw_verb, typeof(raw_result)])
	return EngineResult.fail(
		EngineResult.ErrorCode.INVALID_DIRECTIVE,
		raw_verb,
		"Invalid return payload from verb script."
	).to_dict()

## Scans directories recursively for action_*.gd files
static func _scan_and_mount_verbs(verbs_root_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(verbs_root_dir):
		return

	var dir: DirAccess = DirAccess.open(verbs_root_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full_path: String = verbs_root_dir.path_join(entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			_scan_and_mount_verbs(full_path) # Recurse into subfolders (e.g. buy/, travel/)
		elif entry.ends_with(".gd") and entry.begins_with("action_"):
			var script_res = load(full_path)
			if script_res and script_res.has_method("execute"):
				var verb_token: String = entry.replace("action_", "").replace(".gd", "").to_upper()
				_registry[verb_token] = script_res
		entry = dir.get_next()
	dir.list_dir_end()

## Ingests alias translations from JSON
static func _load_verb_mappings(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file:
		var json: JSON = JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_verb_mappings.merge(json.data, true)