# res://systems/ui_commands/cmd_open_family_bible.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

## Switches to the Family Bible view and binds Fog-of-War filtered subject-centric lineage and vital records
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var current_sim_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)

	var subject_id: int = _resolve_subject_resident_id(payload, intel_ctx)
	var bible_data: Dictionary = SocietyQueriesScript.get_subject_family_tree(subject_id, intel_ctx, current_sim_day)

	view_host.switch_to_domain("FAMILY_BIBLE")
	view_host.update_active_view_data(bible_data)

static func _resolve_subject_resident_id(payload: Dictionary, intel_ctx: Dictionary) -> int:
	for key in ["subject_resident_id", "resident_id", "filter_key"]:
		if payload.has(key):
			var raw_val: Variant = payload[key]
			if typeof(raw_val) == TYPE_INT or (typeof(raw_val) == TYPE_STRING and str(raw_val).is_valid_int()):
				var parsed: int = int(raw_val)
				if parsed > 0:
					return parsed

	for raw_crew_id in intel_ctx.get("crew_resident_ids", []):
		var crew_id: int = int(raw_crew_id)
		if crew_id > 0:
			return crew_id

	return 0