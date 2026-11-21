# res://systems/economy/manager_ai_resolver.gd
class_name ManagerAIResolver
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const OrgMandateManagerScript = preload("res://systems/economy/org_mandate_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")
const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")

const MANAGER_RULES_DIR := "res://systems/economy/manager_rules/"

static var _rules_cache: Dictionary = {}
static var _hook_scripts_cache: Array = []
static var _hooks_initialized: bool = false

## Clears cached config & discovered hook scripts (for test isolation or manifest reload)
static func reset_cache() -> void:
	_rules_cache.clear()
	_hook_scripts_cache.clear()
	_hooks_initialized = false

## Loads manager_adaptation_rules.json from the active scenario manifest
static func get_rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache
	assert(ScenarioManifestManagerScript.has_module("manager_adaptation"),
		"FATAL: [ManagerAIResolver] 'manager_adaptation' module not registered in active society manifest.")
	_rules_cache = ScenarioManifestManagerScript.load_module("manager_adaptation")
	return _rules_cache

## Discovers optional plug-in rule scripts (rule_*.gd) via FileSystemCrawler
static func _get_hook_scripts() -> Array:
	if _hooks_initialized:
		return _hook_scripts_cache
	_hook_scripts_cache.clear()
	var paths: Array[String] = FileSystemCrawlerScript.find_files_recursive(MANAGER_RULES_DIR, "", ".gd")
	paths.sort()
	for path in paths:
		if not path.get_file().to_lower().begins_with("rule_"):
			continue
		var script_res = load(path)
		assert(script_res != null, "FATAL: [ManagerAIResolver] Failed to load manager rule hook: %s" % path)
		_hook_scripts_cache.append(script_res)
	_hooks_initialized = true
	return _hook_scripts_cache

## Extracts normalized cognitive & OCEAN profile using profile_defaults from config
static func get_manager_profile(resident: Dictionary) -> Dictionary:
	var defaults: Dictionary = get_rules().get("profile_defaults", {})
	var ocean: Dictionary = resident.get("ocean", resident.get("personality", {})) if resident.get("ocean", resident.get("personality", {})) is Dictionary else {}
	var profile: Dictionary = {}
	for key in defaults.keys():
		var raw_val: Variant = ocean.get(key, resident.get(key, defaults[key]))
		if key == "iq_score":
			profile[key] = float(raw_val)
		else:
			profile[key] = clampf(float(raw_val), 0.0, 1.0)
	profile["neurodivergence_tags"] = resident.get("neurodivergence_tags", [])
	return profile

## Determines standing-order standardization vs. worker autonomy using standardization_model config
static func evaluate_standardization_policy(resident: Dictionary, mandate: Dictionary) -> Dictionary:
	var cfg: Dictionary = get_rules().get("standardization_model", {})
	var p := get_manager_profile(resident)
	var mode: String = str(mandate.get("mandate_mode", "CASHFLOW")).to_upper()

	var c_w: float = float(cfg.get("conscientiousness_weight", 0.65))
	var closed_w: float = float(cfg.get("closedness_weight", 0.35))
	var mode_deltas: Dictionary = cfg.get("mode_rigidity_deltas", {})
	var mode_delta: float = float(mode_deltas.get(mode, 0.0))

	var rigidity: float = clampf(
		(float(p.get("conscientiousness", 0.5)) * c_w) + ((1.0 - float(p.get("openness", 0.5))) * closed_w) + mode_delta,
		0.0,
		1.0
	)

	var auto_w: Dictionary = cfg.get("autonomy_weights", {})
	var autonomy_allowance: float = clampf(
		(float(p.get("openness", 0.5)) * float(auto_w.get("openness", 0.5))) +
		(float(p.get("agreeableness", 0.5)) * float(auto_w.get("agreeableness", 0.35))) -
		(rigidity * float(auto_w.get("rigidity_penalty", 0.35))),
		0.0,
		1.0
	)

	var thresh: Dictionary = cfg.get("thresholds", {})
	var rigid_min: float = float(thresh.get("rigid_sop_min_rigidity", 0.65))
	var auto_min: float = float(thresh.get("autonomous_min_allowance", 0.55))
	var style := "RIGID_SOP" if rigidity >= rigid_min else ("AUTONOMOUS_DELEGATION" if autonomy_allowance >= auto_min else "BALANCED_OVERSIGHT")

	var result: Dictionary = {
		"policy_style": style,
		"rigidity_score": rigidity,
		"autonomy_allowance": autonomy_allowance,
		"suppress_billy_tweaks": rigidity >= float(thresh.get("suppress_billy_min_rigidity", 0.70)),
		"auto_generate_standing_orders": rigidity >= float(thresh.get("auto_generate_sop_min_rigidity", 0.55))
	}
	return _apply_hooks("on_standardization_evaluated", result, {"resident": resident, "mandate": mandate, "profile": p})

