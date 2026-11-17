# res://systems/ui_commands/cmd_save_game.gd
class_name CmdSaveGame
extends RefCounted

static func execute(
	_payload: Dictionary,
	view_host: ViewHost,
	_context_refs: Dictionary = {}
) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [CmdSaveGame] GameState or world_state unmounted.")
	var ws: Dictionary = gs.world_state
	if not (ws.get("metadata") is Dictionary):
		ws["metadata"] = {}
	var meta: Dictionary = ws["metadata"]

	var is_ironman: bool = bool(meta.get("ironman_mode", false))
	if is_ironman:
		SystemLogger.log_warn("[CmdSaveGame] Manual save rejected: ironman_mode is active.")
		if view_host != null and view_host.has_method("sync_save_button_state"):
			view_host.sync_save_button_state(true)
		return

	var slot_id: String = str(meta.get("save_slot_id", "")).strip_edges()
	if slot_id.is_empty():
		slot_id = SaveManager.get_latest_save_slot()
	if slot_id.is_empty():
		slot_id = SaveManager.get_next_available_slot()

	meta["save_slot_id"] = slot_id
	SaveManager.save_game(slot_id, null, ws)
	SystemLogger.log_info("[CmdSaveGame] Manual save completed for slot '%s'." % slot_id)