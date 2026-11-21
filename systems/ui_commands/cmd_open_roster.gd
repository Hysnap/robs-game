# res://systems/ui_commands/cmd_open_roster.gd
extends RefCounted

const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

## Switches to the Roster view and binds active crew members plus 1st-degree known contacts
static func execute(_payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var current_sim_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var home_id: String = str(ws.get("operations", {}).get("home_district_id", ""))
	var home_dist_name: String = str(ws.get("districts", {}).get(home_id, {}).get("display_name", home_id))
	var enterprise_title: String = str(ws.get("operations", {}).get("enterprise_name", "CREW_ENTERPRISE"))

	var crew_source: Dictionary = ws.get("residents", {})
	var crew_members: Array[Dictionary] = []
	var seen_res_ids: Dictionary = {}

	for slot_id in crew_source.keys():
		var member = crew_source[slot_id]
		if member is Dictionary and bool(member.get("is_crew", true)):
			var r_id: int = int(member.get("resident_id", 0))
			if r_id > 0 and seen_res_ids.has(r_id):
				continue
			if r_id > 0:
				seen_res_ids[r_id] = true

			var name_str: String = str(member.get("name", slot_id))
			var inv: Dictionary = member.get("inventory", {})
			var cash_val: float = float(inv.get("CASH", 0.0))
			var daily_hrs: float = float(member.get("daily_operational_limit_hours", 8.0))

			var age_val: int = int(member.get("age", 25))
			if r_id > 0:
				var demo: Dictionary = SocietyQueriesScript.get_resident_profile(r_id, current_sim_day)
				age_val = int(demo.get("age", age_val))

			var summary: String = "Age %d • £%.2f • %.0fh max" % [age_val, cash_val, daily_hrs]

			crew_members.append({
				"resident_id": r_id if r_id > 0 else slot_id,
				"name": name_str,
				"summary_line": summary,
				"slot_id": slot_id,
				"assigned_district": str(member.get("current_district_id", home_id))
			})

	var intel_ctx: Dictionary = IntelManagerScript.build_player_intel_context(ws)
	var raw_contacts: Array[Dictionary] = SocietyQueriesScript.get_known_contacts_for_crew(
		intel_ctx,
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