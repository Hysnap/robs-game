# res://systems/impacts/universal_metric_sink.gd
class_name UniversalMetricSink
extends RefCounted

const CONDITION_EVALUATOR = preload("res://systems/condition_evaluator.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

var metric_id: String = ""
var metric_class: String = ""
var target_scope: String = "DISTRICT"
var state_container: String = "districts"
var state_field: String = ""

# Route definition resolved from routing_manifest.json
var route_path: String = ""
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
var reset_on_cycle: bool = false

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
	metric_class = _resolve_metric_class(profile, tuning)
	_apply_metric_class_defaults(profile, tuning)
	allow_negative = bool(tuning.get("allow_negative_balance", tuning.get("allow_negative_stock", false)))
	discovery_floor = float(tuning.get("discovery_floor", min_floor))
	reset_on_cycle = bool(tuning.get("reset_on_cycle", false))

	_resolve_route_from_manifest(profile)
	_configure_ambient_rule(profile, tuning)

func _resolve_metric_class(profile: Dictionary, tuning: Dictionary) -> String:
	var explicit: String = str(profile.get("metric_class", tuning.get("metric_class", ""))).to_upper().strip_edges()
	if not explicit.is_empty():
		return explicit
	var raw_min: float = float(tuning.get("minimum_floor", profile.get("min_value", 0.0)))
	var raw_max: float = float(tuning.get("maximum_ceiling", profile.get("max_value", 1.0)))
	if raw_min < 0.0:
		return "BIPOLAR_IMPACT"
	if raw_max > 100.0:
		return "FACTUAL_COUNTER"
	if raw_max > 1.0:
		return "SEVERITY_IMPACT"
	return "SEVERITY_IMPACT"

func _apply_metric_class_defaults(profile: Dictionary, tuning: Dictionary) -> void:
	var has_explicit_min: bool = tuning.has("minimum_floor") or profile.has("min_value")
	var has_explicit_max: bool = tuning.has("maximum_ceiling") or profile.has("max_value")
	default_baseline = _resolve_default_baseline(tuning)
	match metric_class:
		"BIPOLAR_IMPACT":
			min_floor = float(tuning.get("minimum_floor", profile.get("min_value", -100.0))) if has_explicit_min else -100.0
			max_ceiling = float(tuning.get("maximum_ceiling", profile.get("max_value", 100.0))) if has_explicit_max else 100.0
		"PERC_MEASURE":
			min_floor = float(tuning.get("minimum_floor", profile.get("min_value", 0.0))) if has_explicit_min else 0.0
			max_ceiling = float(tuning.get("maximum_ceiling", profile.get("max_value", 100.0))) if has_explicit_max else 100.0
		"FACTUAL_COUNTER":
			min_floor = float(tuning.get("minimum_floor", profile.get("min_value", 0.0))) if has_explicit_min else 0.0
			max_ceiling = float(tuning.get("maximum_ceiling", profile.get("max_value", INF))) if has_explicit_max else INF
		"CONTROL_FLAG":
			min_floor = 0.0
			max_ceiling = 1.0
			default_baseline = 0.0
		_:
			min_floor = float(tuning.get("minimum_floor", profile.get("min_value", 0.0))) if has_explicit_min else 0.0
			max_ceiling = float(tuning.get("maximum_ceiling", profile.get("max_value", 100.0))) if has_explicit_max else 100.0

func _resolve_default_baseline(tuning: Dictionary) -> float:
	if tuning.has("default_baseline"):
		return float(tuning["default_baseline"])
	for key in tuning.keys():
		if str(key).begins_with("default_baseline_"):
			return float(tuning[key])
	return 0.0

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
		search_containers = r.get("search_containers", [])
		stamp_field = str(r.get("stamp_field", ""))
		create_missing = bool(r.get("create_missing", false))
		erase_at_min = bool(r.get("erase_at_min", false))
	else:
		push_error("[UniversalMetricSink FATAL] Metric '%s' declares unmapped target_scope '%s' (missing from routing_manifest.json)." % [metric_id, lookup_key])
		route_path = ""
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

func reset_for_cycle(world_state: Dictionary) -> void:
	if not reset_on_cycle or route_path.is_empty():
		return

	var segments: Array[String] = []
	for segment in route_path.split("."):
		segments.append(segment.replace("{state_container}", state_container).replace("{state_field}", state_field))
	_walk_cycle_reset(world_state, segments, 0)

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
		var resolved_key: Variant = key
		if not cur_node.has(resolved_key) and key.is_valid_int() and cur_node.has(int(key)):
			resolved_key = int(key)
		if not cur_node.has(resolved_key) or not (cur_node[resolved_key] is Dictionary):
			if not allow_create:
				return false
			cur_node[resolved_key] = {}
		cur_node = cur_node[resolved_key]

	if not (cur_node is Dictionary):
		return false

	var leaf_key := _expand_segment(raw_segments[raw_segments.size() - 1], tokens)
	if leaf_key.is_empty():
		return false
	if not cur_node.has(leaf_key) and not allow_create:
		return false

	var current_day: int = CalendarHelperScript.get_current_sim_day(world_state)
	if metric_class == "CONTROL_FLAG":
		var duration_days: int = maxi(0, int(round(delta)) - 1) if delta >= 1.0 else 0
		var stamped_until: int = current_day + duration_days
		cur_node[leaf_key] = 1.0
		if not stamp_field.is_empty():
			var resolved_flag_stamp := _expand_segment(stamp_field, tokens)
			if not resolved_flag_stamp.is_empty():
				cur_node[resolved_flag_stamp] = stamped_until
		return true

	var cur_val: float = float(cur_node.get(leaf_key, default_baseline))
	var updated: float = cur_val + delta
	var is_unbounded: bool = is_inf(max_ceiling)
	var final_val: float
	if allow_negative:
		final_val = updated
	elif is_unbounded:
		final_val = maxf(updated, min_floor)
	else:
		final_val = clampf(updated, min_floor, max_ceiling)

	if erase_at_min and final_val <= min_floor:
		cur_node.erase(leaf_key)
		return true

	cur_node[leaf_key] = final_val
	if not stamp_field.is_empty():
		var resolved_stamp_key := _expand_segment(stamp_field, tokens)
		if not resolved_stamp_key.is_empty():
			cur_node[resolved_stamp_key] = current_day
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
				var target_base: float = 0.0 if metric_class == "BIPOLAR_IMPACT" else default_baseline
				next_val = maxf(target_base, cur - ambient_rate) if cur > target_base else minf(target_base, cur + ambient_rate)
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

func _walk_cycle_reset(node: Variant, segments: Array[String], depth: int) -> void:
	if not (node is Dictionary) or depth >= segments.size():
		return

	var dict_node: Dictionary = node
	var seg := segments[depth]
	if depth == segments.size() - 1:
		if dict_node.has(seg):
			dict_node[seg] = 0.0
		return

	if seg.begins_with("{") and seg.ends_with("}"):
		for key in dict_node.keys():
			_walk_cycle_reset(dict_node[key], segments, depth + 1)
	elif dict_node.has(seg):
		_walk_cycle_reset(dict_node[seg], segments, depth + 1)