# res://scripts/world/district_namer.gd
class_name DistrictNamer
extends RefCounted

static var _lexicon: Dictionary = {}

static func load_lexicon(file_path: String = "res://data_modules/core/spatial/districts/names/en_gb.json") -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_lexicon = json.data
			return
	push_error("[DistrictNamer] Failed to load naming lexicon from: %s" % file_path)

static func generate_district_name(district_type: String, seed_id: String, grid_x: int, grid_z: int) -> String:
	if _lexicon.is_empty():
		load_lexicon()
		
	# 1. Unique Civic Sites
	var civic_sites: Dictionary = _lexicon.get("civic_sites", {})
	if civic_sites.has(district_type):
		var options: Array = civic_sites[district_type]
		var hash_val = abs(("%s:%s:%d:%d" % [seed_id, district_type, grid_x, grid_z]).hash())
		return options[hash_val % options.size()]

	# 2. Procedural Combinations
	var prefixes: Dictionary = _lexicon.get("prefixes", {})
	var suffixes: Dictionary = _lexicon.get("suffixes", {})
	
	var prefix_list: Array = prefixes.get(district_type, prefixes.get("suburban_low_density", ["District"]))
	var suffix_list: Array = suffixes.get(district_type, suffixes.get("suburban_low_density", ["Area"]))
	
	var combined_hash = abs(("%s:%s:%d:%d" % [seed_id, district_type, grid_x, grid_z]).hash())
	var prefix: String = prefix_list[combined_hash % prefix_list.size()]
	var suffix: String = suffix_list[(combined_hash / prefix_list.size()) % suffix_list.size()]
	
	if prefix == suffix:
		var fallback_tpl: String = _lexicon.get("grammar", {}).get("duplicate_fallback", "{prefix} Common")
		return fallback_tpl.replace("{prefix}", prefix)
		
	var template: String = _lexicon.get("grammar", {}).get("format", "{prefix} {suffix}")
	return template.replace("{prefix}", prefix).replace("{suffix}", suffix)