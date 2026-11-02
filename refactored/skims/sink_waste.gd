# res://data_modules/core/impacts/waste/sink_waste.gd
class_name SinkMaterialWaste
extends ImpactSinkBase

## 1. IDENTITY
static func get_metric_key() -> String:
	return "MATERIAL_WASTE"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, _target_id: String, delta: float) -> void:
	if delta == 0.0:
		return
	
	if not world_state.has("operations"):
		world_state["operations"] = {}
	
	var current: float = float(world_state["operations"].get("material_waste_accumulated", 0.0))
	world_state["operations"]["material_waste_accumulated"] = maxf(0.0, current + delta)

## 3. AMBIENT DISSIPATION / CLEARING
static func process_ambient(world_state: Dictionary) -> void:
	# Passive cleaning/binning reduces accumulated scrap by up to 2.0 units per week
	if world_state.has("operations"):
		var cur: float = float(world_state["operations"].get("material_waste_accumulated", 0.0))
		world_state["operations"]["material_waste_accumulated"] = maxf(0.0, cur - 2.0)