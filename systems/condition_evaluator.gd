# res://systems/condition_evaluator.gd
class_name ConditionEvaluator extends RefCounted

const _Calculator = preload("res://systems/impacts/impact_calculator.gd")

# =====================================================================
# 1. ATOMIC COMPARISON OPERATOR ENGINE
# =====================================================================

## Evaluates whether a value breaches a threshold using a string operator
static func evaluate(current_val: float, threshold_val: float, operator: String = ">=") -> bool:
	match operator:
		"<":  return current_val < threshold_val
		"<=": return current_val <= threshold_val
		">":  return current_val > threshold_val
		">=": return current_val >= threshold_val
		"==": return is_equal_approx(current_val, threshold_val)
		"!=": return not is_equal_approx(current_val, threshold_val)
		_:
			push_error("[CONDITION EVALUATOR] Unknown operator: %s" % operator)
			return false

# =====================================================================
# 2. UNIVERSAL REQUIREMENT GATES (SINGLE & COMPOUND)
# =====================================================================

## Universal Requirement Check: Gating cash, commodities, fatigue, time, or social standing
static func has_sufficient(
	world_state: Dictionary, 
	actor_id: String, 
	metric: String, 
	target_val: float, 
	operator: String = ">=", 
	context: Dictionary = {}
) -> bool:
	# 1. CASH & LIQUIDITY
	if metric.to_upper() in ["CASH", "LIQUID_CASH"]:
		if _is_infinite_mode_active(actor_id, "third_party_funds_mode", "INFINITE_FUNDS"):
			return true

		var current_cash: float = get_state_metric(world_state, actor_id, "CASH", context)
		if current_cash == -INF:
			return false
		return evaluate(current_cash, target_val, operator)

	# 2. PHYSICAL INVENTORY / COMMODITY STOCK
	if _is_infinite_mode_active(actor_id, "supplier_stock_mode", "INFINITE_SUPPLY"):
		return true

	var current_stock: float = get_state_metric(world_state, actor_id, metric, context)
	if current_stock == -INF:
		return false
	return evaluate(current_stock, target_val, operator)

## Evaluates a compound list of condition rules where ALL must pass ("AND" gate / Tolerance Band)
static func has_all(world_state: Dictionary, actor_id: String, gate_list: Array, context: Dictionary = {}) -> bool:
	for gate in gate_list:
		var metric: String = gate.get("metric", "")
		var required_qty: float = float(gate.get("amount", gate.get("required_qty", 0.0)))
		var op: String = gate.get("operator", ">=")
		
		if not has_sufficient(world_state, actor_id, metric, required_qty, op, context):
			return false
	return true

## Evaluates whether AT LEAST ONE condition in an array is met ("OR" gate / Bifurcated Exclusion Zone)
static func has_any(world_state: Dictionary, actor_id: String, gate_list: Array, context: Dictionary = {}) -> bool:
	if gate_list.is_empty():
		return true
		
	for gate in gate_list:
		var metric: String = gate.get("metric", "")
		var required_qty: float = float(gate.get("amount", gate.get("required_qty", 0.0)))
		var op: String = gate.get("operator", ">=")
		
		if has_sufficient(world_state, actor_id, metric, required_qty, op, context):
			return true
	return false

# =====================================================================
# 3. NON-LINEAR CURVE GATE EVALUATION
# =====================================================================

## Transforms an input value through a chosen curve (EXP, LOG, STEPPED, LINEAR, INVERTED_U_CURVE)
## via ImpactCalculator and tests if the scaled output satisfies the threshold
static func evaluate_curve_gate(
	raw_input_value: float, 
	model_type: String, 
	factor: float, 
	params: Dictionary, 
	threshold_val: float, 
	operator: String = ">="
) -> bool:
	var transformed_val: float = _Calculator.calculate(model_type, raw_input_value, factor, params)
	return evaluate(transformed_val, threshold_val, operator)

