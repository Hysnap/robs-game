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
const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")

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

## Returns direct stored entry { "score": float, "last_updated_day": int } for a single observer -> target pair
static func get_direct_entry(
	world_state: Dictionary,
	observer_scope: String,
	observer_id: String,
	target_scope: String,
	target_id: String,
	pool_container: String = DEFAULT_POOL_CONTAINER
) -> Dictionary:
	var pools = world_state.get(pool_container, null)
	if not (pools is Dictionary):
		return {}
	var scope_pool = pools.get(observer_scope.to_upper(), null)
	if not (scope_pool is Dictionary):
		return {}
	var dossier = scope_pool.get(observer_id, null)
	if not (dossier is Dictionary):
		return {}
	var target_key := "%s:%s" % [target_scope.to_upper(), target_id]
	var entry = dossier.get(target_key, null)
	if entry is Dictionary:
		return entry
	return {}

## Returns direct stored score (0.0 - 100.0) for a single observer -> target pair
static func get_direct_score(
	world_state: Dictionary,
	observer_scope: String,
	observer_id: String,
	target_scope: String,
	target_id: String,
	pool_container: String = DEFAULT_POOL_CONTAINER
) -> float:
	var entry: Dictionary = get_direct_entry(world_state, observer_scope, observer_id, target_scope, target_id, pool_container)
	if not entry.is_empty():
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

## Computes collective best score AND freshest last_updated_day / age_days across observers & org affiliations
static func get_collective_intel_status(
	world_state: Dictionary,
	observers: Array,
	target_scope: String,
	target_id: String,
	pool_container: String = DEFAULT_POOL_CONTAINER,
	clearance_field: String = "intel_clearance"
) -> Dictionary:
	var best_score: float = 0.0
	var freshest_day: int = -1
	var current_day: int = CalendarHelperScript.get_current_sim_day(world_state)

	for obs in observers:
		if not (obs is Dictionary):
			continue
		var o_scope: String = str(obs.get("observer_scope", "RESIDENT")).to_upper()
		var o_id: String = str(obs.get("observer_id", ""))
		if o_id.is_empty():
			continue

		var direct_entry: Dictionary = get_direct_entry(world_state, o_scope, o_id, target_scope, target_id, pool_container)
		if not direct_entry.is_empty():
			var d_score: float = clampf(float(direct_entry.get("score", 0.0)), 0.0, 100.0)
			if d_score > best_score:
				best_score = d_score
			if d_score > 0.0 and direct_entry.has("last_updated_day"):
				freshest_day = maxi(freshest_day, int(direct_entry["last_updated_day"]))

		var affs: Array = obs.get("affiliations", [])
		for aff in affs:
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
			var org_entry: Dictionary = get_direct_entry(world_state, org_scope, org_id, target_scope, target_id, pool_container)
			if not org_entry.is_empty():
				var org_raw: float = clampf(float(org_entry.get("score", 0.0)), 0.0, 100.0)
				var inherited: float = org_raw * clampf(clearance, 0.0, 1.0)
				if inherited > best_score:
					best_score = inherited
				if inherited > 0.0 and org_entry.has("last_updated_day"):
					freshest_day = maxi(freshest_day, int(org_entry["last_updated_day"]))

	var age_days: int = maxi(0, current_day - freshest_day) if freshest_day >= 0 else -1
	return {
		"score": clampf(best_score, 0.0, 100.0),
		"last_updated_day": freshest_day,
		"age_days": age_days
	}

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

