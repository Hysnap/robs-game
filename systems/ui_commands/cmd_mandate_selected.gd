# res://systems/ui_commands/cmd_mandate_selected.gd
extends RefCounted

const _CmdOpenManagement = preload("res://systems/ui_commands/cmd_open_management.gd")

## Selects a mandate row in the Management view and refreshes its review & executive intervention panel
static func execute(payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var raw_key = payload.get("filter_key", payload.get("mandate_id", 0))
	var mandate_id: int = int(raw_key)
	if mandate_id <= 0:
		return

	if not ws.has("ui_state") or not (ws["ui_state"] is Dictionary):
		ws["ui_state"] = {}
	ws["ui_state"]["selected_mandate_id"] = mandate_id

	_CmdOpenManagement.execute({
		"keep_domain": true,
		"mandate_id": mandate_id
	}, view_host, context_refs)