## Evaluates cognitive span-of-control capacity and mid-horizon micromanagement churn from config
static func evaluate_span_of_control(resident: Dictionary, subordinate_count: int) -> Dictionary:
	var cfg: Dictionary = get_rules().get("span_of_control_model", {})
	var p := get_manager_profile(resident)

	var base_span: float = float(cfg.get("base_span", 3.0))
	var iq_base: float = float(cfg.get("iq_baseline", 100.0))
	var iq_slope: float = float(cfg.get("iq_slope", 0.08))
	var agility_mult: float = float(cfg.get("agility_multiplier", 4.0))
	var min_span: int = int(cfg.get("min_span", 2))
	var max_span: int = int(cfg.get("max_span", 12))

	var iq_bonus: float = (float(p.get("iq_score", iq_base)) - iq_base) * iq_slope
	var agility_bonus: float = float(p.get("mental_agility", 0.5)) * agility_mult
	var max_effective_span: int = clampi(int(round(base_span + iq_bonus + agility_bonus)), min_span, max_span)

	var overload: int = maxi(0, subordinate_count - max_effective_span)
	var bottleneck_ratio: float = clampf(float(overload) / float(maxi(1, max_effective_span)), 0.0, 1.0)

	var tw: Dictionary = cfg.get("tinker_weights", {})
	var tinker_propensity: float = clampf(
		(float(p.get("neuroticism", 0.5)) * float(tw.get("neuroticism", 0.55))) +
		((1.0 - float(p.get("agreeableness", 0.5))) * float(tw.get("disagreeableness", 0.25))) +
		(bottleneck_ratio * float(tw.get("bottleneck_ratio", 0.35))) -
		(float(p.get("mental_agility", 0.5)) * float(tw.get("agility_relief", 0.20))),
		0.0,
		1.0
	)

	var eff_pen: float = float(cfg.get("efficiency_penalty_per_overload_ratio", 0.30))
	var min_eff: float = float(cfg.get("min_efficiency_mult", 0.55))

	var result: Dictionary = {
		"subordinate_count": subordinate_count,
		"max_effective_span": max_effective_span,
		"overload_count": overload,
		"bottleneck_ratio": bottleneck_ratio,
		"execution_efficiency_mult": clampf(1.0 - (bottleneck_ratio * eff_pen), min_eff, 1.0),
		"tinker_propensity": tinker_propensity,
		"triggers_mid_horizon_churn": tinker_propensity >= float(cfg.get("churn_threshold", 0.68))
	}
	return _apply_hooks("on_span_evaluated", result, {"resident": resident, "profile": p})

