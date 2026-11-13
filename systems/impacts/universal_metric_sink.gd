# res://systems/impacts/universal_metric_sink.gd
class_name UniversalMetricSink
extends RefCounted

const CONDITION_EVALUATOR = preload("res://systems/condition_evaluator.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")

var metric_id: String = ""
var target_scope: String = "DISTRICT"
var state_container: String = "districts"
var state_field: String = ""

# Route definition resolved from routing_manifest.json
var route_path: String = ""
var fallback_path: String = ""
var search_containers: Array = []
var stamp_field: String = ""
var create_missing: bool = false
var erase_at_min: bool = false

# Numeric Bounds & Baseline Tuning
var min_floor: float = 0.0
var max_ceiling: float = 1.0
var default_baseline: float = 0.0
var allow_negative: bool = false
var discovery_floor: float = 0.0

# Ambient Heartbeat Configuration
var ambient_rate: float = 0.0
var ambient_direction: String = "NONE" # "FLOOR", "CEILING", "BASELINE", "RESET", "CONDITIONAL"
var ambient_max: float = 1.0
var gate_field: String = ""
var gate_threshold: float = 0.0
var gate_operator: String = "<"

func _init(profile: Dictionary) -> void:
	metric_id = str(profile.get("metric_id", ""))
	target_scope = str(profile.get("target_scope", "DISTRICT")).to_upper()
	state_container = str(profile.get("state_container", "districts"))
	state_field = str(profile.get("state_field", metric_id.to_lower()))

	var tuning: Dictionary = profile.get("tuning", {})
	min_floor = float(tuning.get("minimum_floor", profile.get("min_value", 0.0)))
	max_ceiling = float(tuning.get("maximum_ceiling", profile.get("max_value", 1.0)))
	default_baseline = float(tuning.get("default_baseline", tuning.get("default_baseline_sentiment", tuning.get("default_baseline_reputation", min_floor))))
	allow_negative = bool(tuning.get("allow_negative_balance", tuning.get("allow_negative_stock", false)))
	discovery_floor = float(tuning.get("discovery_floor", min_floor))

	_resolve_route_from_manifest(profile)
	_configure_ambient_rule(profile, tuning)

func _resolve_route_from_manifest(profile: Dictionary) -> void:
	var legacy_mode: String = str(profile.get("routing_mode", "")).to_upper()
	var lookup_key: String = legacy_mode if not legacy_mode.is_empty() and legacy_mode != "DIRECT" else target_scope
	if lookup_key == "SPATIAL":
		lookup_key = "DISTRICT"
	elif lookup_key == "ACTOR" or lookup_key == "ACTOR_FALLBACK":
		lookup_key = "RESIDENT"
	elif lookup_key == "INVENTORY_LANE":
		lookup_key = "INVENTORY"
	elif lookup_key == "GLOBAL_SCALAR":
		lookup_key = "GLOBAL"

	var routes: Dictionary = {}
	if ScenarioManifestManagerScript.has_module("impact_routing"):
		var manifest: Dictionary = ScenarioManifestManagerScript.load_module("impact_routing")
		routes = manifest.get("routes", {})

	if routes.has(lookup_key) and routes[lookup_key] is Dictionary:
		var r: Dictionary = routes[lookup_key]
		route_path = str(r.get("path", ""))
		fallback_path = str(r.get("fallback_path", ""))
		search_containers = r.get("search_containers", [])
		stamp_field = str(r.get("stamp_field", ""))
		create_missing = bool(r.get("create_missing", false))
		erase_at_min = bool(r.get("erase_at_min", false))
	else:
		route_path = "%s.{target_id}.%s" % [state_container, state_field]
		create_missing = false

func _configure_ambient_rule(profile: Dictionary, tuning: Dictionary) -> void:
	if tuning.has("passive_cooling_per_week") or tuning.has("ambient_decay_step"):
		ambient_direction = "FLOOR"
		ambient_rate = float(tuning.get("passive_cooling_per_week", tuning.get("ambient_decay_step", 0.0)))
	elif tuning.has("passive_recovery_per_tick"):
		ambient_direction = "CEILING"
		ambient_rate = float(tuning["passive_recovery_per_tick"])
	elif tuning.has("passive_drift_per_tick") or tuning.has("passive_decay_rate_per_tick"):
		ambient_direction = "BASELINE"
		ambient_rate = float(tuning.get("passive_drift_per_tick", tuning.get("passive_decay_rate_per_tick", 0.0)))
	elif tuning.has("ambient_reset_to_zero") and bool(tuning["ambient_reset_to_zero"]):
		ambient_direction = "RESET"
	elif tuning.has("loyalty_skim_threshold"):
		ambient_direction = "CONDITIONAL"
		gate_field = str(tuning.get("loyalty_field", "loyalty"))
		gate_threshold = float(tuning.get("loyalty_skim_threshold", 0.60))
		gate_operator = str(tuning.get("loyalty_operator", "<"))
		ambient_rate = float(tuning.get("ambient_skim_increment", 0.01))
		ambient_max = float(tuning.get("max_ambient_skim", 1.0))
	elif profile.has("ambient_rate"):
		ambient_direction = "FLOOR"
		ambient_rate = float(profile.get("ambient_rate", 0.0))

## 1. IDENTITY CONTRACT
func get_metric_key() -> String:
	return metric_id

func get_target_scope() -> String:
	return target_scope