## Resolves slider disclosure_level (0.0 - 1.0) into { "share_ratio": float, "max_score_cap": float, "label_token": String }
static func resolve_disclosure_tier(disclosure_level: float, rules_module: String = DEFAULT_RULES_MODULE) -> Dictionary:
	var rules: Dictionary = get_rules(rules_module)
	var disc_cfg: Dictionary = rules.get("disclosure_tiers", {})
	var tiers: Array = disc_cfg.get("tiers", [])
	assert(not tiers.is_empty(), "FATAL: [IntelManager] '%s' module missing 'disclosure_tiers.tiers'." % rules_module)

	var clamped_slider: float = clampf(disclosure_level, 0.0, 1.0)
	for tier in tiers:
		if tier is Dictionary and clamped_slider <= float(tier.get("max_slider", 1.0)):
			return {
				"share_ratio": clampf(float(tier.get("share_ratio", 1.0)), 0.0, 1.0),
				"max_score_cap": clampf(float(tier.get("max_score_cap", 100.0)), 0.0, MAX_ASYMPTOTIC_CAP),
				"label_token": str(tier.get("label_token", "UI_INTEL_SHARE_STANDARD_CREW"))
			}

	var last_tier: Dictionary = tiers[tiers.size() - 1]
	return {
		"share_ratio": clampf(float(last_tier.get("share_ratio", 1.0)), 0.0, 1.0),
		"max_score_cap": clampf(float(last_tier.get("max_score_cap", 100.0)), 0.0, MAX_ASYMPTOTIC_CAP),
		"label_token": str(last_tier.get("label_token", "UI_INTEL_SHARE_SKELETONS_ALL"))
	}

## Transfers an actor's personal knowledge about a subject scope (or "SELF" / "ALL") upward to an organization
## gated by a 0.0-1.0 disclosure_level slider and declarative share_expansions in intel_exposure_rules.json.
static func share_actor_intel_with_org(
	world_state: Dictionary,
	actor_id: String,
	org_id: String,
	share_scope: String,
	subject_id: String = "",
	disclosure_level: float = -1.0,
	context: Dictionary = {},
	rules_module: String = DEFAULT_RULES_MODULE,
	metric_id: String = DEFAULT_METRIC_ID
) -> Dictionary:
	var clean_actor: String = actor_id.strip_edges()
	var clean_org: String = org_id.strip_edges()
	var norm_scope: String = share_scope.to_upper().strip_edges()
	if clean_actor.is_empty() or clean_org.is_empty() or norm_scope.is_empty():
		return {"targets_shared": 0}

	var rules: Dictionary = get_rules(rules_module)
	var effective_slider: float = disclosure_level
	if effective_slider < 0.0:
		effective_slider = float(rules.get("disclosure_tiers", {}).get("default_initial_crew_level", 0.8))

	var tier_cfg: Dictionary = resolve_disclosure_tier(effective_slider, rules_module)
	var share_ratio: float = float(tier_cfg["share_ratio"])
	var tier_cap: float = float(tier_cfg["max_score_cap"])
	var pool_container: String = str(context.get("pool_container", DEFAULT_POOL_CONTAINER))

	var candidate_targets: Array[Dictionary] = []
	var seen_keys: Dictionary = {}

	if norm_scope == "ALL":
		var actor_dossier = world_state.get(pool_container, {}).get("RESIDENT", {}).get(clean_actor, null)
		if actor_dossier is Dictionary:
			for raw_key in actor_dossier.keys():
				var compound := str(raw_key)
				var sep_idx := compound.find(":")
				if sep_idx <= 0:
					continue
				var t_scope := compound.substr(0, sep_idx).to_upper()
				var t_id := compound.substr(sep_idx + 1)
				if not t_id.is_empty() and not seen_keys.has(compound):
					seen_keys[compound] = true
					candidate_targets.append({"target_scope": t_scope, "target_id": t_id})
	else:
		var expansions: Dictionary = rules.get("share_expansions", {})
		var exp_cfg: Dictionary = expansions.get(norm_scope, {}) if expansions.get(norm_scope, null) is Dictionary else {}
		var resolved_scope: String = str(exp_cfg.get("alias_scope", norm_scope)).to_upper().strip_edges()
		var resolved_subject: String = clean_actor if bool(exp_cfg.get("use_actor_id", false)) else subject_id.strip_edges()

		if not resolved_scope.is_empty() and not resolved_subject.is_empty():
			var direct_key := "%s:%s" % [resolved_scope, resolved_subject]
			seen_keys[direct_key] = true
			candidate_targets.append({"target_scope": resolved_scope, "target_id": resolved_subject})

			var sub_exp_cfg: Dictionary = expansions.get(resolved_scope, {}) if expansions.get(resolved_scope, null) is Dictionary else {}
			var query_method: String = str(sub_exp_cfg.get("query_method", "")).strip_edges()
			if not query_method.is_empty() and query_method in SocietyQueriesScript:
				var resolver := Callable(SocietyQueriesScript, query_method)
				if resolver.is_valid():
					var child_targets: Array = resolver.call(resolved_scope, resolved_subject)
					for item in child_targets:
						if item is Dictionary:
							var c_scope := str(item.get("target_scope", "")).to_upper().strip_edges()
							var c_id := str(item.get("target_id", "")).strip_edges()
							var c_key := "%s:%s" % [c_scope, c_id]
							if not c_scope.is_empty() and not c_id.is_empty() and not seen_keys.has(c_key):
								seen_keys[c_key] = true
								candidate_targets.append({"target_scope": c_scope, "target_id": c_id})

	var shared_count: int = 0
	for tgt in candidate_targets:
		var t_scope: String = tgt["target_scope"]
		var t_id: String = tgt["target_id"]
		var actor_score: float = get_direct_score(world_state, "RESIDENT", clean_actor, t_scope, t_id, pool_container)
		if not is_entity_known(actor_score, t_scope, rules_module):
			continue

		var target_max_cap: float = minf(tier_cap, actor_score * share_ratio)
		if target_max_cap <= 0.0:
			continue

		var transfer_ctx := context.duplicate(true)
		transfer_ctx["max_cap"] = target_max_cap
		var current_org_score: float = get_direct_score(world_state, "ORG", clean_org, t_scope, t_id, pool_container)
		if current_org_score >= target_max_cap:
			continue

		transfer_intel(
			world_state, "RESIDENT", clean_actor, "ORG", clean_org, t_scope, t_id, share_ratio,
			transfer_ctx, rules_module, metric_id
		)
		shared_count += 1

	return {
		"actor_id": clean_actor,
		"org_id": clean_org,
		"share_scope": norm_scope,
		"disclosure_level": effective_slider,
		"label_token": tier_cfg["label_token"],
		"targets_shared": shared_count
	}

