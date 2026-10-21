# res://data_modules/core/verbs/travel/action_travel.gd
extends ActionBase
class_name ActionTravel

const _Calculator = preload("res://systems/impacts/impact_calculator.gd")

static var _fallback_hierarchy: Array = []

static func _ensure_fallbacks_loaded() -> void:
	if not _fallback_hierarchy.is_empty():
		return
	var path := "res://data_modules/core/business_rules.cfg"
	if FileAccess.file_exists(path):
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK and cfg.has_section("travel_fallback_hierarchy"):
			for key in cfg.get_section_keys("travel_fallback_hierarchy"):
				_fallback_hierarchy.append(cfg.get_value("travel_fallback_hierarchy", key))
	if _fallback_hierarchy.is_empty():
		# Safe engine defaults if config is missing
		_fallback_hierarchy = ["SERVICE_BLACK_CAB", "SERVICE_MINI_CAB", "SERVICE_BUS_TRANSIT", "SERVICE_WALK"]

static func execute(world_state: Dictionary, directive: Dictionary) -> EngineResult:
	_ensure_fallbacks_loaded()
	
	var actor_id: String = directive.get("initiator_id", "PLAYER")
	var origin_id: String = directive.get("origin_node_id", "")
	var target_id: String = directive.get("target_node_id", "")
	var requested_service_id: String = directive.get("travel_service_id", "SERVICE_BUS_TRANSIT")
	
	# Capacity / Group context
	var group_members: Array = directive.get("passengers", [])
	var passenger_count: int = max(group_members.size(), int(directive.get("passenger_count", 1)))
	var cargo_volume: float = float(directive.get("cargo_volume_litres", 0.0))

	# 1. Validation: Already there?
	if origin_id == target_id or target_id.is_empty():
		return EngineResult.ok("TRAVEL", "Already at destination.", {}, 0.0, target_id)

	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(origin_id) or not districts.has(target_id):
		return EngineResult.fail(
			EngineResult.ErrorCode.INVALID_TARGET, 
			"TRAVEL", 
			"Invalid spatial nodes: %s -> %s" % [origin_id, target_id], 
			target_id,
			{"origin": origin_id, "target": target_id}
		)

	var pos_origin: Vector2 = districts[origin_id].get("spatial_anchor", Vector2.ZERO)
	var pos_target: Vector2 = districts[target_id].get("spatial_anchor", Vector2.ZERO)
	var travel_distance: float = pos_origin.distance_to(pos_target)

	# 2. RESOLVE TRAVEL SERVICE WITH AFFORDABILITY FALLBACK
	var registry: Dictionary = world_state.get("commodity_registry", {})
	var chosen_service_id: String = requested_service_id
	var resolved_plan: Dictionary = {}
	var was_downgraded: bool = false
	
	# Determine candidate order starting from the requested service
	var candidate_services: Array = []
	var start_idx = _fallback_hierarchy.find(requested_service_id)
	if start_idx != -1:
		for i in range(start_idx, _fallback_hierarchy.size()):
			candidate_services.append(_fallback_hierarchy[i])
	else:
		candidate_services.append(requested_service_id)
		for s in _fallback_hierarchy:
			if not candidate_services.has(s):
				candidate_services.append(s)

	# Iterate candidate modes until finding one the actor can afford and fit into
	for candidate_id in candidate_services:
		var service: Dictionary = registry.get(candidate_id, {})
		if service.is_empty():
			continue

		var evaluation = _evaluate_service_journey(world_state, actor_id, service, travel_distance, passenger_count, cargo_volume)
		if evaluation["affordable"] and evaluation["fits_capacity"]:
			chosen_service_id = candidate_id
			resolved_plan = evaluation
			was_downgraded = (candidate_id != requested_service_id)
			break

	if resolved_plan.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.CAPACITY_EXCEEDED,
			"TRAVEL",
			"No viable transport mode found capable of carrying %d passenger(s) and %.1fL cargo." % [passenger_count, cargo_volume],
			target_id
		)

	# 3. UPDATE SPATIAL POSITION ON SUCCESS
	if actor_id != "PLAYER" and world_state.get("staff", {}).has(actor_id):
		world_state["staff"][actor_id]["current_district_id"] = target_id
	else:
		world_state["operations"]["current_district_id"] = target_id

	var service_name = registry.get(chosen_service_id, {}).get("display_name", chosen_service_id)
	var travel_time: float = resolved_plan["deltas"].get("OPERATIONAL_TIME", 0.0)
	var total_fare: float = resolved_plan["fare"]
	
	var msg := ""
	if was_downgraded:
		msg = "Couldn't afford requested transit; downgraded to %s for journey to %s (%.0fm | ~%.0f mins | Fare: £%.2f)." % [
			service_name, target_id, travel_distance, travel_time, total_fare
		]
	else:
		msg = "Journey: %s -> %s via %s (%.0fm | ~%.0f mins | Fare: £%.2f)." % [
			origin_id, target_id, service_name, travel_distance, travel_time, total_fare
		]

	return EngineResult.ok(
		"TRAVEL",
		msg,
		resolved_plan["deltas"],
		travel_distance,
		target_id,
		{
			"distance": travel_distance, 
			"fare": total_fare, 
			"time_spent": travel_time,
			"service_id": chosen_service_id, 
			"requested_service_id": requested_service_id,
			"was_downgraded": was_downgraded,
			"passengers": passenger_count,
			"vehicles": resolved_plan["vehicles_needed"]
		}
	)

