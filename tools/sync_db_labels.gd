# res://tools/sync_db_labels.gd
extends SceneTree

const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const TAXONOMY_HARVESTER = preload("res://systems/taxonomy_harvester.gd")

## Engine-core and runtime-code enum domains that are not declared in scenario config JSONs
const STATIC_CORE_DOMAINS: Array[String] = [
	"CHANGE_REASON",
	"GENDER",
	"CONTRACT_CLASS",
	"CONTRACT_TYPE",
	"SCHEDULE_WINDOW",
	"DEATH_REASON",
	"TENURE_TYPE",
	"WEALTH_BRACKET",
	"BEHAVIORAL_TAG",
	"SECTOR_CATEGORY"
]

func _init() -> void:
	var flavours: Array[String] = []
	var target_flavour: String = ""

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--flavours="):
			var raw: String = arg.substr("--flavours=".length()).strip_edges()
			for part in raw.split(","):
				var slug: String = part.strip_edges().to_lower()
				if not slug.is_empty() and slug != "core" and not flavours.has(slug):
					flavours.append(slug)
		elif arg.begins_with("--target-flavour="):
			target_flavour = arg.substr("--target-flavour=".length()).strip_edges().to_lower()

	if not target_flavour.is_empty() and target_flavour != "core" and not flavours.has(target_flavour):
		flavours.append(target_flavour)

	MANIFEST_MANAGER.reset_cache()
	MANIFEST_MANAGER.set_active_flavours(flavours)
	MANIFEST_MANAGER.get_manifest()
	assert(MANIFEST_MANAGER.has_module("db_labels"), "FATAL: [sync_db_labels] Scenario manifest missing 'db_labels' module!")

	var core_labels_path: String = MANIFEST_MANAGER.get_module_path("db_labels").strip_edges()
	var labels_filename: String = core_labels_path.get_file()
	var data_modules_root: String = core_labels_path.get_base_dir().get_base_dir().get_base_dir()

	var all_label_files: Array[String] = [core_labels_path]
	var active_flavours: Array[String] = MANIFEST_MANAGER.get_active_flavours()
	var manifest_flavours: Variant = MANIFEST_MANAGER.get_manifest().get("active_flavours", [])
	if manifest_flavours is Array:
		for raw_f in manifest_flavours:
			var s: String = str(raw_f).strip_edges().to_lower()
			if not s.is_empty() and s != "core" and not active_flavours.has(s):
				active_flavours.append(s)

	for fl in active_flavours:
		var fl_path: String = data_modules_root.path_join(fl).path_join("localization").path_join(labels_filename)
		if FileAccess.file_exists(fl_path) and not all_label_files.has(fl_path):
			all_label_files.append(fl_path)

	# 1. Load all existing db_labels files and strip 'description' bloat
	var known_signatures: Dictionary = {} # "DOMAIN:CODE" -> source_path
	var file_payloads: Dictionary = {} # path -> Dictionary

	for f_path in all_label_files:
		var payload: Dictionary = _read_labels_json(f_path)
		var cleaned_list: Array[Dictionary] = []
		for item in payload.get("labels", []):
			if not (item is Dictionary):
				continue
			var dom: String = str(item.get("domain", "")).strip_edges().to_upper()
			var code: String = str(item.get("code", "")).strip_edges().to_upper()
			var title: String = str(item.get("title", "")).strip_edges()
			if dom.is_empty() or code.is_empty():
				continue
			if title.is_empty():
				title = code.capitalize().replace("_", " ")
			var sig := "%s:%s" % [dom, code]
			known_signatures[sig] = f_path
			cleaned_list.append({
				"domain": dom,
				"code": code,
				"title": title
			})
		payload["labels"] = cleaned_list
		file_payloads[f_path] = payload

	# 2. Harvest current scenario taxonomies dynamically from manifest
	var harvested: Array[Dictionary] = TAXONOMY_HARVESTER.harvest_all_taxonomies()
	var harvested_signatures: Dictionary = {}

	var write_target_path: String = core_labels_path
	if not target_flavour.is_empty() and target_flavour != "core":
		write_target_path = data_modules_root.path_join(target_flavour).path_join("localization").path_join(labels_filename)
		if not file_payloads.has(write_target_path):
			file_payloads[write_target_path] = {
				"_meta": {
					"flavour": target_flavour,
					"description": "Synchronized taxonomy labels for flavour '%s'." % target_flavour
				},
				"labels": []
			}

	var added_count: int = 0
	for h_item in harvested:
		var dom: String = str(h_item.get("domain", "")).strip_edges().to_upper()
		var code: String = str(h_item.get("code", "")).strip_edges().to_upper()
		var title: String = str(h_item.get("title", "")).strip_edges()
		if dom.is_empty() or code.is_empty():
			continue
		var sig := "%s:%s" % [dom, code]
		harvested_signatures[sig] = true
		if not known_signatures.has(sig):
			known_signatures[sig] = write_target_path
			file_payloads[write_target_path]["labels"].append({
				"domain": dom,
				"code": code,
				"title": title
			})
			added_count += 1
			print("[sync_db_labels] + Added [%s:%s] ('%s') -> %s" % [dom, code, title, write_target_path])

	# 3. Warn on obsolete labels no longer referenced by active scenario configs
	var obsolete_count: int = 0
	for sig in known_signatures.keys():
		var parts: PackedStringArray = str(sig).split(":")
		var dom: String = parts[0]
		if STATIC_CORE_DOMAINS.has(dom):
			continue
		if not harvested_signatures.has(sig):
			obsolete_count += 1
			push_warning("[sync_db_labels] OBSOLETE LABEL WARNING: [%s] in %s is no longer referenced in active scenario modules." % [
				sig, str(known_signatures[sig])
			])

	# 4. Sort deterministically, write cleaned db_labels JSONs, and sync matching ui_strings.csv
	var ui_added_total: int = 0
	for out_path in file_payloads.keys():
		var payload: Dictionary = file_payloads[out_path]
		var arr: Array = payload["labels"]
		arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["domain"] != b["domain"]:
				return a["domain"] < b["domain"]
			return a["code"] < b["code"]
		)
		payload["labels"] = arr
		_write_labels_json(out_path, payload)

		var ui_csv_path: String = out_path.get_base_dir().path_join("ui_strings.csv")
		ui_added_total += _sync_ui_strings_csv(ui_csv_path, arr)

	print("[sync_db_labels] Complete. Added %d new label(s), added %d UI string(s), flagged %d obsolete warning(s) across %d file(s)." % [
		added_count, ui_added_total, obsolete_count, file_payloads.size()
	])
	quit(0)

