# res://systems/catalog_validator.gd
class_name CatalogValidator
extends RefCounted

const COMMODITIES_ROOT = "res://data_modules/core/commodities/"
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

## Dynamically discovers valid calculation/condition models from the evaluator
static func get_discovered_models() -> Array:
	# 1. Check ConditionEvaluator if it exports models or methods
	if ClassDB.class_exists("ConditionEvaluator") or ResourceLoader.exists("res://systems/condition_evaluator.gd"):
		var evaluator = load("res://systems/condition_evaluator.gd")
		if evaluator:
			if evaluator.has_method("get_supported_models"):
				return evaluator.get_supported_models()
			elif "ModelType" in evaluator:
				return evaluator.ModelType.keys()
	
	# 2. Check ImpactCalculator fallback if models are math-impact profiles
	if ClassDB.class_exists("ImpactCalculator") or ResourceLoader.exists("res://systems/impacts/impact_calculator.gd"):
		var calc = load("res://systems/impacts/impact_calculator.gd")
		if calc:
			if calc.has_method("get_supported_models"):
				return calc.get_supported_models()
			elif "ModelType" in calc:
				return calc.ModelType.keys()

	# 3. Fallback baseline if evaluator is unmounted during isolated tests
	return ["LINEAR_PER_UNIT", "WEIGHTED_PER_UNIT", "EXP_PER_UNIT", "LOG_PER_UNIT", "STEPPED_PER_UNIT"]

## Dynamically discovers valid categories directly from disk directories
static func get_discovered_categories(root_path: String = COMMODITIES_ROOT) -> Array:
	var categories: Array = []
	if not DirAccess.dir_exists_absolute(root_path):
		return categories

	var dir = DirAccess.open(root_path)
	if not dir:
		return categories

	dir.list_dir_begin()
	var entry_name = dir.get_next()
	while entry_name != "":
		var full_path = root_path.path_join(entry_name)
		if dir.current_is_dir() and not entry_name.begins_with("."):
			var cat_token = entry_name.to_upper()
			if cat_token.ends_with("S"):
				cat_token = cat_token.left(cat_token.length() - 1)
			categories.append(cat_token)
			if not categories.has(entry_name.to_upper()):
				categories.append(entry_name.to_upper())
		entry_name = dir.get_next()
	dir.list_dir_end()

	return categories

# =============================================================================
# 1. COMMODITY & RECIPE VALIDATOR
# =============================================================================

