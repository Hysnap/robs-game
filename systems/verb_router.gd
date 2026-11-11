# res://systems/verb_router.gd
class_name VerbRouter extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const EngineResultScript = preload("res://systems/engine_result.gd")
const ActionPipelineRunnerScript = preload("res://systems/action_pipeline/action_pipeline_runner.gd")

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
	SystemLogger.log_info("[VERB ROUTER] Mounted %d atomic verbs into execution switchboard." % _registry.size())

## Executes an action directive safely through the registered verb
static func dispatch(world_state: Dictionary, action_directive: Dictionary) -> Dictionary:
	if not _initialized:
		initialize()
		
	# 1. Extract raw verb token
	var raw_verb: String = str(action_directive.get("verb", action_directive.get("type", ""))).to_upper()
	if raw_verb.is_empty():
		return EngineResultScript.fail(
			EngineResultScript.ErrorCode.INVALID_PARAMETER,
			"UNKNOWN",
			"Directive missing required 'verb' or 'type' key."
		).to_dict()

	# 2. Resolve aliases via verb_mappings.json (e.g. RESTOCK -> BUY)
	var resolved_verb: String = _verb_mappings.get(raw_verb, raw_verb)
	
	# 3. Locate mounted verb definition or script in the registry
	if not _registry.has(resolved_verb):
		SystemLogger.log_error("[VERB ROUTER] No action definition or script mounted for verb key: %s (Raw: %s)" % [resolved_verb, raw_verb])
		push_error("[VERB ROUTER] No action definition or script mounted for verb key: %s (Raw: %s)" % [resolved_verb, raw_verb])
		return EngineResultScript.fail(
			EngineResultScript.ErrorCode.ROUTER_UNMAPPED_VERB,
			raw_verb,
			"Unmapped verb: '%s'" % raw_verb
		).to_dict()

	var verb_entry: Variant = _registry[resolved_verb]

	# 4. Route Execution
	# Case A: Declarative JSON Pipeline Definition
	if verb_entry is Dictionary:
		return ActionPipelineRunnerScript.run_action_pipeline(world_state, action_directive, verb_entry)
		
	# Case B: Legacy Action Script Fallback
	if verb_entry is GDScript or (verb_entry is Object and verb_entry.has_method("execute")):
		var raw_result = verb_entry.execute(world_state, action_directive)
		if raw_result is Dictionary:
			return raw_result
		elif raw_result != null and raw_result.has_method("to_dict"):
			return raw_result.to_dict()

	SystemLogger.log_error("[VERB ROUTER] Verb '%s' entry has invalid executable type: %s" % [raw_verb, typeof(verb_entry)])
	push_error("[VERB ROUTER] Verb '%s' entry has invalid executable type: %s" % [raw_verb, typeof(verb_entry)])
	return EngineResultScript.fail(
		EngineResultScript.ErrorCode.INTERNAL_SIM_ERROR,
		raw_verb,
		"Invalid executable definition for verb."
	).to_dict()

## Scans directories recursively using FileSystemCrawler, mounting all declarative verb_definition.json files
static func _scan_and_mount_verbs(verbs_root_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(verbs_root_dir):
		return

	var verb_files: Array[String] = FileSystemCrawlerScript.find_files_recursive(verbs_root_dir, "verb_definition.json")
	for file_path in verb_files:
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				var default_slug: String = file_path.get_base_dir().get_file()
				var token: String = str(parsed.get("_meta", {}).get("verb_token", default_slug)).to_upper().strip_edges()
				_registry[token] = parsed

## Ingests alias translations from JSON
static func _load_verb_mappings(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			_verb_mappings.merge(parsed, true)

## Returns a sorted list of all active mounted verb tokens
static func get_registered_verbs() -> Array[String]:
	if not _initialized:
		initialize()
	var verbs: Array[String] = []
	for k in _registry.keys():
		verbs.append(str(k))
	verbs.sort()
	return verbs

## Returns active alias verb mappings
static func get_verb_mappings() -> Dictionary:
	if not _initialized:
		initialize()
	return _verb_mappings.duplicate(true)