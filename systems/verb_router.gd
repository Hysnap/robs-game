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

## Scans directories recursively using FileSystemCrawler, mounting or overlaying declarative verb_definition.json files
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
				var verb_dir: String = file_path.get_base_dir()
				var default_slug: String = verb_dir.get_file()
				var meta: Dictionary = parsed.get("_meta", {})
				var token: String = str(meta.get("verb_token", default_slug)).to_upper().strip_edges()
				var impacts_dir: String = verb_dir.path_join("impacts")

				if not _registry.has(token) or bool(meta.get("replace_core", false)):
					var entry: Dictionary = parsed.duplicate(true)
					var entry_meta: Dictionary = entry.get("_meta", {}).duplicate(true)
					entry_meta["impacts_dirs"] = [impacts_dir] if DirAccess.dir_exists_absolute(impacts_dir) else []
					entry["_meta"] = entry_meta
					_registry[token] = entry
				elif _registry[token] is Dictionary:
					_registry[token] = _merge_verb_overlay(_registry[token], parsed, impacts_dir)

## Deep-merges a flavour pack verb_definition.json overlay onto an existing core verb definition
static func _merge_verb_overlay(base_def: Dictionary, overlay_def: Dictionary, overlay_impacts_dir: String) -> Dictionary:
	var merged: Dictionary = base_def.duplicate(true)

	# 1. Merge parameters
	var merged_params: Dictionary = merged.get("parameters", {}).duplicate(true)
	var overlay_params: Dictionary = overlay_def.get("parameters", {})
	for p_key in overlay_params.keys():
		merged_params[p_key] = overlay_params[p_key]
	merged["parameters"] = merged_params

	# 2. Merge steps by step_id (update existing step in place, or append new mode/branch steps)
	var merged_steps: Array = merged.get("steps", []).duplicate(true)
	var step_index_by_id: Dictionary = {}
	for i in range(merged_steps.size()):
		if merged_steps[i] is Dictionary and merged_steps[i].has("step_id"):
			step_index_by_id[str(merged_steps[i]["step_id"])] = i

	for raw_step in overlay_def.get("steps", []):
		if not (raw_step is Dictionary):
			continue
		var s_id: String = str(raw_step.get("step_id", ""))
		if not s_id.is_empty() and step_index_by_id.has(s_id):
			var idx: int = int(step_index_by_id[s_id])
			var updated_step: Dictionary = merged_steps[idx].duplicate(true)
			updated_step.merge(raw_step, true)
			merged_steps[idx] = updated_step
		else:
			if not s_id.is_empty():
				step_index_by_id[s_id] = merged_steps.size()
			merged_steps.append(raw_step.duplicate(true))
	merged["steps"] = merged_steps

	# 3. Accumulate impacts_dirs so both core and flavour impacts execute
	var merged_meta: Dictionary = merged.get("_meta", {}).duplicate(true)
	var impacts_dirs: Array = merged_meta.get("impacts_dirs", []).duplicate()
	if DirAccess.dir_exists_absolute(overlay_impacts_dir) and not impacts_dirs.has(overlay_impacts_dir):
		impacts_dirs.append(overlay_impacts_dir)
	merged_meta["impacts_dirs"] = impacts_dirs
	merged["_meta"] = merged_meta

	return merged

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

## Returns the mounted verb definition dictionary for a verb token (resolving aliases)
static func get_verb_definition(verb_token: String) -> Dictionary:
	if not _initialized:
		initialize()
	var raw_verb: String = verb_token.to_upper().strip_edges()
	var resolved_verb: String = _verb_mappings.get(raw_verb, raw_verb)
	var entry: Variant = _registry.get(resolved_verb, {})
	return entry.duplicate(true) if entry is Dictionary else {}

## Returns the ordered list of active impacts/ directories (core + active flavour overlay) for a verb
static func get_impacts_dirs(verb_token: String) -> Array[String]:
	var def: Dictionary = get_verb_definition(verb_token)
	var raw_dirs: Array = def.get("_meta", {}).get("impacts_dirs", [])
	var dirs: Array[String] = []
	for d in raw_dirs:
		var clean_dir: String = str(d).strip_edges()
		if not clean_dir.is_empty():
			dirs.append(clean_dir)
	return dirs