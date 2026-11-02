# res://data_modules/core/impacts/zone_health/sink_zone_health.gd
extends ImpactSinkBase
class_name SinkZoneHealth

static func get_metric_key() -> String:
	return "ZONE_HEALTH"

static func get_target_scope() -> String:
	return "DISTRICT"

## Applies quantitative delta to the targeted district's zone health
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	var districts: Dictionary = world_state.get("districts", {})
	if districts.has(target_id):
		var cur: float = float(districts[target_id].get("actual_zone_health", 100.0))
		districts[target_id]["actual_zone_health"] = clampf(cur + delta, 0.0, 100.0)
	else:
		if not world_state.has("operations"):
			world_state["operations"] = {}
		var cur_ops: float = float(world_state["operations"].get("actual_zone_health", 100.0))
		world_state["operations"]["actual_zone_health"] = clampf(cur_ops + delta, 0.0, 100.0)

## Ambient recovery: neglected districts slowly drift towards baseline stability
static func process_ambient(world_state: Dictionary) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	for dist_id in districts.keys():
		var cur: float = float(districts[dist_id].get("actual_zone_health", 100.0))
		if cur < 100.0:
			# Passive ambient recovery: +1.0 per quiet cycle towards pristine stability
			districts[dist_id]["actual_zone_health"] = minf(100.0, cur + 1.0)