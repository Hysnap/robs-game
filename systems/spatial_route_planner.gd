# res://systems/spatial_route_planner.gd
class_name SpatialRoutePlanner
extends RefCounted

const IMPACT_CALCULATOR = preload("res://systems/impacts/impact_calculator.gd")
const METERS_PER_DISTANCE_UNIT: float = 100.0

## Ensures world_state["transit_stops"] is procedurally populated from transport_modes.json rules
static func ensure_transit_stops(world_state: Dictionary) -> void:
	if world_state.has("transit_stops") and world_state["transit_stops"] is Dictionary and not world_state["transit_stops"].is_empty():
		return
	deploy_transit_stops(world_state)

## Procedurally generates transit stops along visible road/rail edges or junctions using transport_modes.json
static func deploy_transit_stops(world_state: Dictionary) -> Dictionary:
	assert(ScenarioManifestManager.has_module("transport_modes"),
		"FATAL: [SpatialRoutePlanner] Scenario manifest missing 'transport_modes' module.")
	var modes_cfg: Dictionary = ScenarioManifestManager.load_module("transport_modes")
	var modes: Dictionary = modes_cfg.get("modes", {})
	var graph: Dictionary = build_spatial_graph(world_state, modes_cfg)
	var stops: Dictionary = {}

	for mode_id in modes.keys():
		var mode_def: Dictionary = modes[mode_id]
		var placement = mode_def.get("stop_placement", null)
		if not (placement is Dictionary) or placement.is_empty():
			continue

		var strategy: String = str(placement.get("strategy", "EDGE_MIDPOINT")).to_upper()
		var base_spacing: float = float(placement.get("min_spacing_m", 200.0))
		var eligible_classes: Array = placement.get("eligible_road_classes", [])
		var density_mults: Dictionary = placement.get("district_density_multipliers", {})
		var placed_positions: Array[Vector2] = []
		var stop_idx: int = 0

		if strategy == "EDGE_MIDPOINT":
			var edge_keys: Array = graph["edges"].keys()
			edge_keys.sort()
			for edge_id in edge_keys:
				var edge: Dictionary = graph["edges"][edge_id]
				if str(edge.get("kind", "")) != "ROAD":
					continue
				var r_class: String = str(edge.get("road_class", ""))
				if not eligible_classes.is_empty() and not eligible_classes.has(r_class):
					continue
				var pos: Vector2 = edge["midpoint"]
				var d_id: String = str(edge.get("primary_district_id", ""))
				var d_type: String = str(world_state.get("districts", {}).get(d_id, {}).get("district_type", "DEFAULT"))
				var mult: float = float(density_mults.get(d_type, density_mults.get("DEFAULT", 1.0)))
				var min_dist: float = base_spacing * mult

				if _is_far_enough(pos, placed_positions, min_dist):
					placed_positions.append(pos)
					stop_idx += 1
					var stop_id := "STOP:%s:%s" % [mode_id, edge_id]
					stops[stop_id] = {
						"stop_id": stop_id,
						"mode_id": mode_id,
						"strategy": strategy,
						"position": pos,
						"edge_id": edge_id,
						"node_a": edge["from"],
						"node_b": edge["to"],
						"district_id": d_id,
						"sector": _resolve_district_sector(world_state, d_id),
						"active": true
					}
		elif strategy == "JUNCTION":
			var node_keys: Array = graph["nodes"].keys()
			node_keys.sort()
			for node_id in node_keys:
				var node: Dictionary = graph["nodes"][node_id]
				if str(node.get("kind", "")) != "JUNCTION":
					continue
				if not _junction_has_eligible_road(node_id, graph, eligible_classes):
					continue
				var pos: Vector2 = node["position"]
				var d_id: String = str(node.get("primary_district_id", ""))
				var d_type: String = str(world_state.get("districts", {}).get(d_id, {}).get("district_type", "DEFAULT"))
				var mult: float = float(density_mults.get(d_type, density_mults.get("DEFAULT", 1.0)))
				var min_dist: float = base_spacing * mult

				if _is_far_enough(pos, placed_positions, min_dist):
					placed_positions.append(pos)
					stop_idx += 1
					var stop_id := "STOP:%s:%s" % [mode_id, node_id]
					stops[stop_id] = {
						"stop_id": stop_id,
						"mode_id": mode_id,
						"strategy": strategy,
						"position": pos,
						"edge_id": "",
						"node_a": node_id,
						"node_b": node_id,
						"district_id": d_id,
						"sector": _resolve_district_sector(world_state, d_id),
						"active": true
					}

	world_state["transit_stops"] = stops
	return stops

