# res://systems/ui_commands/cmd_operative_detail.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const CmdOpenResidentialDocketScript = preload("res://systems/ui_commands/cmd_open_residential_docket.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const _OrgRecordLedger = preload("res://systems/economy/org_record_ledger.gd")

## Opens the operational dossier for a crew operative, or the home residential docket for a street contact
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var current_sim_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var filter_key: Variant = payload.get("filter_key", payload.get("resident_id", 0))

	var residents_dict: Dictionary = ws.get("residents", {})
	var res_id: int = 0
	var crew_record: Dictionary = {}

	if typeof(filter_key) == TYPE_INT or (typeof(filter_key) == TYPE_STRING and str(filter_key).is_valid_int()):
		res_id = int(filter_key)
		for k in residents_dict.keys():
			var rec = residents_dict[k]
			if rec is Dictionary and int(rec.get("resident_id", 0)) == res_id:
				crew_record = rec
				break
	else:
		var s_id: String = str(filter_key).strip_edges()
		if residents_dict.has(s_id) and residents_dict[s_id] is Dictionary:
			crew_record = residents_dict[s_id]
			res_id = int(crew_record.get("resident_id", 0))

	if res_id <= 0 and crew_record.is_empty():
		SystemLogger.log_error("[CmdOperativeDetail] Cannot route to operative detail: Invalid or missing resident_id.")
		push_error("[CmdOperativeDetail] Cannot route to operative detail: Invalid or missing resident_id.")
		return

	# If this resident is an active crew operative, render their operational status & personal inventory
	if not crew_record.is_empty() and bool(crew_record.get("is_crew", true)):
		var demo: Dictionary = SocietyQueriesScript.get_resident_profile(res_id, current_sim_day) if res_id > 0 else {}
		var op_name: String = str(crew_record.get("name", demo.get("full_name", str(filter_key))))
		var role_title: String = str(crew_record.get("role", demo.get("occupation", "OPERATIVE"))).capitalize()

		var districts_dict: Dictionary = ws.get("districts", {})
		var default_base_id: String = str(ws.get("operations", {}).get("home_district_id", "")).strip_edges()
		var base_id: String = str(crew_record.get("base_district_id", default_base_id)).strip_edges()
		if base_id.is_empty():
			base_id = default_base_id
		var curr_id: String = str(crew_record.get("current_district_id", base_id)).strip_edges()

		var curr_loc_name: String = str(districts_dict.get(curr_id, {}).get("display_name", curr_id))
		var base_loc_name: String = str(districts_dict.get(base_id, {}).get("display_name", base_id))

		var rtb_enabled: bool = bool(crew_record.get("auto_return_to_base", false))
		var rtb_status: String = TranslationServer.translate("UI_STATE_ENABLED") if rtb_enabled else TranslationServer.translate("UI_STATE_DISABLED")

		var fatigue_val: float = float(crew_record.get("fatigue", 0.0))
		var inv: Dictionary = crew_record.get("inventory", {})
		var cash_val: float = float(inv.get("CASH", 0.0))

		var inv_lines: Array[String] = []
		var item_keys: Array = inv.keys()
		item_keys.sort()
		for item_key in item_keys:
			var qty: float = float(inv[item_key])
			if qty > 0.0:
				inv_lines.append("%s: %.2f" % [str(item_key), qty])

		view_host.switch_to_domain("OPERATIVE_DOSSIER")
		if view_host.get_active_domain() != "OPERATIVE_DOSSIER":
			SystemLogger.log_error("[CmdOperativeDetail] FAIL_LOUD: ViewHost did not switch to OPERATIVE_DOSSIER.")
			return
		var org_id: String = str(ws.get("operations", {}).get("crew_org_id", "ORG:CREW_ENTERPRISE")).strip_edges()
		view_host.update_active_view_data({
			"operative_name": op_name,
			"role_title": role_title,
			"current_location_name": curr_loc_name,
			"base_location_name": base_loc_name,
			"return_to_base_status": rtb_status,
			"fatigue_display": "%.1f" % fatigue_val,
			"cash_display": "£%.2f" % cash_val,
			"inventory_lines": inv_lines,
			"inscriptions": _OrgRecordLedger.get_filed_inscriptions(org_id, "ROSTER", "", -1, res_id),
			"navigation_links": [
				{
					"target_id": "ROSTER",
					"label": TranslationServer.translate("UI_HDR_CREW_DOSSIER")
				}
			]
		})
		return

	# Otherwise, external contact -> open their residential docket
	var demo_ext: Dictionary = SocietyQueriesScript.get_resident_profile(res_id, current_sim_day)
	var home_estab: int = int(demo_ext.get("home_establishment_id", demo_ext.get("establishment_id", 0)))

	if home_estab > 0:
		CmdOpenResidentialDocketScript.execute({"establishment_id": home_estab}, view_host)
	else:
		SystemLogger.log_error("[CmdOperativeDetail] Resident %d lacks a valid home establishment. Routing aborted." % res_id)
		push_error("[CmdOperativeDetail] Resident %d lacks a valid home establishment. Routing aborted." % res_id)