## Evaluates a declarative gate dictionary loaded from JSON or config files
static func evaluate_gate_dict(world_state: Dictionary, gate_def: Dictionary, context: Dictionary = {}) -> bool:
	if gate_def.is_empty():
		return true

	var actor_id: String = gate_def.get("actor_id", "PLAYER")
	var metric: String = gate_def.get("metric", gate_def.get("resource", "CASH"))
	var op: String = gate_def.get("operator", ">=")
	var target_val: float = float(gate_def.get("target_value", gate_def.get("amount", 0.0)))

	if gate_def.get("gate_type", "FLAT") == "CURVE":
		var raw_val: float = get_state_metric(world_state, actor_id, metric, context)
		if raw_val == -INF:
			return false
		return evaluate_curve_gate(
			raw_val,
			gate_def.get("model", "LINEAR_PER_UNIT"),
			float(gate_def.get("factor", 1.0)),
			gate_def.get("params", {}),
			target_val,
			op
		)
	else:
		return has_sufficient(world_state, actor_id, metric, target_val, op, context)

# =====================================================================
# 4. UNIVERSAL STATE METRIC RESOLVER
# =====================================================================

## Dynamically extracts numerical values across all architectural categories:
## Finances, Personal Attributes, Relational Standing, and Physical Stock
static func get_state_metric(world_state: Dictionary, actor_id: String, metric_key: String, context: Dictionary = {}) -> float:
	var upper_key: String = metric_key.to_upper()
	
	# --- A. LIQUID CASH & FINANCES ---
	if upper_key in ["CASH", "LIQUID_CASH"]:
		if _is_infinite_mode_active(actor_id, "third_party_funds_mode", "INFINITE_FUNDS"):
			return INF
		if actor_id in ["PLAYER", "", "HQ"]:
			return float(world_state.get("finances", {}).get("liquid_cash", 0.0))
		var staff_member: Dictionary = world_state.get("staff", {}).get(actor_id, {})
		if not staff_member.is_empty():
			return float(staff_member.get("cash", 0.0))
		var counterparty: Dictionary = world_state.get("counterparties", world_state.get("npcs", {})).get(actor_id, {})
		if not counterparty.is_empty():
			return float(counterparty.get("cash", 0.0))
		return -INF

	# --- B. PERSONAL ATTRIBUTES (Fatigue, Loyalty, Intoxication, Shift Time) ---
	if upper_key in ["FATIGUE", "WORKER_FATIGUE", "LOYALTY", "INTOXICATION", "SHIFT_TIME_SPENT", "OPERATIONAL_TIME"]:
		var attr_key: String = upper_key.to_lower()
		if attr_key == "worker_fatigue": attr_key = "fatigue"
		if attr_key == "operational_time": attr_key = "shift_time_spent"
		
		if actor_id in ["PLAYER", "", "HQ"]:
			return float(world_state.get("operations", {}).get(attr_key, 0.0))
		var staff: Dictionary = world_state.get("staff", {}).get(actor_id, {})
		if not staff.is_empty():
			return float(staff.get(attr_key, 0.0))
		return -INF

	# --- C. RELATIONAL STANDING (Reputation / Influence / Trust) ---
	if upper_key in ["REPUTATION", "PERSONAL_REPUTATION", "INFLUENCE", "PERSONAL_INFLUENCE", "TRUST"]:
		var target_entity: String = context.get("target_entity_id", context.get("target_node_id", context.get("venue_id", "")))
		return _resolve_relational_metric(world_state, actor_id, target_entity, upper_key)

	# --- D. PHYSICAL COMMODITIES (Stock Balance) ---
	var inventory: Dictionary = get_actor_inventory(world_state, actor_id)
	if inventory.has(metric_key):
		if _is_infinite_mode_active(actor_id, "supplier_stock_mode", "INFINITE_SUPPLY"):
			return INF
		return float(inventory[metric_key].get("STOCK", 0.0))

	return 0.0

# =====================================================================
# 5. UNIVERSAL INVENTORY CALCULATIONS
# =====================================================================

