# res://systems/commodity_manager.gd
class_name CommodityManager extends RefCounted

## Recursively scans folders and builds the inheritance registry
static func load_hierarchical_commodities(root_dir_path: String) -> Dictionary:
	var registry: Dictionary = {}
	_scan_directory_recursive(root_dir_path, {}, {}, registry)
	return registry

static func _scan_directory_recursive(
	current_path: String, 
	inherited_traits: Dictionary, 
	inherited_activations: Dictionary, 
	out_registry: Dictionary
) -> void:
	if not DirAccess.dir_exists_absolute(current_path):
		return

	var dir = DirAccess.open(current_path)
	if not dir:
		return

	var current_scope_traits = inherited_traits.duplicate(true)
	var current_scope_activations = inherited_activations.duplicate(true)

	# 1. Ingest local _base.json or item_profile.json
	var base_file = current_path.path_join("_base.json")
	if not FileAccess.file_exists(base_file):
		base_file = current_path.path_join("item_profile.json")
	if not FileAccess.file_exists(base_file):
		base_file = current_path.path_join("recipe_profile.json")
	var is_leaf_item = false
	if FileAccess.file_exists(base_file):
		var profile_data = _read_json(base_file)
		_deep_merge_dict(current_scope_traits, profile_data)
		if profile_data.has("id"):
			is_leaf_item = true

	# 2. Ingest any local verb folders (buy/, sell/, make/)
	var local_verb_activations = _load_verb_impact_files(current_path)
	_merge_activations(current_scope_activations, local_verb_activations)

	# 3. If leaf item, commit assembled dictionary to registry
	if is_leaf_item:
		var final_product = current_scope_traits.duplicate(true)
		final_product["impact_activations"] = current_scope_activations.duplicate(true)
		out_registry[final_product["id"]] = final_product

	# 4. Recurse down into child directories
	dir.list_dir_begin()
	var entry_name = dir.get_next()
	while entry_name != "":
		if dir.current_is_dir() and not entry_name.begins_with("."):
			var upper_name = entry_name.to_upper()
			# Exclude action folders from recursion (they are consumed by _load_verb_impact_files)
			if upper_name != "BUY" and upper_name != "SELL" and upper_name != "MAKE":
				var sub_path = current_path.path_join(entry_name)
				_scan_directory_recursive(sub_path, current_scope_traits, current_scope_activations, out_registry)
		entry_name = dir.get_next()
	dir.list_dir_end()

## Merges verb activations: child impact files overwrite parent impact files for matching metrics
static func _merge_activations(target: Dictionary, source: Dictionary) -> void:
	for verb_key in source.keys():
		if not target.has(verb_key):
			target[verb_key] = source[verb_key].duplicate(true)
		else:
			var target_list: Array = target[verb_key]
			var source_list: Array = source[verb_key]
			
			for src_impact in source_list:
				var metric = src_impact.get("metric", "")
				var replaced = false
				for i in range(target_list.size()):
					if target_list[i].get("metric", "") == metric:
						target_list[i] = src_impact.duplicate(true)
						replaced = true
						break
				if not replaced:
					target_list.append(src_impact.duplicate(true))

static func _load_verb_impact_files(path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir = DirAccess.open(path)
	if not dir:
		return result

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		var upper_name = folder_name.to_upper()
		if dir.current_is_dir() and (upper_name == "BUY" or upper_name == "SELL" or upper_name == "MAKE"):
			var verb_path = path.path_join(folder_name)
			result[upper_name] = _read_impacts_in_dir(verb_path)
		folder_name = dir.get_next()
	dir.list_dir_end()
	return result

static func _read_impacts_in_dir(verb_path: String) -> Array:
	var list: Array = []
	var dir = DirAccess.open(verb_path)
	if not dir:
		return list

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data = _read_json(verb_path.path_join(file_name))
			if not data.is_empty() and data.has("metric"):
				list.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()
	return list

static func _deep_merge_dict(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		if key == "_meta":
			continue
		if source[key] is Dictionary and target.get(key) is Dictionary:
			_deep_merge_dict(target[key], source[key])
		else:
			target[key] = source[key]

static func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return json.data
	return {}