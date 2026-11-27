# res://systems/ui_commands/cmd_open_street_residences.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

## Opens the road/building residential drill-down view listing known house and flat numbers
static func execute(payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var raw_key: String = str(payload.get("filter_key", payload.get("street_key", ""))).strip_edges()
	var district_id: String = str(payload.get("district_id", "")).strip_edges()
	var street_name: String = str(payload.get("street_name", "")).strip_edges()

	if not raw_key.is_empty() and raw_key.contains("::"):
		var parts: PackedStringArray = raw_key.split("::", false, 1)
		if parts.size() == 2:
			district_id = parts[0].strip_edges()
			street_name = parts[1].strip_edges()

	var gs = context_refs.get("game_state", ScenarioManifestManager.get_game_state())
	var ws: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
	if district_id.is_empty():
		district_id = str(ws.get("selected_district_id", "")).strip_edges()

	if district_id.is_empty() or street_name.is_empty():
		SystemLogger.log_error("[CmdOpenStreetResidences] Missing district_id or street_name for drill-down.")
		push_error("[CmdOpenStreetResidences] Missing district_id or street_name for drill-down.")
		return

	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)

	var district_name: String = str(ws.get("districts", {}).get(district_id, {}).get("display_name", district_id))
	var raw_units: Array[Dictionary] = SocietyQueriesScript.get_street_residential_units(district_id, street_name, intel_ctx)

	var units_summary: Array[Dictionary] = []
	for u in raw_units:
		var is_vacant: bool = int(u.get("is_vacant", 0)) != 0
		var occ_count: int = int(u.get("occupant_count", 0))
		var summary_text: String = str(TranslationServer.translate("UI_LBL_OCCUPIED_UNIT"))
		if is_vacant:
			summary_text = str(TranslationServer.translate("UI_LBL_VACANT_UNIT"))
		elif occ_count > 0:
			summary_text = "%d %s" % [occ_count, str(TranslationServer.translate("UI_LBL_RESIDENTS_COUNT"))]
		units_summary.append({
			"establishment_id": int(u.get("establishment_id", 0)),
			"unit_door_number": str(u.get("unit_door_number", u.get("name", ""))),
			"occupant_summary": summary_text
		})

	view_host.switch_to_domain("STREET_RESIDENCES")
	view_host.update_active_view_data({
		"district_id": district_id,
		"district_name": district_name,
		"street_name": street_name,
		"units_summary": units_summary
	})