## Universal inventory accessor (internal & external tool)
static func get_actor_inventory(world_state: Dictionary, actor_id: String) -> Dictionary:
	if actor_id in ["PLAYER", "", "HQ"]:
		return world_state.get("inventory_registry", {})
	if actor_id in ["WHOLESALER", "MARKET_CONSUMERS"]:
		return {}

	var staff_record: Dictionary = world_state.get("staff", {}).get(actor_id, {})
	if not staff_record.is_empty():
		return staff_record.get("inventory", {})

	var cp_record: Dictionary = world_state.get("counterparties", world_state.get("npcs", {})).get(actor_id, {})
	if not cp_record.is_empty():
		return cp_record.get("inventory", {})

	return {}

## Internal helper: Resolves social/relational capital across Venues, Counterparties, or Districts
static func _resolve_relational_metric(world_state: Dictionary, actor_id: String, target_entity: String, metric_type: String) -> float:
	if target_entity.is_empty():
		return 0.0
		
	# 1. Check if target is a Venue (Pub / Taproom)
	for dist_id in world_state.get("districts", {}).keys():
		var venues = world_state["districts"][dist_id].get("venues", {})
		if venues.has(target_entity):
			var staff_rep = venues[target_entity].get("staff_reputation", {})
			var personal = staff_rep.get(actor_id, {})
			if metric_type in ["REPUTATION", "PERSONAL_REPUTATION"]:
				return float(personal.get("personal_reputation", 0.0))
			else:
				return float(personal.get("personal_influence", 0.0))

	# 2. Check if target is an NPC / Counterparty / Faction
	var counterparties = world_state.get("counterparties", world_state.get("npcs", {}))
	if counterparties.has(target_entity):
		return float(counterparties[target_entity].get("trust_network", {}).get(actor_id, 0.0))

	# 3. Check if target is a Macro District
	if world_state.get("districts", {}).has(target_entity):
		if metric_type in ["REPUTATION", "PERSONAL_REPUTATION"]:
			return float(world_state["districts"][target_entity].get("local_reputation", 0.0))
		else:
			return float(world_state["districts"][target_entity].get("local_influence", 0.0))

	return 0.0

## Universal check: inspects if a third-party actor has infinite capacity for a given rule
static func _is_infinite_mode_active(actor_id: String, rule_key: String, bypass_value: String) -> bool:
	if actor_id in ["PLAYER", "", "HQ"]:
		return false

	var manifest: Dictionary = {}
	if ClassDB.class_exists("ScenarioManifestManager"):
		manifest = ScenarioManifestManager.get_manifest()

	var mode: String = manifest.get("market_rules", {}).get(rule_key, "").to_upper()
	return mode == bypass_value

# =====================================================================
# 6. PERCEPTION, FUZZINESS & SCALED ROUNDING ENGINE
# =====================================================================

## Categorizes a normalized or continuous ratio into an ordered N-bucket configuration
## `buckets` is an Array of Dictionaries formatted as:
## [
##   {"max": 0.04, "token": "UI_UNEMP_NEGLIGIBLE"},
##   {"max": 0.09, "token": "UI_UNEMP_LOW"},
##   ...
##   {"token": "UI_UNEMP_CRITICAL"} ; Final terminal bucket without max
## ]
static func evaluate_n_bucket(val: float, buckets: Array, fallback_token: String = "") -> String:
	if buckets.is_empty():
		return fallback_token

	for bucket in buckets:
		if bucket.has("max"):
			var upper_bound: float = float(bucket["max"])
			if val <= upper_bound:
				return str(bucket.get("token", fallback_token))
		else:
			# Terminal catch-all bucket
			return str(bucket.get("token", fallback_token))

	return fallback_token

## Calculates a fuzzed ratio with an additive home-turf modifier and clamped minimum error floor
static func calculate_fuzzed_ratio(
	base_val: float, 
	is_home_turf: bool, 
	jitter_min: float = -0.15, 
	jitter_max: float = 0.15, 
	home_fuzz_modifier: float = 0.10, 
	min_floor: float = 0.03
) -> float:
	var span_half: float = (absf(jitter_max) + absf(jitter_min)) * 0.5
	
	# Additive modifier narrows the fuzz span on home turf
	if is_home_turf:
		span_half = maxf(min_floor, span_half - absf(home_fuzz_modifier))
	else:
		span_half = maxf(min_floor, span_half)

	# Generate deterministic or ambient variance within the computed window
	var noise: float = randf_range(-span_half, span_half)
	return maxf(0.0, base_val * (1.0 + noise))

