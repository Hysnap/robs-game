# res://systems/ui_commands/cmd_open_management.gd
extends RefCounted

const _CalendarHelper = preload("res://systems/calendar_helper.gd")
const _OrgMandateManager = preload("res://systems/economy/org_mandate_manager.gd")
const _ManagerAIResolver = preload("res://systems/economy/manager_ai_resolver.gd")

## Switches to the Organization & Mandate Management view and binds hierarchy, mandates, and collisions
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	if not bool(payload.get("keep_domain", false)):
		view_host.switch_to_domain("MANAGEMENT")

	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var meta: Dictionary = ws.get("metadata", {})
	var current_day: int = _CalendarHelper.get_current_sim_day(ws)
	var horizon: String = str(meta.get("time_horizon", "day")).to_upper()
	var checkpoint: int = int(meta.get("month_checkpoint", 0))

	var orgs: Dictionary = ws.get("organizations", {})
	var residents: Dictionary = ws.get("residents", {})
	var mandates: Dictionary = ws.get("org_mandates", {})

	var org_nodes: Array[Dictionary] = []
	var arms_length_count: int = 0
	for o_id in orgs.keys():
		var o = orgs[o_id]
		if not (o is Dictionary):
			continue
		var mode: String = str(o.get("autonomy_mode", "DIRECT")).to_upper()
		if mode == "ARMS_LENGTH":
			arms_length_count += 1
		org_nodes.append({
			"org_id": str(o_id),
			"display_name": str(o.get("display_name", o_id)),
			"status_summary": "%s | %s: %.0f%% | %s: %.0f" % [
				mode,
				TranslationServer.translate("UI_LBL_LOYALTY"),
				float(o.get("loyalty", 1.0)) * 100.0,
				TranslationServer.translate("UI_LBL_HEAT"),
				float(o.get("police_heat", 0.0))
			]
		})
	org_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["display_name"]) < str(b["display_name"])
	)

	var active_mandates_list: Array[Dictionary] = []
	var active_raw: Array[Dictionary] = []
	for m_id in mandates.keys():
		var m = mandates[m_id]
		if not (m is Dictionary) or not bool(m.get("is_active", true)):
			continue
		active_raw.append(m)
		var mgr_id: int = int(m.get("manager_resident_id", 0))
		var target_org: String = str(m.get("target_org_id", "")).strip_edges()
		var owner_label: String = target_org if not target_org.is_empty() else str(residents.get(str(mgr_id), residents.get(mgr_id, {})).get("name", str(mgr_id)))
		var scope_str: String = _format_scope_summary(m.get("scope_filter", {}))
		var locked: bool = current_day < int(m.get("commitment_lock_until_day", 0))
		var assist_open: bool = current_day <= int(m.get("assistance_request_expires_day", 0))
		var lock_tok: String = "UI_STATUS_ASSISTANCE_OPEN" if assist_open else ("UI_STATUS_LOCKED" if locked else "UI_STATUS_OPEN")

		active_mandates_list.append({
			"mandate_id": int(m.get("mandate_id", m_id)),
			"title": "%s (%s)" % [str(m.get("title", "")), owner_label],
			"scope_summary": "%s | %s | %s | %s" % [
				str(m.get("mandate_mode", "CASHFLOW")),
				str(m.get("planning_horizon", "MONTH")),
				TranslationServer.translate(lock_tok),
				scope_str
			]
		})

	var collisions: Array[Dictionary] = []
	for i in range(active_raw.size()):
		for j in range(i + 1, active_raw.size()):
			var ma: Dictionary = active_raw[i]
			var mb: Dictionary = active_raw[j]
			if str(ma.get("org_id", "")) != str(mb.get("org_id", "")):
				continue
			var id_a: int = int(ma.get("manager_resident_id", 0))
			var id_b: int = int(mb.get("manager_resident_id", 0))
			var res_a: Dictionary = residents.get(str(id_a), residents.get(id_a, {}))
			var res_b: Dictionary = residents.get(str(id_b), residents.get(id_b, {}))
			var col: Dictionary = _ManagerAIResolver.resolve_dyadic_mandate_collision(res_a, ma, res_b, mb)
			if bool(col.get("has_collision", false)):
				collisions.append({
					"collision_key": "%d_%d" % [int(ma.get("mandate_id", i)), int(mb.get("mandate_id", j))],
					"outcome_label": str(col.get("outcome", "FRICTIONAL_OVERLAP")),
					"overlap_summary": "%s <-> %s" % [str(ma.get("title", "")), str(mb.get("title", ""))]
				})

	var enterprise_name: String = str(orgs.get("ORG:CREW_ENTERPRISE", {}).get("display_name", TranslationServer.translate("UI_ORG_CHART_TITLE")))
	var cycle_text: String = "%s: %s" % [TranslationServer.translate("UI_LBL_PLANNING_HORIZON"), horizon]
	if horizon == "MONTH" and checkpoint > 0:
		cycle_text += " (%d/4)" % checkpoint

	view_host.update_active_view_data({
		"enterprise_title": enterprise_name,
		"cycle_summary": cycle_text,
		"active_mandate_count": active_mandates_list.size(),
		"arms_length_count": arms_length_count,
		"organization_nodes": org_nodes,
		"active_mandates": active_mandates_list,
		"dyadic_collisions": collisions
	})

static func _format_scope_summary(scope_filter: Variant) -> String:
	if not (scope_filter is Dictionary):
		return "*"
	var parts: Array[String] = []
	for axis in ["spatial", "premises", "commodities", "verbs"]:
		var vals = scope_filter.get(axis, [])
		if vals is Array and not vals.is_empty():
			parts.append("%s:%s" % [axis, ",".join(vals)])
	return " | ".join(parts) if not parts.is_empty() else "*"