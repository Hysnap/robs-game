# res://systems/ui_commands/cmd_open_diary.gd
extends RefCounted

const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _DiaryAgendaBuilder = preload("res://systems/economy/diary_agenda_builder.gd")
const _OrgRecordLedger = preload("res://systems/economy/org_record_ledger.gd")

## Switches to the Diary Log view and binds current week, dispatch counters, calendar schedule, and date-scoped filed notes
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	if not bool(payload.get("keep_domain", false)):
		view_host.switch_to_domain("DIARY")

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var meta: Dictionary = ws.get("metadata", {})
	var ops: Dictionary = ws.get("operations", {})
	var current_day: int = _CalendarHelper.get_current_sim_day(ws)
	var week_tick: int = int(meta.get("current_week_tick", _CalendarHelper.day_to_week(current_day)))
	var dispatched_count: int = int(ops.get("total_dispatched_orders", 0))
	var calendar_payload: Dictionary = _DiaryAgendaBuilder.build_calendar_payload(ws, current_day, payload)
	var selected_day: int = int(calendar_payload.get("selected_sim_day", payload.get("selected_sim_day", current_day)))
	var org_id: String = str(ops.get("crew_org_id", "ORG:CREW_ENTERPRISE")).strip_edges()

	view_host.update_active_view_data({
		"current_week_tick": week_tick,
		"total_dispatched_orders": dispatched_count,
		"calendar_payload": calendar_payload,
		"inscriptions": _OrgRecordLedger.get_filed_inscriptions(org_id, "DIARY", "", selected_day)
	})