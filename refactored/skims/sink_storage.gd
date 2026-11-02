# res://data_modules/core/impacts/storage/sink_storage.gd
class_name SinkMaterialStorage
extends ImpactSinkBase

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "MATERIAL_STORAGE"

static func get_target_scope() -> String:
	return "ACTOR"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return
	
	if target_id != "" and target_id != "PLAYER" and world_state.get("staff", {}).has(target_id):
		var staff_member: Dictionary = world_state["staff"][target_id]
		var cur: float = float(staff_member.get("material_storage_accumulated", 0.0))
		staff_member["material_storage_accumulated"] = maxf(0.0, cur + delta)
	else:
		if not world_state.has("operations"):
			world_state["operations"] = {}
		var cur_ops: float = float(world_state["operations"].get("material_storage_accumulated", 0.0))
		world_state["operations"]["material_storage_accumulated"] = maxf(0.0, cur_ops + delta)

## 3. AMBIENT HEARTBEAT
static func process_ambient(_world_state: Dictionary) -> void:
	pass