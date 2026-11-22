# res://systems/economy/mandate_cohort_catalog.gd
class_name MandateCohortCatalog
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const CommodityManagerScript = preload("res://systems/commodity_manager.gd")
const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

const VERBS_ROOT := "res://data_modules/"

## Builds complete 4-axis cohort options (including unscouted districts/building classes for planning with hope)
static func build_allocator_catalog(ws: Dictionary) -> Dictionary:
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)
	var observers: Array = intel_ctx.get("observers", [])

	# 1. Assignable Managers & ARMS_LENGTH Subsidiary Orgs
	var assignees: Array[Dictionary] = []
	var residents: Dictionary = ws.get("residents", {})
	var sorted_res_keys: Array = residents.keys()
	sorted_res_keys.sort()
	for r_key in sorted_res_keys:
		var rec = residents[r_key]
		if rec is Dictionary and bool(rec.get("is_crew", true)):
			var r_id: int = int(rec.get("resident_id", 0))
			if r_id > 0:
				assignees.append({
					"type": "RESIDENT",
					"id": r_id,
					"label": str(rec.get("name", str(r_id)))
				})

	var orgs: Dictionary = ws.get("organizations", {})
	var sorted_org_keys: Array = orgs.keys()
	sorted_org_keys.sort()
	for o_key in sorted_org_keys:
		var o_rec = orgs[o_key]
		if o_rec is Dictionary and str(o_rec.get("autonomy_mode", "")).to_upper() == "ARMS_LENGTH":
			assignees.append({
				"type": "ORG",
				"id": str(o_key),
				"label": "%s (ARMS_LENGTH)" % str(o_rec.get("display_name", o_key))
			})

	# 2. Spatial Axis: ALL city districts (unscouted districts explicitly included & flagged)
	var spatial_options: Array[Dictionary] = [
		{"id": "*", "label_token": "UI_COHORT_ALL_DISTRICTS", "is_unscouted": false}
	]
	var districts: Dictionary = ws.get("districts", {})
	var sorted_dist_ids: Array = districts.keys()
	sorted_dist_ids.sort()
	for d_key in sorted_dist_ids:
		var d_id: String = str(d_key)
		var d_rec: Dictionary = districts[d_key] if districts[d_key] is Dictionary else {}
		var score: float = IntelManagerScript.get_collective_score(ws, observers, "DISTRICT", d_id)
		var is_known: bool = IntelManagerScript.is_entity_known(score, "DISTRICT")
		var d_name: String = str(d_rec.get("display_name", d_id))
		spatial_options.append({
			"id": d_id,
			"label": d_name,
			"is_unscouted": not is_known,
			"intel_score": score
		})

	# 3. Premises Axis: ALL building_classes (even in unscouted areas) + known specific establishments
	var premises_options: Array[Dictionary] = [
		{"id": "*", "label_token": "UI_COHORT_ALL_PREMISES", "kind": "WILDCARD"}
	]
	if ScenarioManifestManagerScript.has_module("building_classes"):
		var b_classes: Dictionary = ScenarioManifestManagerScript.load_module("building_classes")
		var classes_map: Dictionary = b_classes.get("building_classes", b_classes)
		var sorted_cls: Array = classes_map.keys()
		sorted_cls.sort()
		for cls_key in sorted_cls:
			var cls_str: String = str(cls_key).strip_edges().to_upper()
			if cls_str.begins_with("_"):
				continue
			var cls_obj = classes_map[cls_key]
			var cls_title: String = str(cls_obj.get("title", cls_str)) if cls_obj is Dictionary else cls_str
			premises_options.append({
				"id": cls_str,
				"label": cls_title,
				"kind": "BUILDING_CLASS"
			})

	var active_dist: String = str(ws.get("selected_district_id", ws.get("operations", {}).get("home_district_id", "")))
	if not active_dist.is_empty():
		var known_locs: Array[Dictionary] = IntelManagerScript.get_known_locations(active_dist, ws)
		for loc in known_locs:
			if str(loc.get("type", "")) == "ESTABLISHMENT":
				premises_options.append({
					"id": int(loc.get("id", 0)),
					"label": str(loc.get("display", "")),
					"kind": "ESTABLISHMENT"
				})

	# 4. Commodities Axis: ALL live commodities from CommodityManager
	var commodity_options: Array[Dictionary] = [
		{"id": "*", "label_token": "UI_COHORT_ALL_COMMODITIES"}
	]
	var comm_reg: Dictionary = ws.get("commodity_registry", {}) if ws.get("commodity_registry", null) is Dictionary else {}
	var sorted_comms: Array = comm_reg.keys()
	sorted_comms.sort()
	for c_id in sorted_comms:
		var c_def = comm_reg[c_id]
		var c_name: String = str(c_def.get("name", c_id)) if c_def is Dictionary else str(c_id)
		commodity_options.append({
			"id": str(c_id).to_upper(),
			"label": c_name
		})

	# 5. Verbs Axis: ALL live/visible macro verbs (including SCOUT & INVESTIGATE)
	var verb_options: Array[Dictionary] = [
		{"id": "*", "label_token": "UI_COHORT_ALL_VERBS"}
	]
	var verb_paths: Array[String] = FileSystemCrawlerScript.find_files_recursive(VERBS_ROOT, "verb_definition.json", ".json")
	verb_paths.sort()
	for v_path in verb_paths:
		if not v_path.contains("/verbs/"):
			continue
		var v_def: Dictionary = ScenarioManifestManagerScript.load_json_file(v_path)
		if v_def.is_empty():
			continue
		var v_tok: String = str(v_def.get("verb_token", v_path.get_base_dir().get_file())).strip_edges().to_upper()
		if not v_tok.is_empty():
			verb_options.append({
				"id": v_tok,
				"label_token": "UI_VERB_" + v_tok
			})

	return {
		"assignees": assignees,
		"spatial": spatial_options,
		"premises": premises_options,
		"commodities": commodity_options,
		"verbs": verb_options,
		"mandate_modes": ["CASHFLOW", "SUPPLY", "EXPAND", "CONSOLIDATE"],
		"planning_horizons": ["DAY", "WEEK", "MONTH", "QUARTER"]
	}

