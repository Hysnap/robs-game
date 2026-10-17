# res://data_modules/core/verbs/sell/impacts/impact_police_heat.gd
extends VerbImpactBase
class_name ImpactPoliceHeat

## 1. IDENTITY
## Informs the verb router which global metric sink receives this calculation
static func get_target_metric() -> String:
	return "POLICE_HEAT"

## 2. ACTION IMPULSE (Triggered when SELL executes)
## Reads the commodity's impact_activations profile, passes inputs to ImpactCalculator,
## and scales by situational operational security / mobility modifiers.
static func calculate_action_delta(action_params: Dictionary, summary: Dictionary, commodity_profile: Dictionary) -> float:
	# A. Pull the impact activation rules for this verb from the commodity definition
	var activations: Array = commodity_profile.get("impact_activations", {}).get("SELL", [])
	var heat_rule: Dictionary = {}
	
	for entry in activations:
		if entry.get("metric", "") == "POLICE_HEAT":
			heat_rule = entry
			break
			
	# If this commodity generates no police heat (e.g. lemons, ice cubes), exit early
	if heat_rule.is_empty():
		return 0.0
		
	var model: String = heat_rule.get("model", "LINEAR_PER_UNIT")
	var base_factor: float = float(heat_rule.get("factor", 0.0))
	var model_params: Dictionary = heat_rule.get("params", {}).duplicate()
	var units: float = float(summary.get("units_transacted", 0.0))

	# B. Contextual & OpSec Modifiers
	# Exposure modifier (e.g., selling from a static corner vs. encrypted pagers/mobile)
	var exposure_mod: float = float(action_params.get("exposure_modifier", 1.0))
	
	# Pass through to the central math engine in systems/
	model_params["environment_weight"] = exposure_mod
	var calculated_delta: float = ImpactCalculator.calculate(model, units, base_factor, model_params)

	return calculated_delta

## 3. AMBIENT PULSE (Triggered on global weekly simulation tick)
## Evaluates background district realities without player action:
## - Passive dissipation / heat cooling off over quiet weeks
## - Spillover spikes from low Zone Health (ZHI) and desperate consumer crimes
static func process_ambient_tick(world_state: Dictionary, node_id: String) -> float:
	var district: Dictionary = world_state.get("districts", {}).get(node_id, {})
	if district.is_empty():
		return 0.0
		
	var ambient_delta: float = 0.0
	
	# A. Baseline passive dissipation (-0.03 per quiet week)
	ambient_delta -= 0.03
	
	# B. Unintended Consumer Spillover
	# When ZHI crashes (< 40%) and desperation spikes, consumer crimes (ram-raids, ATM smash-and-grabs)
	# bring regional taskforces and dragnet heat into the quadrant unprompted
	var zhi: float = float(district.get("zone_health_index", 100.0))
	var desperation: float = float(district.get("consumer_desperation_index", 0.0))
	
	# Agnostic check using ConditionEvaluator
	var is_collapsing: bool = ConditionEvaluator.evaluate(zhi, 40.0, "<")
	var is_desperate: bool = ConditionEvaluator.evaluate(desperation, 0.60, ">")
	
	if is_collapsing and is_desperate:
		# 25% chance of an ambient flashpoint event causing sudden law enforcement mobilization
		if randf() < 0.25:
			ambient_delta += 0.35
			
	return ambient_delta