# res://systems/ui_commands/cmd_toggle_return_to_base.gd
class_name CmdToggleReturnToBase
extends RefCounted

static func execute(_payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return
	var planner_view: Control = view_host.get_action_component()
	if not is_instance_valid(planner_view) or not ("_queue" in planner_view):
		return

	var active_op_id: Variant = planner_view._queue.get_active_operative_filter()
	if active_op_id == null or not (active_op_id is int):
		SystemLogger.log_warn("[CmdToggleReturnToBase] Cannot toggle return-to-base while ALL operatives filter is active.")
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not ("world_state" in gs):
		return

	var ws: Dictionary = gs.world_state
	var residents_dict: Dictionary = ws.get("residents", {})
	if not residents_dict.has(active_op_id):
		push_error("[CmdToggleReturnToBase] FAIL_LOUD: Operative '%s' not found in canonical residents registry." % str(active_op_id))
		return

	var target_rec: Dictionary = residents_dict[active_op_id]

	var new_state: bool = not bool(target_rec.get("auto_return_to_base", false))
	target_rec["auto_return_to_base"] = new_state

	var op_display: String = str(target_rec.get("name", active_op_id))
	var rtb_display: String = TranslationServer.translate("UI_STATE_ENABLED") if new_state else TranslationServer.translate("UI_STATE_DISABLED")

	planner_view.bind_data({
		"active_operative_display": op_display,
		"return_to_base_display": rtb_display,
		"staged_queue": planner_view._queue.get_display_lines()
	})