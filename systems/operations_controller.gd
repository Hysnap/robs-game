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

## Projects raw SQLite establishment docket into the flat view contract expected by GenResidentialDocket
static func _format_residential_docket_payload(raw_docket: Dictionary) -> Dictionary:
	if raw_docket.is_empty():
		return {}

	var view_data: Dictionary = raw_docket.duplicate(true)
	var hh_rows: Array = view_data.get("household", [])
	if not hh_rows.is_empty() and hh_rows[0] is Dictionary:
		var hh: Dictionary = hh_rows[0]
		view_data["residence_type"] = str(hh.get("residence_type", ""))
		view_data["local_pub_name"] = str(hh.get("local_pub_name", ""))
	else:
		view_data["residence_type"] = ""
		view_data["local_pub_name"] = ""

	var residents_summary: Array[String] = []
	for r in view_data.get("residents", []):
		if not (r is Dictionary):
			continue
		if bool(r.get("is_masked", false)):
			var decade: int = int(r.get("age_decade", 30))
			residents_summary.append("%s (Age %d+)" % [TranslationServer.translate("UI_MASKED_OCCUPANT"), decade])
		else:
			var r_name: String = str(r.get("full_name", ""))
			var r_age: int = int(r.get("age", 0))
			var r_occ: String = str(r.get("occupation", ""))
			if not r_occ.is_empty():
				residents_summary.append("%s (Age %d) — %s" % [r_name, r_age, r_occ])
			else:
				residents_summary.append("%s (Age %d)" % [r_name, r_age])

	view_data["residents_summary"] = residents_summary
	return view_data

## Builds the player's 1st-degree intel and crew context for SocietyQueries Fog-of-War filtering
static func _build_player_intel_context(ws: Dictionary) -> Dictionary:
	var crew_ids: Array[int] = []
	var residents_dict: Dictionary = ws.get("residents", {})
	for key in residents_dict.keys():
		var rec = residents_dict[key]
		if rec is Dictionary and bool(rec.get("is_crew", true)):
			var r_id: int = int(rec.get("resident_id", 0))
			if r_id > 0 and not crew_ids.has(r_id):
				crew_ids.append(r_id)

	var staff_dict: Dictionary = ws.get("staff", {})
	for key in staff_dict.keys():
		var member = staff_dict[key]
		if member is Dictionary:
			var r_id: int = int(member.get("resident_id", 0))
			if r_id > 0 and not crew_ids.has(r_id):
				crew_ids.append(r_id)

	var pk: Dictionary = ws.get("player_knowledge", {})
	return {
		"crew_resident_ids": crew_ids,
		"known_resident_ids": pk.get("known_residents", []),
		"scouted_establishment_ids": pk.get("scouted_establishments", [])
	}

