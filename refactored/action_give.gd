# res://data_modules/core/verbs/give/action_give.gd
extends ActionBase
class_name ActionGive

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
	var item_key: String = str(action.get("target_item", "CASH")).strip_edges()
	var amount: float = float(action.get("amount", 0.0))
	var target_node: String = str(action.get("target_node_id", "HQ")).strip_edges()
	
	var source_id: String = str(action.get("initiator_id", "PLAYER")).strip_edges()
	if source_id.is_empty():
		source_id = "PLAYER"

	var dest_id: String = str(action.get("counterparty_id", "")).strip_edges()
	if dest_id.is_empty():
		dest_id = str(action.get("target_entity_id", "")).strip_edges()

	if dest_id.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.INVALID_TARGET,
			"GIVE",
			"No valid recipient specified for GIVE action.",
			target_node
		).to_dict()

	if amount <= 0.0:
		return EngineResult.fail(
			EngineResult.ErrorCode.INVALID_DIRECTIVE,
			"GIVE",
			"Transfer amount must be greater than zero.",
			target_node
		).to_dict()

	var is_cash: bool = item_key.to_upper() in ["CASH", "CURRENCY", "MONEY"]
	var metric_check: String = "CASH" if is_cash else item_key

	# 1. Execution-Time Solvency Gate (Planning on Margin)
	if not ConditionEvaluator.has_sufficient(world_state, source_id, metric_check, amount):
		return EngineResult.fail(
			EngineResult.ErrorCode.INSUFFICIENT_RESOURCE,
			"GIVE",
			"Source '%s' lacks sufficient %s (%.2f required)." % [source_id, metric_check, amount],
			target_node
		).to_dict()

	# 2. State Mutation: Currency vs Commodity
	if is_cash:
		_transfer_cash(world_state, source_id, dest_id, amount)
	else:
		_transfer_commodity(world_state, source_id, dest_id, item_key, amount)

	# 3. Compile Subfolder Impacts (e.g. staff loyalty/fatigue deltas)
	var impact_scripts := ActionBase.load_subfolder_impacts("res://data_modules/core/verbs/give/impacts")
	var summary := {"amount": amount, "item": item_key, "source": source_id, "dest": dest_id}
	var compiled_deltas := ActionBase.compile_impact_deltas(impact_scripts, action, summary, {})

	var ctx := {
		"target_item": item_key,
		"amount": amount,
		"source_id": source_id,
		"dest_id": dest_id,
		"target_location": target_node
	}

	return EngineResult.ok(
		"GIVE",
		"Transferred %.2f of %s from %s to %s." % [amount, item_key, source_id, dest_id],
		compiled_deltas,
		amount,
		target_node,
		ctx
	).to_dict()

static func _transfer_cash(world_state: Dictionary, from_id: String, to_id: String, amount: float) -> void:
	# Deduct from source
	if from_id in ["PLAYER", "HQ"]:
		if not world_state.has("finances"):
			world_state["finances"] = {}
		var current_vault: float = float(world_state["finances"].get("vault_cash", world_state["finances"].get("liquid_cash", 0.0)))
		world_state["finances"]["vault_cash"] = maxf(0.0, current_vault - amount)
		if world_state["finances"].has("liquid_cash"):
			world_state["finances"]["liquid_cash"] = world_state["finances"]["vault_cash"]
	else:
		var staff_dict: Dictionary = world_state.get("staff", {})
		if staff_dict.has(from_id) and staff_dict[from_id] is Dictionary:
			var current_pocket: float = float(staff_dict[from_id].get("pocket_cash", 0.0))
			staff_dict[from_id]["pocket_cash"] = maxf(0.0, current_pocket - amount)

	# Credit to destination
	if to_id in ["PLAYER", "HQ"]:
		if not world_state.has("finances"):
			world_state["finances"] = {}
		var current_vault: float = float(world_state["finances"].get("vault_cash", world_state["finances"].get("liquid_cash", 0.0)))
		world_state["finances"]["vault_cash"] = current_vault + amount
		if world_state["finances"].has("liquid_cash"):
			world_state["finances"]["liquid_cash"] = world_state["finances"]["vault_cash"]
	else:
		var staff_dict: Dictionary = world_state.get("staff", {})
		if staff_dict.has(to_id) and staff_dict[to_id] is Dictionary:
			var current_pocket: float = float(staff_dict[to_id].get("pocket_cash", 0.0))
			staff_dict[to_id]["pocket_cash"] = current_pocket + amount

static func _transfer_commodity(world_state: Dictionary, from_id: String, to_id: String, item_key: String, amount: float) -> void:
	# Deduct from source inventory
	var source_inv: Dictionary = ConditionEvaluator.get_actor_inventory(world_state, from_id)
	var current_source_qty: float = float(source_inv.get(item_key, 0.0))
	source_inv[item_key] = maxf(0.0, current_source_qty - amount)

	# Credit to recipient inventory
	var dest_inv: Dictionary = ConditionEvaluator.get_actor_inventory(world_state, to_id)
	var current_dest_qty: float = float(dest_inv.get(item_key, 0.0))
	dest_inv[item_key] = current_dest_qty + amount