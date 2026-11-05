# res://systems/commodity_manager.gd
class_name CommodityManager extends RefCounted

## Recursively scans folders and builds the inheritance registry
static func load_hierarchical_commodities(root_dir_path: String) -> Dictionary:
	var registry: Dictionary = {}
	_scan_directory_recursive(root_dir_path, root_dir_path, {}, {}, registry)
	return registry

static func _scan_directory_recursive(
	root_path: String,
	current_path: String, 
	inherited_traits: Dictionary, 
	inherited_activations: Dictionary, 
	out_registry: Dictionary
) -> void:
	var dir = DirAccess.open(current_path)
	if not dir:
		return

	var current_scope_traits = inherited_traits.duplicate(true)
	var current_scope_activations = inherited_activations.duplicate(true)

	# Extract relative folder taxonomy segments
	var rel_path := current_path.trim_prefix(root_path).trim_prefix("/")
	var path_segments: Array[String] = []
	for part in rel_path.split("/", false):
		var clean_part := part.strip_edges().to_upper()
		if not clean_part.is_empty():
			path_segments.append(clean_part)
	
	# -------------------------------------------------------------
	# 1. READ BASELINE TRAITS (_base.json)
	# -------------------------------------------------------------
	var base_file = current_path.path_join("_base.json")
	if FileAccess.file_exists(base_file):
		var base_data = _read_json(base_file)
		_tag_stocking_provenance(base_data, base_file)
		_deep_merge_dict(current_scope_traits, base_data)

	# -------------------------------------------------------------
	# 2. INGEST LOCAL VERB IMPACT FOLDERS (buy/, sell/, make/)
	# -------------------------------------------------------------
	var local_verb_activations = _load_verb_impact_files(current_path)
	_merge_activations(current_scope_activations, local_verb_activations)

	# -------------------------------------------------------------
	# 3. READ LEAF PROFILE (item_profile.json or recipe_profile.json)
	# -------------------------------------------------------------
	var leaf_file = ""
	if FileAccess.file_exists(current_path.path_join("item_profile.json")):
		leaf_file = current_path.path_join("item_profile.json")
	elif FileAccess.file_exists(current_path.path_join("recipe_profile.json")):
		leaf_file = current_path.path_join("recipe_profile.json")

	if leaf_file != "":
		var leaf_data = _read_json(leaf_file)
		_tag_stocking_provenance(leaf_data, leaf_file)
		var final_item = current_scope_traits.duplicate(true)
		_deep_merge_dict(final_item, leaf_data)
		final_item["impact_activations"] = current_scope_activations.duplicate(true)

		# Use 'id' from JSON, fallback to uppercase folder name
		var item_id: String = str(final_item.get("id", current_path.get_file())).to_upper()
		final_item["id"] = item_id
		final_item["source_path"] = leaf_file
		_apply_path_taxonomy(final_item, path_segments, leaf_file)
		out_registry[item_id] = final_item

	# -------------------------------------------------------------
	# 4. RECURSE INTO SUBDIRECTORIES
	# -------------------------------------------------------------
	dir.list_dir_begin()
	var entry_name = dir.get_next()
	while entry_name != "":
		var sub_path = current_path.path_join(entry_name)
		if dir.current_is_dir() and not entry_name.begins_with("."):
			var upper_name = entry_name.to_upper()
			# Skip impact verb folders from being scanned as commodity tiers
			if upper_name != "BUY" and upper_name != "SELL" and upper_name != "MAKE" and upper_name != "ORDER" and upper_name != "PAY" and upper_name != "RECEIVE":
				_scan_directory_recursive(root_path, sub_path, current_scope_traits, current_scope_activations, out_registry)
		elif entry_name.ends_with(".json") and entry_name != "_base.json" and entry_name != "item_profile.json" and entry_name != "recipe_profile.json":
			# Flat item support (e.g. beer.json)
			var flat_data = _read_json(sub_path)
			if flat_data is Dictionary and not flat_data.is_empty():
				_tag_stocking_provenance(flat_data, sub_path)
				var flat_item = current_scope_traits.duplicate(true)
				_deep_merge_dict(flat_item, flat_data)
				flat_item["impact_activations"] = current_scope_activations.duplicate(true)
				var flat_id: String = str(flat_item.get("id", entry_name.get_basename())).to_upper()
				flat_item["id"] = flat_id

				_apply_path_taxonomy(flat_item, path_segments, leaf_file)
				out_registry[flat_id] = flat_item

		entry_name = dir.get_next()
	dir.list_dir_end()

