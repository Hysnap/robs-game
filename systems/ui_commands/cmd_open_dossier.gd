# res://systems/ui_commands/cmd_open_dossier.gd
extends RefCounted

## Switches to the District Dossier view and binds telemetry for the active or requested district
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	view_host.switch_to_domain("DOSSIER")
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var district_id: String = str(payload.get("district_id", gs.world_state.get("selected_district_id", ""))).strip_edges()
	if not district_id.is_empty() and gs.has_method("get_district_view"):
		view_host.update_active_view_data(gs.get_district_view(district_id))