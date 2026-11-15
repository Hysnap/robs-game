# res://scenes/ui/feedback/feedback_manager.gd
class_name FeedbackManager
extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const DATA_MODULES_ROOT := "res://data_modules/"

## Discovers and loads all shared feedback dictionaries and core/flavour verb feedback.json files via FileSystemCrawler
static func load_all_feedback(root_dir: String = DATA_MODULES_ROOT) -> Dictionary:
	var matrix: Dictionary = {"shared": {}, "verbs": {}}
	var all_json: Array[String] = FileSystemCrawlerScript.find_files_recursive(root_dir, "", ".json")

	for full_path in all_json:
		if full_path.contains("/feedback/"):
			var content: Dictionary = ScenarioManifestManagerScript.load_json_file(full_path)
			for code in content.keys():
				if code == "_meta":
					continue
				if not matrix["shared"].has(code):
					matrix["shared"][code] = []
				if content[code] is Array:
					matrix["shared"][code].append_array(content[code])
		elif full_path.ends_with("/feedback.json") and full_path.contains("/verbs/"):
			var verb_content: Dictionary = ScenarioManifestManagerScript.load_json_file(full_path)
			if not verb_content.is_empty():
				var verb_token: String = ""
				if verb_content.has("_meta") and verb_content["_meta"] is Dictionary:
					verb_token = str(verb_content["_meta"].get("verb_token", "")).strip_edges().to_upper()
				if verb_token.is_empty():
					verb_token = full_path.get_base_dir().get_file().strip_edges().to_upper()
				matrix["verbs"][verb_token] = verb_content

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