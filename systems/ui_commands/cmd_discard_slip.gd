# res://systems/ui_commands/cmd_discard_slip.gd
extends RefCounted

const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _OrgRecordLedger = preload("res://systems/economy/org_record_ledger.gd")

## Handles discarding a feedback slip from the desk inbox stack (soft-deleted as BINNED in org_records)
static func execute(payload: Dictionary, _view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	var slip_data: Dictionary = payload.get("slip_data", payload)
	var record_id: int = int(slip_data.get("record_id", payload.get("record_id", 0)))

	if record_id > 0:
		var gs = ScenarioManifestManager.get_game_state()
		var ws: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
		var current_day: int = _CalendarHelper.get_current_sim_day(ws)
		_OrgRecordLedger.dispose_record(record_id, "BINNED", current_day)

	SystemLogger.log_info("[CmdDiscardSlip] Discarded slip (record_id=%d): %s" % [
		record_id, str(slip_data.get("display_text", ""))
	])