## Determines reporting cadence and whether the manager opens a solicited assistance window
static func evaluate_reporting_and_escalation(
	world_state: Dictionary,
	resident: Dictionary,
	mandate: Dictionary,
	kpis: Dictionary
) -> Dictionary:
	var cfg: Dictionary = get_rules().get("reporting_and_escalation_model", {})
	var p := get_manager_profile(resident)
	var current_day: int = CalendarHelperScript.get_current_sim_day(world_state)
	var mandate_id: int = int(mandate.get("mandate_id", 0))
	var heat_ceiling: float = float(mandate.get("heat_ceiling", 0.65))

	var current_heat: float = float(kpis.get("current_heat", 0.0))
	var target_attainment: float = float(kpis.get("target_attainment", 1.0))
	var subordinate_escalations: int = int(kpis.get("subordinate_escalations", 0))
	var kpi_floor: float = float(cfg.get("kpi_attainment_floor", 0.75))

	var heat_breached: bool = current_heat > heat_ceiling
	var kpi_breached: bool = target_attainment < kpi_floor
	var crisis_detected: bool = heat_breached or kpi_breached or subordinate_escalations > 0

	var is_verbose: bool = _matches_any_rule_block(cfg.get("verbose_digest_rules", []), p)
	var reporting_mode: String = "VERBOSE_DIGEST" if is_verbose else "EXCEPTION_ONLY"
	var should_emit_report: bool = crisis_detected or is_verbose

	var bounds: Array = cfg.get("coping_bounds", [0.35, 0.85])
	var coping_raw: float = float(cfg.get("coping_base", 0.55)) + (float(p.get("mental_agility", 0.5)) * float(cfg.get("coping_agility_bonus", 0.25))) - (float(p.get("neuroticism", 0.5)) * float(cfg.get("coping_neuroticism_penalty", 0.25)))
	var coping_threshold: float = clampf(coping_raw, float(bounds[0]), float(bounds[1]))

	var severity: float = 0.0
	if heat_breached:
		severity += (current_heat - heat_ceiling) * 1.5
	if kpi_breached:
		severity += (kpi_floor - target_attainment)
	if subordinate_escalations > 0:
		severity += 0.25 * float(subordinate_escalations)

	var agree_min: float = float(cfg.get("high_agreeableness_escalation_min", 0.70))
	var requested_assistance: bool = crisis_detected and (severity >= coping_threshold or float(p.get("agreeableness", 0.5)) >= agree_min)
	if requested_assistance and mandate_id > 0:
		var win_days: int = int(cfg.get("assistance_window_days", 7))
		OrgMandateManagerScript.grant_assistance_window(world_state, mandate_id, current_day + win_days)

	var tokens: Dictionary = cfg.get("memo_tokens", {})
	var report_token: String = str(tokens.get("assistance_requested", "UI_MEMO_MGR_ASSISTANCE_REQ")) if requested_assistance else (
		str(tokens.get("crisis_alert", "UI_MEMO_MGR_CRISIS_ALERT")) if crisis_detected else str(tokens.get("routine_digest", "UI_MEMO_MGR_ROUTINE_DIGEST"))
	)

	var result: Dictionary = {
		"mandate_id": mandate_id,
		"reporting_mode": reporting_mode,
		"should_emit_report": should_emit_report,
		"crisis_detected": crisis_detected,
		"requested_assistance": requested_assistance,
		"report_token": report_token
	}
	return _apply_hooks("on_reporting_evaluated", result, {"resident": resident, "mandate": mandate, "kpis": kpis, "profile": p})