## Runs an end-to-end integrity audit across commodities, recipes, and verbs
static func validate_catalogs(world_state: Dictionary, write_to_disk: bool = true) -> Dictionary:
	var commodities: Dictionary = world_state.get("commodity_registry", {})
	var recipes: Dictionary = world_state.get("recipe_registry", {})
	var valid_categories: Array = get_discovered_categories()
	var valid_models: Array = get_discovered_models()

	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"is_clean": true,
		"errors": [],
		"warnings": [],
		"commodity_count": commodities.size(),
		"recipe_count": recipes.size(),
		"raw_commodity_count": commodities.size(),
		"sanitized_commodity_count": commodities.size(),
		"raw_recipe_count": recipes.size(),
		"sanitized_recipe_count": recipes.size(),
		"discovered_categories": valid_categories,
		"discovered_models": valid_models
	}

	# -------------------------------------------------------------
	# 1. COMMODITY INTEGRITY AUDIT
	# -------------------------------------------------------------
	for item_id in commodities.keys():
		var item = commodities[item_id]
		if not item is Dictionary:
			report["errors"].append("Commodity '%s' is not a Dictionary." % item_id)
			report["is_clean"] = false
			continue

		# Category check against discovered directory tokens
		var cat: String = item.get("category", "").to_upper()
		if not valid_categories.has(cat):
			report["errors"].append("Commodity '%s' has unrecognised category '%s' (not found on disk)" % [item_id, cat])
			report["is_clean"] = false

		# Base cost check (warning only if present and non-positive)
		if item.has("base_cost") and float(item["base_cost"]) <= 0.0:
			report["warnings"].append("Commodity '%s' has zero or negative base_cost." % item_id)

		# Impact activations check against discovered models
		var activations = item.get("impact_activations", {})
		if activations is Dictionary:
			for verb_key in activations.keys():
				var act_list = activations[verb_key]
				if act_list is Array:
					for impact in act_list:
						if impact is Dictionary:
							var model: String = impact.get("model", "")
							if not valid_models.has(model):
								report["errors"].append("Commodity '%s' [%s] references unsupported model: '%s'" % [item_id, verb_key, model])
								report["is_clean"] = false

	# -------------------------------------------------------------
	# 2. RECIPE INTEGRITY AUDIT
	# -------------------------------------------------------------
	for recipe_id in recipes.keys():
		var recipe = recipes[recipe_id]
		if not recipe is Dictionary:
			report["errors"].append("Recipe '%s' is not a Dictionary." % recipe_id)
			report["is_clean"] = false
			continue

		var output_item: String = recipe.get("output_item", "")
		if output_item == "":
			report["errors"].append("Recipe '%s' defines no output_item." % recipe_id)
			report["is_clean"] = false
		elif not commodities.has(output_item):
			report["errors"].append("Recipe '%s' outputs '%s', which does not exist in commodity_registry!" % [recipe_id, output_item])
			report["is_clean"] = false

		if float(recipe.get("output_yield_units", 0.0)) <= 0.0:
			report["errors"].append("Recipe '%s' has zero or negative output_yield_units." % recipe_id)
			report["is_clean"] = false

		var inputs = recipe.get("inputs", {})
		if not inputs is Dictionary or inputs.is_empty():
			report["warnings"].append("Recipe '%s' defines no inputs." % recipe_id)
		else:
			for ing_id in inputs.keys():
				if not commodities.has(ing_id):
					report["errors"].append("Recipe '%s' requires input ingredient '%s', which is NOT in commodity_registry!" % [recipe_id, ing_id])
					report["is_clean"] = false
				elif float(inputs[ing_id]) <= 0.0:
					report["errors"].append("Recipe '%s' requires zero or negative quantity for ingredient '%s'." % [recipe_id, ing_id])
					report["is_clean"] = false

	_print_summary(report)
	if write_to_disk:
		_write_log_to_disk(report)

	return report

