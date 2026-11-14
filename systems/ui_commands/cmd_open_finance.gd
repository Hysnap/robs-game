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
		var residents_dict: Dictionary = ws.get("residents", {})
		for slot_id in residents_dict.keys():
			var member = residents_dict[slot_id]
			if member is Dictionary and bool(member.get("is_crew", true)):
				reported_cash += float(member.get("inventory", {}).get("CASH", 0.0))

	var total_filed_expenses: float = float(pk.get("total_filed_expenses", 0.0))
	view_host.update_active_view_data({
		"reported_cash": reported_cash,
		"total_filed_expenses": total_filed_expenses
	})