## Plans a complete multi-leg route between two districts using transport_registry and transport_modes.json
static func plan_route(
	world_state: Dictionary,
	origin_district_id: String,
	dest_district_id: String,
	options: Dictionary = {}
) -> Dictionary:
	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(origin_district_id) or not districts.has(dest_district_id):
		return {"reachable": false, "error_code": "INVALID_TARGET", "legs": []}

	if origin_district_id == dest_district_id:
		return {
			"reachable": true,
			"service_id": "SERVICE_WALK",
			"mode_id": "WALK",
			"routing_policy": str(options.get("routing_policy", "SHORTEST")),
			"legs": [],
			"total_distance_m": 0.0,
			"total_distance_units": 0.0,
			"total_duration_minutes": 0.0,
			"total_operational_time": 0.0,
			"total_fare": 0.0,
			"total_fatigue": 0.0
		}

	assert(ScenarioManifestManager.has_module("transport_modes"),
		"FATAL: [SpatialRoutePlanner] Scenario manifest missing 'transport_modes' module.")
	var modes_cfg: Dictionary = ScenarioManifestManager.load_module("transport_modes")
	ensure_transit_stops(world_state)

	var requested_service: String = str(options.get("service_id", "AUTO")).strip_edges().to_upper()
	var routing_policy: String = str(options.get("routing_policy", modes_cfg.get("default_routing_policy", "SHORTEST"))).strip_edges().to_upper()
	var waypoints: Array = options.get("waypoints", [])
	var actor_id: String = str(options.get("actor_id", ""))
	var is_off_peak: bool = bool(options.get("is_off_peak", false))

	var graph: Dictionary = build_spatial_graph(world_state, modes_cfg)
	var transport_reg: Dictionary = world_state.get("transport_registry", {})
	assert(not transport_reg.is_empty(), "FATAL: [SpatialRoutePlanner] world_state['transport_registry'] is empty.")

	# Resolve candidate service list (explicit service_id or fallback_hierarchy)
	var candidate_services: Array[String] = []
	if requested_service != "" and requested_service != "AUTO":
		assert(transport_reg.has(requested_service),
			"FATAL: [SpatialRoutePlanner] Unknown transport service '%s'." % requested_service)
		candidate_services.append(requested_service)
	else:
		for fb_id in modes_cfg.get("fallback_hierarchy", []):
			var s_id := str(fb_id).strip_edges().to_upper()
			if transport_reg.has(s_id):
				candidate_services.append(s_id)
		if not candidate_services.has("SERVICE_WALK") and transport_reg.has("SERVICE_WALK"):
			candidate_services.append("SERVICE_WALK")

	var current_year: int = int(world_state.get("metadata", {}).get("calendar_year", 1980))
	var actor_record: Dictionary = _resolve_actor_record(world_state, actor_id)
	var actor_cash: float = float(actor_record.get("inventory", {}).get("CASH", 0.0))

	for service_id in candidate_services:
		var service_def: Dictionary = transport_reg[service_id]
		var from_yr: int = int(service_def.get("valid_from_year", -9999))
		var to_yr: int = int(service_def.get("valid_to_year", 9999))
		if current_year < from_yr or current_year > to_yr:
			continue

		var mode_id: String = str(service_def.get("mode_id", "WALK")).to_upper()
		var modes_dict: Dictionary = modes_cfg.get("modes", {})
		assert(modes_dict.has(mode_id), "FATAL: [SpatialRoutePlanner] Service '%s' references unknown mode_id '%s'." % [service_id, mode_id])
		var mode_def: Dictionary = modes_dict[mode_id]

		# Check required item (e.g., BICYCLE or MOTOR_CAR) if not explicitly forced
		var req_item = mode_def.get("requires_item", null)
		if req_item != null and not str(req_item).is_empty():
			var owned_qty: float = float(actor_record.get("inventory", {}).get(str(req_item), 0.0))
			if owned_qty <= 0.0 and requested_service == "AUTO":
				continue

		var plan: Dictionary = _build_multileg_plan(
			world_state,
			graph,
			modes_cfg,
			service_def,
			mode_def,
			origin_district_id,
			dest_district_id,
			routing_policy,
			waypoints,
			is_off_peak
		)
		if not bool(plan.get("reachable", false)):
			continue

		# In AUTO fallback mode, verify the actor has enough physical CASH for the fare
		if requested_service == "AUTO" and not actor_id.is_empty():
			if float(plan.get("total_fare", 0.0)) > actor_cash + 0.0001:
				continue

		return plan

	return {"reachable": false, "error_code": "ROUTE_UNREACHABLE", "legs": []}