## Sanitizes registry by stripping invalid entries
static func sanitize_and_audit(world_state: Dictionary, write_to_disk: bool = true) -> Dictionary:
	var raw_commodities: Dictionary = world_state.get("commodity_registry", {})
	var raw_recipes: Dictionary = world_state.get("recipe_registry", {})
	var valid_categories: Array = get_discovered_categories()
	var valid_models: Array = get_discovered_models()

	var valid_commodities: Dictionary = {}
	var valid_recipes: Dictionary = {}

	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"is_clean": true,
		"errors": [],
		"warnings": [],
		"commodity_count": raw_commodities.size(),
		"recipe_count": raw_recipes.size(),
		"raw_commodity_count": raw_commodities.size(),
		"raw_recipe_count": raw_recipes.size(),
		"sanitized_commodity_count": 0,
		"sanitized_recipe_count": 0,
		"discovered_categories": valid_categories,
		"discovered_models": valid_models
	}

	# 1. Sanitize Commodities
	for item_id in raw_commodities.keys():
		var item = raw_commodities[item_id]
		var is_valid = true

		var cat: String = item.get("category", "").to_upper()
		if not valid_categories.has(cat):
			report["errors"].append("Commodity '%s' omitted: category '%s' not found on disk." % [item_id, cat])
			is_valid = false

		var activations = item.get("impact_activations", {})
		if activations is Dictionary:
			for verb_key in activations.keys():
				var act_list = activations[verb_key]
				if act_list is Array:
					for impact in act_list:
						if impact is Dictionary:
							var model: String = impact.get("model", "")
							if not valid_models.has(model):
								report["errors"].append("Commodity '%s' omitted: unsupported model '%s'" % [item_id, model])
								is_valid = false

		if is_valid:
			valid_commodities[item_id] = item
		else:
			report["is_clean"] = false

	# 2. Sanitize Recipes
	for recipe_id in raw_recipes.keys():
		var recipe = raw_recipes[recipe_id]
		var is_valid = true

		var output_item: String = recipe.get("output_item", "")
		if output_item == "" or not valid_commodities.has(output_item):
			report["errors"].append("Recipe '%s' omitted: output '%s' not in valid commodities." % [recipe_id, output_item])
			is_valid = false

		if float(recipe.get("output_yield_units", 0.0)) <= 0.0:
			report["errors"].append("Recipe '%s' omitted: non-positive yield." % recipe_id)
			is_valid = false

		var inputs = recipe.get("inputs", {})
		if not inputs is Dictionary or inputs.is_empty():
			report["warnings"].append("Recipe '%s' has no inputs." % recipe_id)
		else:
			for ing_id in inputs.keys():
				if not valid_commodities.has(ing_id):
					report["errors"].append("Recipe '%s' omitted: input '%s' not in valid commodities." % [recipe_id, ing_id])
					is_valid = false
				elif float(inputs[ing_id]) <= 0.0:
					report["errors"].append("Recipe '%s' omitted: non-positive quantity for '%s'." % [recipe_id, ing_id])
					is_valid = false

		if is_valid:
			valid_recipes[recipe_id] = recipe
		else:
			report["is_clean"] = false

	report["sanitized_commodity_count"] = valid_commodities.size()
	report["sanitized_recipe_count"] = valid_recipes.size()

	world_state["commodity_registry"] = valid_commodities
	world_state["recipe_registry"] = valid_recipes

	_print_summary(report)
	if write_to_disk:
		_write_log_to_disk(report)

	return report

static func _print_summary(report: Dictionary) -> void:
	print("\n=======================================================")
	print("       SYSTEM CATALOG AUDIT & SANITIZATION             ")
	print("=======================================================")
	var raw_c = report.get("raw_commodity_count", report.get("commodity_count", 0))
	var san_c = report.get("sanitized_commodity_count", raw_c)
	var raw_r = report.get("raw_recipe_count", report.get("recipe_count", 0))
	var san_r = report.get("sanitized_recipe_count", raw_r)

	print("  Discovered Categories: ", report.get("discovered_categories", []))
	print("  Discovered Models:     ", report.get("discovered_models", []))
	print("  Commodities: %d on disk  ->  %d surfaced to player" % [raw_c, san_c])
	print("  Recipes:     %d on disk  ->  %d surfaced to player" % [raw_r, san_r])
	print("  Status:      ", "100% CLEAN" if report["is_clean"] else "ISSUES DETECTED & ISOLATED")

	if not report["errors"].is_empty():
		print("\n  [!] ISOLATED ITEMS (Hidden from player):")
		for err in report["errors"]:
			print("    ⚠️  ", err)

	print("=======================================================\n")

static func _write_log_to_disk(report: Dictionary) -> void:
	var file = FileAccess.open("user://catalog_audit.log", FileAccess.WRITE)
	if file:
		var raw_c = report.get("raw_commodity_count", report.get("commodity_count", 0))
		var san_c = report.get("sanitized_commodity_count", raw_c)
		var raw_r = report.get("raw_recipe_count", report.get("recipe_count", 0))
		var san_r = report.get("sanitized_recipe_count", raw_r)

		file.store_line("CATALOG INTEGRITY AUDIT - " + report.get("timestamp", ""))
		file.store_line("Clean: " + str(report.get("is_clean", false)))
		file.store_line("Categories Found: " + str(report.get("discovered_categories", [])))
		file.store_line("Models Discovered: " + str(report.get("discovered_models", [])))
		file.store_line("Commodities Surfaced: %d / %d" % [san_c, raw_c])
		file.store_line("Recipes Surfaced: %d / %d" % [san_r, raw_r])
		file.store_line("\nISOLATED DEFECTS:")
		for err in report.get("errors", []):
			file.store_line("- " + err)
		file.close()

