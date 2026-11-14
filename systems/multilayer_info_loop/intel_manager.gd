# res://systems/multilayer_info_loop/intel_manager.gd
## Reusable, Parameterized 0–100 Saturating Measure & Threshold Exposure Engine.
##
## Architecture & Cross-Domain Reusability:
## Parameterized by `rules_module`, `metric_id`, `pool_container`, and `clearance_field`
## so it governs ANY saturating 0–100 simulation measure with zero GDScript changes:
##   1. Field Intelligence & Surveillance ("intel_exposure" / "INTEL_SCORE")
##   2. Market Brand Penetration & Customer Awareness ("brand_exposure" / "BRAND_AWARENESS")
##   3. Gang Turf Control & Street Influence ("turf_control_rules" / "TURF_CONTROL")
##   4. Skill Mastery, Habit Formation, or Chemical Tolerance ("tolerance_rules" / "TOLERANCE_SCORE")
##   5. Law Enforcement Case Files ("case_file_rules" / "CASE_PROGRESS")
class_name IntelManager
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")

const DEFAULT_RULES_MODULE: String = "intel_exposure"
const DEFAULT_METRIC_ID: String = "INTEL_SCORE"
const DEFAULT_POOL_CONTAINER: String = "knowledge_pools"
const MAX_ASYMPTOTIC_CAP: float = 99.95

## Keyed by rules_module -> parsed Dictionary
static var _rules_cache: Dictionary = {}
## Keyed by clearance_field -> { role_code -> float }
static var _job_clearances_cache: Dictionary = {}

## Clears cached JSON configs (useful for test isolation or manifest reloads)
static func reset_cache() -> void:
	_rules_cache.clear()
	_job_clearances_cache.clear()

## Loads a rules module (default: "intel_exposure") from the active scenario manifest
static func get_rules(rules_module: String = DEFAULT_RULES_MODULE) -> Dictionary:
	if _rules_cache.has(rules_module):
		return _rules_cache[rules_module]
	assert(ScenarioManifestManagerScript.has_module(rules_module),
		"FATAL: [IntelManager] '%s' module not registered in active society manifest." % rules_module)
	var parsed: Dictionary = ScenarioManifestManagerScript.load_module(rules_module)
	assert(parsed.has("scopes") and parsed.has("curve_defaults"),
		"FATAL: [IntelManager] '%s' module missing required 'scopes' or 'curve_defaults' sections." % rules_module)
	_rules_cache[rules_module] = parsed
	return parsed

## Resolves era-specific role clearance (0.0 - 1.0) from job_definitions.json
static func get_role_clearance(role_code: String, clearance_field: String = "intel_clearance", fallback: float = 0.35) -> float:
	if role_code.is_empty():
		return 0.0
	if not _job_clearances_cache.has(clearance_field):
		var role_map: Dictionary = {}
		if ScenarioManifestManagerScript.has_module("job_definitions"):
			var jobs_mod: Dictionary = ScenarioManifestManagerScript.load_module("job_definitions")
			var roles: Dictionary = jobs_mod.get("roles", {})
			for r_key in roles.keys():
				if roles[r_key] is Dictionary:
					role_map[str(r_key)] = float(roles[r_key].get(clearance_field, fallback))
		_job_clearances_cache[clearance_field] = role_map
	return float(_job_clearances_cache[clearance_field].get(role_code, fallback))

## Returns direct stored score (0.0 - 100.0) for a single observer -> target pair
static func get_direct_score(
	world_state: Dictionary,
	observer_scope: String,
	observer_id: String,
	target_scope: String,
	target_id: String,
	pool_container: String = DEFAULT_POOL_CONTAINER
) -> float:
	var pools = world_state.get(pool_container, null)
	if not (pools is Dictionary):
		return 0.0
	var scope_pool = pools.get(observer_scope.to_upper(), null)
	if not (scope_pool is Dictionary):
		return 0.0
	var dossier = scope_pool.get(observer_id, null)
	if not (dossier is Dictionary):
		return 0.0
	var target_key := "%s:%s" % [target_scope.to_upper(), target_id]
	var entry = dossier.get(target_key, null)
	if entry is Dictionary:
		return clampf(float(entry.get("score", 0.0)), 0.0, 100.0)
	return 0.0

