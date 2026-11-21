# res://systems/target_resolvers/resolver_calendar_event.gd
class_name ResolverCalendarEvent
extends RefCounted

const DOMAIN_TOKEN := "CALENDAR_EVENT"
const DB_MGR = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

## Resolves upcoming or active 1-to-N calendar events (and any linked 1-to-1 crew event obligations) from SQLite
static func resolve(config: Dictionary, world_state: Dictionary, category_filter: String = "") -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var allowed_types: Array = config.get("event_types", [])
	var cat_upper := category_filter.strip_edges().to_upper()
	var current_day: int = CALENDAR_HELPER.get_current_sim_day(world_state)

	var crew_ids: Array[String] = []
	var residents: Dictionary = world_state.get("residents", {})
	for r_key in residents.keys():
		var rec = residents[r_key]
		if rec is Dictionary and bool(rec.get("is_crew", false)):
			var rid := str(rec.get("resident_id", r_key)).strip_edges()
			if not rid.is_empty():
				crew_ids.append("'%s'" % rid.replace("'", "''"))

	var events := DB_MGR.query_rows("""
		SELECT * FROM calendar_events
		WHERE status IN ('SCHEDULED', 'ACTIVE')
		  AND end_day >= %d
		ORDER BY start_day ASC, event_id ASC;
	""" % current_day)

	for ev in events:
		var ev_type := str(ev.get("event_type", "")).strip_edges().to_upper()
		if not allowed_types.is_empty() and not allowed_types.has(ev_type):
			continue
		if not cat_upper.is_empty() and cat_upper != "ALL" and ev_type != cat_upper:
			continue

		var ev_id := int(ev["event_id"])
		var linked_obl_id := 0
		if not crew_ids.is_empty():
			var crew_in := ", ".join(crew_ids)
			var obl_rows := DB_MGR.query_rows("""
				SELECT obligation_id FROM obligations
				WHERE linked_event_id = %d
				  AND status = 'ACTIVE'
				  AND ((debtor_scope = 'RESIDENT' AND debtor_id IN (%s)) OR (creditor_scope = 'RESIDENT' AND creditor_id IN (%s)))
				LIMIT 1;
			""" % [ev_id, crew_in, crew_in])
			if not obl_rows.is_empty():
				linked_obl_id = int(obl_rows[0]["obligation_id"])

		# Private/household events without a crew obligation or public visibility are filtered out
		var vis := str(ev.get("visibility_scope", "PUBLIC")).strip_edges().to_upper()
		if vis == "PRIVATE" and linked_obl_id == 0:
			continue

		results.append({
			"id": str(ev_id),
			"label_token": str(ev.get("title_token", "UI_EVENT_DEFAULT")),
			"category": ev_type,
			"target_node_id": str(ev.get("location_id", "")),
			"event_id": ev_id,
			"obligation_id": linked_obl_id,
			"start_day": int(ev.get("start_day", current_day)),
			"end_day": int(ev.get("end_day", current_day))
		})

	return results