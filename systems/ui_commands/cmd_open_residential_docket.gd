# res://systems/ui_commands/cmd_open_residential_docket.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

## Opens a residential establishment docket with Fog-of-War masking and flat summary projection
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var estab_id: int = int(payload.get("filter_key", payload.get("establishment_id", 0)))
	if estab_id <= 0:
		SystemLogger.log_error("[CmdOpenResidentialDocket] Invalid establishment ID for residential docket routing.")
		push_error("[CmdOpenResidentialDocket] Invalid establishment ID for residential docket routing.")
		return

	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
	var current_sim_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)

	var raw_docket: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id, current_sim_day, intel_ctx)
	var view_data: Dictionary = _project_residential_payload(raw_docket)

	view_host.switch_to_domain("RESIDENTIAL_DOCKET")
	view_host.update_active_view_data(view_data)

static func _project_residential_payload(raw_docket: Dictionary) -> Dictionary:
	if raw_docket.is_empty():
		return {}

	var view_data: Dictionary = raw_docket.duplicate(true)
	var hh_rows: Array = view_data.get("household", [])
	if not hh_rows.is_empty() and hh_rows[0] is Dictionary:
		var hh: Dictionary = hh_rows[0]
		view_data["residence_type"] = str(hh.get("residence_type", ""))
		view_data["local_pub_name"] = str(hh.get("local_pub_name", ""))
	else:
		view_data["residence_type"] = ""
		view_data["local_pub_name"] = ""

	var residents_summary: Array[String] = []
	for r in view_data.get("residents", []):
		if not (r is Dictionary):
			continue
		if bool(r.get("is_masked", false)):
			var decade: int = int(r.get("age_decade", 30))
			residents_summary.append("%s (Age %d+)" % [TranslationServer.translate("UI_MASKED_OCCUPANT"), decade])
		else:
			var r_name: String = str(r.get("full_name", ""))
			var r_age: int = int(r.get("age", 0))
			var r_occ: String = str(r.get("occupation", ""))
			if not r_occ.is_empty():
				residents_summary.append("%s (Age %d) — %s" % [r_name, r_age, r_occ])
			else:
				residents_summary.append("%s (Age %d)" % [r_name, r_age])

	view_data["residents_summary"] = residents_summary
	return view_data