## Internal helper: calculates capacity, fare, and deltas for a specific candidate service
static func _evaluate_service_journey(
	world_state: Dictionary, 
	actor_id: String, 
	service: Dictionary, 
	travel_distance: float, 
	passenger_count: int, 
	cargo_volume: float
) -> Dictionary:
	var cap_rules: Dictionary = service.get("capacity", {})
	var max_seats: int = int(cap_rules.get("max_passengers_per_unit", 4))
	var max_cargo: float = float(cap_rules.get("max_cargo_volume_litres", 50.0))
	var fleet_scale_allowed: bool = bool(cap_rules.get("requires_multiple_units_for_groups", true))
	var service_id: String = service.get("id", "")

	# Check cargo capacity
	if cargo_volume > max_cargo:
		return {"fits_capacity": false, "affordable": false}

	var vehicles_needed: int = 1
	if fleet_scale_allowed:
		vehicles_needed = int(ceil(float(passenger_count) / float(max(max_seats, 1))))
	elif passenger_count > max_seats:
		return {"fits_capacity": false, "affordable": false}

	# Evaluate impacts via ImpactCalculator
	var deltas: Dictionary = {}
	var base_drop: float = float(service.get("base_fare_drop", 0.0))
	var activations: Array = service.get("impact_activations", {}).get("TRAVEL", [])

	for entry in activations:
		var metric: String = entry.get("metric", "")
		var model: String = entry.get("model", "LINEAR_PER_UNIT")
		var factor: float = float(entry.get("factor", 0.0))
		var params: Dictionary = entry.get("params", {}).duplicate()
		
		var delta_val: float = _Calculator.calculate(model, travel_distance, factor, params)
		
		if metric == "CASH":
			if service_id == "SERVICE_BUS_TRANSIT":
				delta_val *= float(passenger_count)
			else:
				delta_val *= float(vehicles_needed)
				
		if metric != "" and delta_val != 0.0:
			deltas[metric] = deltas.get(metric, 0.0) + delta_val

	if base_drop > 0.0:
		var total_flag_drop = base_drop * (float(passenger_count) if service_id == "SERVICE_BUS_TRANSIT" else float(vehicles_needed))
		deltas["CASH"] = deltas.get("CASH", 0.0) - total_flag_drop

	var total_fare: float = abs(deltas.get("CASH", 0.0))
	var is_affordable: bool = true
	if total_fare > 0.0:
		is_affordable = ConditionEvaluator.has_sufficient_resource(world_state, actor_id, "CASH", total_fare)

	return {
		"fits_capacity": true,
		"affordable": is_affordable,
		"deltas": deltas,
		"fare": total_fare,
		"vehicles_needed": vehicles_needed
	}