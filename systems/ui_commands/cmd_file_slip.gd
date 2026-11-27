# res://systems/ui_commands/cmd_file_slip.gd
extends RefCounted

const _OrgRecordLedger = preload("res://systems/economy/org_record_ledger.gd")

## Files a card slip into org_records (SQLite) and inscribes it into the active domain view when in scope.
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	var slip_data: Dictionary = payload.get("slip_data", payload)
	var dest: String = str(payload.get("destination", slip_data.get("destination", "DIARY"))).to_upper().strip_edges()

	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if (gs != null and "world_state" in gs) else {}
	var ops: Dictionary = ws.get("operations", {})
	var meta: Dictionary = ws.get("metadata", {})
	var org_id: String = str(ops.get("crew_org_id", "ORG:CREW_ENTERPRISE")).strip_edges()
	var hq_estab_id: int = int(ops.get("hq_establishment_id", 0))
	var current_day: int = int(meta.get("current_sim_day", 1))

	var scope_type: String = ""
	var scope_id: String = ""
	var selected_district_id: String = str(meta.get("selected_district_id", ops.get("home_district_id", ""))).strip_edges()

	match dest:
		"DOSSIER":
			scope_type = "DISTRICT"
			scope_id = _resolve_district_scope(ws, slip_data, selected_district_id)
		"ROSTER":
			scope_type = "RESIDENT"
			scope_id = str(slip_data.get("resident_id", slip_data.get("author_resident_id", ""))).strip_edges()
		"DIARY":
			scope_type = "DAY"
			scope_id = str(int(slip_data.get("tick", slip_data.get("day_offset", current_day))))
		"FINANCE":
			scope_type = "ORG"
			scope_id = org_id

	var existing_record_id: int = int(slip_data.get("record_id", 0))
	if existing_record_id > 0:
		_OrgRecordLedger.file_record(existing_record_id, dest, scope_type, scope_id, current_day)
	else:
		_OrgRecordLedger.record_slip(org_id, slip_data, current_day, hq_estab_id, "FILED", dest, scope_type, scope_id)

	if view_host != null:
		var should_inscribe_live: bool = true
		if dest == "DOSSIER" and not scope_id.is_empty() and not selected_district_id.is_empty() and scope_id != selected_district_id:
			should_inscribe_live = false

		if should_inscribe_live:
			view_host.inscribe_entry_to_domain(dest, {
				"tick": int(slip_data.get("tick", slip_data.get("day_offset", current_day))),
				"author": str(slip_data.get("author", "")),
				"text": str(slip_data.get("display_text", slip_data.get("text", "")))
			})

	SystemLogger.log_info("[CmdFileSlip] Filed slip to %s (%s=%s): %s" % [dest, scope_type, scope_id, slip_data.get("display_text", "")])

static func _resolve_district_scope(ws: Dictionary, slip_data: Dictionary, fallback_district_id: String) -> String:
	var raw_target: String = str(slip_data.get("target_node_id", "")).strip_edges()
	var districts: Dictionary = ws.get("districts", {})
	if not raw_target.is_empty():
		if districts.has(raw_target):
			return raw_target
		var estabs: Dictionary = ws.get("establishments", {})
		var est_token: String = raw_target.trim_prefix("ESTABLISHMENT:")
		var est_rec: Variant = estabs.get(est_token, estabs.get(int(est_token) if est_token.is_valid_int() else -1, null))
		if est_rec is Dictionary:
			var parent_dist: String = str(est_rec.get("district_id", "")).strip_edges()
			if not parent_dist.is_empty():
				return parent_dist
	return fallback_district_id