## Builds the 1-leg or 3-leg multi-modal journey for a specific service definition
static func _build_multileg_plan(
	world_state: Dictionary,
	graph: Dictionary,
	modes_cfg: Dictionary,
	service_def: Dictionary,
	mode_def: Dictionary,
	origin_district_id: String,
	dest_district_id: String,
	routing_policy: String,
	waypoints: Array,
	is_off_peak: bool
) -> Dictionary:
	var mode_id: String = str(service_def.get("mode_id", "WALK")).to_upper()
	var service_id: String = str(service_def.get("id", "SERVICE_WALK")).to_upper()
	var entry_access = mode_def.get("entry_access_mode", null)
	var exit_access = mode_def.get("exit_access_mode", null)
	var allowed_classes: Array = service_def.get("allowed_road_classes", mode_def.get("eligible_road_classes", []))
	var speed_kph: float = float(mode_def.get("base_speed_kph", 5.0)) * float(service_def.get("speed_multiplier", 1.0))

	var legs: Array[Dictionary] = []
	var origin_anchor: Vector2 = world_state["districts"][origin_district_id]["spatial_anchor"]
	var dest_anchor: Vector2 = world_state["districts"][dest_district_id]["spatial_anchor"]

	# Case A: Direct center-to-center mode (WALK, BIKE)
	if entry_access == null and exit_access == null:
		var direct_nodes: Array[String] = _build_waypoint_chain(origin_district_id, dest_district_id, waypoints)
		var total_m: float = 0.0
		var full_path: Array[String] = []
		var total_heat_exposure: float = 0.0
		var total_crowd_exposure: float = 0.0

		for i in range(direct_nodes.size() - 1):
			var seg_from := "DISTRICT:%s" % direct_nodes[i]
			var seg_to := "DISTRICT:%s" % direct_nodes[i + 1]
			var astar := _run_astar(graph, modes_cfg, seg_from, seg_to, allowed_classes, speed_kph, routing_policy)
			if not bool(astar.get("reachable", false)):
				return {"reachable": false, "error_code": "ROUTE_UNREACHABLE", "legs": []}
			total_m += float(astar["distance_m"])
			total_heat_exposure += float(astar["heat_exposure"])
			total_crowd_exposure += float(astar["crowd_exposure"])
			for p_node in astar["path"]:
				if full_path.is_empty() or full_path[full_path.size() - 1] != p_node:
					full_path.append(p_node)

		var leg := _evaluate_service_leg(
			world_state, service_def, mode_id,
			"DISTRICT:%s" % origin_district_id,
			"DISTRICT:%s" % dest_district_id,
			total_m, speed_kph, 0.0, full_path
		)
		legs.append(leg)
		return _finalize_plan_totals(service_id, mode_id, routing_policy, legs, total_heat_exposure, total_crowd_exposure)

	# Case B: Multi-leg stop/terminal mode (BUS, TAXI, CAR, RAIL)
	var stop_filter = service_def.get("stop_strategy_filter", null)
	var origin_stop: Dictionary = _find_nearest_stop(world_state, mode_id, origin_anchor, stop_filter)
	var dest_stop: Dictionary = _find_nearest_stop(world_state, mode_id, dest_anchor, stop_filter)
	if origin_stop.is_empty() or dest_stop.is_empty():
		return {"reachable": false, "error_code": "ROUTE_UNREACHABLE", "legs": []}

	var walk_service: Dictionary = world_state.get("transport_registry", {}).get("SERVICE_WALK", {})
	var walk_mode: Dictionary = modes_cfg.get("modes", {}).get("WALK", {"base_speed_kph": 5.0})
	var walk_speed_kph: float = float(walk_mode.get("base_speed_kph", 5.0))

	# Leg 1: Center of origin district -> Origin boarding stop (at walking speed)
	var walk_in_m: float = origin_anchor.distance_to(origin_stop["position"])
	var leg1 := _evaluate_service_leg(
		world_state, walk_service, "WALK",
		"DISTRICT:%s" % origin_district_id,
		str(origin_stop["stop_id"]),
		walk_in_m, walk_speed_kph, 0.0,
		["DISTRICT:%s" % origin_district_id, str(origin_stop["stop_id"])]
	)
	legs.append(leg1)

	# Leg 2: Origin stop -> (Optional Waypoints) -> Destination stop along road/rail graph at service speed
	var leg2_m: float = 0.0
	var leg2_path: Array[String] = []
	var total_heat: float = 0.0
	var total_crowd: float = 0.0

	var stop_chain: Array[String] = [str(origin_stop["node_a"])]
	for wp in waypoints:
		var wp_str := str(wp)
		if world_state.get("districts", {}).has(wp_str):
			var wp_anchor: Vector2 = world_state["districts"][wp_str]["spatial_anchor"]
			var wp_stop: Dictionary = _find_nearest_stop(world_state, mode_id, wp_anchor, stop_filter)
			if not wp_stop.is_empty():
				stop_chain.append(str(wp_stop["node_a"]))
		elif world_state.get("transit_stops", {}).has(wp_str):
			stop_chain.append(str(world_state["transit_stops"][wp_str]["node_a"]))
	stop_chain.append(str(dest_stop["node_a"]))

	for i in range(stop_chain.size() - 1):
		var astar := _run_astar(graph, modes_cfg, stop_chain[i], stop_chain[i + 1], allowed_classes, speed_kph, routing_policy)
		if not bool(astar.get("reachable", false)):
			return {"reachable": false, "error_code": "ROUTE_UNREACHABLE", "legs": []}
		leg2_m += float(astar["distance_m"])
		total_heat += float(astar["heat_exposure"])
		total_crowd += float(astar["crowd_exposure"])
		for p_node in astar["path"]:
			if leg2_path.is_empty() or leg2_path[leg2_path.size() - 1] != p_node:
				leg2_path.append(p_node)

	# Add half-block midpoint offsets if stops sit on edge midpoints
	if str(origin_stop.get("strategy", "")) == "EDGE_MIDPOINT":
		leg2_m += Vector2(origin_stop["position"]).distance_to(graph["nodes"][origin_stop["node_a"]]["position"])
	if str(dest_stop.get("strategy", "")) == "EDGE_MIDPOINT":
		leg2_m += Vector2(dest_stop["position"]).distance_to(graph["nodes"][dest_stop["node_a"]]["position"])

	var origin_sector: String = str(origin_stop.get("sector", "DEFAULT")).to_upper()
	var headways: Dictionary = service_def.get("headway_minutes_by_sector", {})
	var headway_min: float = float(headways.get(origin_sector, headways.get("DEFAULT", 0.0)))
	var wait_mult: float = float(service_def.get("off_peak_wait_multiplier", 1.0)) if is_off_peak else 1.0
	var wait_minutes: float = (headway_min * 0.5) * wait_mult

	var leg2 := _evaluate_service_leg(
		world_state, service_def, mode_id,
		str(origin_stop["stop_id"]),
		str(dest_stop["stop_id"]),
		leg2_m, speed_kph, wait_minutes, leg2_path
	)
	legs.append(leg2)

	# Leg 3: Destination alighting stop -> Center of destination district (at walking speed)
	var walk_out_m: float = Vector2(dest_stop["position"]).distance_to(dest_anchor)
	var leg3 := _evaluate_service_leg(
		world_state, walk_service, "WALK",
		str(dest_stop["stop_id"]),
		"DISTRICT:%s" % dest_district_id,
		walk_out_m, walk_speed_kph, 0.0,
		[str(dest_stop["stop_id"]), "DISTRICT:%s" % dest_district_id]
	)
	legs.append(leg3)

	return _finalize_plan_totals(service_id, mode_id, routing_policy, legs, total_heat, total_crowd)

