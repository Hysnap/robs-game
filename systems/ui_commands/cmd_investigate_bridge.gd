# res://systems/ui_commands/cmd_investigate_bridge.gd
extends RefCounted

const _CalendarHelper = preload("res://systems/calendar_helper.gd")

## Stages a reconnaissance directive targeting the known endpoints flanking an unconfirmed TBC_BRIDGE hierarchy link
static func execute(payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var node_data: Dictionary = payload.get("node", payload)
	var parent_id: String = str(node_data.get("parent_entity_id", "")).strip_edges()
	var child_ids: Array = node_data.get("bridged_child_ids", []) if node_data.get("bridged_child_ids", null) is Array else []

	var target_raw: String = str(child_ids[0]) if not child_ids.is_empty() else parent_id
	if target_raw.is_empty():
		return

	var target_entity_id: Variant = int(target_raw) if target_raw.is_valid_int() else target_raw
	var actor_id: Variant = _pick_available_scout(ws)
	if actor_id == null:
		return

	var target_district: String = _resolve_target_district(ws, target_entity_id)
	var current_day: int = _CalendarHelper.get_current_sim_day(ws)

	var directive: Dictionary = {
		"verb": "INVESTIGATE",
		"initiator_id": actor_id,
		"assigned_to": actor_id,
		"target_entity_id": target_entity_id,
		"target_node_id": target_district,
		"duration_ticks": 2.0,
		"staged_sim_day": current_day,
		"source_tag": "BRIDGE_RECON"
	}

	if not ws.has("staged_directives") or not (ws["staged_directives"] is Array):
		ws["staged_directives"] = []
	ws["staged_directives"].append(directive)

	var planner_node = context_refs.get("planner_view", null)
	if planner_node != null and planner_node.has_method("stage_directive"):
		planner_node.stage_directive(directive)

	if view_host != null and view_host.has_method("show_status_toast"):
		view_host.show_status_toast(TranslationServer.translate("UI_BTN_INVESTIGATE_BRIDGE"))

static func _pick_available_scout(ws: Dictionary) -> Variant:
	var residents: Dictionary = ws.get("residents", {})
	var keys: Array = residents.keys()
	keys.sort()
	for k in keys:
		var rec = residents[k]
		if rec is Dictionary and bool(rec.get("is_crew", true)):
			var r_id: int = int(rec.get("resident_id", 0))
			return r_id if r_id > 0 else k
	return null

static func _resolve_target_district(ws: Dictionary, target_entity_id: Variant) -> String:
	var residents: Dictionary = ws.get("residents", {})
	if residents.has(target_entity_id) and residents[target_entity_id] is Dictionary:
		return str(residents[target_entity_id].get("current_district_id", ""))
	var estabs: Dictionary = ws.get("establishments", {})
	if estabs.has(target_entity_id) and estabs[target_entity_id] is Dictionary:
		return str(estabs[target_entity_id].get("district_id", ""))
	return str(ws.get("operations", {}).get("home_district_id", ""))