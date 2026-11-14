# res://systems/ui_commands/cmd_open_order_composer.gd
extends RefCounted

## Opens the active shell's directive composer modal for the selected or requested district
static func execute(payload: Dictionary, _view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	var default_district: String = ""
	if gs != null and "world_state" in gs:
		default_district = str(gs.world_state.get("selected_district_id", ""))

	var target_district: String = str(payload.get("target_district_id", default_district)).strip_edges()
	var directive_modal = context_refs.get("directive_modal", null)
	assert(directive_modal != null and directive_modal.has_method("open_for_context"),
		"FATAL: [CmdOpenOrderComposer] Missing or invalid 'directive_modal' in context_refs.")

	directive_modal.open_for_context({"target_district_id": target_district})