## Generic declarative saturating impact executor (completely measure- & scope-agnostic)
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
			"last_updated_day": CalendarHelperScript.get_current_sim_day(world_state)
		}

## Builds the player's canonical 1st-degree intel and observer context from residents & continuous knowledge_pools
static func build_player_intel_context(ws: Dictionary) -> Dictionary:
	var crew_ids: Array[int] = []
	var observers: Array = []
	var residents_dict: Dictionary = ws.get("residents", {})
	var ops_cfg: Dictionary = ws.get("operations", {})
	var crew_org_id: String = str(ops_cfg.get("crew_org_id", "ORG:CREW_ENTERPRISE")).strip_edges()
	var hq_estab_id: int = int(ops_cfg.get("hq_establishment_id", 0))

	for key in residents_dict.keys():
		var rec = residents_dict[key]
		if rec is Dictionary and bool(rec.get("is_crew", true)):
			var r_id: int = int(rec.get("resident_id", 0))
			var affiliations: Array = []

			if not crew_org_id.is_empty():
				var crew_clearance: float = 1.0 if bool(rec.get("is_leader", false)) else float(rec.get("crew_clearance", 0.85))
				affiliations.append({
					"org_scope": "ORG",
					"org_id": crew_org_id,
					"clearance": crew_clearance
				})

			if hq_estab_id > 0:
				affiliations.append({
					"org_scope": "ESTABLISHMENT",
					"org_id": str(hq_estab_id),
					"clearance": 1.0
				})

			var primary_role_code: String = str(rec.get("primary_role_code", rec.get("role_title", rec.get("role", "")))).strip_edges()
			var work_est_id: int = int(rec.get("primary_employer_establishment_id", 0))
			if work_est_id > 0:
				affiliations.append({
					"org_scope": "ESTABLISHMENT",
					"org_id": str(work_est_id),
					"role_code": primary_role_code
				})

			var work_org_id: String = str(rec.get("primary_employer_org_id", "")).strip_edges()
			if not work_org_id.is_empty() and work_org_id != crew_org_id:
				affiliations.append({
					"org_scope": "ORG",
					"org_id": work_org_id,
					"role_code": primary_role_code
				})

			if r_id > 0 and not crew_ids.has(r_id):
				crew_ids.append(r_id)
				observers.append({
					"observer_scope": "RESIDENT",
					"observer_id": str(r_id),
					"affiliations": affiliations
				})
			var slot_str := str(key)
			if not slot_str.is_empty() and slot_str != str(r_id):
				observers.append({
					"observer_scope": "RESIDENT",
					"observer_id": slot_str,
					"affiliations": affiliations
				})

	return {
		"world_state": ws,
		"observers": observers,
		"crew_resident_ids": crew_ids
	}