## Computes effective score (0.0 - 100.0) combining personal score and role-cleared organizational score
## affiliations: Array of { "org_scope": String, "org_id": String, "role_code": String }
static func get_effective_score(
	world_state: Dictionary,
	observer_scope: String,
	observer_id: String,
	target_scope: String,
	target_id: String,
	affiliations: Array = [],
	pool_container: String = DEFAULT_POOL_CONTAINER,
	clearance_field: String = "intel_clearance"
) -> float:
	var best_score: float = get_direct_score(world_state, observer_scope, observer_id, target_scope, target_id, pool_container)

	for aff in affiliations:
		if not (aff is Dictionary):
			continue
		var org_scope: String = str(aff.get("org_scope", "ESTABLISHMENT")).to_upper()
		var org_id: String = str(aff.get("org_id", ""))
		if org_id.is_empty():
			continue
		var clearance: float = float(aff.get("clearance", -1.0))
		if clearance < 0.0:
			clearance = get_role_clearance(str(aff.get("role_code", "")), clearance_field)
		if clearance <= 0.0:
			continue
		var org_raw: float = get_direct_score(world_state, org_scope, org_id, target_scope, target_id, pool_container)
		var inherited: float = org_raw * clampf(clearance, 0.0, 1.0)
		if inherited > best_score:
			best_score = inherited

	return clampf(best_score, 0.0, 100.0)

## Computes collective best score across multiple observers
static func get_collective_score(
	world_state: Dictionary,
	observers: Array,
	target_scope: String,
	target_id: String,
	pool_container: String = DEFAULT_POOL_CONTAINER,
	clearance_field: String = "intel_clearance"
) -> float:
	var best: float = 0.0
	for obs in observers:
		if not (obs is Dictionary):
			continue
		var o_scope: String = str(obs.get("observer_scope", "RESIDENT")).to_upper()
		var o_id: String = str(obs.get("observer_id", ""))
		if o_id.is_empty():
			continue
		var affs: Array = obs.get("affiliations", [])
		var s: float = get_effective_score(world_state, o_scope, o_id, target_scope, target_id, affs, pool_container, clearance_field)
		if s > best:
			best = s
	return best

