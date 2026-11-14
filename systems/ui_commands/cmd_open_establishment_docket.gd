# res://systems/ui_commands/cmd_open_establishment_docket.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

## Opens a commercial, industrial, or civic establishment docket with Fog-of-War masking and summary projection
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var estab_id: int = int(payload.get("filter_key", payload.get("establishment_id", 0)))
	if estab_id <= 0:
		SystemLogger.log_error("[CmdOpenEstablishmentDocket] Invalid establishment ID for establishment docket routing.")
		push_error("[CmdOpenEstablishmentDocket] Invalid establishment ID for establishment docket routing.")
		return

	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
	var current_sim_day: int = int(ws.get("metadata", {}).get("current_sim_day", 29219))
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)

	var raw_docket: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id, current_sim_day, intel_ctx)
	var view_data: Dictionary = _project_establishment_payload(raw_docket)

	view_host.switch_to_domain("ESTABLISHMENT_DOCKET")
	view_host.update_active_view_data(view_data)

static func _project_establishment_payload(raw_docket: Dictionary) -> Dictionary:
	if raw_docket.is_empty():
		return {}

	var view_data: Dictionary = raw_docket.duplicate(true)
	var catchment: Dictionary = view_data.get("market_catchment", {})
	if catchment is Dictionary and not catchment.is_empty():
		view_data["total_catchment_population"] = int(catchment.get("total_catchment_population", 0))
		view_data["total_catchment_households"] = int(catchment.get("total_catchment_households", 0))
		view_data["avg_neighbor_disposable_income"] = float(catchment.get("avg_neighbor_disposable_income", 0.0))

	var personnel_summary: Array[String] = []
	for emp in view_data.get("employees", []):
		if not (emp is Dictionary):
			continue
		if bool(emp.get("is_masked", false)):
			personnel_summary.append(TranslationServer.translate("UI_MASKED_STAFF"))
		else:
			var e_name: String = str(emp.get("full_name", ""))
			var e_role: String = str(emp.get("role_title", ""))
			var e_sched: String = str(emp.get("schedule_window", ""))
			if not e_role.is_empty() and not e_sched.is_empty():
				personnel_summary.append("%s — %s (%s)" % [e_name, e_role, e_sched])
			elif not e_role.is_empty():
				personnel_summary.append("%s — %s" % [e_name, e_role])
			else:
				personnel_summary.append(e_name)

	view_data["personnel_summary"] = personnel_summary
	return view_data