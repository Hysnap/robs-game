class_name FeedbackManager extends RefCounted

static func load_all_feedback(
	shared_dir: String = "res://data_modules/shared/feedback/", 
	verbs_dir: String = "res://data_modules/core/verbs/"
) -> Dictionary:
	var matrix: Dictionary = {"shared": {}, "verbs": {}}
	_scan_shared(shared_dir, matrix["shared"])
	_scan_verbs(verbs_dir, matrix["verbs"])
	return matrix

static func _scan_shared(path: String, out_dict: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = path.path_join(file_name)
		if dir.current_is_dir() and not file_name.begins_with("."):
			_scan_shared(full_path, out_dict)
		elif file_name.ends_with(".json"):
			var content = _load_json(full_path)
			for code in content.keys():
				if not out_dict.has(code):
					out_dict[code] = []
				out_dict[code].append_array(content[code])
		file_name = dir.get_next()
	dir.list_dir_end()

static func _scan_verbs(path: String, out_dict: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry_name = dir.get_next()
	while entry_name != "":
		var sub_path = path.path_join(entry_name)
		if dir.current_is_dir() and not entry_name.begins_with("."):
			var feedback_file = sub_path.path_join("feedback.json")
			if FileAccess.file_exists(feedback_file):
				out_dict[entry_name.to_upper()] = _load_json(feedback_file)
			# Recurse into nested subfolders (e.g. buy/, sell/, etc.)
			_scan_verbs(sub_path, out_dict)
		entry_name = dir.get_next()
	dir.list_dir_end()

static func _load_json(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return json.data
	return {}