# res://systems/operations_controller.gd
class_name OperationsController
extends RefCounted

const SimControllerScript = preload("res://systems/sim_controller.gd")
const StationeryRegistryScript = preload("res://scenes/ui/feedback/stationery_registry.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")
const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const UIActionCommandScript = preload("res://scenes/ui/shell_host/ui_action_command.gd")

## Primary entry point for unified UI action commands crossing the MVC boundary
static func dispatch_ui_command(command: UIActionCommandScript, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	match command.type:
		UIActionCommandScript.CommandType.ROUTE_REQUEST:
			_handle_route_request(command.domain, view_host)
		UIActionCommandScript.CommandType.ACTION_CLICKED:
			_handle_action_clicked(command.action_code, command.payload, view_host, command.domain, context_refs)
		UIActionCommandScript.CommandType.ITEM_SELECTED:
			_handle_item_selected(command.domain, command.payload.get("filter_key"), view_host)
		UIActionCommandScript.CommandType.SLIP_FILED:
			file_card_slip(command.payload, view_host)

static func _handle_route_request(domain_key: String, view_host: ViewHost) -> void:
	match domain_key:
		"ROSTER":
			var gs = ScenarioManifestManager.get_game_state()
			if gs == null or not "world_state" in gs: 
				return
			
			var ws: Dictionary = gs.world_state
			var staff_dict: Dictionary = ws.get("staff", {})
			var home_id: String = str(ws.get("operations", {}).get("home_district_id", "block_0_0"))
			var crew_members: Array[Dictionary] = []
			
			for staff_id in staff_dict.keys():
				var member = staff_dict[staff_id]
				if member is Dictionary:
					var r_id: int = int(member.get("resident_id", 0))
					var name_str: String = str(member.get("name", staff_id))
					var cash_val: float = float(member.get("pocket_cash", 0.0))
					var daily_hrs: float = float(member.get("daily_operational_limit_hours", 8.0))

					var age_val: int = 25
					if r_id > 0:
						var demo: Dictionary = SocietyQueriesScript.get_resident_profile(r_id)
						age_val = int(demo.get("age", 25))

					var summary: String = "Age %d • £%.2f Pocket • %.0fh max" % [age_val, cash_val, daily_hrs]

					crew_members.append({
						"resident_id": r_id if r_id > 0 else staff_id,
						"name": name_str,
						"summary_line": summary,
						"staff_id": staff_id,
						"assigned_district": str(member.get("current_district_id", home_id))
					})

			view_host.switch_to_domain("ROSTER")
			view_host.update_active_view_data({"crew_members": crew_members})
			
		"DOSSIER":
			view_host.switch_to_domain("DOSSIER")
			var gs = ScenarioManifestManager.get_game_state()
			var active_id: String = ""
			if gs != null and "world_state" in gs:
				active_id = str(gs.world_state.get("selected_district_id", ""))
			if not active_id.is_empty() and gs.has_method("get_district_view"):
				view_host.update_active_view_data(gs.get_district_view(active_id))
				
		_:
			view_host.switch_to_domain(domain_key)

static func _handle_action_clicked(action_code: String, payload: Dictionary, view_host: ViewHost, domain: String, context: Dictionary) -> void:
	if domain == "INBOX":
		if action_code == "FILE":
			file_card_slip(payload, view_host)
		else:
			SystemLogger.log_info("[OperationsController] Discarded slip: %s" % payload.get("display_text"))
		return

	match action_code:
		"OPEN_PAD", "NEW_ORDER", "OPEN_COMPOSER":
			var gs = ScenarioManifestManager.get_game_state()
			var target_district: String = ""
			if gs != null and "world_state" in gs:
				target_district = str(gs.world_state.get("selected_district_id", ""))
			
			var directive_modal = context.get("directive_modal")
			if directive_modal != null and directive_modal.has_method("open_for_context"):
				directive_modal.open_for_context({"target_district_id": target_district})
				
		"COMMIT_SHIFT", "EXECUTE_TURN", "END_DAY":
			var staged: Array = []
			var planner_node = context.get("action_planner")
			if planner_node != null and planner_node.get_child_count() > 0:
				var active_planner = planner_node.get_child(0)
				if active_planner.has_method("consume_selected_directives"):
					staged = active_planner.consume_selected_directives()
				elif active_planner.has_method("get_staged_directives"):
					staged = active_planner.get_staged_directives()
					
			execute_staged_cycle(staged, view_host)

static func _handle_item_selected(target_route: String, filter_key: Variant, view_host: ViewHost) -> void:
	match target_route:
		"OPERATIVE_DETAIL":
			var gs = ScenarioManifestManager.get_game_state()
			if gs == null or not "world_state" in gs:
				return
				
			var ws: Dictionary = gs.world_state
			var staff_dict: Dictionary = ws.get("staff", {})
			var res_id: int = 0

			if typeof(filter_key) == TYPE_INT or (typeof(filter_key) == TYPE_STRING and str(filter_key).is_valid_int()):
				res_id = int(filter_key)
			else:
				var s_id: String = str(filter_key)
				if staff_dict.has(s_id):
					res_id = int(staff_dict[s_id].get("resident_id", 0))

			if res_id <= 0:
				SystemLogger.log_error("[OperationsController] Cannot route to OPERATIVE_DETAIL: Invalid or missing resident_id.")
				push_error("[OperationsController] Cannot route to OPERATIVE_DETAIL: Invalid or missing resident_id.")
				return

			var demo: Dictionary = SocietyQueriesScript.get_resident_profile(res_id)
			var home_estab: int = int(demo.get("home_establishment_id", demo.get("establishment_id", 0)))
			
			if home_estab > 0:
				var res_data: Dictionary = SocietyQueriesScript.get_establishment_docket(home_estab)
				view_host.switch_to_domain("RESIDENTIAL_DOCKET")
				view_host.update_active_view_data(res_data)
			else:
				SystemLogger.log_error("[OperationsController] Operative %d lacks a valid home establishment. Routing aborted." % res_id)
				push_error("[OperationsController] Operative %d lacks a valid home establishment. Routing aborted." % res_id)
				return

		"RESIDENTIAL_DOCKET", "ESTABLISHMENT_DOCKET":
			var estab_id: int = int(filter_key)
			if estab_id <= 0:
				SystemLogger.log_error("[OperationsController] Invalid establishment ID for docket routing.")
				push_error("[OperationsController] Invalid establishment ID for docket routing.")
				return
				
			var docket_data: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id)
			view_host.switch_to_domain(target_route)
			view_host.update_active_view_data(docket_data)

		_:
			view_host.switch_to_domain(target_route)