## Evaluates a single transit leg using its transport_profile.json + travel/*.json impact rules
static func _evaluate_service_leg(
	world_state: Dictionary,
	service_def: Dictionary,
	mode_id: String,
	from_node: String,
	to_node: String,
	distance_m: float,
	speed_kph: float,
	wait_minutes: float,
	path_nodes: Array[String]
) -> Dictionary:
	var dist_units: float = distance_m / METERS_PER_DISTANCE_UNIT
	var move_minutes: float = ((distance_m / 1000.0) / maxf(0.1, speed_kph)) * 60.0
	var total_minutes: float = move_minutes + wait_minutes

	var fare_cost: float = float(service_def.get("base_fare_drop", 0.0)) if distance_m > 0.0 else 0.0
	var op_time_delta: float = 0.0
	var fatigue_delta: float = 0.0

	var travel_impacts: Array = service_def.get("impact_activations", {}).get("TRAVEL", [])
	for rule in travel_impacts:
		if not (rule is Dictionary):
			continue
		var metric: String = str(rule.get("metric", "")).to_upper()
		var model_type: String = str(rule.get("model", "LINEAR_PER_UNIT")).to_upper()
		var factor: float = float(rule.get("factor", 0.0))
		var params: Dictionary = rule.get("params", {})
		var delta: float = IMPACT_CALCULATOR.calculate(model_type, dist_units, factor, params)
		if metric == "CASH":
			# fare_cost.json uses negative factor (-0.30, -0.015) for cash outflow
			fare_cost += absf(delta)
		elif metric == "OPERATIONAL_TIME":
			op_time_delta += absf(delta)
		elif metric == "WORKER_FATIGUE":
			fatigue_delta += absf(delta)

	# Include waiting time into operational time ticks (1.0 operational time unit = 60 minutes)
	op_time_delta += (wait_minutes / 60.0)

	return {
		"service_id": str(service_def.get("id", "SERVICE_WALK")),
		"mode_id": mode_id,
		"from_node": from_node,
		"to_node": to_node,
		"distance_m": distance_m,
		"distance_units": dist_units,
		"wait_minutes": wait_minutes,
		"duration_minutes": total_minutes,
		"operational_time": op_time_delta,
		"fare": fare_cost,
		"fatigue": fatigue_delta,
		"path_nodes": path_nodes
	}