## Scaled adaptive rounding for headcounts (small shops remain granular, large works round coarser)
## `tiers` is an Array of Dictionaries sorted ascending by `threshold`:
## [
##   {"threshold": 10, "round_to": 1},
##   {"threshold": 50, "round_to": 5},
##   {"threshold": 250, "round_to": 25},
##   {"threshold": 1000, "round_to": 100}
## ]
static func round_adaptive(raw_count: int, tiers: Array = [], default_step: int = 1) -> int:
	if raw_count <= 0:
		return 0

	var chosen_step: int = default_step

	for tier in tiers:
		var thresh: int = int(tier.get("threshold", 0))
		if raw_count <= thresh:
			chosen_step = int(tier.get("round_to", default_step))
			break
		# If past the threshold, update candidate step to the highest encountered bracket
		chosen_step = int(tier.get("round_to", chosen_step))

	if chosen_step <= 1:
		return raw_count

	var step_f: float = float(chosen_step)
	return int(roundf(float(raw_count) / step_f) * step_f)

## Universal Transformation Pipeline for Continuous Numeric Measures
## Passes any numeric measure through configured noise fuzzing and maps it
## to either an N-Bucket semantic token, an adaptively rounded value, or a raw clamped float.
static func transform_measure(
	raw_val: float, 
	spec: Dictionary, 
	is_home_turf: bool = false
) -> Variant:
	if spec.is_empty():
		return raw_val

	# 1. Bounded Fuzz Stage (if noise parameters exist in spec)
	var j_min: float = float(spec.get("fuzz_jitter_min", 0.0))
	var j_max: float = float(spec.get("fuzz_jitter_max", 0.0))
	var h_mod: float = float(spec.get("home_modifier", 0.0))
	var floor_val: float = float(spec.get("error_floor", 0.0))

	var evaluated_val: float = raw_val
	if j_min != 0.0 or j_max != 0.0:
		evaluated_val = calculate_fuzzed_ratio(raw_val, is_home_turf, j_min, j_max, h_mod, floor_val)

	# 2. Discretization Engine Dispatch
	var mode: String = str(spec.get("mode", "DIRECT")).to_upper()
	match mode:
		"N_BUCKET":
			var buckets: Array = spec.get("buckets", [])
			var fallback: String = str(spec.get("fallback_token", "UI_INTEL_MASKED_BLANK"))
			return evaluate_n_bucket(evaluated_val, buckets, fallback)
			
		"STEPPED_ROUNDING":
			var tiers: Array = spec.get("tiers", [])
			var default_step: int = int(spec.get("default_step", 1))
			return round_adaptive(int(evaluated_val), tiers, default_step)

		"FUZZ_RATIO", "RATIO":
			return clampf(evaluated_val, 0.0, 1.0)

		"CURVE":
			var model_type: String = str(spec.get("model", "LINEAR_PER_UNIT"))
			var factor: float = float(spec.get("factor", 1.0))
			var params: Dictionary = spec.get("params", {})
			return _Calculator.calculate(model_type, evaluated_val, factor, params)

		"GATE", "BOOLEAN":
			var threshold: float = float(spec.get("threshold", 0.0))
			var op: String = str(spec.get("operator", ">="))
			return evaluate(evaluated_val, threshold, op)

		"QUANTILE":
			var thresholds: Array[float] = []
			for t in spec.get("thresholds", []):
				thresholds.append(float(t))
			return evaluate_quantile_bucket(evaluated_val, thresholds)

		"PRECISION_ROUND", "PRECISION":
			var decimals: int = int(spec.get("precision", 2))
			var scale: float = pow(10.0, float(decimals))
			return roundf(evaluated_val * scale) / scale

		"DIRECT":
			return evaluated_val
			
		_:
			push_error("[ConditionEvaluator] Unknown transformation mode: %s" % mode)
			return evaluated_val

