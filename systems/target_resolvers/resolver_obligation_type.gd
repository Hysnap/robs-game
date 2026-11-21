# res://systems/target_resolvers/resolver_obligation_type.gd
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

const DOMAIN_TOKEN := "OBLIGATION_TYPE"

static func resolve(target_cat: Dictionary, world_state: Dictionary, _verb_code: String) -> Array[Dictionary]:
	var rules_mod: String = str(target_cat.get("rules_module", "obligation_types"))
	if not ScenarioManifestManagerScript.has_module(rules_mod):
		push_warning("[ResolverObligationType] Rules module '%s' not found in active manifest." % rules_mod)
		return []

	var module_data: Dictionary = ScenarioManifestManagerScript.load_module(rules_mod)
	var obl_types: Dictionary = module_data.get("obligation_types", {})
	var include_system: bool = bool(target_cat.get("include_system_types", false))
	var current_day: int = CalendarHelperScript.get_current_sim_day(world_state)
	var sim_year: int = CalendarHelperScript.day_to_year(current_day)

	var sorted_types: Array = obl_types.keys()
	sorted_types.sort()

	var results: Array[Dictionary] = []
	for type_code in sorted_types:
		var code_upper: String = str(type_code).strip_edges().to_upper()
		var type_cfg = obl_types[type_code]
		var lbl_tok: String = "UI_OBL_" + code_upper
		if type_cfg is Dictionary:
			if not include_system and not bool(type_cfg.get("user_creatable", true)):
				continue
			var from_yr: int = int(type_cfg.get("valid_from_year", -9999))
			var to_yr: int = int(type_cfg.get("valid_to_year", 9999))
			if sim_year < from_yr or sim_year > to_yr:
				continue
			if type_cfg.has("label_token"):
				lbl_tok = str(type_cfg["label_token"])
		results.append({
			"id": code_upper,
			"label_token": lbl_tok,
			"unit_cost": 0.0,
			"category": "OBLIGATION_TYPE",
			"sub_category": "",
			"taxonomy_path": []
		})

	return results