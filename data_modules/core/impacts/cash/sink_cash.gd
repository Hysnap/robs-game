# res://data_modules/core/impacts/cash/sink_cash.gd
extends ImpactSinkBase
class_name SinkCash

static func get_metric_key() -> String:
	return "CASH"

static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	# 1. Check if the actor is a staff member
	var staff_table = world_state.get("staff", {})
	if staff_table.has(target_id):
		var staff_member: Dictionary = staff_table[target_id]
		staff_member["cash"] = max(0.0, float(staff_member.get("cash", 0.0)) + delta)
		return

	# 2. Check if the actor is an NPC / Counterparty / Faction
	var npcs = world_state.get("counterparties", world_state.get("npcs", {}))
	if npcs.has(target_id):
		var npc: Dictionary = npcs[target_id]
		npc["cash"] = max(0.0, float(npc.get("cash", 0.0)) + delta)
		return

	# 3. Default Actor: Player / Vault Finances
	# (Matches whatever initiator_id represents the player's core ledger)
	var finances = world_state.get("finances", {})
	var current: float = float(finances.get("liquid_cash", 0.0))
	finances["liquid_cash"] = max(0.0, current + delta)