func _read_labels_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "FATAL: [sync_db_labels] Missing labels file: %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "FATAL: [sync_db_labels] Failed opening labels file: %s" % path)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	assert(parsed is Dictionary and parsed.has("labels"), "FATAL: [sync_db_labels] Invalid JSON structure in: %s" % path)
	return parsed

func _write_labels_json(path: String, payload: Dictionary) -> void:
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "FATAL: [sync_db_labels] Failed writing labels file: %s" % path)
	f.store_string(JSON.stringify(payload, "  ") + "\n")
	f.close()

func _sync_ui_strings_csv(csv_path: String, labels: Array) -> int:
	var dir_path: String = csv_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var existing_keys: Dictionary = {}
	var lines: PackedStringArray = PackedStringArray()
	var col_count: int = 2

	if FileAccess.file_exists(csv_path):
		var f_read := FileAccess.open(csv_path, FileAccess.READ)
		assert(f_read != null, "FATAL: [sync_db_labels] Failed opening ui_strings.csv: %s" % csv_path)
		var is_first_line: bool = true
		while not f_read.eof_reached():
			var raw_line: String = f_read.get_line()
			if raw_line.strip_edges().is_empty() and f_read.eof_reached():
				break
			if is_first_line:
				is_first_line = false
				var header_cols: PackedStringArray = raw_line.split(",")
				col_count = maxi(2, header_cols.size())
				lines.append(raw_line)
				continue
			lines.append(raw_line)
			var parsed_key: String = _extract_first_csv_column(raw_line).strip_edges().to_upper()
			if not parsed_key.is_empty():
				existing_keys[parsed_key] = true
		f_read.close()
	else:
		lines.append("\"key\",\"en_GB\"")

	var added: int = 0
	for item in labels:
		if not (item is Dictionary):
			continue
		var dom: String = str(item.get("domain", "")).strip_edges().to_upper()
		var code: String = str(item.get("code", "")).strip_edges().to_upper()
		var title: String = str(item.get("title", "")).strip_edges()
		if dom.is_empty() or code.is_empty():
			continue
		var ui_key: String = "UI_%s_%s" % [dom, code]
		if existing_keys.has(ui_key):
			continue
		existing_keys[ui_key] = true
		var safe_title: String = title.replace("\"", "\"\"")
		var row_cells: PackedStringArray = PackedStringArray()
		row_cells.append("\"%s\"" % ui_key)
		row_cells.append("\"%s\"" % safe_title)
		while row_cells.size() < col_count:
			row_cells.append("\"%s\"" % safe_title)
		lines.append(",".join(row_cells))
		added += 1

	if added > 0 or not FileAccess.file_exists(csv_path):
		var f_write := FileAccess.open(csv_path, FileAccess.WRITE)
		assert(f_write != null, "FATAL: [sync_db_labels] Failed writing ui_strings.csv: %s" % csv_path)
		f_write.store_string("\n".join(lines) + "\n")
		f_write.close()

	return added

func _extract_first_csv_column(line: String) -> String:
	var trimmed: String = line.strip_edges()
	if trimmed.begins_with("\""):
		var end_quote: int = trimmed.find("\"", 1)
		if end_quote > 1:
			return trimmed.substr(1, end_quote - 1)
	var comma_idx: int = trimmed.find(",")
	if comma_idx > 0:
		return trimmed.substr(0, comma_idx)
	return trimmed