## Derives category and taxonomy path from directory segments if not explicitly authored in JSON
static func _apply_path_taxonomy(item: Dictionary, raw_segments: Array[String], source_file_path: String) -> void:
	var segments: Array[String] = raw_segments.duplicate()
	
	# Strip root container folder if present
	if not segments.is_empty() and (segments[0] == "COMMODITIES" or segments[0] == "CORE"):
		segments.remove_at(0)
	if not segments.is_empty() and segments[0] == "COMMODITIES":
		segments.remove_at(0)

	item["taxonomy_path"] = segments.duplicate()

	# 1. Resolve Category (Trade Department)
	if item.has("category") and not str(item["category"]).strip_edges().is_empty():
		item["category"] = str(item["category"]).strip_edges().to_upper()
	else:
		assert(not segments.is_empty(), 
			"FATAL: [CommodityManager] Item at '%s' has no explicit category and is placed directly in root with no folder taxonomy!" % source_file_path)

		var top_seg := segments[0]
		# If the top segment is the broad archetype, step down to the trade department
		if (top_seg == "CONSUMABLES" or top_seg == "DURABLES" or top_seg == "SERVICES") and segments.size() >= 2:
			item["category"] = segments[1]
		else:
			item["category"] = top_seg

	# 2. Resolve Sub-Category (Shelf / Specific grouping)
	if item.has("sub_category") and not str(item["sub_category"]).strip_edges().is_empty():
		item["sub_category"] = str(item["sub_category"]).strip_edges().to_upper()
	else:
		var top_seg := segments[0]
		if (top_seg == "CONSUMABLES" or top_seg == "DURABLES" or top_seg == "SERVICES"):
			if segments.size() >= 3:
				item["sub_category"] = segments[2]
			else:
				item["sub_category"] = ""
		elif segments.size() >= 2:
			item["sub_category"] = segments[1]
		else:
			item["sub_category"] = ""

## Stamps stocking_rules blocks with their declaring file path for developer forensics
static func _tag_stocking_provenance(data: Dictionary, file_path: String) -> void:
	if data.has("stocking_rules") and data["stocking_rules"] is Dictionary:
		data["stocking_rules"]["_auth_origin"] = file_path

# -------------------------------------------------------------
# RUNTIME GAMEPLAY API
# -------------------------------------------------------------

## Retrieves all commodities available for a specific venue or store.
## Pure, lean runtime evaluation.
static func get_available_commodities_for_venue(
	venue_data: Dictionary, 
	world_state: Dictionary, 
	include_off_book: bool = false
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var registry: Dictionary = world_state.get("commodity_registry", {})
	if registry.is_empty():
		return result

	# Check debug override
	var debug_rules: Dictionary = world_state.get("debug_rules", {})
	if bool(debug_rules.get("all_items_in_all_stores", false)):
		for item_id in registry.keys():
			var item_def = registry[item_id]
			if item_def is Dictionary:
				result.append(item_def)
		return result

	# Extract venue permissions
	var venue_roles: Array[String] = []
	var primary_arch: String = str(venue_data.get("archetype", "")).to_upper()
	if not primary_arch.is_empty():
		venue_roles.append(primary_arch)

	for group in venue_data.get("taxonomic_groups", []):
		var g_token: String = str(group).to_upper()
		if not g_token.is_empty() and not venue_roles.has(g_token):
			venue_roles.append(g_token)

	for cat in venue_data.get("trade_categories", []):
		var cat_token: String = str(cat).to_upper()
		if not cat_token.is_empty() and not venue_roles.has(cat_token):
			venue_roles.append(cat_token)

	for item_id in registry.keys():
		var item: Dictionary = registry[item_id]
		var rules: Dictionary = item.get("stocking_rules", {})

		# 1. Check Open Access
		var open_rules = rules.get("openly_stocked_in", null)
		if _matches_role(open_rules, venue_roles):
			result.append(item)
			continue

		# 2. Check Off-Book Access (if requested)
		if include_off_book:
			var possible_rules = rules.get("possibly_stocked_in", null)
			if _matches_role(possible_rules, venue_roles):
				result.append(item)
				continue

		# 3. Fallback: Legacy Category Matching (if no explicit stocking_rules exist)
		if rules.is_empty():
			var item_cat: String = str(item.get("category", "")).to_upper()
			var item_subcat: String = str(item.get("sub_category", "")).to_upper()
			for r in venue_roles:
				if r == item_cat or r == item_subcat:
					result.append(item)
					break

	return result

static func _matches_role(rule_definition, venue_roles: Array[String]) -> bool:
	if rule_definition is Dictionary:
		for role in venue_roles:
			if rule_definition.has(role):
				return true
	elif rule_definition is Array:
		for role in venue_roles:
			if rule_definition.has(role):
				return true
	return false

# -------------------------------------------------------------
# INTERNAL MERGE HELPERS
# -------------------------------------------------------------

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
		var sub_path = path.path_join(folder_name)
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var impacts = _read_impacts_in_dir(sub_path)
			if not impacts.is_empty():
				result[folder_name.to_upper()] = impacts
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
		var full_file = verb_path.path_join(file_name)
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data = _read_json(full_file)
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
	if not file:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return json.data
	return {}
