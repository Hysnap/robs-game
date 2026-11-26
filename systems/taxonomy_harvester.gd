# res://systems/taxonomy_harvester.gd
class_name TaxonomyHarvester
extends RefCounted

const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")

## Manifest module keys that are non-taxonomy or pure localization/routing metadata
const EXCLUDED_MODULES: Array[String] = [
	"db_schema",
	"extra_schema_dir",
	"db_labels",
	"ui_strings",
	"lexicon",
	"spatial_lexicon",
	"dialects",
	"startpoint",
	"impact_routing",
	"intel_exposure",
	"ocean_personality",
	"transport_modes",
	"fiscal_regimes",
	"city_configuration"
]

## Harvests all domain taxonomies dynamically from every JSON module registered in the active manifest.
## Returns: Array[Dictionary] where each element is { "domain": String, "code": String, "title": String }
static func harvest_all_taxonomies() -> Array[Dictionary]:
	var harvested: Array[Dictionary] = []
	var seen_keys: Dictionary = {} # "DOMAIN:CODE" -> true

	var manifest: Dictionary = MANIFEST_MANAGER.get_manifest()
	var modules: Dictionary = manifest.get("modules", {})

	for mod_key_raw in modules.keys():
		var mod_key: String = str(mod_key_raw).strip_edges()
		if mod_key.is_empty() or EXCLUDED_MODULES.has(mod_key):
			continue

		var mod_path: String = str(modules[mod_key]).strip_edges()
		if not mod_path.to_lower().ends_with(".json"):
			continue

		var mod_data: Dictionary = MANIFEST_MANAGER.load_module(mod_key)
		_harvest_module_node(mod_data, "", harvested, seen_keys)

	return harvested