static func _finalize_plan_totals(
	service_id: String,
	mode_id: String,
	routing_policy: String,
	legs: Array[Dictionary],
	heat_exposure: float,
	crowd_exposure: float
) -> Dictionary:
	var tot_m: float = 0.0
	var tot_units: float = 0.0
	var tot_min: float = 0.0
	var tot_op_time: float = 0.0
	var tot_fare: float = 0.0
	var tot_fatigue: float = 0.0

	for leg in legs:
		tot_m += float(leg.get("distance_m", 0.0))
		tot_units += float(leg.get("distance_units", 0.0))
		tot_min += float(leg.get("duration_minutes", 0.0))
		tot_op_time += float(leg.get("operational_time", 0.0))
		tot_fare += float(leg.get("fare", 0.0))
		tot_fatigue += float(leg.get("fatigue", 0.0))

	return {
		"reachable": true,
		"service_id": service_id,
		"mode_id": mode_id,
		"routing_policy": routing_policy,
		"legs": legs,
		"total_distance_m": tot_m,
		"total_distance_units": tot_units,
		"total_duration_minutes": tot_min,
		"total_operational_time": tot_op_time,
		"total_fare": tot_fare,
		"total_fatigue": tot_fatigue,
		"police_exposure": heat_exposure,
		"crowd_exposure": crowd_exposure
	}

