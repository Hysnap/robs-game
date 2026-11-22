# res://systems/ui_commands/cmd_save_standing_order.gd
extends RefCounted

const DBManagerScript = preload("res://systems/db_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

## Persists the active operative's selected staged queue as a recurring DAILY standing order in SQLite
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not ("world_state" in gs):
		return
	var ws: Dictionary = gs.world_state

	var operative_id: Variant = payload.get("operative_id", null)
	var directives: Array = payload.get("directives", [])

	if view_host != null:
		var planner_view: Control = view_host.get_action_component()
		if is_instance_valid(planner_view) and "_queue_presenter" in planner_view and planner_view._queue_presenter != null:
			if operative_id == null:
				operative_id = planner_view._queue_presenter.get_active_operative_filter()
			if directives.is_empty():
				directives = planner_view._queue_presenter.get_staged_directives(operative_id)

	var actor_str: String = str(operative_id).strip_edges() if operative_id != null else ""
	if actor_str.is_empty() or not actor_str.is_valid_int():
		if view_host != null:
			view_host.inscribe_entry_to_domain("DIARY", {
				"text": TranslationServer.translate("UI_ERR_SELECT_SINGLE_OPERATIVE")
			})
		return

	var resident_id: int = int(actor_str)
	var selected_steps: Array[Dictionary] = []
	for d in directives:
		if d is Dictionary and bool(d.get("is_selected", true)):
			var step_copy: Dictionary = d.duplicate(true)
			step_copy.erase("is_selected")
			step_copy.erase("standing_order_warning")
			selected_steps.append(step_copy)

	if selected_steps.is_empty():
		if view_host != null:
			view_host.inscribe_entry_to_domain("DIARY", {
				"text": TranslationServer.translate("UI_ERR_NO_DIRECTIVES_TO_SAVE")
			})
		return

	var current_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var cadence_rule: String = str(payload.get("cadence_rule", "DAILY")).strip_edges().to_upper()
	var title_str: String = str(payload.get("title", "UI_STANDING_ORDER_DEFAULT")).strip_edges()
	var steps_json: String = JSON.stringify(selected_steps)

	if DBManagerScript.is_database_open():
		var reason_id: int = DBManagerScript.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
		var sql := """
			INSERT INTO standing_orders (
				assigned_resident_id, issuer_resident_id, title,
				cadence_rule, cadence_params_json, steps_json,
				priority, is_active, valid_from, change_reason_id
			) VALUES (
				%d, 0, '%s',
				'%s', '{}', '%s',
				50, 1, %d, %d
			);
		""" % [
			resident_id,
			title_str.replace("'", "''"),
			cadence_rule.replace("'", "''"),
			steps_json.replace("'", "''"),
			current_day,
			reason_id
		]
		DBManagerScript.query_rows(sql)

	if not ws.has("standing_orders") or not (ws["standing_orders"] is Dictionary):
		ws["standing_orders"] = {}
	ws["standing_orders"][str(resident_id)] = true

	if view_host != null:
		view_host.inscribe_entry_to_domain("DIARY", {
			"text": TranslationServer.translate("UI_MSG_STANDING_ORDER_SAVED")
		})