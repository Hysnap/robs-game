# res://systems/verb_impact_base.gd
class_name VerbImpactBase extends RefCounted

## Target metric key (e.g. "POLICE_HEAT", "WORKER_FATIGUE", "ZONE_HEALTH")
static func get_target_metric() -> String:
	push_error("get_target_metric() must be overridden.")
	return ""

## TRIGGER: Action Impulse (Evaluated during verb execution)
static func calculate_action_delta(_action_params: Dictionary, _summary: Dictionary, _commodity_profile: Dictionary) -> float:
	return 0.0