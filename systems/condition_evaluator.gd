# res://systems/condition_evaluator.gd
class_name ConditionEvaluator extends RefCounted

## Evaluates whether a metric has breached a threshold using standard operators
static func evaluate(current_val: float, threshold_val: float, operator: String) -> bool:
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