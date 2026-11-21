# res://systems/target_resolvers/resolver_settlement_rail.gd
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

const DOMAIN_TOKEN := "SETTLEMENT_RAIL"

static func resolve(target_cat: Dictionary, world_state: Dictionary, _verb_code: String) -> Array[Dictionary]:
	var rules_mod: String = str(target_cat.get("rules_module", "settlement_rails"))
	assert(ScenarioManifestManagerScript.has_module(rules_mod),
		"FATAL: [ResolverSettlementRail] Active scenario manifest missing module '%s'." % rules_mod)

	var module_data: Dictionary = ScenarioManifestManagerScript.load_module(rules_mod)
	var rails: Dictionary = module_data.get("settlement_rails", {})
	var current_day: int = CalendarHelperScript.get_current_sim_day(world_state)
	var sim_year: int = CalendarHelperScript.day_to_year(current_day)

	var sorted_keys: Array = rails.keys()
	sorted_keys.sort()

	var results: Array[Dictionary] = []
	for rail_key in sorted_keys:
		var code_upper: String = str(rail_key).strip_edges().to_upper()
		var cfg = rails[rail_key]
		if not (cfg is Dictionary):
			continue

		var from_yr: int = int(cfg.get("valid_from_year", -9999))
		var to_yr: int = int(cfg.get("valid_to_year", 9999))
		if sim_year < from_yr or sim_year > to_yr:
			continue

		results.append({
			"id": code_upper,
			"label_token": str(cfg.get("label_token", "UI_RAIL_" + code_upper)),
			"unit_cost": 0.0,
			"category": "SETTLEMENT_RAIL",
			"sub_category": str(cfg.get("clearing_mode", "BANKING")),
			"taxonomy_path": [],
			"can_post": bool(cfg.get("can_post", false)),
			"requires_co_location": bool(cfg.get("requires_co_location", false)),
			"clearing_working_days": int(cfg.get("clearing_working_days", 0))
		})

	return results