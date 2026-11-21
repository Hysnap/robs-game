# res://systems/economy/diary_agenda_builder.gd
class_name DiaryAgendaBuilder
extends RefCounted

const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _ObligationLedger = preload("res://systems/economy/obligation_ledger.gd")
const _SocietyQueries = preload("res://systems/society_queries.gd")

## Builds the perception-scoped month grid and selected-day agenda for CalendarNavigator
static func build_calendar_payload(ws: Dictionary, current_day: int, payload: Dictionary = {}) -> Dictionary:
	var month_offset: int = int(payload.get("month_offset", 0))
	var grid_meta: Dictionary = _CalendarHelper.get_month_grid_meta(current_day, month_offset)
	var start_day: int = int(grid_meta["start_day"])
	var end_day: int = int(grid_meta["end_day"])

	var selected_day: int = int(payload.get("sim_day", -999999999))
	if selected_day < start_day or selected_day > end_day:
		selected_day = current_day if (current_day >= start_day and current_day <= end_day) else start_day

	var crew_ids := _extract_crew_ids(ws)
	var events: Array = _ObligationLedger.get_calendar_events_in_window(start_day, end_day)
	var linked_event_ids: Dictionary = _SocietyQueries.get_crew_linked_event_ids(crew_ids)
	var standalone_obligations: Array = _SocietyQueries.get_crew_standalone_obligations_in_window(crew_ids, start_day, end_day)

	var marked_days: Dictionary = {}
	var selected_day_items: Array[Dictionary] = []
	var districts: Dictionary = ws.get("districts", {})

	for ev in events:
		if not (ev is Dictionary):
			continue
		var ev_id := int(ev.get("event_id", 0))
		var vis := str(ev.get("visibility_scope", "PUBLIC")).strip_edges().to_upper()
		if vis == "PRIVATE" and not linked_event_ids.has(ev_id):
			continue

		var ev_start := maxi(start_day, int(ev.get("start_day", start_day)))
		var ev_end := mini(end_day, int(ev.get("end_day", ev_start)))
		for d in range(ev_start, ev_end + 1):
			marked_days[d] = true

		if selected_day >= int(ev.get("start_day", start_day)) and selected_day <= int(ev.get("end_day", ev_start)):
			var loc_id := str(ev.get("location_id", "")).strip_edges()
			var status_str := str(ev.get("status", "SCHEDULED")).to_upper()
			selected_day_items.append({
				"title_token": str(ev.get("title_token", "UI_EVENT_DEFAULT")),
				"location_id": loc_id,
				"location_label": _resolve_location_label(districts, loc_id),
				"event_id": ev_id,
				"can_attend": (status_str in ["SCHEDULED", "ACTIVE"]) and (selected_day >= current_day)
			})

	for obl in standalone_obligations:
		if not (obl is Dictionary):
			continue
		var due_d := int(obl.get("due_day", 0))
		if due_d >= start_day and due_d <= end_day:
			marked_days[due_d] = true
			if due_d == selected_day:
				selected_day_items.append({
					"title_token": "UI_OBL_%s" % str(obl.get("obligation_type", "DUTY")).to_upper(),
					"location_id": "",
					"location_label": "",
					"event_id": 0,
					"can_attend": false
				})

	var days_list: Array[Dictionary] = []
	for idx in range(int(grid_meta["days_in_month"])):
		var sim_d := start_day + idx
		days_list.append({
			"sim_day": sim_d,
			"day_of_month": idx + 1,
			"has_items": marked_days.has(sim_d)
		})

	var resolved_current_day: int = _CalendarHelper.get_current_sim_day({"metadata": {"current_sim_day": current_day}}) if current_day > 0 else _CalendarHelper.get_current_sim_day()

	return {
		"month_offset": month_offset,
		"month_title": str(grid_meta["month_title"]),
		"leading_blank_days": int(grid_meta["leading_blank_days"]),
		"current_sim_day": resolved_current_day,
		"selected_sim_day": selected_day,
		"selected_date_label": _CalendarHelper.format_day_localized(selected_day),
		"days": days_list,
		"selected_day_items": selected_day_items
	}

static func _extract_crew_ids(ws: Dictionary) -> Array[String]:
	var crew_ids: Array[String] = []
	var residents: Dictionary = ws.get("residents", {})
	for r_key in residents.keys():
		var rec = residents[r_key]
		if rec is Dictionary and bool(rec.get("is_crew", false)):
			var rid := str(rec.get("resident_id", r_key)).strip_edges()
			if not rid.is_empty():
				crew_ids.append(rid)
	return crew_ids

static func _resolve_location_label(districts: Dictionary, loc_id: String) -> String:
	if loc_id.is_empty():
		return ""
	if districts.has(loc_id) and districts[loc_id] is Dictionary:
		var name_tok := str(districts[loc_id].get("name_token", districts[loc_id].get("name", loc_id)))
		var translated := str(TranslationServer.translate(name_tok))
		return translated if translated != name_tok else name_tok
	return loc_id