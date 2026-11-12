# res://data_modules/core/verbs/scout/action_scout.gd
extends ActionBase
class_name ActionScout

static func execute(world_state: Dictionary, directive: Dictionary) -> EngineResult:
	var actor: String = directive.get("initiator_id", "PLAYER")
	var target_district: String = directive.get("target_node_id", "")
	
	if target_district.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.INVALID_TARGET,
			"SCOUT",
			"No target district specified for scouting.",
			target_district
		)

	# 1. Determine Home Base (HQ) dynamically from business rules or operations state
	var home_turf: String = world_state.get("operations", {}).get("home_district_id", "")
	if home_turf.is_empty():
		var cfg := ConfigFile.new()
		if cfg.load("res://data_modules/core/business_rules.cfg") == OK:
			home_turf = cfg.get_value("starting_operations", "home_district_id", "block_0_0")
		else:
			home_turf = "block_0_0"

	# Desired travel & reconnaissance services
	var travel_service: String = directive.get("travel_service_id", "SERVICE_BUS_TRANSIT")
	var intel_service: String = directive.get("intel_service_id", "SERVICE_STREET_SCOUT")
	var consolidated_deltas: Dictionary = {}

	# -------------------------------------------------------------
	# STEP 1: TRAVEL OUTWARD (HQ -> Target District)
	# -------------------------------------------------------------
	var travel_out: EngineResult = ActionTravel.execute(world_state, {
		"initiator_id": actor,
		"origin_node_id": home_turf,
		"target_node_id": target_district,
		"travel_service_id": travel_service,
		"passengers": directive.get("passengers", [])
	})
	if not travel_out.success:
		return travel_out
	_merge_deltas(consolidated_deltas, travel_out.impact_deltas)

	# -------------------------------------------------------------
	# STEP 2: INVESTIGATE (Pavement Reconnaissance)
	# -------------------------------------------------------------
	var recon: EngineResult = ActionInvestigate.execute(world_state, {
		"initiator_id": actor,
		"target_node_id": target_district,
		"intel_service_id": intel_service
	})
	if not recon.success:
		# If investigation fails (e.g. insufficient funds on site), return runner home anyway
		ActionTravel.execute(world_state, {
			"initiator_id": actor,
			"origin_node_id": target_district,
			"target_node_id": home_turf,
			"travel_service_id": travel_service
		})
		return recon
	_merge_deltas(consolidated_deltas, recon.impact_deltas)

	# -------------------------------------------------------------
	# STEP 3: TRAVEL RETURN (Target District -> HQ)
	# -------------------------------------------------------------
	var travel_back: EngineResult = ActionTravel.execute(world_state, {
		"initiator_id": actor,
		"origin_node_id": target_district,
		"target_node_id": home_turf,
		"travel_service_id": travel_service,
		"passengers": directive.get("passengers", [])
	})
	if not travel_back.success:
		return travel_back
	_merge_deltas(consolidated_deltas, travel_back.impact_deltas)

	# -------------------------------------------------------------
	# STEP 4: PACKAGE FINAL RESULT
	# -------------------------------------------------------------
	var msg: String = "Scouting mission to %s completed via %s. Inked field notes added to docket." % [
		target_district, travel_service
	]
	
	var context: Dictionary = {
		"target_location": target_district,
		"travel_service": travel_service,
		"intel_service": intel_service,
		"actor": actor
	}

	return EngineResult.ok(
		"SCOUT",
		msg,
		consolidated_deltas,
		1.0,
		target_district,
		context
	)

## Helper to accumulate impact deltas across composite sub-actions
static func _merge_deltas(target: Dictionary, source: Dictionary) -> void:
	for metric in source.keys():
		target[metric] = target.get(metric, 0.0) + source[metric]