# =============================================================================
# 2. N-TIER HIERARCHY PROPERTY AUDITOR
# =============================================================================

## Audits all N-tier structures and traces property settings to their defining files
static func audit_hierarchy_properties(
	root_dir: String = COMMODITIES_ROOT, 
	write_to_disk: bool = true
) -> Dictionary:
	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"root_dir": root_dir,
		"total_files_scanned": 0,
		"unique_properties_discovered": [],
		"property_distribution": {},
		"directory_tree": {}
	}
	
	if not DirAccess.dir_exists_absolute(root_dir):
		push_warning("[CATALOG VALIDATOR] Directory not found for audit: %s" % root_dir)
		return report

	_audit_node_recursive(root_dir, [], report["directory_tree"], report)
	report["unique_properties_discovered"].sort()

	_print_hierarchy_property_summary(report)

	if write_to_disk:
		_write_hierarchy_log_to_disk(report)

	return report

static func _audit_node_recursive(
	current_path: String, 
	parent_inherited_keys: Array, 
	out_tree_node: Dictionary, 
	report: Dictionary
) -> void:
	var dir = DirAccess.open(current_path)
	if not dir:
		return

	var folder_name: String = current_path.get_file()
	if folder_name == "":
		folder_name = "ROOT"

	out_tree_node["folder"] = folder_name
	out_tree_node["path"] = current_path
	out_tree_node["files"] = {}
	out_tree_node["subfolders"] = {}

	var local_keys: Array = []
	var cumulative_keys: Array = parent_inherited_keys.duplicate()

	# 1. Scan JSON files in this directory tier
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_file_path = current_path.path_join(file_name)
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var content = _read_json_file(full_file_path)
			if content is Dictionary:
				report["total_files_scanned"] += 1
				var file_defined_keys = _extract_flattened_keys(content)
				
				# Identify which properties override ancestral settings
				var overrides = []
				for k in file_defined_keys:
					if parent_inherited_keys.has(k):
						overrides.append(k)
					if not local_keys.has(k):
						local_keys.append(k)
					if not cumulative_keys.has(k):
						cumulative_keys.append(k)
					if not report["unique_properties_discovered"].has(k):
						report["unique_properties_discovered"].append(k)
						
					if not report["property_distribution"].has(k):
						report["property_distribution"][k] = []
					report["property_distribution"][k].append(full_file_path)

				out_tree_node["files"][file_name] = {
					"keys": file_defined_keys,
					"overrides": overrides
				}
		file_name = dir.get_next()
	dir.list_dir_end()

	# 2. Recurse down subdirectories passing accumulated keys
	dir.list_dir_begin()
	var sub_entry = dir.get_next()
	while sub_entry != "":
		var sub_path = current_path.path_join(sub_entry)
		if dir.current_is_dir() and not sub_entry.begins_with("."):
			var child_node: Dictionary = {}
			out_tree_node["subfolders"][sub_entry] = child_node
			_audit_node_recursive(sub_path, cumulative_keys, child_node, report)
		sub_entry = dir.get_next()
	dir.list_dir_end()

## Flattens nested dictionary keys (e.g. decay_properties.shelf_life_ticks)
static func _extract_flattened_keys(data: Dictionary, prefix: String = "") -> Array:
	var keys: Array = []
	for k in data.keys():
		var full_key = (prefix + "." + str(k)) if prefix != "" else str(k)
		keys.append(full_key)
		if data[k] is Dictionary and k != "_meta":
			keys.append_array(_extract_flattened_keys(data[k], full_key))
	return keys

static func _read_json_file(file_path: String) -> Variant:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return null
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		return json.data
	return null

