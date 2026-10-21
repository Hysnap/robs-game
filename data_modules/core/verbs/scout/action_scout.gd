# res://data_modules/core/verbs/scout/action_scout.gd
extends ActionBase
class_name ActionScout

static func execute(world_state: Dictionary, directive: Dictionary) -> Dictionary:
	var actor: String = directive.get("initiator_id", "PLAYER")
	var home_turf: String = world_state.get("operations", {}).get("home_district_id", "block_0_-2")
	var target_district: String = directive.get("target_node_id", "")
	var consolidated_deltas: Dictionary = {}

	# 1. TRAVEL OUTWARD (HQ -> Target District)
	var travel_out = ActionTravel.execute(world_state, {
		"initiator_id": actor,
		"origin_node_id": home_turf,
		"target_node_id": target_district,
		"travel_mode": directive.get("travel_mode", "TRANSIT_BUS")
	})
	if not travel_out.get("success", false):
		return travel_out
	_merge_deltas(consolidated_deltas, travel_out.get("impact_deltas", {}))

	# 2. INVESTIGATE (Pavement Reconnaissance)
	var recon = ActionInvestigate.execute(world_state, {
		"initiator_id": actor,
		"target_node_id": target_district,
		"scope": "DISTRICT_PARADE"
	})
	if not recon.get("success", false):
		return recon
	_merge_deltas(consolidated_deltas, recon.get("impact_deltas", {}))

	# 3. TRAVEL RETURN (Target District -> HQ)
	var travel_back = ActionTravel.execute(world_state, {
		"initiator_id": actor,
		"origin_node_id": target_district,
		"target_node_id": home_turf,
		"travel_mode": directive.get("travel_mode", "TRANSIT_BUS")
	})
	if not travel_back.get("success", false):
		return travel_back
	_merge_deltas(consolidated_deltas, travel_back.get("impact_deltas", {}))

	return EngineResult.ok("SCOUT", "Scouted %s and returned to base." % target_district, consolidated_deltas, 1.0, target_district).to_dict()

static func _merge_deltas(target: Dictionary, source: Dictionary) -> void:
	for k in source.keys():
		target[k] = target.get(k, 0.0) + source[k]