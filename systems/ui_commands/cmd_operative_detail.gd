# res://systems/ui_commands/cmd_operative_detail.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const CmdOpenResidentialDocketScript = preload("res://systems/ui_commands/cmd_open_residential_docket.gd")

## Resolves an operative or contact resident_id to their home establishment and opens their residential docket
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var current_sim_day: int = int(ws.get("metadata", {}).get("current_sim_day", 29219))
	var filter_key: Variant = payload.get("filter_key", payload.get("resident_id", 0))

	var residents_dict: Dictionary = ws.get("residents", {})
	var res_id: int = 0

	if typeof(filter_key) == TYPE_INT or (typeof(filter_key) == TYPE_STRING and str(filter_key).is_valid_int()):
		res_id = int(filter_key)
	else:
		var s_id: String = str(filter_key)
		if residents_dict.has(s_id):
			res_id = int(residents_dict[s_id].get("resident_id", 0))

	if res_id <= 0:
		SystemLogger.log_error("[CmdOperativeDetail] Cannot route to operative detail: Invalid or missing resident_id.")
		push_error("[CmdOperativeDetail] Cannot route to operative detail: Invalid or missing resident_id.")
		return

	var demo: Dictionary = SocietyQueriesScript.get_resident_profile(res_id, current_sim_day)
	var home_estab: int = int(demo.get("home_establishment_id", demo.get("establishment_id", 0)))

	if home_estab > 0:
		CmdOpenResidentialDocketScript.execute({"establishment_id": home_estab}, view_host)
	else:
		SystemLogger.log_error("[CmdOperativeDetail] Resident %d lacks a valid home establishment. Routing aborted." % res_id)
		push_error("[CmdOperativeDetail] Resident %d lacks a valid home establishment. Routing aborted." % res_id)