## Returns normalized display descriptors for active crew residents in world_state["residents"]
static func get_crew_residents(ws: Dictionary) -> Array[Dictionary]:
	var crew: Array[Dictionary] = []
	var seen_ids: Array[int] = []
	var residents_dict: Dictionary = ws.get("residents", {})

	for key in residents_dict.keys():
		var rec = residents_dict[key]
		if rec is Dictionary and bool(rec.get("is_crew", true)):
			var r_id: int = int(rec.get("resident_id", 0))
			if r_id <= 0 or seen_ids.has(r_id):
				continue
			seen_ids.append(r_id)
			var full_name: String = str(rec.get("name", "")).strip_edges()
			if full_name.is_empty():
				full_name = ("%s %s" % [str(rec.get("first_name", "")), str(rec.get("current_surname", ""))]).strip_edges()
			if full_name.is_empty():
				continue
			var role_str: String = str(rec.get("role_title", rec.get("role", ""))).strip_edges()
			crew.append({
				"id": r_id,
				"resident_id": r_id,
				"name": full_name,
				"role": role_str
			})

	crew.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["resident_id"]) < int(b["resident_id"])
	)
	return crew

## Returns player-known districts and establishments in active_district_id filtered by 0-100 perception thresholds
static func get_known_locations(active_district_id: String, ws: Dictionary) -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	var intel_ctx: Dictionary = build_player_intel_context(ws)
	var observers: Array = intel_ctx.get("observers", [])

	# A. Known Districts
	var districts_map: Dictionary = ws.get("districts", {})
	var candidate_ids: Array[String] = []
	for d_key in districts_map.keys():
		candidate_ids.append(str(d_key))
	if not active_district_id.is_empty() and not candidate_ids.has(active_district_id):
		candidate_ids.append(active_district_id)

	for s_id in candidate_ids:
		var dist_rec: Dictionary = districts_map.get(s_id, {}) if districts_map.has(s_id) and districts_map[s_id] is Dictionary else {}
		var is_landmark: bool = bool(dist_rec.get("is_public_landmark", false))
		var score: float = get_collective_score(ws, observers, "DISTRICT", s_id)
		if is_landmark and score < 20.0:
			score = 20.0
		if s_id != active_district_id and not is_entity_known(score, "DISTRICT"):
			continue

		var d_name: String = str(dist_rec.get("display_name", ""))
		if d_name.is_empty() and SocietyQueriesScript != null:
			var census: Dictionary = SocietyQueriesScript.get_district_census(s_id)
			d_name = str(census.get("district_name", ""))
		if d_name.is_empty():
			d_name = s_id.trim_prefix("DISTRICT_").capitalize().replace("_", " ")

		locations.append({
			"id": s_id,
			"type": "DISTRICT",
			"category": "DISTRICT",
			"sector": "DISTRICT",
			"display": d_name,
			"intel_score": score
		})

	# B. Known Establishments in active district
	if not active_district_id.is_empty():
		var estabs: Array = SocietyQueriesScript.get_district_establishments(active_district_id)
		for e in estabs:
			var estab_id: int = int(e.get("establishment_id", 0))
			if estab_id <= 0:
				continue
			var e_score: float = get_collective_score(ws, observers, "ESTABLISHMENT", str(estab_id))
			if bool(e.get("is_public_landmark", false)) and e_score < 20.0:
				e_score = 20.0
			if not is_entity_known(e_score, "ESTABLISHMENT"):
				continue

			var e_name: String = str(e.get("name", ""))
			var cat_code: String = str(e.get("category_code", ""))
			var is_residential: bool = (cat_code == "RESIDENTIAL_UNIT" or cat_code.begins_with("RESIDENTIAL"))
			var sector: String = "RESIDENTIAL" if is_residential else "WORKPLACE"

			locations.append({
				"id": estab_id,
				"type": "ESTABLISHMENT",
				"category": cat_code,
				"sector": sector,
				"display": e_name,
				"intel_score": e_score
			})

	return locations

