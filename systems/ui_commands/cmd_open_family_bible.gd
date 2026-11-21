# res://systems/ui_commands/cmd_open_family_bible.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

## Switches to the Family Bible view and binds Fog-of-War filtered crew lineages and vital records
static func execute(_payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var current_sim_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)
	var bible_data: Dictionary = SocietyQueriesScript.get_crew_family_bible(intel_ctx, current_sim_day)

	view_host.switch_to_domain("FAMILY_BIBLE")
	view_host.update_active_view_data(bible_data)