## Builds the unified road/rail + district anchor graph from world_state
static func build_spatial_graph(world_state: Dictionary, modes_cfg: Dictionary) -> Dictionary:
	var nodes: Dictionary = {}
	var edges: Dictionary = {}
	var adj: Dictionary = {}

	var cfg = ScenarioManifestManager.get_city_configuration()
	var block_side_m: float = float(cfg.get("block_size")) if (cfg and "block_size" in cfg) else 200.0
	var street_w_m: float = float(cfg.get("street_width")) if (cfg and "street_width" in cfg) else 25.0
	var cell_pitch: float = block_side_m + street_w_m
	var half_pitch: float = cell_pitch * 0.5

	var road_classes: Dictionary = modes_cfg.get("road_classes", {})
	var districts: Dictionary = world_state.get("districts", {})

	for d_id in districts.keys():
		var d: Dictionary = districts[d_id]
		var anchor: Vector2 = d.get("spatial_anchor", Vector2.ZERO)
		var g_coords: Vector2i = d.get("grid_coords", Vector2i.ZERO)
		var g_size: Vector2i = d.get("grid_size", Vector2i.ONE)
		var d_type: String = str(d.get("district_type", ""))
		var pop: float = float(d.get("population", 0.0))
		var heat: float = float(d.get("actual_police_heat", 0.0))

		var d_node_id := "DISTRICT:%s" % str(d_id)
		nodes[d_node_id] = {
			"node_id": d_node_id,
			"kind": "DISTRICT_ANCHOR",
			"position": anchor,
			"primary_district_id": str(d_id)
		}
		adj[d_node_id] = []

		# Build surrounding road corner junctions for each grid cell covered by this district
		for dx in range(g_size.x):
			for dz in range(g_size.y):
				var cx: int = g_coords.x + dx
				var cz: int = g_coords.y + dz
				var cell_center := Vector2(float(cx) * cell_pitch, float(cz) * cell_pitch)

				var c_nw := "JUNC:%d_%d" % [cx, cz]
				var c_ne := "JUNC:%d_%d" % [cx + 1, cz]
				var c_sw := "JUNC:%d_%d" % [cx, cz + 1]
				var c_se := "JUNC:%d_%d" % [cx + 1, cz + 1]

				_ensure_junction(nodes, adj, c_nw, cell_center + Vector2(-half_pitch, -half_pitch), str(d_id))
				_ensure_junction(nodes, adj, c_ne, cell_center + Vector2(half_pitch, -half_pitch), str(d_id))
				_ensure_junction(nodes, adj, c_sw, cell_center + Vector2(-half_pitch, half_pitch), str(d_id))
				_ensure_junction(nodes, adj, c_se, cell_center + Vector2(half_pitch, half_pitch), str(d_id))

				var r_class := _classify_district_road(d_type, cx, cz)
				var r_speed: float = float(road_classes.get(r_class, {}).get("default_speed_kph", 48.0))

				_add_bidirectional_road(edges, adj, nodes, c_nw, c_ne, r_class, r_speed, str(d_id), pop, heat)
				_add_bidirectional_road(edges, adj, nodes, c_ne, c_se, r_class, r_speed, str(d_id), pop, heat)
				_add_bidirectional_road(edges, adj, nodes, c_se, c_sw, r_class, r_speed, str(d_id), pop, heat)
				_add_bidirectional_road(edges, adj, nodes, c_sw, c_nw, r_class, r_speed, str(d_id), pop, heat)

				# Connect District Anchor to its 4 surrounding junctions via internal access links
				for j_id in [c_nw, c_ne, c_sw, c_se]:
					_add_access_link(edges, adj, nodes, d_node_id, j_id, str(d_id), pop, heat)

	return {"nodes": nodes, "edges": edges, "adj": adj}