## Pure Mathematical Calculation: Calculates the sum of (quantity * weight) pairs
## Completely agnostic to whether this represents cubic meters, currency value, weight, or labor hours.
static func evaluate_weighted_sum(quantities: Dictionary, weights: Dictionary, default_weight: float = 1.0) -> float:
	var total: float = 0.0
	for key in quantities.keys():
		var qty: float = float(quantities[key])
		if qty <= 0.0:
			continue
		var weight: float = float(weights.get(key, default_weight))
		total += qty * weight
	return total

# =====================================================================
# STATISTICAL & AGGREGATE OPERATORS
# =====================================================================

## Calculates the arithmetic mean of an array of numbers
static func evaluate_mean(values: Array, fallback: float = 0.0) -> float:
	if values.is_empty():
		return fallback
	var sum: float = 0.0
	var count: int = 0
	for val in values:
		if val != null:
			sum += float(val)
			count += 1
	if count == 0:
		return fallback
	return sum / float(count)

## Computes the median (50th percentile) value from an array of numbers
static func evaluate_median(values: Array, fallback: float = 0.0) -> float:
	var clean: Array[float] = []
	for v in values:
		if v != null:
			clean.append(float(v))
	if clean.is_empty():
		return fallback

	clean.sort()
	var n: int = clean.size()
	var mid: int = n / 2
	if n % 2 == 1:
		return clean[mid]
	else:
		return (clean[mid - 1] + clean[mid]) * 0.5

## Computes the modal (most frequent) value from an array of numbers.
## rounding_precision: -1 preserves raw values; >= 0 rounds values prior to counting.
static func evaluate_mode(values: Array, fallback: float = 0.0, rounding_precision: int = -1) -> float:
	if values.is_empty():
		return fallback

	var frequency_map: Dictionary = {}
	var max_frequency: int = 0
	var modal_val: float = fallback

	for raw_v in values:
		if raw_v == null:
			continue
		var val: float = float(raw_v)
		if rounding_precision >= 0:
			var scale: float = pow(10.0, rounding_precision)
			val = roundf(val * scale) / scale

		var count: int = int(frequency_map.get(val, 0)) + 1
		frequency_map[val] = count

		if count > max_frequency:
			max_frequency = count
			modal_val = val

	return modal_val

## Calculates (num_buckets - 1) boundary thresholds that divide a population into N equal-count groups (quantiles).
## Example: For 100 values and 5 buckets (quintiles), returns 4 cutoff values [Q1, Q2, Q3, Q4].
static func calculate_quantile_thresholds(values: Array, num_buckets: int) -> Array[float]:
	var thresholds: Array[float] = []
	if num_buckets <= 1 or values.is_empty():
		return thresholds

	var clean: Array[float] = []
	for v in values:
		if v != null:
			clean.append(float(v))
	if clean.is_empty():
		return thresholds

	clean.sort()
	var m: float = float(clean.size())
	var n: float = float(num_buckets)

	for k in range(1, num_buckets):
		var target_idx: int = mini(clean.size() - 1, floori((float(k) * m) / n) - 1)
		target_idx = maxi(0, target_idx)
		thresholds.append(clean[target_idx])

	return thresholds

## Evaluates which quantile bucket index a value belongs to, given sorted quantile boundary thresholds.
## Returns index k in [0, thresholds.size()].
static func evaluate_quantile_bucket(val: float, thresholds: Array[float]) -> int:
	for i in range(thresholds.size()):
		if val <= thresholds[i]:
			return i
	return thresholds.size()

## Partitions an array of values into N sub-arrays, each containing an equal count of items (+/- 1).
static func partition_into_equal_frequency_buckets(values: Array, num_buckets: int) -> Array:
	var result: Array = []
	if num_buckets <= 0:
		return result

	for _i in range(num_buckets):
		result.append([])

	if values.is_empty():
		return result

	var sorted_items: Array = values.duplicate()
	sorted_items.sort()

	var total_items: float = float(sorted_items.size())
	var n_buckets_f: float = float(num_buckets)

	for idx in range(sorted_items.size()):
		var bucket_idx: int = mini(num_buckets - 1, floori((float(idx) * n_buckets_f) / total_items))
		result[bucket_idx].append(sorted_items[idx])

	return result