# res://systems/file_system_crawler.gd
class_name FileSystemCrawler
extends RefCounted

## Recursively scans root_path across N-tiers and returns a list of matching absolute file paths.
## If target_filename is specified, only files matching that exact name are returned.
## Otherwise, matches all files ending with extension.
static func find_files_recursive(
	root_path: String,
	target_filename: String = "",
	extension: String = ".json"
) -> Array[String]:
	var results: Array[String] = []
	if root_path.is_empty() or not DirAccess.dir_exists_absolute(root_path):
		return results

	_scan_dir_internal(root_path, target_filename, extension, results)
	results.sort()
	return results

static func _scan_dir_internal(
	current_dir: String,
	target_filename: String,
	extension: String,
	out_results: Array[String]
) -> void:
	var dir := DirAccess.open(current_dir)
	if dir == null:
		push_warning("[FileSystemCrawler] Unable to open directory: %s" % current_dir)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()

	while not entry.is_empty():
		# Skip hidden files, system files, and VCS metadata
		if entry.begins_with("."):
			entry = dir.get_next()
			continue

		var full_path := current_dir.path_join(entry)

		if dir.current_is_dir():
			_scan_dir_internal(full_path, target_filename, extension, out_results)
		else:
			if not target_filename.is_empty():
				if entry == target_filename:
					out_results.append(full_path)
			elif not extension.is_empty():
				if entry.ends_with(extension):
					out_results.append(full_path)
			else:
				out_results.append(full_path)

		entry = dir.get_next()

	dir.list_dir_end()