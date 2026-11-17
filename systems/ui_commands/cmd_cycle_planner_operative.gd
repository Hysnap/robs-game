# res://systems/ui_commands/cmd_cycle_planner_operative.gd
class_name CmdCyclePlannerOperative
extends RefCounted

static func execute(_payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return
	var planner_view: Control = view_host.get_action_component()
	if not is_instance_valid(planner_view) or not ("_queue" in planner_view):
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not ("world_state" in gs):
		return

	var ws: Dictionary = gs.world_state
	var residents_dict: Dictionary = ws.get("residents", {})
	var crew_ids: Array[int] = []
	var seen_ids: Dictionary = {}

	for res_key in residents_dict.keys():
		var rec = residents_dict[res_key]
		if rec is Dictionary and bool(rec.get("is_crew", true)):
			var cid: int = int(rec.get("resident_id", res_key))
			if cid > 0 and not seen_ids.has(cid):
				seen_ids[cid] = true
				crew_ids.append(cid)

	crew_ids.sort()
	var queue_presenter = planner_view._queue
	var current_filter: Variant = queue_presenter.get_active_operative_filter()
	var next_filter: Variant = null

	if not crew_ids.is_empty():
		var idx: int = crew_ids.find(current_filter) if current_filter is int else -1
		if idx < 0:
			next_filter = crew_ids[0]
		elif idx + 1 < crew_ids.size():
			next_filter = crew_ids[idx + 1]
		else:
			next_filter = null

	queue_presenter.set_active_operative_filter(next_filter)

	var op_display: String = TranslationServer.translate("UI_OPT_ALL_OPERATIVES")
	var rtb_display: String = "-"
	if next_filter != null and residents_dict.has(next_filter):
		var target_rec: Dictionary = residents_dict[next_filter]
		op_display = str(target_rec.get("name", str(next_filter)))
		var rtb_enabled: bool = bool(target_rec.get("auto_return_to_base", false))
		rtb_display = TranslationServer.translate("UI_STATE_ENABLED") if rtb_enabled else TranslationServer.translate("UI_STATE_DISABLED")

	planner_view.bind_data({
		"active_operative_display": op_display,
		"return_to_base_display": rtb_display,
		"staged_queue": queue_presenter.get_display_lines()
	})