static func _handle_route_request(domain_key: String, view_host: ViewHost) -> void:
	match domain_key:
		"ROSTER":
			var gs = ScenarioManifestManager.get_game_state()
			if gs == null or not "world_state" in gs: 
				return
			
			var ws: Dictionary = gs.world_state
			var current_sim_day: int = int(ws.get("metadata", {}).get("current_sim_day", 29219))
			var home_id: String = str(ws.get("operations", {}).get("home_district_id", ""))
			var home_dist_name: String = str(ws.get("districts", {}).get(home_id, {}).get("display_name", home_id))
			var enterprise_title: String = str(ws.get("operations", {}).get("enterprise_name", "CREW_ENTERPRISE"))

			var crew_source: Dictionary = ws.get("residents", ws.get("staff", {}))
			if crew_source.is_empty():
				crew_source = ws.get("staff", {})

			var crew_members: Array[Dictionary] = []
			var seen_res_ids: Dictionary = {}
			
			for staff_id in crew_source.keys():
				var member = crew_source[staff_id]
				if member is Dictionary:
					var r_id: int = int(member.get("resident_id", 0))
					if r_id > 0 and seen_res_ids.has(r_id):
						continue
					if r_id > 0:
						seen_res_ids[r_id] = true

					var name_str: String = str(member.get("name", staff_id))
					var inv: Dictionary = member.get("inventory", {})
					var cash_val: float = float(inv.get("CASH", 0.0))
					var daily_hrs: float = float(member.get("daily_operational_limit_hours", 8.0))

					var age_val: int = int(member.get("age", 25))
					if r_id > 0:
						var demo: Dictionary = SocietyQueriesScript.get_resident_profile(r_id, current_sim_day)
						age_val = int(demo.get("age", age_val))

					var summary: String = "Age %d • £%.2f • %.0fh max" % [age_val, cash_val, daily_hrs]

					crew_members.append({
						"resident_id": r_id if r_id > 0 else staff_id,
						"name": name_str,
						"summary_line": summary,
						"staff_id": staff_id,
						"assigned_district": str(member.get("current_district_id", home_id))
					})

			var intel_ctx: Dictionary = _build_player_intel_context(ws)
			var raw_contacts: Array[Dictionary] = SocietyQueriesScript.get_known_contacts_for_crew(
				intel_ctx["crew_resident_ids"],
				intel_ctx["known_resident_ids"],
				current_sim_day
			)
			var known_contacts: Array[Dictionary] = []
			for c in raw_contacts:
				var c_occ: String = str(c.get("occupation", ""))
				var c_addr: String = str(c.get("home_address", ""))
				var c_summary: String = "%s • %s" % [c_occ, c_addr] if not c_occ.is_empty() else c_addr
				known_contacts.append({
					"resident_id": int(c["resident_id"]),
					"name": str(c.get("full_name", "")),
					"summary_line": c_summary,
					"establishment_id": int(c.get("establishment_id", 0))
				})

			view_host.switch_to_domain("ROSTER")
			view_host.update_active_view_data({
				"enterprise_title": enterprise_title,
				"home_district_name": home_dist_name,
				"crew_members": crew_members,
				"known_contacts": known_contacts
			})
			
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
	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
	var current_sim_day: int = int(ws.get("metadata", {}).get("current_sim_day", 29219))
	var intel_ctx: Dictionary = _build_player_intel_context(ws)

	match target_route:
		"OPERATIVE_DETAIL", "CONTACT_DETAIL":
			if ws.is_empty():
				return
				
			var staff_dict: Dictionary = ws.get("residents", ws.get("staff", {}))
			var res_id: int = 0

			if typeof(filter_key) == TYPE_INT or (typeof(filter_key) == TYPE_STRING and str(filter_key).is_valid_int()):
				res_id = int(filter_key)
			else:
				var s_id: String = str(filter_key)
				if staff_dict.has(s_id):
					res_id = int(staff_dict[s_id].get("resident_id", 0))

			if res_id <= 0:
				SystemLogger.log_error("[OperationsController] Cannot route to %s: Invalid or missing resident_id." % target_route)
				push_error("[OperationsController] Cannot route to %s: Invalid or missing resident_id." % target_route)
				return

			var demo: Dictionary = SocietyQueriesScript.get_resident_profile(res_id, current_sim_day)
			var home_estab: int = int(demo.get("home_establishment_id", demo.get("establishment_id", 0)))
			
			if home_estab > 0:
				var raw_res_data: Dictionary = SocietyQueriesScript.get_establishment_docket(home_estab, current_sim_day, intel_ctx)
				var res_data: Dictionary = _format_residential_docket_payload(raw_res_data)
				view_host.switch_to_domain("RESIDENTIAL_DOCKET")
				view_host.update_active_view_data(res_data)
			else:
				SystemLogger.log_error("[OperationsController] Resident %d lacks a valid home establishment. Routing aborted." % res_id)
				push_error("[OperationsController] Resident %d lacks a valid home establishment. Routing aborted." % res_id)
				return

		"RESIDENTIAL_DOCKET", "ESTABLISHMENT_DOCKET":
			var estab_id: int = int(filter_key)
			if estab_id <= 0:
				SystemLogger.log_error("[OperationsController] Invalid establishment ID for docket routing.")
				push_error("[OperationsController] Invalid establishment ID for docket routing.")
				return
				
			var docket_data: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id, current_sim_day, intel_ctx)
			if target_route == "RESIDENTIAL_DOCKET":
				docket_data = _format_residential_docket_payload(docket_data)
			elif target_route == "ESTABLISHMENT_DOCKET":
				docket_data = _format_establishment_docket_payload(docket_data)
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

## Projects raw SQLite establishment docket into the flat view contract expected by GenEstablishmentDocket
static func _format_establishment_docket_payload(raw_docket: Dictionary) -> Dictionary:
	if raw_docket.is_empty():
		return {}

	var view_data: Dictionary = raw_docket.duplicate(true)
	var catchment: Dictionary = view_data.get("market_catchment", {})
	if catchment is Dictionary and not catchment.is_empty():
		view_data["total_catchment_population"] = int(catchment.get("total_catchment_population", 0))
		view_data["total_catchment_households"] = int(catchment.get("total_catchment_households", 0))
		view_data["avg_neighbor_disposable_income"] = float(catchment.get("avg_neighbor_disposable_income", 0.0))

	var personnel_summary: Array[String] = []
	for emp in view_data.get("employees", []):
		if not (emp is Dictionary):
			continue
		if bool(emp.get("is_masked", false)):
			personnel_summary.append(TranslationServer.translate("UI_MASKED_STAFF"))
		else:
			var e_name: String = str(emp.get("full_name", ""))
			var e_role: String = str(emp.get("role_title", ""))
			var e_sched: String = str(emp.get("schedule_window", ""))
			if not e_role.is_empty() and not e_sched.is_empty():
				personnel_summary.append("%s — %s (%s)" % [e_name, e_role, e_sched])
			elif not e_role.is_empty():
				personnel_summary.append("%s — %s" % [e_name, e_role])
			else:
				personnel_summary.append(e_name)

	view_data["personnel_summary"] = personnel_summary
	return view_data