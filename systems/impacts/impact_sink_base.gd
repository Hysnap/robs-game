# res://systems/impacts/impact_sink_base.gd
class_name ImpactSinkBase extends RefCounted

## 1. IDENTITY
## Returns the string token that matches the metric in commodity impact activations
## (e.g., "POLICE_HEAT", "ZONE_HEALTH", "WORKER_FATIGUE")
static func get_metric_key() -> String:
	push_error("get_metric_key() must be overridden by concrete metric sink.")
	return ""

## 2. ACTION IMPULSE CONTRACT
## Called when a Verb + Commodity calculation produces a delta.
## Mutates the target state (district, inventory, or player operations) with clamping.
static func apply_delta(_world_state: Dictionary, _target_id: String, _delta: float) -> void:
	push_error("apply_delta() must be overridden by concrete metric sink.")

## 3. AMBIENT HEARTBEAT CONTRACT
## Called at the end of every simulation turn/week tick.
## Handles passive drift, natural dissipation, or threshold event triggers.
static func process_ambient(_world_state: Dictionary) -> void:
	pass # Optional: not all metrics need ambient background drift

## For SQL-backed metrics: computes the live ground truth value for a target entity/district
static func query_metric_value(_target_id: String) -> Variant:
	return null