static func _print_hierarchy_property_summary(report: Dictionary) -> void:
	print("\n=======================================================")
	print("       N-TIER HIERARCHY PROPERTY AUDIT                 ")
	print("=======================================================")
	print("  Root Scanned:         ", report["root_dir"])
	print("  Files Analyzed:       ", report["total_files_scanned"])
	print("  Unique Properties:    ", report["unique_properties_discovered"].size())
	print("\n  [PROPERTY CATALOG & DEFINITION SOURCES]")

	for prop in report["unique_properties_discovered"]:
		var sources: Array = report["property_distribution"].get(prop, [])
		print("    • %-32s (Set in %d file%s)" % [prop, sources.size(), "s" if sources.size() != 1 else ""])
		for src in sources:
			var short_path = src.replace("res://data_modules/core/", "")
			print("        └─ %s" % short_path)

	print("\n  [TIER STRUCTURE TREE]")
	_print_tree_node_console(report["directory_tree"], 0)
	print("=======================================================\n")

static func _print_tree_node_console(node: Dictionary, depth: int) -> void:
	var indent = "  ".repeat(depth)
	print("%s📂 %s/" % [indent, node.get("folder", "")])

	var files: Dictionary = node.get("files", {})
	for f in files.keys():
		var f_info = files[f]
		var keys_count = f_info["keys"].size()
		var override_count = f_info["overrides"].size()
		var extra = ""
		if override_count > 0:
			extra = " [OVERRIDES: %s]" % ", ".join(f_info["overrides"])
		print("%s   📄 %s -> %d properties%s" % [indent, f, keys_count, extra])

	var subfolders: Dictionary = node.get("subfolders", {})
	for sf in subfolders.keys():
		_print_tree_node_console(subfolders[sf], depth + 1)

static func _write_hierarchy_log_to_disk(report: Dictionary) -> void:
	var file = FileAccess.open("user://n_tier_hierarchy_audit.log", FileAccess.WRITE)
	if not file:
		return

	file.store_line("N-TIER HIERARCHY AUDIT REPORT - " + report["timestamp"])
	file.store_line("Root: " + report["root_dir"])
	file.store_line("Total Files: " + str(report["total_files_scanned"]))
	file.store_line("Unique Properties: " + str(report["unique_properties_discovered"].size()))
	file.store_line("\n=======================================================")
	file.store_line("PROPERTY SETTINGS AND LOCATIONS")
	file.store_line("=======================================================")

	for prop in report["unique_properties_discovered"]:
		var sources: Array = report["property_distribution"].get(prop, [])
		file.store_line("\nPROPERTY: " + prop)
		for src in sources:
			file.store_line("  - " + src)

	file.close()

# =============================================================================
# 3. CODEBASE PROPERTY USAGE AUDITOR
# =============================================================================

## Cross-references defined catalog properties against actual codebase usage
static func audit_property_usage(
	catalogs_root: String = COMMODITIES_ROOT, 
	code_scan_roots: Array = ["res://systems/", "res://scenes/", "res://data_modules/"], 
	write_to_disk: bool = true
) -> Dictionary:
	# 1. First, discover all properties declared across the catalogs
	var catalog_audit = audit_hierarchy_properties(catalogs_root, false)
	var defined_properties: Array = catalog_audit["unique_properties_discovered"]
	
	var property_tokens: Dictionary = {}
	for p in defined_properties:
		var parts = p.split(".")
		var leaf_token = parts[-1]
		if leaf_token != "_meta":
			property_tokens[leaf_token] = p

	# 2. Gather all codebase script/scene/data text
	var code_files: Dictionary = {}
	for root_dir in code_scan_roots:
		_gather_source_files_recursive(root_dir, code_files)

	var usage_report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"total_defined_properties": property_tokens.size(),
		"total_source_files_scanned": code_files.size(),
		"referenced_properties": {},
		"orphaned_properties": []
	}

	# 3. Search codebase for references to each property token
	for token in property_tokens.keys():
		var occurrences: Array = []
		
		var pattern_get = ".get(\"%s\"" % token
		var pattern_bracket = "[\"%s\"]" % token
		var pattern_brace = "{%s}" % token
		var pattern_json_key = "\"%s\":" % token
		
		for file_path in code_files.keys():
			if file_path.begins_with(catalogs_root):
				continue
				
			var lines: PackedStringArray = code_files[file_path]
			for i in range(lines.size()):
				var line_text = lines[i]
				if line_text.contains(pattern_get) or line_text.contains(pattern_bracket) or line_text.contains(pattern_brace) or line_text.contains(pattern_json_key):
					occurrences.append({
						"file": file_path,
						"line": i + 1,
						"snippet": line_text.strip_edges()
					})
					
		if not occurrences.is_empty():
			usage_report["referenced_properties"][token] = {
				"full_property_path": property_tokens[token],
				"defined_in": catalog_audit["property_distribution"].get(property_tokens[token], []),
				"references": occurrences
			}
		else:
			usage_report["orphaned_properties"].append({
				"token": token,
				"full_property_path": property_tokens[token],
				"defined_in": catalog_audit["property_distribution"].get(property_tokens[token], [])
			})

	_print_usage_audit_summary(usage_report)
	if write_to_disk:
		_write_usage_log_to_disk(usage_report)

	return usage_report

