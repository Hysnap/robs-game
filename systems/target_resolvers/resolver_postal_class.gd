# res://systems/target_resolvers/resolver_postal_class.gd
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

const DOMAIN_TOKEN := "POSTAL_CLASS"

static func resolve(target_cat: Dictionary, world_state: Dictionary, _verb_code: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = [
		{
			"id": "",
			"label_token": "UI_DELIVERY_IN_PERSON",
			"unit_cost": 0.0,
			"category": "POSTAL_CLASS",
			"sub_category": "IN_PERSON",
			"taxonomy_path": [],
			"is_physical": false,
			"stamps_commodity_id": ""
		}
	]

	var rules_mod: String = str(target_cat.get("rules_module", "civic_hierarchy"))
	if not ScenarioManifestManagerScript.has_module(rules_mod):
		return results

	var civic: Dictionary = ScenarioManifestManagerScript.load_module(rules_mod)
	var postal_rules: Dictionary = civic.get("postal_rules", {})
	var classes: Dictionary = postal_rules.get("classes", {})
	var schedules: Array = postal_rules.get("era_schedules", [])

	var current_day: int = int(world_state.get("metadata", {}).get("current_sim_day", CalendarHelperScript.get_simulation_start_day()))
	var sim_year: int = CalendarHelperScript.day_to_year(current_day)

	var active_transit: Dictionary = {}
	for sched in schedules:
		if sched is Dictionary:
			var from_yr: int = int(sched.get("valid_from_year", -9999))
			var to_yr: int = int(sched.get("valid_to_year", 9999))
			if sim_year >= from_yr and sim_year <= to_yr:
				active_transit = sched.get("transit_days", {})
				break

	var sorted_classes: Array = classes.keys()
	sorted_classes.sort()
	for cls_key in sorted_classes:
		var cls_upper: String = str(cls_key).strip_edges().to_upper()
		if not active_transit.is_empty() and not active_transit.has(cls_upper):
			continue
		var cls_cfg = classes[cls_key]
		if cls_cfg is Dictionary:
			results.append({
				"id": cls_upper,
				"label_token": str(cls_cfg.get("label_token", "UI_POST_" + cls_upper)),
				"unit_cost": 0.0,
				"category": "POSTAL_CLASS",
				"sub_category": "POSTAL",
				"taxonomy_path": [],
				"is_physical": bool(cls_cfg.get("is_physical", true)),
				"stamps_commodity_id": str(cls_cfg.get("stamps_commodity_id", ""))
			})

	return results