# res://data_modules/core/verbs/communicate/action_communicate.gd
extends ActionBase
class_name ActionCommunicate

static func execute(world_state: Dictionary, directive: Dictionary) -> EngineResult:
	var actor_id: String = directive.get("initiator_id", "PLAYER")
	var channel: String = directive.get("channel", "IN_PERSON_PUB") # PAYPHONE, VHF_BEEPER, IN_PERSON_PUB
	var expense: float = float(directive.get("spend_amount", 5.00)) # Pints or phone coins
	var target_node: String = directive.get("target_node_id", "")
	
	# 1. Gate Check: Liquidity
	if expense > 0.0:
		if not ConditionEvaluator.has_sufficient_resource(world_state, actor_id, "CASH", expense):
			return EngineResult.fail(
				EngineResult.ErrorCode.INSUFFICIENT_RESOURCE,
				"COMMUNICATE",
				"Not enough cash for rounds/calls (£%.2f required)." % expense,
				target_node,
				{"required_cash": expense}
			)

	# 2. Compile Deltas
	var deltas: Dictionary = {
		"WORKER_FATIGUE": -8.0 if channel == "IN_PERSON_PUB" else 0.0, # Social downtime recovers a little fatigue
		"POLICE_HEAT": 0.02 # Loose talk in public places slightly increments visibility
	}
	if expense > 0.0:
		deltas["CASH"] = -expense # ImpactRouter/SinkCash will deduct this!

	return EngineResult.ok(
		"COMMUNICATE",
		"Established contact at %s via %s." % [target_node, channel],
		deltas,
		1.0,
		target_node,
		{"channel": channel, "expense": expense}
	)