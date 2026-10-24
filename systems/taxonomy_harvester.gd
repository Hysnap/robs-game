# res://systems/taxonomy_harvester.gd
class_name TaxonomyHarvester
extends RefCounted

const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")

## Harvests all domain taxonomies from active scenario files into a normalized array of dictionaries:
## Returns: Array[Dictionary] where each element is:
##   { "domain": String, "code": String, "title": String }
static func harvest_all_taxonomies() -> Array[Dictionary]:
	var harvested: Array[Dictionary] = []
	var seen_keys: Dictionary = {} # "DOMAIN:CODE" -> true to deduplicate

	_harvest_archetypes(harvested, seen_keys)
	_harvest_cultural_demographics(harvested, seen_keys)
	_harvest_civic_hierarchy(harvested, seen_keys)
	_harvest_demographics(harvested, seen_keys)
	_harvest_building_classes(harvested, seen_keys)

	return harvested

static func _harvest_archetypes(out_list: Array[Dictionary], seen: Dictionary) -> void:
	var archetypes: Dictionary = {}
	if MANIFEST_MANAGER.has_module("archetypes"):
		archetypes = MANIFEST_MANAGER.load_module("archetypes")
	elif MANIFEST_MANAGER.has_module("spatial_archetypes"):
		archetypes = MANIFEST_MANAGER.load_module("spatial_archetypes")

	for arch_key in archetypes.keys():
		if arch_key in ["_meta", "setup"]:
			continue
		var arch: Dictionary = archetypes[arch_key]

		# 1. Residence Type from housing_profile
		var h_prof: Dictionary = arch.get("housing_profile", {})
		if h_prof.has("residence_type"):
			var res_code: String = str(h_prof["residence_type"]).to_upper()
			_add_token(out_list, seen, "RESIDENCE_TYPE", res_code, res_code.capitalize().replace("_", " "))

		# 2. Establishment Category from archetype root
		if arch.has("establishment_category"):
			var cat_code: String = str(arch["establishment_category"]).to_upper()
			var cat_title: String = str(arch.get("display_name", cat_code.capitalize().replace("_", " ")))
			_add_token(out_list, seen, "ESTABLISHMENT_CATEGORY", cat_code, cat_title)

		# 3. Roles from institution_profile
		if arch.has("institution_profile"):
			var inst: Dictionary = arch["institution_profile"]
			if inst.has("client_profile") and inst["client_profile"].has("role_title"):
				var r_code: String = str(inst["client_profile"]["role_title"]).to_upper()
				_add_token(out_list, seen, "ROLE_TITLE", r_code, r_code.capitalize().replace("_", " "))

			if inst.has("staff_profile") and inst["staff_profile"].has("role_title"):
				var s_code: String = str(inst["staff_profile"]["role_title"]).to_upper()
				_add_token(out_list, seen, "ROLE_TITLE", s_code, s_code.capitalize().replace("_", " "))

static func _harvest_cultural_demographics(out_list: Array[Dictionary], seen: Dictionary) -> void:
	var cult_data: Dictionary = MANIFEST_MANAGER.load_module("cultural_demographics")
	var ethnicities: Dictionary = cult_data.get("ethnicities", {})
	
	for eth_code in ethnicities.keys():
		var eth: Dictionary = ethnicities[eth_code]
		var eth_title: String = str(eth.get("display_name", eth_code.capitalize()))
		_add_token(out_list, seen, "ETHNICITY", eth_code, eth_title)

		var rel_dist: Dictionary = eth.get("religion_distribution", {})
		for rel_code in rel_dist.keys():
			_add_token(out_list, seen, "RELIGION", rel_code, str(rel_code).capitalize().replace("_", " "))

