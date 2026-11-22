# res://systems/ui_commands/cmd_pause_standing_orders.gd
extends RefCounted

const SimControllerScript = preload("res://systems/sim_controller.gd")
const OperationsControllerScript = preload("res://systems/operations_controller.gd")

## Suspends the active operative's recurring standing orders for the current simulation day only
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not ("world_state" in gs):
		return
	var ws: Dictionary = gs.world_state

	var operative_id: Variant = payload.get("operative_id", null)
	if operative_id == null and view_host != null:
		var planner_view: Control = view_host.get_action_component()
		if is_instance_valid(planner_view) and "_queue_presenter" in planner_view and planner_view._queue_presenter != null:
			operative_id = planner_view._queue_presenter.get_active_operative_filter()

	var actor_str: String = str(operative_id).strip_edges() if operative_id != null else ""
	if actor_str.is_empty() or not actor_str.is_valid_int():
		if view_host != null:
			view_host.inscribe_entry_to_domain("DIARY", {
				"text": TranslationServer.translate("UI_ERR_SELECT_SINGLE_OPERATIVE")
			})
		return

	var result: Dictionary = SimControllerScript.execute_directive(ws, {
		"verb": "PAUSE_STANDING_ORDERS",
		"assigned_to": int(actor_str)
	})

	if view_host != null:
		if bool(result.get("success", false)):
			view_host.inscribe_entry_to_domain("DIARY", {
				"text": TranslationServer.translate("UI_MSG_STANDING_ORDERS_PAUSED_TODAY")
			})
			OperationsControllerScript.refresh_domain_view(view_host.get_active_domain(), view_host)