## Resolves dyadic interaction when two managers' 4-axis mandate scopes overlap via ConditionEvaluator rules
static func resolve_dyadic_mandate_collision(
	resident_a: Dictionary,
	mandate_a: Dictionary,
	resident_b: Dictionary,
	mandate_b: Dictionary
) -> Dictionary:
	var overlap_axes: Array[String] = OrgMandateManagerScript.detect_scope_overlap(
		mandate_a.get("scope_filter", {}),
		mandate_b.get("scope_filter", {})
	)
	if overlap_axes.is_empty():
		return {
			"has_collision": false,
			"outcome": "DISJOINT",
			"overlap_axes": []
		}

	var pa := get_manager_profile(resident_a)
	var pb := get_manager_profile(resident_b)

	var metrics: Dictionary = {
		"avg_agreeableness": (float(pa.get("agreeableness", 0.5)) + float(pb.get("agreeableness", 0.5))) * 0.5,
		"avg_conscientiousness": (float(pa.get("conscientiousness", 0.5)) + float(pb.get("conscientiousness", 0.5))) * 0.5,
		"avg_neuroticism": (float(pa.get("neuroticism", 0.5)) + float(pb.get("neuroticism", 0.5))) * 0.5,
		"extraversion_gap": absf(float(pa.get("extraversion", 0.5)) - float(pb.get("extraversion", 0.5)))
	}
	for k in pa.keys():
		if pa[k] is float or pa[k] is int:
			metrics["a." + str(k)] = float(pa[k])
	for k in pb.keys():
		if pb[k] is float or pb[k] is int:
			metrics["b." + str(k)] = float(pb[k])

	var rules: Array = get_rules().get("dyadic_collision_rules", [])
	var chosen_rule: Dictionary = {}
	for rule in rules:
		if rule is Dictionary and _evaluate_rule_block(rule, metrics):
			chosen_rule = rule
			break

	var effects: Dictionary = chosen_rule.get("effects", {})
	var result: Dictionary = {
		"has_collision": true,
		"outcome": str(chosen_rule.get("outcome", "FRICTIONAL_OVERLAP")),
		"overlap_axes": overlap_axes,
		"mandate_a_id": int(mandate_a.get("mandate_id", 0)),
		"mandate_b_id": int(mandate_b.get("mandate_id", 0)),
		"efficiency_delta": float(effects.get("efficiency_delta", 0.0)),
		"heat_delta": float(effects.get("heat_delta", 0.0)),
		"trust_delta": float(effects.get("trust_delta", 0.0))
	}
	return _apply_hooks("on_dyadic_collision_resolved", result, {
		"resident_a": resident_a, "mandate_a": mandate_a,
		"resident_b": resident_b, "mandate_b": mandate_b,
		"metrics": metrics
	})

static func _matches_any_rule_block(rule_blocks: Array, metrics: Dictionary) -> bool:
	for block in rule_blocks:
		if block is Dictionary and _evaluate_rule_block(block, metrics):
			return true
	return false

static func _evaluate_rule_block(block: Dictionary, metrics: Dictionary) -> bool:
	var logic: String = str(block.get("logic", "SINGLE")).to_upper()
	if logic == "ALWAYS":
		return true
	if block.has("metric"):
		var m_key: String = str(block.get("metric", ""))
		if not metrics.has(m_key):
			return false
		return ConditionEvaluatorScript.evaluate_gate({
			"current": float(metrics[m_key]),
			"target": block.get("value", 0.0),
			"operator": str(block.get("op", "==")),
			"lower": float(block.get("value", 0.0)),
			"upper": float(block.get("value_max", 0.0))
		})

	var conds: Array = block.get("conditions", [])
	if conds.is_empty():
		return false
	var leaf_gates: Array = []
	for c in conds:
		if not (c is Dictionary):
			continue
		if c.has("metric"):
			var c_key: String = str(c.get("metric", ""))
			if not metrics.has(c_key):
				return false
			leaf_gates.append({
				"current": float(metrics[c_key]),
				"target": c.get("value", 0.0),
				"operator": str(c.get("op", "==")),
				"lower": float(c.get("value", 0.0)),
				"upper": float(c.get("value_max", 0.0))
			})
		else:
			leaf_gates.append({
				"current": 1.0 if _evaluate_rule_block(c, metrics) else 0.0,
				"target": 1.0,
				"operator": "=="
			})
	return ConditionEvaluatorScript.evaluate_logic_block(logic, leaf_gates)

static func _apply_hooks(hook_method: String, result: Dictionary, context: Dictionary) -> Dictionary:
	var current: Dictionary = result
	for script_res in _get_hook_scripts():
		if script_res != null and script_res.has_method(hook_method):
			var modified = script_res.call(hook_method, current, context)
			if modified is Dictionary:
				current = modified
	return current