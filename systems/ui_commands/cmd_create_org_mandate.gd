# res://systems/ui_commands/cmd_create_org_mandate.gd
extends RefCounted

const _OrgMandateManager = preload("res://systems/economy/org_mandate_manager.gd")
const _CmdOpenManagement = preload("res://systems/ui_commands/cmd_open_management.gd")

## Creates a 4-axis delegated mandate via OrgMandateManager and refreshes the Management view
static func execute(payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [CmdCreateOrgMandate] GameState unavailable.")

	var ws: Dictionary = gs.world_state
	var mandate_spec: Dictionary = payload.duplicate(true)

	if not mandate_spec.has("org_id"):
		mandate_spec["org_id"] = "ORG:CREW_ENTERPRISE"

	var mgr_id: int = int(mandate_spec.get("manager_resident_id", 0))
	var target_org_id: String = str(mandate_spec.get("target_org_id", "")).strip_edges()

	if mgr_id <= 0 and target_org_id.is_empty():
		mgr_id = _pick_default_crew_manager(ws)

	assert(mgr_id > 0 or not target_org_id.is_empty(),
		"FATAL: [CmdCreateOrgMandate] Requires a valid integer manager_resident_id or target_org_id.")

	if mgr_id > 0:
		mandate_spec["manager_resident_id"] = mgr_id

	if str(mandate_spec.get("title", "")).strip_edges().is_empty():
		mandate_spec["title"] = TranslationServer.translate("UI_ORG_MANDATE_DEFAULT_TITLE")

	if not mandate_spec.has("scope_filter") or not (mandate_spec["scope_filter"] is Dictionary):
		var home_dist: String = str(ws.get("operations", {}).get("home_district_id", ""))
		mandate_spec["scope_filter"] = {
			"spatial": [home_dist] if not home_dist.is_empty() else [],
			"premises": [],
			"commodities": [],
			"verbs": []
		}

	_OrgMandateManager.create_mandate(ws, mandate_spec)

	if view_host != null:
		_CmdOpenManagement.execute({"keep_domain": true}, view_host, context_refs)

static func _pick_default_crew_manager(ws: Dictionary) -> int:
	var residents: Dictionary = ws.get("residents", {})
	var sorted_keys: Array = residents.keys()
	sorted_keys.sort()
	for r_id in sorted_keys:
		if r_id is int and r_id > 0:
			return r_id
	return 0