## 2. ACTION IMPULSE (Delta Application via Route Template)
func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	var tokens := _parse_target_tokens(target_id)
	if not search_containers.is_empty():
		for c_name in search_containers:
			var candidate_path := "%s.{target_id}.{state_field}" % str(c_name)
			if _mutate_path(world_state, candidate_path, tokens, delta, false):
				return
		return

	if not route_path.is_empty():
		if _mutate_path(world_state, route_path, tokens, delta, create_missing):
			return

	if not fallback_path.is_empty():
		_mutate_path(world_state, fallback_path, tokens, delta, create_missing)

## 3. AMBIENT HEARTBEAT CONTRACT
func process_ambient(world_state: Dictionary) -> void:
	if ambient_direction == "NONE":
		return
	if ambient_direction in ["FLOOR", "CEILING", "BASELINE"] and ambient_rate <= 0.0:
		return

	var template := route_path if not route_path.is_empty() else "%s.{target_id}.%s" % [state_container, state_field]
	var raw_segments := template.split(".")
	var segments: Array[String] = []
	for seg in raw_segments:
		segments.append(seg.replace("{state_container}", state_container).replace("{state_field}", state_field))

	_walk_ambient(world_state, segments, 0, world_state)

# --- PATH TOKENIZATION & TRAVERSAL ---

func _parse_target_tokens(target_id: String) -> Dictionary:
	var tokens := {
		"target_id": target_id,
		"state_container": state_container,
		"state_field": state_field,
		"item_id": target_id,
		"lane": "STOCK",
		"observer_scope": "",
		"observer_id": "",
		"target_key": ""
	}

	if target_id.contains("->"):
		var arrow := target_id.split("->")
		if arrow.size() == 2:
			var obs := arrow[0].split(":")
			if obs.size() == 2:
				tokens["observer_scope"] = obs[0].strip_edges().to_upper()
				tokens["observer_id"] = obs[1].strip_edges()
			tokens["target_key"] = arrow[1].strip_edges()
	elif target_id.contains(":"):
		var parts := target_id.split(":")
		tokens["item_id"] = parts[0]
		if parts.size() > 1 and not parts[1].is_empty():
			tokens["lane"] = parts[1]

	return tokens

func _expand_segment(segment: String, tokens: Dictionary) -> String:
	var out := segment
	for k in tokens.keys():
		out = out.replace("{%s}" % k, str(tokens[k]))
	return out

func _mutate_path(world_state: Dictionary, template: String, tokens: Dictionary, delta: float, allow_create: bool) -> bool:
	var raw_segments := template.split(".")
	if raw_segments.is_empty():
		return false

	var cur_node: Variant = world_state
	for i in range(raw_segments.size() - 1):
		var key := _expand_segment(raw_segments[i], tokens)
		if key.is_empty() or not (cur_node is Dictionary):
			return false
		if not cur_node.has(key) or not (cur_node[key] is Dictionary):
			if not allow_create:
				return false
			cur_node[key] = {}
		cur_node = cur_node[key]

	if not (cur_node is Dictionary):
		return false

	var leaf_key := _expand_segment(raw_segments[raw_segments.size() - 1], tokens)
	if leaf_key.is_empty():
		return false
	if not cur_node.has(leaf_key) and not allow_create:
		return false

	var cur_val: float = float(cur_node.get(leaf_key, default_baseline))
	var updated: float = cur_val + delta
	var final_val: float = updated if allow_negative else clampf(updated, min_floor, max_ceiling)

	if erase_at_min and final_val <= min_floor:
		cur_node.erase(leaf_key)
		return true

	cur_node[leaf_key] = final_val
	if not stamp_field.is_empty():
		cur_node[stamp_field] = int(world_state.get("metadata", {}).get("current_sim_day", 0))
	return true

func _walk_ambient(node: Variant, segments: Array[String], depth: int, root_state: Dictionary) -> void:
	if not (node is Dictionary) or depth >= segments.size():
		return

	var dict_node: Dictionary = node
	var seg := segments[depth]
	var is_wildcard := seg.begins_with("{") and seg.ends_with("}")
	var is_leaf := (depth == segments.size() - 1)

	if is_leaf:
		if not dict_node.has(seg):
			return
		if ambient_direction == "CONDITIONAL":
			var gate_val: float = float(dict_node.get(gate_field, 1.0))
			if CONDITION_EVALUATOR.evaluate(gate_val, gate_threshold, gate_operator):
				dict_node[seg] = clampf(float(dict_node[seg]) + ambient_rate, min_floor, ambient_max)
			return

		var cur: float = float(dict_node[seg])
		var next_val: float = cur
		match ambient_direction:
			"FLOOR":
				var effective_floor: float = discovery_floor if (discovery_floor > min_floor and cur >= discovery_floor) else min_floor
				next_val = maxf(effective_floor, cur - ambient_rate)
			"CEILING":
				next_val = minf(max_ceiling, cur + ambient_rate)
			"BASELINE":
				next_val = maxf(default_baseline, cur - ambient_rate) if cur > default_baseline else minf(default_baseline, cur + ambient_rate)
			"RESET":
				next_val = 0.0

		if erase_at_min and next_val <= min_floor:
			dict_node.erase(seg)
		else:
			dict_node[seg] = next_val
		return

	if is_wildcard:
		var keys: Array = dict_node.keys()
		for k in keys:
			var child = dict_node[k]
			_walk_ambient(child, segments, depth + 1, root_state)
			if erase_at_min and child is Dictionary and child.is_empty():
				dict_node.erase(k)
	elif dict_node.has(seg):
		var child = dict_node[seg]
		_walk_ambient(child, segments, depth + 1, root_state)
		if erase_at_min and child is Dictionary and child.is_empty():
			dict_node.erase(seg)