static func _gather_source_files_recursive(path: String, out_files: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir = DirAccess.open(path)
	if not dir:
		return
		
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var full_path = path.path_join(entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			_gather_source_files_recursive(full_path, out_files)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn") or entry.ends_with(".json"):
			var file = FileAccess.open(full_file_path_safe(full_path), FileAccess.READ)
			if file:
				out_files[full_path] = file.get_as_text().split("\n")
		entry = dir.get_next()
	dir.list_dir_end()

static func full_file_path_safe(p: String) -> String:
	return p

static func _print_usage_audit_summary(report: Dictionary) -> void:
	print("\n=======================================================")
	print("       CATALOG PROPERTY USAGE & CODE REFERENCE AUDIT   ")
	print("=======================================================")
	print("  Source Files Scanned:       ", report["total_source_files_scanned"])
	print("  Total Properties Defined:   ", report["total_defined_properties"])
	print("  Actively Consumed:          ", report["referenced_properties"].size())
	print("  Orphaned / Unused:          ", report["orphaned_properties"].size())
	
	if not report["referenced_properties"].is_empty():
		print("\n  [ACTIVE CONSUMPTION TRACE]")
		for token in report["referenced_properties"].keys():
			var info = report["referenced_properties"][token]
			print("    • %s  (Referenced in %d locations)" % [token, info["references"].size()])
			for ref in info["references"]:
				print("        └─ %s:%d -> %s" % [ref["file"].replace("res://", ""), ref["line"], ref["snippet"]])

	if not report["orphaned_properties"].is_empty():
		print("\n  ⚠️  [ORPHANED / UNUSED PROPERTIES (Never read in code or UI)]:")
		for orphan in report["orphaned_properties"]:
			print("    ❌ %-25s Defined in: %s" % [orphan["token"], orphan["defined_in"]])
			
	print("=======================================================\n")

static func _write_usage_log_to_disk(report: Dictionary) -> void:
	var file = FileAccess.open("user://catalog_property_usage.log", FileAccess.WRITE)
	if not file:
		return

	file.store_line("CATALOG PROPERTY USAGE AUDIT - " + report["timestamp"])
	file.store_line("Files Scanned: " + str(report["total_source_files_scanned"]))
	file.store_line("Referenced: " + str(report["referenced_properties"].size()))
	file.store_line("Orphaned: " + str(report["orphaned_properties"].size()))
	
	file.store_line("\n--- ACTIVE CODE REFERENCES ---")
	for token in report["referenced_properties"].keys():
		var info = report["referenced_properties"][token]
		file.store_line("\nPROPERTY: " + token + " (" + info["full_property_path"] + ")")
		for ref in info["references"]:
			file.store_line("  - %s:%d | %s" % [ref["file"], ref["line"], ref["snippet"]])

	file.store_line("\n--- ORPHANED / UNREFERENCED PROPERTIES ---")
	for orphan in report["orphaned_properties"]:
		file.store_line("UNUSED: " + orphan["token"] + " | Defined in: " + str(orphan["defined_in"]))

	file.close()

# =============================================================================
# 4. SOCIETY & MANIFEST CROSS-REFERENCE AUDITOR
# =============================================================================

## Audits all inter-manifest relationships (jobs, labels, archetypes, tenancies, education)
static func validate_society_manifests() -> Dictionary:
	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"is_clean": true,
		"errors": [],
		"warnings": [],
		"jobs_scanned": 0,
		"archetypes_scanned": 0,
		"tenancies_scanned": 0,
		"labels_scanned": 0
	}

	# 1. Harvest Core System Labels (db_labels_en_gb.json)
	var labels_dict: Dictionary = {} # domain -> Set of codes
	var db_labels_path := "res://data_modules/core/localization/db_labels_en_gb.json"
	if FileAccess.file_exists(db_labels_path):
		var raw_labels = MANIFEST_MGR.load_json_file(db_labels_path)
		for entry in raw_labels.get("labels", []):
			var d: String = str(entry.get("domain", "")).to_upper()
			var c: String = str(entry.get("code", "")).to_upper()
			if not labels_dict.has(d):
				labels_dict[d] = {}
			labels_dict[d][c] = true
			report["labels_scanned"] += 1
	else:
		report["errors"].append("Missing core labels baseline at: %s" % db_labels_path)
		report["is_clean"] = false
		return report

	var has_label := func(domain: String, code: String) -> bool:
		return labels_dict.has(domain.to_upper()) and labels_dict[domain.to_upper()].has(code.to_upper())

	# 2. Audit Job Definitions
	var job_defs: Dictionary = {}
	if MANIFEST_MGR.has_module("job_definitions"):
		var raw_jobs = MANIFEST_MGR.load_module("job_definitions")
		job_defs = raw_jobs.get("roles", {})
		report["jobs_scanned"] = job_defs.size()

		for job_code in job_defs.keys():
			var job: Dictionary = job_defs[job_code]
			
			if not has_label.call("ROLE_TITLE", job_code):
				report["errors"].append("job_definitions role '%s' is missing from db_labels under 'ROLE_TITLE'!" % job_code)
				report["is_clean"] = false

			var c_cls: String = str(job.get("contract_class", "FORMAL_LEGAL"))
			if not has_label.call("CONTRACT_CLASS", c_cls):
				report["errors"].append("job_definitions role '%s' references unknown CONTRACT_CLASS '%s'!" % [job_code, c_cls])
				report["is_clean"] = false

			var edu: String = str(job.get("education_required", "NO_FORMAL"))
			if not has_label.call("EDUCATION_LEVEL", edu):
				report["errors"].append("job_definitions role '%s' references unknown EDUCATION_LEVEL '%s'!" % [job_code, edu])
				report["is_clean"] = false

			if job.has("hourly_rate_range"):
				var r: Array = job["hourly_rate_range"]
				if r.size() < 2 or float(r[0]) > float(r[1]) or float(r[0]) <= 0.0:
					report["errors"].append("job_definitions role '%s' has invalid hourly_rate_range %s!" % [job_code, str(r)])
					report["is_clean"] = false
	else:
		report["errors"].append("Scenario manifest missing 'job_definitions' module declaration!")
		report["is_clean"] = false

	# 3. Audit Archetypes against Job Definitions & System Labels
	if MANIFEST_MGR.has_module("archetypes"):
		var archetypes: Dictionary = MANIFEST_MGR.load_module("archetypes")
		for arch_key in archetypes.keys():
			if arch_key in ["_meta", "setup"]:
				continue
			report["archetypes_scanned"] += 1
			var arch: Dictionary = archetypes[arch_key]

			var housing: Dictionary = arch.get("housing_profile", {})
			var res_type: String = str(housing.get("residence_type", "NONE"))
			if res_type != "NONE" and not has_label.call("RESIDENCE_TYPE", res_type):
				report["errors"].append("Archetype '%s' references unknown RESIDENCE_TYPE '%s'!" % [arch_key, res_type])
				report["is_clean"] = false

			var tenure: String = str(housing.get("tenure_type", "NONE"))
			if tenure != "NONE" and not has_label.call("TENURE_TYPE", tenure):
				report["errors"].append("Archetype '%s' references unknown TENURE_TYPE '%s'!" % [arch_key, tenure])
				report["is_clean"] = false

			if arch.has("institution_profile"):
				var inst: Dictionary = arch["institution_profile"]
				for slot in inst.get("staffing_roster", []):
					var j_id: String = str(slot.get("job_id", ""))
					if not job_defs.has(j_id):
						report["errors"].append("Archetype '%s' roster references unknown job_id '%s' (not in job_definitions.json)!" % [arch_key, j_id])
						report["is_clean"] = false

				var serves: String = str(inst.get("serves_role", ""))
				if not serves.is_empty() and not has_label.call("ROLE_TITLE", serves):
					report["warnings"].append("Archetype '%s' serves_role '%s' not explicitly in db_labels ROLE_TITLE." % [arch_key, serves])
	else:
		report["errors"].append("Scenario manifest missing 'archetypes' module declaration!")
		report["is_clean"] = false

	# 4. Audit Building Classes against Job Definitions
	if MANIFEST_MGR.has_module("building_classes"):
		var b_classes: Dictionary = MANIFEST_MGR.load_module("building_classes")
		for group_key in ["commercial_tenants", "industrial_tenants", "civic_tenants"]:
			var group: Dictionary = b_classes.get(group_key, {})
			for ten_key in group.keys():
				report["tenancies_scanned"] += 1
				var tenancy: Dictionary = group[ten_key]

				if not has_label.call("ESTABLISHMENT_CATEGORY", ten_key):
					report["warnings"].append("Building tenancy '%s' has no matching ESTABLISHMENT_CATEGORY in db_labels." % ten_key)

				for slot in tenancy.get("staffing_roster", []):
					var j_id: String = str(slot.get("job_id", ""))
					if not job_defs.has(j_id):
						report["errors"].append("Tenancy '%s' roster references unknown job_id '%s'!" % [ten_key, j_id])
						report["is_clean"] = false
	else:
		report["errors"].append("Scenario manifest missing 'building_classes' module declaration!")
		report["is_clean"] = false

	# 5. Audit Education Model in Demographics
	if MANIFEST_MGR.has_module("demographics"):
		var demo: Dictionary = MANIFEST_MGR.load_module("demographics")
		var edu_model: Dictionary = demo.get("education_attainment_model", {})
		for tier in edu_model.get("tiers", []):
			var code: String = str(tier.get("code", ""))
			if not has_label.call("EDUCATION_LEVEL", code):
				report["errors"].append("demographics education_attainment_model tier '%s' missing from db_labels!" % code)
				report["is_clean"] = false
	else:
		report["errors"].append("Scenario manifest missing 'demographics' module declaration!")
		report["is_clean"] = false

	_print_society_summary(report)
	return report

static func _print_society_summary(report: Dictionary) -> void:
	print("\n=======================================================")
	print("     SOCIETY MANIFEST & CROSS-REFERENCE AUDIT         ")
	print("=======================================================")
	print("  Labels Baseline Scanned: ", report["labels_scanned"])
	print("  Job Definitions Scanned: ", report["jobs_scanned"])
	print("  Archetypes Scanned:      ", report["archetypes_scanned"])
	print("  Tenancies Scanned:       ", report["tenancies_scanned"])
	print("  Integrity Status:        ", "100% CLEAN" if report["is_clean"] else "INTEGRITY DEFECTS FOUND")

	if not report["errors"].is_empty():
		print("\n  [!] CRITICAL DEFECTS (%d):" % report["errors"].size())
		for err in report["errors"]:
			print("    ❌ ", err)

	if not report["warnings"].is_empty():
		print("\n  [*] WARNINGS (%d):" % report["warnings"].size())
		for warn in report["warnings"]:
			print("    ⚠️  ", warn)

	print("=======================================================\n")