# res://systems/ui_commands/cmd_grant_mandate_assistance.gd
extends RefCounted

const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _OrgMandateManager = preload("res://systems/economy/org_mandate_manager.gd")
const _CmdOpenManagement = preload("res://systems/ui_commands/cmd_open_management.gd")

## Opens a solicited assistance window on a mandate so direct player intervention incurs zero loyalty penalty
static func execute(payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var mandates: Dictionary = ws.get("org_mandates", {})
	if mandates.is_empty():
		return

	var mandate_id: int = int(payload.get("mandate_id", 0))
	if mandate_id <= 0:
		for m_key in mandates.keys():
			var m = mandates[m_key]
			if m is Dictionary and bool(m.get("is_active", true)):
				mandate_id = int(m.get("mandate_id", m_key))
				break

	if mandate_id <= 0:
		return

	var current_day: int = _CalendarHelper.get_current_sim_day(ws)
	var duration_days: int = int(payload.get("duration_days", _CalendarHelper.get_days_per_tick()))
	_OrgMandateManager.grant_assistance_window(ws, mandate_id, current_day + duration_days)

	if view_host != null:
		_CmdOpenManagement.execute({"keep_domain": true}, view_host, context_refs)