## Executes staged directives through SimController, updates world state, and returns UI payloads
static func execute_staged_cycle(staged_orders: Array, view_host: ViewHost = null) -> Dictionary:
	SystemLogger.log_info("[OperationsController] Executing %d staged directives." % staged_orders.size())
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		SystemLogger.log_error("[OperationsController] GameState or world_state unmounted.")
		push_error("[OperationsController] GameState or world_state unmounted.")
		return {}

	if staged_orders.is_empty():
		SystemLogger.log_info("[OperationsController] No directives staged: executing idle turn cycle.")

	# 1. Run pure simulation cycle
	var report: Dictionary = SimControllerScript.process_turn_cycle(gs.world_state, staged_orders)

	# 2. Ingest outcome slips via FeedbackTranslator
	var events: Array = report.get("executed_events", [])
	var cards: Array = FeedbackTranslatorScript.triggers_to_slip_cards(events)

	# 3. If a ViewHost is present, update the UI layers using the typed mount contract
	if view_host != null:
		var planner_view: Control = view_host.get_action_component()
		if is_instance_valid(planner_view) and planner_view.has_method("clear_staged_directives"):
			planner_view.clear_staged_directives()

		var current_date_str: String = report.get("calendar_date", "Shift Report")
		for memo in report.get("diary_memos", []):
			view_host.inscribe_entry_to_domain("DIARY", {
				"tick": report.get("week", 1),
				"text": "[%s] %s" % [current_date_str, memo]
			})

		if not cards.is_empty():
			view_host.push_feedback_slips(cards)
			if view_host.has_method("show_feedback_inbox"):
				view_host.show_feedback_inbox()

		var active_id: String = str(gs.world_state.get("selected_district_id", ""))
		if not active_id.is_empty() and gs.has_method("get_district_view"):
			var district_data: Dictionary = gs.get_district_view(active_id)
			view_host.update_active_view_data(district_data)

	# 4. Notify world of timeline step
	if gs.has_signal("turn_advanced"):
		var current_day_tick: int = int(report.get("current_sim_day", report.get("day_offset", gs.world_state.get("metadata", {}).get("current_day_tick", 1))))
		gs.turn_advanced.emit(current_day_tick)

	SystemLogger.log_info("[OperationsController] Operational cycle produced %d feedback cards." % cards.size())
	return report

## Files a card slip into the appropriate ledger domain
static func file_card_slip(card_payload: Dictionary, view_host: ViewHost = null) -> void:
	var dest: String = card_payload.get("destination", "DIARY")
	if view_host != null:
		view_host.inscribe_entry_to_domain(dest, {
			"tick": card_payload.get("tick", 1),
			"text": card_payload.get("display_text", "")
		})
	SystemLogger.log_info("[OperationsController] Filed slip to %s: %s" % [dest, card_payload.get("display_text")])