## Builds a review summary dictionary for the currently selected mandate
static func build_mandate_review_summary(ws: Dictionary, mandate_id: int) -> Dictionary:
	var mandates: Dictionary = ws.get("org_mandates", {})
	if mandate_id <= 0 or not mandates.has(mandate_id) or not (mandates[mandate_id] is Dictionary):
		return {}

	var m: Dictionary = mandates[mandate_id]
	var current_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)
	var observers: Array = intel_ctx.get("observers", [])

	var scope_filter: Dictionary = m.get("scope_filter", {})
	var spatial_list: Array = scope_filter.get("spatial", ["*"])
	var unscouted_targets: Array[String] = []
	var districts: Dictionary = ws.get("districts", {})
	for s_id in spatial_list:
		var s_str: String = str(s_id)
		if s_str == "*":
			continue
		var d_score: float = IntelManagerScript.get_collective_score(ws, observers, "DISTRICT", s_str)
		if not IntelManagerScript.is_entity_known(d_score, "DISTRICT"):
			unscouted_targets.append(str(districts.get(s_str, {}).get("display_name", s_str)))

	var lock_until: int = int(m.get("commitment_lock_until_day", 0))
	var assist_until: int = int(m.get("assistance_request_expires_day", -1))
	var target_metrics: Dictionary = m.get("target_metrics", {}) if m.get("target_metrics", null) is Dictionary else {}

	return {
		"mandate_id": mandate_id,
		"title": str(m.get("title", "")),
		"mandate_mode": str(m.get("mandate_mode", "CASHFLOW")),
		"planning_horizon": str(m.get("planning_horizon", "MONTH")),
		"heat_ceiling": float(m.get("heat_ceiling", 0.65)),
		"remittance_target": float(target_metrics.get("remittance_target", 0.0)),
		"operating_float": float(target_metrics.get("operating_float", 0.0)),
		"is_locked": current_day < lock_until,
		"lock_until_day": lock_until,
		"assistance_open": current_day <= assist_until,
		"assistance_expires_day": assist_until,
		"unscouted_districts": unscouted_targets,
		"requires_recon_first": not unscouted_targets.is_empty()
	}