# res://systems/condition_evaluator.gd
class_name ConditionEvaluator extends RefCounted

const _Calculator = preload("res://systems/impacts/impact_calculator.gd")

# =====================================================================
# 1. ATOMIC COMPARISON OPERATOR ENGINE
# =====================================================================

## Evaluates whether a numeric value breaches a threshold using a string operator
static func evaluate(current_val: float, threshold_val: float, operator: String = ">=") -> bool:
	match operator.strip_edges().to_upper():
		"<":  return current_val < threshold_val
		"<=": return current_val <= threshold_val
		">":  return current_val > threshold_val
		">=": return current_val >= threshold_val
		"==": return is_equal_approx(current_val, threshold_val)
		"!=": return not is_equal_approx(current_val, threshold_val)
		_:
			push_error("[CONDITION EVALUATOR] FAIL_LOUD: Unknown numeric operator: %s" % operator)
			return false

## Evaluates whether a numeric value falls within [lower_bound, upper_bound]
static func evaluate_between(current_val: float, lower_bound: float, upper_bound: float, inclusive: bool = true) -> bool:
	var low: float = minf(lower_bound, upper_bound)
	var high: float = maxf(lower_bound, upper_bound)
	if inclusive:
		return current_val >= low and current_val <= high
	return current_val > low and current_val < high

## Evaluates string / token equality or inequality (used for spatial IDs, tags, and state tokens)
static func evaluate_string(current_str: String, target_str: String, operator: String = "==") -> bool:
	var clean_curr: String = current_str.strip_edges()
	var clean_targ: String = target_str.strip_edges()
	match operator.strip_edges().to_upper():
		"==": return clean_curr == clean_targ
		"!=": return clean_curr != clean_targ
		"CONTAINS": return clean_curr.contains(clean_targ)
		_:
			push_error("[CONDITION EVALUATOR] FAIL_LOUD: Unknown string operator: %s" % operator)
			return false

## Evaluates a single resolved gate dictionary supporting scalars, ranges (BETWEEN), and strings
## Expected shape: {"current": Variant, "target": Variant, "operator": String, "lower": float, "upper": float}
static func evaluate_gate(gate: Dictionary) -> bool:
	var op: String = str(gate.get("operator", ">=")).strip_edges().to_upper()
	var raw_current: Variant = gate.get("current", 0.0)
	var raw_target: Variant = gate.get("target", 0.0)

	if op == "BETWEEN" or op == "NOT_BETWEEN":
		var low: float = float(gate.get("lower", 0.0))
		var high: float = float(gate.get("upper", 0.0))
		if raw_target is Array and raw_target.size() >= 2:
			low = float(raw_target[0])
			high = float(raw_target[1])
		var in_range: bool = evaluate_between(float(raw_current), low, high, true)
		return in_range if op == "BETWEEN" else not in_range

	if typeof(raw_current) == TYPE_STRING or typeof(raw_target) == TYPE_STRING:
		if not str(raw_current).is_valid_float() or not str(raw_target).is_valid_float():
			return evaluate_string(str(raw_current), str(raw_target), op)

	return evaluate(float(raw_current), float(raw_target), op)

# =====================================================================
# 2. COMPOUND COMPARISON GATES & DECISION BRANCHING (RESOLVED VALUES)
# =====================================================================

## Evaluates an array of resolved conditions where ALL must satisfy their threshold (AND gate)
static func has_all(resolved_gates: Array) -> bool:
	for gate in resolved_gates:
		if not evaluate_gate(gate):
			return false
	return true

## Evaluates an array of resolved conditions where AT LEAST ONE must satisfy its threshold (OR gate)
static func has_any(resolved_gates: Array) -> bool:
	if resolved_gates.is_empty():
		return true
	for gate in resolved_gates:
		if evaluate_gate(gate):
			return true
	return false

## Evaluates an array of resolved conditions where NOT ALL may be true (NAND gate)
static func has_nand(resolved_gates: Array) -> bool:
	if resolved_gates.is_empty():
		return false
	return not has_all(resolved_gates)

## Evaluates an array of resolved conditions where ZERO may be true (NOR gate)
static func has_none(resolved_gates: Array) -> bool:
	if resolved_gates.is_empty():
		return true
	return not has_any(resolved_gates)

## Evaluates an array of resolved conditions where EXACTLY ONE must be true (XOR gate)
static func has_xor(resolved_gates: Array) -> bool:
	var true_count: int = 0
	for gate in resolved_gates:
		if evaluate_gate(gate):
			true_count += 1
	return true_count == 1

## Universal compound logic gate dispatcher for macro verb decision trees
static func evaluate_logic_block(logic_gate: String, resolved_gates: Array) -> bool:
	match logic_gate.strip_edges().to_upper():
		"AND", "ALL":
			return has_all(resolved_gates)
		"OR", "ANY":
			return has_any(resolved_gates)
		"NAND", "NOT_ALL":
			return has_nand(resolved_gates)
		"NOR", "NONE":
			return has_none(resolved_gates)
		"XOR", "ONE":
			return has_xor(resolved_gates)
		_:
			push_error("[CONDITION EVALUATOR] FAIL_LOUD: Unknown logic gate: %s" % logic_gate)
			return false