## Queries establishment dockets through the Fog-of-War intel filter and extracts unmasked contacts
static func resolve_known_contacts_for_location(location_meta: Dictionary, ws: Dictionary) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	if not (location_meta is Dictionary) or str(location_meta.get("type", "")) != "ESTABLISHMENT":
		return contacts

	var estab_id: int = int(location_meta.get("id", 0))
	if estab_id <= 0:
		return contacts

	var sim_day: int = CalendarHelperScript.get_current_sim_day(ws)
	var intel_ctx: Dictionary = build_player_intel_context(ws)
	var docket: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id, sim_day, intel_ctx)

	for emp in docket.get("employees", []):
		if bool(emp.get("is_masked", false)):
			continue
		var res_id: int = int(emp.get("resident_id", 0))
		var emp_name: String = str(emp.get("full_name", ""))
		var emp_role: String = str(emp.get("role_title", ""))
		if res_id > 0 and not emp_name.is_empty():
			contacts.append({
				"id": res_id,
				"name": emp_name,
				"role": emp_role,
				"type": "EMPLOYEE"
			})

	for res in docket.get("residents", []):
		if bool(res.get("is_masked", false)):
			continue
		var res_id: int = int(res.get("resident_id", 0))
		var res_name: String = str(res.get("full_name", ""))
		var res_role: String = "OCCUPANT"
		if res_id > 0 and not res_name.is_empty():
			contacts.append({
				"id": res_id,
				"name": res_name,
				"role": res_role,
				"type": "RESIDENTIAL"
			})

	return contacts

## Estimates perceived unit price using transacted price memory or intel-attenuated fuzzing
static func estimate_perceived_unit_cost(item_id: String, base_cost: float, location_meta: Dictionary, ws: Dictionary) -> Dictionary:
	if base_cost <= 0.0 or item_id.is_empty():
		return {
			"perceived_unit_cost": 0.0,
			"is_exact": true
		}

	var venue_id: String = str(location_meta.get("id", ""))
	var known_prices: Dictionary = ws.get("player_knowledge", {}).get("transacted_prices", {})
	var venue_prices: Dictionary = known_prices.get(venue_id, {})
	if venue_prices.has(item_id):
		return {
			"perceived_unit_cost": float(venue_prices[item_id]),
			"is_exact": true
		}

	var is_home: bool = bool(location_meta.get("is_home_turf", false))
	var venue_score: float = float(location_meta.get("intel_score", 0.0))
	var scaled_jitter: float = attenuate_fuzz(0.25, 0.02, venue_score)
	var fuzzed_cost: float = ConditionEvaluatorScript.calculate_fuzzed_ratio(base_cost, is_home, -scaled_jitter, scaled_jitter, 0.10, 0.02)
	return {
		"perceived_unit_cost": snappedf(fuzzed_cost, 0.05),
		"is_exact": false
	}