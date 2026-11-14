# res://systems/ui_commands/cmd_open_diary.gd
extends RefCounted

## Switches to the Diary Log view and binds current week and dispatch counters
static func execute(_payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	view_host.switch_to_domain("DIARY")
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var meta: Dictionary = ws.get("metadata", {})
	var ops: Dictionary = ws.get("operations", {})
	var week_tick: int = int(meta.get("current_week_tick", 1))
	var dispatched_count: int = int(ops.get("total_dispatched_orders", 0))

	view_host.update_active_view_data({
		"current_week_tick": week_tick,
		"total_dispatched_orders": dispatched_count
	})