## Standardised call-and-response decision router: evaluates a logic block and returns the branch outcome
static func evaluate_decision_branch(
	logic_gate: String,
	resolved_gates: Array,
	on_true_step: String = "",
	on_false_step: String = "",
	default_error_code: String = "INSUFFICIENT_RESOURCE"
) -> Dictionary:
	var passed: bool = evaluate_logic_block(logic_gate, resolved_gates)
	if passed:
		return {
			"passed": true,
			"next_step": on_true_step.strip_edges(),
			"halt": false,
			"error_code": ""
		}

	var clean_false: String = on_false_step.strip_edges()
	if not clean_false.is_empty() and clean_false.to_upper() != "HALT":
		return {
			"passed": false,
			"next_step": clean_false,
			"halt": false,
			"error_code": ""
		}

	return {
		"passed": false,
		"next_step": "",
		"halt": true,
		"error_code": default_error_code.strip_edges()
	}

# =====================================================================
# 3. NON-LINEAR CURVE GATE EVALUATION
# =====================================================================

## Transforms a raw numeric value through a curve model and compares it to a threshold
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

# =====================================================================
# 4. STATISTICAL & AGGREGATE OPERATORS
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
	var mid: int = int(floor(float(n) / 2.0))
	if n % 2 == 1:
		return clean[mid]
	else:
		return (clean[mid - 1] + clean[mid]) * 0.5

## Computes the modal (most frequent) value from an array of numbers
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

## Calculates quantile boundary thresholds that divide a population into N equal-count groups
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

## Evaluates which quantile bucket index a value belongs to
static func evaluate_quantile_bucket(val: float, thresholds: Array[float]) -> int:
	for i in range(thresholds.size()):
		if val <= thresholds[i]:
			return i
	return thresholds.size()

## Partitions an array of values into N sub-arrays of equal frequency
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

# =====================================================================
# 5. PERCEPTION, FUZZINESS & SCALED ROUNDING ENGINE
# =====================================================================

static func evaluate_n_bucket(val: float, buckets: Array, fallback_token: String = "") -> String:
	if buckets.is_empty():
		return fallback_token

	for bucket in buckets:
		if bucket.has("max"):
			var upper_bound: float = float(bucket["max"])
			if val <= upper_bound:
				return str(bucket.get("token", fallback_token))
		else:
			return str(bucket.get("token", fallback_token))

	return fallback_token

static func calculate_fuzzed_ratio(
	base_val: float, 
	is_home_turf: bool, 
	jitter_min: float = -0.15, 
	jitter_max: float = 0.15, 
	home_fuzz_modifier: float = 0.10, 
	min_floor: float = 0.03
) -> float:
	var span_half: float = (absf(jitter_max) + absf(jitter_min)) * 0.5
	if is_home_turf:
		span_half = maxf(min_floor, span_half - absf(home_fuzz_modifier))
	else:
		span_half = maxf(min_floor, span_half)

	var noise: float = randf_range(-span_half, span_half)
	return maxf(0.0, base_val * (1.0 + noise))

static func round_adaptive(raw_count: int, tiers: Array = [], default_step: int = 1) -> int:
	if raw_count <= 0:
		return 0

	var chosen_step: int = default_step

	for tier in tiers:
		var thresh: int = int(tier.get("threshold", 0))
		if raw_count <= thresh:
			chosen_step = int(tier.get("round_to", default_step))
			break
		chosen_step = int(tier.get("round_to", chosen_step))

	if chosen_step <= 1:
		return raw_count

	var step_f: float = float(chosen_step)
	return int(roundf(float(raw_count) / step_f) * step_f)

static func transform_measure(
	raw_val: float, 
	spec: Dictionary, 
	is_home_turf: bool = false
) -> Variant:
	if spec.is_empty():
		return raw_val

	var j_min: float = float(spec.get("fuzz_jitter_min", 0.0))
	var j_max: float = float(spec.get("fuzz_jitter_max", 0.0))
	var h_mod: float = float(spec.get("home_modifier", 0.0))
	var floor_val: float = float(spec.get("error_floor", 0.0))

	var evaluated_val: float = raw_val
	if j_min != 0.0 or j_max != 0.0:
		evaluated_val = calculate_fuzzed_ratio(raw_val, is_home_turf, j_min, j_max, h_mod, floor_val)

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

static func evaluate_weighted_sum(quantities: Dictionary, weights: Dictionary, default_weight: float = 1.0) -> float:
	var total: float = 0.0
	for key in quantities.keys():
		var qty: float = float(quantities[key])
		if qty <= 0.0:
			continue
		var weight: float = float(weights.get(key, default_weight))
		total += qty * weight
	return total