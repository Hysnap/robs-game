# res://data_modules/core/impacts/scrutiny/sink_regulatory_scrutiny.gd
class_name SinkRegulatoryScrutiny
extends ImpactSinkBase

## 1. IDENTITY
static func get_metric_key() -> String:
	return "REGULATORY_SCRUTINY"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return
	
	# Sinks scrutiny into the specific district where the workshop or retail node operates
	var districts: Dictionary = world_state.get("districts", {})
	if districts.has(target_id):
		var cur: float = float(districts[target_id].get("regulatory_scrutiny", 0.0))
		districts[target_id]["regulatory_scrutiny"] = clampf(cur + delta, 0.0, 1.0)
	else:
		# Fallback to general operations scrutiny if target_id is global or unmapped
		if not world_state.has("operations"):
			world_state["operations"] = {}
		var cur_ops: float = float(world_state["operations"].get("regulatory_scrutiny", 0.0))
		world_state["operations"]["regulatory_scrutiny"] = clampf(cur_ops + delta, 0.0, 1.0)

## 3. AMBIENT DISSIPATION
static func process_ambient(world_state: Dictionary) -> void:
	# Inspection cycles cool off slowly by -0.02 per week
	var districts: Dictionary = world_state.get("districts", {})
	for dist_id in districts.keys():
		var cur: float = float(districts[dist_id].get("regulatory_scrutiny", 0.0))
		if cur > 0.0:
			districts[dist_id]["regulatory_scrutiny"] = maxf(0.0, cur - 0.02)