static func _run_astar(
	graph: Dictionary,
	modes_cfg: Dictionary,
	start_id: String,
	goal_id: String,
	allowed_classes: Array,
	mode_speed_kph: float,
	routing_policy: String
) -> Dictionary:
	var nodes: Dictionary = graph["nodes"]
	var edges: Dictionary = graph["edges"]
	var adj: Dictionary = graph["adj"]

	if not nodes.has(start_id) or not nodes.has(goal_id):
		return {"reachable": false}
	if start_id == goal_id:
		return {"reachable": true, "path": [start_id], "distance_m": 0.0, "heat_exposure": 0.0, "crowd_exposure": 0.0}

	var policies: Dictionary = modes_cfg.get("routing_policies", {})
	var pop_weight: float = float(policies.get("LEAST_POPULATED", {}).get("population_weight", 1.5))
	var heat_weight: float = float(policies.get("LEAST_POLICED", {}).get("police_heat_weight", 3.0))

	var open_set: Array[String] = [start_id]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_id: 0.0}
	var f_score: Dictionary = {start_id: Vector2(nodes[start_id]["position"]).distance_to(nodes[goal_id]["position"])}
	var dist_acc: Dictionary = {start_id: 0.0}
	var heat_acc: Dictionary = {start_id: 0.0}
	var crowd_acc: Dictionary = {start_id: 0.0}

	while not open_set.is_empty():
		var current: String = open_set[0]
		var best_f: float = float(f_score.get(current, INF))
		for candidate in open_set:
			var cf: float = float(f_score.get(candidate, INF))
			if cf < best_f:
				best_f = cf
				current = candidate

		if current == goal_id:
			var path: Array[String] = [current]
			var curr_cursor := current
			while came_from.has(curr_cursor):
				curr_cursor = came_from[curr_cursor]
				path.push_front(curr_cursor)
			return {
				"reachable": true,
				"path": path,
				"distance_m": float(dist_acc[goal_id]),
				"heat_exposure": float(heat_acc[goal_id]),
				"crowd_exposure": float(crowd_acc[goal_id])
			}

		open_set.erase(current)

		for edge_id in adj.get(current, []):
			var edge: Dictionary = edges[edge_id]
			var kind: String = str(edge.get("kind", ""))
			var neighbor: String = str(edge["to"]) if str(edge["from"]) == current else str(edge["from"])

			# Access links only connect DISTRICT:<id> endpoints
			if kind == "ACCESS":
				if neighbor != goal_id and current != start_id:
					continue
			elif kind == "ROAD":
				var r_class: String = str(edge.get("road_class", ""))
				if not allowed_classes.is_empty() and not allowed_classes.has(r_class):
					continue

			var seg_m: float = float(edge["length_m"])
			var seg_speed: float = minf(mode_speed_kph, float(edge.get("speed_limit_kph", mode_speed_kph)))
			var seg_pop_norm: float = clampf(float(edge.get("population", 0.0)) / 500.0, 0.0, 5.0)
			var seg_heat_norm: float = clampf(float(edge.get("police_heat", 0.0)) / 100.0, 0.0, 5.0)

			var step_cost: float = seg_m
			if routing_policy == "FASTEST":
				step_cost = ((seg_m / 1000.0) / maxf(0.1, seg_speed)) * 60.0
			elif routing_policy == "LEAST_POPULATED":
				step_cost = seg_m * (1.0 + pop_weight * seg_pop_norm)
			elif routing_policy == "LEAST_POLICED":
				step_cost = seg_m * (1.0 + heat_weight * seg_heat_norm)

			var tentative_g: float = float(g_score[current]) + step_cost
			if tentative_g < float(g_score.get(neighbor, INF)):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				dist_acc[neighbor] = float(dist_acc[current]) + seg_m
				heat_acc[neighbor] = float(heat_acc[current]) + (seg_heat_norm * (seg_m / 1000.0))
				crowd_acc[neighbor] = float(crowd_acc[current]) + (seg_pop_norm * (seg_m / 1000.0))

				var h_dist: float = Vector2(nodes[neighbor]["position"]).distance_to(nodes[goal_id]["position"])
				var h_cost: float = h_dist
				if routing_policy == "FASTEST":
					h_cost = ((h_dist / 1000.0) / maxf(0.1, mode_speed_kph)) * 60.0
				f_score[neighbor] = tentative_g + h_cost

				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return {"reachable": false}

static func _ensure_junction(nodes: Dictionary, adj: Dictionary, j_id: String, pos: Vector2, d_id: String) -> void:
	if not nodes.has(j_id):
		nodes[j_id] = {
			"node_id": j_id,
			"kind": "JUNCTION",
			"position": pos,
			"primary_district_id": d_id
		}
		adj[j_id] = []

static func _add_bidirectional_road(
	edges: Dictionary,
	adj: Dictionary,
	nodes: Dictionary,
	a_id: String,
	b_id: String,
	road_class: String,
	speed_kph: float,
	d_id: String,
	pop: float,
	heat: float
) -> void:
	var pair: Array[String] = [a_id, b_id]
	pair.sort()
	var edge_id := "ROAD:%s__%s" % [pair[0], pair[1]]
	if edges.has(edge_id):
		# Upgrade road class if a higher-tier bordering district shares this street
		var existing: Dictionary = edges[edge_id]
		existing["population"] = maxf(float(existing["population"]), pop)
		existing["police_heat"] = maxf(float(existing["police_heat"]), heat)
		if speed_kph > float(existing["speed_limit_kph"]):
			existing["road_class"] = road_class
			existing["speed_limit_kph"] = speed_kph
		return

	var pos_a: Vector2 = nodes[pair[0]]["position"]
	var pos_b: Vector2 = nodes[pair[1]]["position"]
	edges[edge_id] = {
		"edge_id": edge_id,
		"kind": "ROAD",
		"from": pair[0],
		"to": pair[1],
		"length_m": pos_a.distance_to(pos_b),
		"midpoint": (pos_a + pos_b) * 0.5,
		"road_class": road_class,
		"speed_limit_kph": speed_kph,
		"primary_district_id": d_id,
		"population": pop,
		"police_heat": heat
	}
	adj[pair[0]].append(edge_id)
	adj[pair[1]].append(edge_id)