static func _harvest_civic_hierarchy(out_list: Array[Dictionary], seen: Dictionary) -> void:
	var civic_data: Dictionary = MANIFEST_MANAGER.load_module("civic_hierarchy")
	var insts: Dictionary = civic_data.get("civic_institutions", {})
	
	for inst_key in insts.keys():
		var inst: Dictionary = insts[inst_key]
		var inst_title: String = str(inst.get("display_name", inst_key.capitalize()))
		_add_token(out_list, seen, "ESTABLISHMENT_CATEGORY", inst_key, inst_title)

		if inst.has("client_profile") and inst["client_profile"].has("role_title"):
			var r_title: String = str(inst["client_profile"]["role_title"]).to_upper()
			_add_token(out_list, seen, "ROLE_TITLE", r_title, r_title.capitalize().replace("_", " "))

		if inst.has("staff_profile") and inst["staff_profile"].has("role_title"):
			var s_title: String = str(inst["staff_profile"]["role_title"]).to_upper()
			_add_token(out_list, seen, "ROLE_TITLE", s_title, s_title.capitalize().replace("_", " "))

	var est_templates: Dictionary = civic_data.get("establishment_templates", {})
	for tmpl_key in est_templates.keys():
		_add_token(out_list, seen, "ESTABLISHMENT_CATEGORY", tmpl_key, tmpl_key.capitalize() + " Sector")

static func _harvest_demographics(out_list: Array[Dictionary], seen: Dictionary) -> void:
	var demo_data: Dictionary = MANIFEST_MANAGER.load_module("demographics")
	
	# Education Tiers
	var edu_model: Dictionary = demo_data.get("education_attainment_model", {})
	var def_edu: String = str(edu_model.get("default_code", "NO_FORMAL")).to_upper()
	_add_token(out_list, seen, "EDUCATION_LEVEL", def_edu, def_edu.capitalize().replace("_", " "))
	for tier in edu_model.get("tiers", []):
		var t_code: String = str(tier.get("code", "")).to_upper()
		if not t_code.is_empty():
			_add_token(out_list, seen, "EDUCATION_LEVEL", t_code, t_code.capitalize().replace("_", " "))

	# Deep Cohort Profile Roles (Fixed, Labor Market, and Probabilistic Branches)
	for c in demo_data.get("cohort_profiles", []):
		# 1. Top-level roles
		for role_field in ["role", "unemployed_role", "commercial_role", "industrial_role"]:
			if c.has(role_field):
				var r_code: String = str(c[role_field]).to_upper()
				_add_token(out_list, seen, "ROLE_TITLE", r_code, r_code.capitalize().replace("_", " "))

		# 2. Nested strategy branches (handles APPRENTICE, STUDENT, etc.)
		for branch_key in ["if_true", "if_false"]:
			if c.has(branch_key) and c[branch_key] is Dictionary:
				var branch: Dictionary = c[branch_key]
				if branch.has("role"):
					var b_code: String = str(branch["role"]).to_upper()
					_add_token(out_list, seen, "ROLE_TITLE", b_code, b_code.capitalize().replace("_", " "))

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

static func _harvest_building_classes(out_list: Array[Dictionary], seen: Dictionary) -> void:
	if not MANIFEST_MANAGER.has_module("building_classes"):
		return

	var bldg_classes: Dictionary = MANIFEST_MANAGER.load_module("building_classes")

	for section_key in ["commercial_tenants", "industrial_tenants"]:
		var tenants: Dictionary = bldg_classes.get(section_key, {})
		for t_code in tenants.keys():
			var t_data: Dictionary = tenants[t_code]
			var t_title: String = str(t_data.get("display_name", t_code.capitalize().replace("_", " ")))
			
			# 1. Harvest establishment category
			_add_token(out_list, seen, "ESTABLISHMENT_CATEGORY", t_code, t_title)

			# 2. Harvest staff role titles if defined
			if t_data.has("staff_roles"):
				for r_code in t_data["staff_roles"]:
					_add_token(out_list, seen, "ROLE_TITLE", str(r_code), str(r_code).capitalize().replace("_", " "))