static func _harvest_module_node(node: Variant, parent_key: String, out_list: Array[Dictionary], seen: Dictionary) -> void:
	if node is Dictionary:
		var dict: Dictionary = node
		var norm_parent: String = parent_key.strip_edges().to_lower()

		# 1. Establishment Category maps (building_classes tenants & civic_placement_quotas)
		if norm_parent in ["commercial_tenants", "industrial_tenants", "civic_placement_quotas", "civic_institutions", "establishment_templates"]:
			for k in dict.keys():
				var code_str: String = str(k).strip_edges()
				if code_str.is_empty() or code_str.begins_with("_"):
					continue
				var entry = dict[k]
				var title_str: String = code_str.capitalize().replace("_", " ")
				if entry is Dictionary and entry.has("display_name"):
					title_str = str(entry["display_name"]).strip_edges()
				_add_token(out_list, seen, "ESTABLISHMENT_CATEGORY", code_str, title_str)

		# 2. Job Definitions ("roles" map)
		if norm_parent == "roles":
			for role_key in dict.keys():
				var r_code: String = str(role_key).strip_edges()
				if r_code.is_empty() or r_code.begins_with("_"):
					continue
				var r_entry = dict[role_key]
				var r_title: String = r_code.capitalize().replace("_", " ")
				if r_entry is Dictionary and r_entry.has("display_name"):
					r_title = str(r_entry["display_name"]).strip_edges()
				_add_token(out_list, seen, "ROLE_TITLE", r_code, r_title)

		# 3. Cultural Demographics ("ethnicities" & "religion_distribution")
		if norm_parent == "ethnicities":
			for eth_key in dict.keys():
				var eth_code: String = str(eth_key).strip_edges()
				if eth_code.is_empty() or eth_code.begins_with("_"):
					continue
				var eth_entry = dict[eth_key]
				var eth_title: String = eth_code.capitalize().replace("_", " ")
				if eth_entry is Dictionary and eth_entry.has("display_name"):
					eth_title = str(eth_entry["display_name"]).strip_edges()
				_add_token(out_list, seen, "ETHNICITY", eth_code, eth_title)

		if norm_parent == "religion_distribution":
			for rel_key in dict.keys():
				var rel_code: String = str(rel_key).strip_edges()
				if not rel_code.is_empty() and not rel_code.begins_with("_"):
					_add_token(out_list, seen, "RELIGION", rel_code, rel_code.capitalize().replace("_", " "))

		# 4. Education Tiers ("ocean_tier_nudges", "male_probabilities", "female_probabilities")
		if norm_parent in ["ocean_tier_nudges", "male_probabilities", "female_probabilities"]:
			for edu_key in dict.keys():
				var edu_code: String = str(edu_key).strip_edges()
				if not edu_code.is_empty() and not edu_code.begins_with("_"):
					_add_token(out_list, seen, "EDUCATION_LEVEL", edu_code, edu_code.capitalize().replace("_", " "))

		# 5. Kinship Weaving Bonds ("kinship_weaving_rules.bonds")
		if norm_parent == "bonds":
			for bond_key in dict.keys():
				var bond_def = dict[bond_key]
				if bond_def is Dictionary:
					for sub_key in bond_def.keys():
						if str(sub_key).to_lower() == "affinity":
							continue
						var rel_code: String = str(bond_def[sub_key]).strip_edges()
						if not rel_code.is_empty():
							_add_token(out_list, seen, "RELATIONSHIP_TYPE", rel_code, rel_code.capitalize().replace("_", " "))

		# 6. Service & Crime Route Rounds ("rounds")
		if norm_parent == "rounds":
			for rnd_key in dict.keys():
				var rnd_def = dict[rnd_key]
				if not (rnd_def is Dictionary):
					continue
				var svc_code: String = str(rnd_def.get("service_code", rnd_key)).strip_edges()
				if not svc_code.is_empty():
					_add_token(out_list, seen, "SERVICE_CODE", svc_code, svc_code.capitalize().replace("_", " "))
				var t_mode: String = str(rnd_def.get("territory_mode", "")).strip_edges()
				if not t_mode.is_empty():
					_add_token(out_list, seen, "TERRITORY_MODE", t_mode, t_mode.capitalize().replace("_", " "))

		# 7. Scalar field extraction on any nested object
		if dict.has("establishment_category") and dict["establishment_category"] is String:
			var cat_code: String = str(dict["establishment_category"]).strip_edges()
			var cat_title: String = str(dict.get("display_name", cat_code.capitalize().replace("_", " "))).strip_edges()
			_add_token(out_list, seen, "ESTABLISHMENT_CATEGORY", cat_code, cat_title)

		if dict.has("residence_type") and dict["residence_type"] is String:
			var res_code: String = str(dict["residence_type"]).strip_edges().to_upper()
			if not res_code.is_empty() and res_code != "NONE":
				_add_token(out_list, seen, "RESIDENCE_TYPE", res_code, res_code.capitalize().replace("_", " "))

		for role_field in ["role_title", "role", "unemployed_role", "commercial_role", "industrial_role", "job_id"]:
			if dict.has(role_field) and dict[role_field] is String:
				var r_val: String = str(dict[role_field]).strip_edges()
				if not r_val.is_empty():
					_add_token(out_list, seen, "ROLE_TITLE", r_val, r_val.capitalize().replace("_", " "))

		if dict.has("staff_roles") and dict["staff_roles"] is Array:
			for sr in dict["staff_roles"]:
				var sr_code: String = str(sr).strip_edges()
				if not sr_code.is_empty():
					_add_token(out_list, seen, "ROLE_TITLE", sr_code, sr_code.capitalize().replace("_", " "))

		if norm_parent == "education_attainment_model":
			if dict.has("default_code") and dict["default_code"] is String:
				var def_edu: String = str(dict["default_code"]).strip_edges()
				if not def_edu.is_empty():
					_add_token(out_list, seen, "EDUCATION_LEVEL", def_edu, def_edu.capitalize().replace("_", " "))
			if dict.has("tiers") and dict["tiers"] is Array:
				for t_item in dict["tiers"]:
					if t_item is Dictionary and t_item.has("code"):
						var t_code: String = str(t_item["code"]).strip_edges()
						if not t_code.is_empty():
							_add_token(out_list, seen, "EDUCATION_LEVEL", t_code, t_code.capitalize().replace("_", " "))

		# Recurse into child keys (skipping _meta)
		for child_key in dict.keys():
			var ck_str: String = str(child_key)
			if ck_str.begins_with("_"):
				continue
			_harvest_module_node(dict[child_key], ck_str, out_list, seen)

	elif node is Array:
		for elem in node:
			_harvest_module_node(elem, parent_key, out_list, seen)

static func _add_token(out_list: Array[Dictionary], seen: Dictionary, domain: String, code: String, title: String) -> void:
	var d_clean := domain.strip_edges().to_upper()
	var c_clean := code.strip_edges().to_upper()
	if c_clean.is_empty():
		return

	var signature := "%s:%s" % [d_clean, c_clean]
	if seen.has(signature):
		return

	seen[signature] = true
	out_list.append({
		"domain": d_clean,
		"code": c_clean,
		"title": title
	})