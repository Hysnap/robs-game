# res://ui/components/smooth_progress_bar.gd
class_name SmoothProgressBar
extends ProgressBar

@export var smoothing_speed: float = 12.0
@export var snap_threshold: float = 0.1

var _target_value: float = 0.0

func _ready() -> void:
	_target_value = value

func set_target_value(target: float, immediate: bool = false) -> void:
	_target_value = clampf(target, min_value, max_value)
	if immediate:
		value = _target_value

func _process(delta: float) -> void:
	if is_equal_approx(value, _target_value):
		return
	
	if absf(value - _target_value) <= snap_threshold:
		value = _target_value
	else:
		# Smooth exponential approach towards target value
		value = lerpf(value, _target_value, clampf(delta * smoothing_speed, 0.0, 1.0))