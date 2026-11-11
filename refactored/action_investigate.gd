# res://data_modules/core/verbs/investigate/action_investigate.gd
extends ActionBase
class_name ActionInvestigate

const _Calculator = preload("res://systems/impacts/impact_calculator.gd")

static func execute(world_state: Dictionary, directive: Dictionary) -> EngineResult:
	var actor_id: String = directive.get("initiator_id", "PLAYER")
	var target_district: String = directive.get("target_node_id", "")
	var target_venue_id: String = directive.get("venue_id", "")
	var service_id: String = directive.get("intel_service_id", "SERVICE_STREET_SCOUT")
	var current_tick: int = world_state.get("metadata", {}).get("current_week_tick", 1)

	# 1. Target District Validation
	if not world_state.get("districts", {}).has(target_district):
		return EngineResult.fail(
			EngineResult.ErrorCode.INVALID_TARGET,
			"INVESTIGATE",
			"Target district does not exist on map: %s" % target_district,
			target_district
		)

	var district: Dictionary = world_state["districts"][target_district]

	# 2. Venue Resolution & Staff Standing Initializer
	var venues: Dictionary = district.get("venues", {})
	if target_venue_id.is_empty() and not venues.is_empty():
		target_venue_id = venues.keys()[0]

	if not venues.has(target_venue_id):
		venues[target_venue_id] = {
			"venue_id": target_venue_id,
			"venue_name": "Local Taproom",
			"catchment_population": 400,
			"staff_reputation": {}
		}
		district["venues"] = venues

	var venue: Dictionary = venues[target_venue_id]
	if not venue.has("staff_reputation"):
		venue["staff_reputation"] = {}

	if not venue["staff_reputation"].has(actor_id):
		venue["staff_reputation"][actor_id] = {
			"familiarity_ticks": 0,
			"personal_reputation": 0.0,
			"personal_influence": 0.0
		}

	var personal_data: Dictionary = venue["staff_reputation"][actor_id]
	var current_rep: float = float(personal_data.get("personal_reputation", 0.0))
	var visits: int = int(personal_data.get("familiarity_ticks", 0))
	personal_data["familiarity_ticks"] = visits + 1

	# 3. Fetch Reconnaissance Service Profile
	var registry: Dictionary = world_state.get("commodity_registry", {})
	var service: Dictionary = registry.get(service_id, {})
	if service.is_empty():
		return EngineResult.fail(
			EngineResult.ErrorCode.UNKNOWN_COMMODITY,
			"INVESTIGATE",
			"Unknown intelligence reconnaissance service: %s" % service_id,
			target_district
		)

	# 4. Dynamic Impact Calculation via ImpactCalculator
	var deltas: Dictionary = {}
	var activations: Array = service.get("impact_activations", {}).get("INVESTIGATE", [])
	
	for entry in activations:
		var metric: String = entry.get("metric", "")
		var model: String = entry.get("model", "LINEAR_PER_UNIT")
		var factor: float = float(entry.get("factor", 0.0))
		var params: Dictionary = entry.get("params", {}).duplicate()

		if model == "INVERTED_U_CURVE":
			params["optimal_input"] = lerp(4.0, 30.0, current_rep / 100.0)
			params["tolerance_range"] = lerp(6.0, 45.0, current_rep / 100.0)
		
		var delta_val: float = _Calculator.calculate(model, 1.0, factor, params)
		if metric != "" and delta_val != 0.0:
			deltas[metric] = deltas.get(metric, 0.0) + delta_val

	# 5. Solvency Gate Check
	var required_cash: float = abs(deltas.get("CASH", 0.0))
	if required_cash > 0.0:
		if not ConditionEvaluator.has_sufficient(world_state, actor_id, "CASH", required_cash):
			return EngineResult.fail(
				EngineResult.ErrorCode.INSUFFICIENT_RESOURCE,
				"INVESTIGATE",
				"Cannot afford expenses of £%.2f for %s." % [required_cash, service.get("display_name", service_id)],
				target_district,
				{"required_cash": required_cash, "service_id": service_id}
			)

	# 6. Apply Personal Reputation Gain to Venue
	personal_data["personal_reputation"] = clamp(current_rep + 2.5 + (visits * 0.2), 0.0, 100.0)
	venue["staff_reputation"][actor_id] = personal_data

	# 7. Diegetic Filofax Perception Snapshot
	var cache: Dictionary = world_state.get("filofax_cache", {}).get("districts", {})
	if not cache.has(target_district):
		cache[target_district] = {}

	var perceived_entry: Dictionary = cache[target_district]
	var intel_props: Dictionary = service.get("intel_properties", {})
	var blur: float = float(intel_props.get("variance_blur", 0.0))
	var scope: String = intel_props.get("scope", "DISTRICT_PARADE")

	var skill_modifier: float = 1.0
	if actor_id != "PLAYER" and world_state.get("staff", {}).has(actor_id):
		var staff_skill: float = float(world_state["staff"][actor_id].get("skill_rating", 0.5))
		skill_modifier = max(0.2, 1.0 - (staff_skill * 0.5))

	var effective_blur: float = blur * skill_modifier
	var jitter: float = randf_range(-effective_blur, effective_blur)

	perceived_entry["survey_status"] = "SURVEYED"
	perceived_entry["district_type"] = district.get("district_type", "Residential")
	perceived_entry["data_age_ticks"] = 0
	perceived_entry["last_verified_tick"] = current_tick
	perceived_entry["confidence_rating"] = intel_props.get("confidence_rating", 0.8)

	var true_heat: float = float(district.get("actual_police_heat", 0.20))
	var true_zhi: float = float(district.get("zone_health_index", 50.0))
	perceived_entry["inked_police_heat"] = clamp(true_heat + jitter, 0.0, 1.0)
	perceived_entry["inked_zone_health"] = clamp(true_zhi + (jitter * 100.0), 0.0, 100.0)

	if scope == "RUMOUR":
		perceived_entry["notes"] = "Taproom whispers & pub hearsay. Unverified street word."
	else:
		perceived_entry["notes"] = "Pavements walked. Commercial parade and uniform foot patrol presence catalogued."

	var msg: String = "%s completed on %s (Spent: £%.2f | ~%.0f mins | Heat Inked: %d%%)." % [
		service.get("display_name", "Reconnaissance"),
		district.get("display_name", target_district),
		required_cash,
		deltas.get("OPERATIONAL_TIME", 0.0),
		int(perceived_entry["inked_police_heat"] * 100)
	]

	return EngineResult.ok(
		"INVESTIGATE",
		msg,
		deltas,
		1.0,
		target_district,
		{
			"service_id": service_id,
			"venue_id": target_venue_id,
			"personal_rep": personal_data["personal_reputation"],
			"confidence": perceived_entry["confidence_rating"]
		}
	)