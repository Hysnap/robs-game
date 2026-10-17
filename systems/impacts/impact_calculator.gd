# res://systems/impacts/impact_calculator.gd
class_name ImpactCalculator extends RefCounted

## Evaluates quantitative impact deltas based on standardized calculation archetypes
static func calculate(calc_type: String, quantity: float, factor: float, params: Dictionary = {}) -> float:
	if quantity <= 0.0 or factor == 0.0:
		return 0.0

	match calc_type:
		"LINEAR_PER_UNIT":
			return quantity * factor

		"WEIGHTED_PER_UNIT":
			# factor * quantity scaled by an environmental or situational multiplier
			var weight: float = float(params.get("environment_weight", 1.0))
			return (quantity * factor) * weight

		"EXP_PER_UNIT":
			# Exponential scale: factor * (base^(quantity * rate) - 1.0)
			# Ideal for risk that cascades out of control with large volume
			var exp_base: float = float(params.get("exponent_base", 1.05))
			var rate_scale: float = float(params.get("rate_scale", 1.0))
			return factor * (pow(exp_base, quantity * rate_scale) - 1.0)

		"LOG_PER_UNIT":
			# Logarithmic scale: factor * ln(1 + quantity * rate)
			# Ideal for diminishing returns (tolerance, customer discovery)
			var log_scale: float = float(params.get("log_scale", 1.0))
			return factor * log(1.0 + (quantity * log_scale))

		"STEPPED_PER_UNIT":
			# Discrete bucket jumps: increments only when step threshold is reached
			var step_size: float = max(1.0, float(params.get("step_size", 10.0)))
			var completed_steps: int = floori(quantity / step_size)
			return float(completed_steps) * factor

		_:
			push_warning("[IMPACT CALCULATOR] Unknown calculation model '%s'. Defaulting to 0.0" % calc_type)
			return 0.0