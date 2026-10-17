# res://systems/verb_impact_base.gd
class_name VerbImpactBase extends RefCounted

## Metric key in world_state to modify (e.g., "POLICE_HEAT", "WORKER_FATIGUE", "ZONE_HEALTH")
static func get_target_metric() -> String:
	return ""

## TRIGGER 1 (Action Impulse): Evaluated during verb execution.
## Reads commodity velocity profile to calculate the discrete transaction delta.
static func calculate_action_delta(_action_params: Dictionary, _summary: Dictionary, _commodity_profile: Dictionary) -> float:
	return 0.0

## TRIGGER 2 (Ambient Pulse): Evaluated on every simulation tick/week.
## Handles passive decay, drift, and unprompted environmental events.
static func process_ambient_tick(_world_state: Dictionary, _node_id: String) -> float:
	return 0.0