static func _add_access_link(
	edges: Dictionary,
	adj: Dictionary,
	nodes: Dictionary,
	d_node_id: String,
	j_node_id: String,
	d_id: String,
	pop: float,
	heat: float
) -> void:
	var edge_id := "ACCESS:%s__%s" % [d_node_id, j_node_id]
	if edges.has(edge_id):
		return
	var pos_a: Vector2 = nodes[d_node_id]["position"]
	var pos_b: Vector2 = nodes[j_node_id]["position"]
	edges[edge_id] = {
		"edge_id": edge_id,
		"kind": "ACCESS",
		"from": d_node_id,
		"to": j_node_id,
		"length_m": pos_a.distance_to(pos_b),
		"midpoint": (pos_a + pos_b) * 0.5,
		"road_class": "ACCESS",
		"speed_limit_kph": 5.0,
		"primary_district_id": d_id,
		"population": pop,
		"police_heat": heat
	}
	adj[d_node_id].append(edge_id)
	adj[j_node_id].append(edge_id)

static func _classify_district_road(district_type: String, cx: int, cz: int) -> String:
	var upper := district_type.to_upper()
	if upper.contains("COMMERCIAL") or upper.contains("HIGH_STREET") or upper.contains("CIVIC") or upper.contains("MARKET"):
		return "HIGH_STREET"
	if cx == 0 or cz == 0:
		return "ARTERIAL"
	return "COLLECTOR"

static func _find_nearest_stop(world_state: Dictionary, mode_id: String, target_pos: Vector2, strategy_filter) -> Dictionary:
	var stops: Dictionary = world_state.get("transit_stops", {})
	var best_stop: Dictionary = {}
	var best_dist: float = INF
	var req_strategy: String = str(strategy_filter).to_upper() if strategy_filter != null else ""

	for stop_id in stops.keys():
		var s: Dictionary = stops[stop_id]
		if not bool(s.get("active", true)):
			continue
		if str(s.get("mode_id", "")).to_upper() != mode_id:
			continue
		if not req_strategy.is_empty() and str(s.get("strategy", "")).to_upper() != req_strategy:
			continue
		var d: float = target_pos.distance_to(s["position"])
		if d < best_dist:
			best_dist = d
			best_stop = s
	return best_stop

static func _is_far_enough(pos: Vector2, existing: Array[Vector2], min_dist: float) -> bool:
	for p in existing:
		if pos.distance_to(p) < min_dist - 0.01:
			return false
	return true

static func _junction_has_eligible_road(node_id: String, graph: Dictionary, eligible_classes: Array) -> bool:
	if eligible_classes.is_empty():
		return true
	for edge_id in graph["adj"].get(node_id, []):
		var edge: Dictionary = graph["edges"][edge_id]
		if str(edge.get("kind", "")) == "ROAD" and eligible_classes.has(str(edge.get("road_class", ""))):
			return true
	return false

static func _resolve_district_sector(world_state: Dictionary, district_id: String) -> String:
	var d_type: String = str(world_state.get("districts", {}).get(district_id, {}).get("district_type", ""))
	if ScenarioManifestManager.has_module("archetypes"):
		var arch: Dictionary = ScenarioManifestManager.load_module("archetypes").get(d_type, {})
		var sec := str(arch.get("sector_class", "")).to_upper()
		if not sec.is_empty():
			return sec
	return "DEFAULT"

static func _build_waypoint_chain(origin_id: String, dest_id: String, waypoints: Array) -> Array[String]:
	var chain: Array[String] = [origin_id]
	for wp in waypoints:
		var wp_str := str(wp).strip_edges()
		if not wp_str.is_empty() and wp_str != origin_id and wp_str != dest_id:
			chain.append(wp_str)
	chain.append(dest_id)
	return chain

static func _resolve_actor_record(world_state: Dictionary, actor_id: String) -> Dictionary:
	if actor_id.is_empty():
		return {}
	var residents: Dictionary = world_state.get("residents", {})
	if residents.has(actor_id):
		return residents[actor_id]
	if actor_id.is_valid_int() and residents.has(int(actor_id)):
		return residents[int(actor_id)]
	return {}