## Applies an effort impulse using spatial distance decay, access permeability, and hyperbolic saturation
## Returns the resulting updated score (0.0 - 100.0)
static func apply_effort_impulse(
	world_state: Dictionary,
	observer_scope: String,
	observer_id: String,
	target_scope: String,
	target_id: String,
	base_effort: float,
	context: Dictionary = {},
	rules_module: String = DEFAULT_RULES_MODULE,
	metric_id: String = DEFAULT_METRIC_ID
) -> float:
	var pool_container: String = str(context.get("pool_container", DEFAULT_POOL_CONTAINER))
	if base_effort == 0.0 or observer_id.is_empty() or target_id.is_empty():
		return get_direct_score(world_state, observer_scope, observer_id, target_scope, target_id, pool_container)

	var rules: Dictionary = get_rules(rules_module)
	var defaults: Dictionary = rules.get("curve_defaults", {})
	var scope_cfg: Dictionary = rules.get("scopes", {}).get(target_scope.to_upper(), {})

	# 1. Spatial Distance & Ease-of-Access Friction
	var distance_steps: float = maxf(0.0, float(context.get("distance", 0.0)))
	var dist_lambda: float = float(defaults.get("distance_decay_factor", 0.35))
	var dist_multiplier: float = 1.0 / (1.0 + (dist_lambda * distance_steps))

	var default_perm: float = float(scope_cfg.get("default_access_permeability", defaults.get("default_access_permeability", 0.5)))
	var access_perm: float = clampf(float(context.get("access_permeability", default_perm)), 0.05, 1.0)
	var effective_effort: float = base_effort * dist_multiplier * access_perm

	# 2. Organizational Maintenance Friction
	var base_h: float = float(scope_cfg.get("half_saturation_effort", defaults.get("default_half_saturation_effort", 25.0)))
	var org_size: float = maxf(0.0, float(context.get("observer_org_size", 0.0)))
	var org_factor: float = float(defaults.get("org_size_maintenance_factor", 0.05))
	var effective_h: float = base_h * (1.0 + (org_size * org_factor))

	# 3. Hyperbolic Saturation Mapping delegated to ConditionEvaluator
	var cur_score: float = get_direct_score(world_state, observer_scope, observer_id, target_scope, target_id, pool_container)
	var cur_effort: float = ConditionEvaluatorScript.invert_hyperbolic_saturation(minf(cur_score, MAX_ASYMPTOTIC_CAP), effective_h, 100.0)
	var new_effort: float = maxf(0.0, cur_effort + effective_effort)
	var target_score: float = ConditionEvaluatorScript.evaluate_hyperbolic_saturation(new_effort, effective_h, 100.0)

	var max_cap: float = float(context.get("max_cap", 100.0))
	target_score = clampf(target_score, 0.0, minf(max_cap, MAX_ASYMPTOTIC_CAP))

	var delta: float = target_score - cur_score
	var compound_target := "%s:%s->%s:%s" % [observer_scope.to_upper(), observer_id, target_scope.to_upper(), target_id]

	if ImpactRouterScript.has_sink(metric_id):
		ImpactRouterScript.dispatch_delta(world_state, compound_target, metric_id, delta)
	else:
		_write_score_fallback(world_state, pool_container, observer_scope.to_upper(), observer_id, target_scope.to_upper(), target_id, target_score)

	return get_direct_score(world_state, observer_scope, observer_id, target_scope, target_id, pool_container)

## Explicit compartmentalized score transfer from source observer to recipient observer
static func transfer_intel(
	world_state: Dictionary,
	from_scope: String,
	from_id: String,
	to_scope: String,
	to_id: String,
	target_scope: String,
	target_id: String,
	share_ratio: float = 0.75,
	context: Dictionary = {},
	rules_module: String = DEFAULT_RULES_MODULE,
	metric_id: String = DEFAULT_METRIC_ID
) -> float:
	var pool_container: String = str(context.get("pool_container", DEFAULT_POOL_CONTAINER))
	var source_score: float = get_direct_score(world_state, from_scope, from_id, target_scope, target_id, pool_container)
	if source_score <= 0.0 or share_ratio <= 0.0:
		return get_direct_score(world_state, to_scope, to_id, target_scope, target_id, pool_container)

	var rules: Dictionary = get_rules(rules_module)
	var defaults: Dictionary = rules.get("curve_defaults", {})
	var scope_cfg: Dictionary = rules.get("scopes", {}).get(target_scope.to_upper(), {})
	var base_h: float = float(scope_cfg.get("half_saturation_effort", defaults.get("default_half_saturation_effort", 25.0)))

	var source_effort: float = ConditionEvaluatorScript.invert_hyperbolic_saturation(minf(source_score, MAX_ASYMPTOTIC_CAP), base_h, 100.0)
	var transferred_effort: float = source_effort * clampf(share_ratio, 0.0, 1.0)

	var transfer_ctx := context.duplicate(true)
	transfer_ctx["max_cap"] = source_score * clampf(share_ratio, 0.0, 1.0)
	return apply_effort_impulse(world_state, to_scope, to_id, target_scope, target_id, transferred_effort, transfer_ctx, rules_module, metric_id)

