# res://systems/ui_commands/cmd_open_diary.gd
extends RefCounted

const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _DiaryAgendaBuilder = preload("res://systems/economy/diary_agenda_builder.gd")

## Switches to the Diary Log view and binds current week, dispatch counters, and calendar event schedule
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

	view_host.update_active_view_data({
		"current_week_tick": week_tick,
		"total_dispatched_orders": dispatched_count,
		"calendar_payload": _DiaryAgendaBuilder.build_calendar_payload(ws, current_day, payload)
	})