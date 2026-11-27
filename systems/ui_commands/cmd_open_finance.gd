# res://systems/ui_commands/cmd_open_finance.gd
extends RefCounted

## Switches to the Finance / Cashbook Ledger view and binds reported cash and filed expenses
static func execute(_payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	view_host.switch_to_domain("FINANCE")
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		return

	var ws: Dictionary = gs.world_state
	var pk: Dictionary = ws.get("player_knowledge", {})
	var reported_cash: float = float(pk.get("reported_cash", 0.0))
	if not pk.has("reported_cash"):
		var ops: Dictionary = ws.get("operations", {})
		var hq_estab_id: int = int(ops.get("hq_establishment_id", 0))
		var crew_org_id: String = str(ops.get("crew_org_id", "ORG:CREW_ENTERPRISE")).strip_edges()
		var estabs_dict: Dictionary = ws.get("establishments", {})
		var counted_estabs: Dictionary = {}

		if hq_estab_id > 0:
			var hq_rec = estabs_dict.get(hq_estab_id, estabs_dict.get(str(hq_estab_id), null))
			if hq_rec is Dictionary:
				counted_estabs[hq_estab_id] = true
				reported_cash += float(hq_rec.get("inventory", {}).get("CASH", 0.0))

		for e_key in estabs_dict.keys():
			var e_rec = estabs_dict[e_key]
			if not (e_rec is Dictionary):
				continue
			var e_id: int = int(e_rec.get("establishment_id", e_key if str(e_key).is_valid_int() else 0))
			if e_id > 0 and counted_estabs.has(e_id):
				continue
			if not crew_org_id.is_empty() and str(e_rec.get("owner_org_id", "")).strip_edges() == crew_org_id:
				if e_id > 0:
					counted_estabs[e_id] = true
				reported_cash += float(e_rec.get("inventory", {}).get("CASH", 0.0))

	var total_filed_expenses: float = float(pk.get("total_filed_expenses", 0.0))
	view_host.update_active_view_data({
		"reported_cash": reported_cash,
		"total_filed_expenses": total_filed_expenses
	})