## Generic declarative saturating impact executor (completely measure- & scope-agnostic)
## impact_params: {
##   "observer_scope": String, "observer_id": String,
##   "target_scope": String, "target_id": String,
##   "recipient_scope": String, "recipient_id": String,
##   "subject_scope": String, "subject_id": String,
##   "multiplier": float (e.g. duration_ticks),
##   "context": Dictionary (optional distance, access_permeability, etc.),
##   "secondary_targets": Array of { "target_scope": String, "target_id": String, "effort_ratio": float }
## }
static func process_verb_impact(world_state: Dictionary, impact_params: Dictionary, cfg: Dictionary) -> Dictionary:
	var obs_scope: String = str(cfg.get("observer_scope", impact_params.get("observer_scope", "RESIDENT"))).to_upper().strip_edges()
	var obs_id: String = str(impact_params.get("observer_id", "")).strip_edges()
	if obs_id.is_empty():
		return {}

	var rules_mod: String = str(cfg.get("rules_module", DEFAULT_RULES_MODULE))
	var metric_id: String = str(cfg.get("metric_id", DEFAULT_METRIC_ID)).to_upper().strip_edges()
	var model: String = str(cfg.get("model", "HYPERBOLIC_EFFORT_PER_TICK")).to_upper().strip_edges()
	var ctx: Dictionary = impact_params.get("context", {}).duplicate(true)
	if cfg.has("pool_container"):
		ctx["pool_container"] = str(cfg["pool_container"])

	if model == "HYPERBOLIC_EFFORT_PER_TICK":
		var base_per_unit: float = float(cfg.get("base_effort_per_tick", cfg.get("base_effort", 10.0)))
		var multiplier: float = maxf(0.0, float(impact_params.get("multiplier", 1.0)))
		var total_effort: float = base_per_unit * multiplier
		var tgt_scope: String = str(cfg.get("target_scope", impact_params.get("target_scope", ""))).to_upper().strip_edges()
		var tgt_id: String = str(impact_params.get("target_id", "")).strip_edges()

		if tgt_scope.is_empty() or tgt_id.is_empty() or total_effort <= 0.0:
			return {}

		var new_score: float = apply_effort_impulse(
			world_state, obs_scope, obs_id, tgt_scope, tgt_id, total_effort, ctx, rules_mod, metric_id
		)
		var result: Dictionary = {
			"metric_id": metric_id,
			"observer_scope": obs_scope,
			"observer_id": obs_id,
			"target_scope": tgt_scope,
			"target_id": tgt_id,
			"effort_applied": total_effort,
			"new_score": new_score
		}

		var secondary: Array = impact_params.get("secondary_targets", [])
		var secondary_applied: int = 0
		for item in secondary:
			if not (item is Dictionary):
				continue
			var s_scope: String = str(item.get("target_scope", "")).to_upper().strip_edges()
			var s_id: String = str(item.get("target_id", "")).strip_edges()
			var s_ratio: float = float(item.get("effort_ratio", cfg.get("secondary_effort_ratio", 0.45)))
			if not s_scope.is_empty() and not s_id.is_empty() and s_ratio > 0.0:
				apply_effort_impulse(
					world_state, obs_scope, obs_id, s_scope, s_id, total_effort * s_ratio, ctx, rules_mod, metric_id
				)
				secondary_applied += 1

		if secondary_applied > 0:
			result["secondary_targets_updated"] = secondary_applied
		return result

	elif model == "COMPARTMENTALIZED_TRANSFER":
		var to_scope: String = str(cfg.get("recipient_scope", impact_params.get("recipient_scope", "RESIDENT"))).to_upper().strip_edges()
		var to_id: String = str(impact_params.get("recipient_id", "")).strip_edges()
		var subj_scope: String = str(cfg.get("subject_scope", impact_params.get("subject_scope", ""))).to_upper().strip_edges()
		var subj_id: String = str(impact_params.get("subject_id", "")).strip_edges()
		var share_ratio: float = float(cfg.get("share_ratio", cfg.get("transfer_efficiency", 0.75)))

		if to_id.is_empty() or subj_scope.is_empty() or subj_id.is_empty():
			return {}

		var transferred_score: float = transfer_intel(
			world_state, obs_scope, obs_id, to_scope, to_id, subj_scope, subj_id, share_ratio, ctx, rules_mod, metric_id
		)
		return {
			"metric_id": metric_id,
			"from_scope": obs_scope,
			"from_id": obs_id,
			"to_scope": to_scope,
			"to_id": to_id,
			"subject_scope": subj_scope,
			"subject_id": subj_id,
			"transferred_score": transferred_score
		}

	return {}

## Returns whether an entity's existence/threshold is breached (>= existence_threshold)
static func is_entity_known(score: float, target_scope: String, rules_module: String = DEFAULT_RULES_MODULE) -> bool:
	var rules: Dictionary = get_rules(rules_module)
	var defaults: Dictionary = rules.get("curve_defaults", {})
	var scope_cfg: Dictionary = rules.get("scopes", {}).get(target_scope.to_upper(), {})
	var threshold: float = float(scope_cfg.get("existence_threshold", defaults.get("existence_threshold", 1.0)))
	return score >= threshold

## Returns array of all field/capability tokens unlocked at the given score for target_scope (["*"] at 100.0)
static func get_exposed_fields(score: float, target_scope: String, rules_module: String = DEFAULT_RULES_MODULE) -> Array[String]:
	var exposed: Array[String] = []
	var rules: Dictionary = get_rules(rules_module)
	var scope_cfg: Dictionary = rules.get("scopes", {}).get(target_scope.to_upper(), {})
	var thresholds: Array = scope_cfg.get("thresholds", [])

	for tier in thresholds:
		if not (tier is Dictionary):
			continue
		var min_req: float = float(tier.get("min_score", 0.0))
		if score >= min_req:
			var fields: Array = tier.get("fields", [])
			for f in fields:
				var f_str := str(f)
				if f_str == "*":
					return ["*"]
				if not exposed.has(f_str):
					exposed.append(f_str)
	return exposed

## Checks if a specific field/capability token is unlocked at the given score
static func is_field_exposed(score: float, target_scope: String, field_name: String, rules_module: String = DEFAULT_RULES_MODULE) -> bool:
	var fields := get_exposed_fields(score, target_scope, rules_module)
	return fields.has("*") or fields.has(field_name)

## Scales perception noise/fuzz inversely with score down to error_floor
static func attenuate_fuzz(base_fuzz: float, error_floor: float, score: float, rules_module: String = DEFAULT_RULES_MODULE) -> float:
	var rules: Dictionary = get_rules(rules_module)
	var fuzz_cfg: Dictionary = rules.get("curve_defaults", {}).get("fuzz_attenuation", {})
	var exact_score: float = maxf(1.0, float(fuzz_cfg.get("exact_at_score", 100.0)))
	var t: float = clampf(score / exact_score, 0.0, 1.0)
	return lerpf(base_fuzz, error_floor, t)

## Filters a raw entity record dictionary down to only fields exposed at the given score
static func project_record(raw_record: Dictionary, score: float, target_scope: String, rules_module: String = DEFAULT_RULES_MODULE) -> Dictionary:
	if not is_entity_known(score, target_scope, rules_module):
		return {}
	var exposed := get_exposed_fields(score, target_scope, rules_module)
	if exposed.has("*"):
		return raw_record.duplicate(true)

	var projected: Dictionary = {}
	for f_key in exposed:
		var base_key: String = f_key.split(".")[0]
		if raw_record.has(base_key):
			projected[base_key] = raw_record[base_key]
	projected["_measure_score"] = score
	return projected

static func _write_score_fallback(
	world_state: Dictionary,
	pool_container: String,
	obs_scope: String,
	obs_id: String,
	tgt_scope: String,
	tgt_id: String,
	score: float
) -> void:
	if not world_state.has(pool_container) or not (world_state[pool_container] is Dictionary):
		world_state[pool_container] = {}
	var pools: Dictionary = world_state[pool_container]
	if not pools.has(obs_scope):
		pools[obs_scope] = {}
	if not pools[obs_scope].has(obs_id):
		pools[obs_scope][obs_id] = {}
	var target_key := "%s:%s" % [tgt_scope, tgt_id]
	if score <= 0.0:
		pools[obs_scope][obs_id].erase(target_key)
	else:
		pools[obs_scope][obs_id][target_key] = {
			"score": score,
			"last_updated_day": int(world_state.get("metadata", {}).get("current_sim_day", 0))
		}