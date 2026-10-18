# res://data_modules/crime/impacts/staff_consumption/sink_consumption.gd
extends ImpactSinkBase
class_name SinkStaffConsumption

## Fallback defaults if rules.cfg is missing from the data module
static var _loyalty_threshold: float = 0.60
static var _loyalty_operator: String = "<"
static var _ambient_increment: float = 0.01
static var _initialized: bool = false
static var _staff_addiction: float = 0.01


static func _ensure_config_loaded() -> void:
	if _initialized:
		return
	
	var config_path = "res://data_modules/crime/impacts/staff_consumption/rules.cfg"
	if FileAccess.file_exists(config_path):
		var cfg = ConfigFile.new()
		if cfg.load(config_path) == OK:
			_loyalty_threshold = float(cfg.get_value("thresholds", "loyalty_skim_threshold", 0.60))
			_loyalty_operator = str(cfg.get_value("thresholds", "loyalty_operator", "<"))
			_ambient_increment = float(cfg.get_value("thresholds", "ambient_increment", 0.01))
			_staff_addiction = float(cfg.get_value("thresholds", "staff_addicition", 0.01))
	
	_initialized = true

static func get_metric_key() -> String:
	return "STAFF_CONSUMPTION"

## Action Impulse: Clamps consumption between 0.0 (0%) and 1.0 (100%) of staff members habit (consumption)
static func apply_delta(world_state: Dictionary, staff_id: String, delta: float) -> void:
	var staff_table: Dictionary = world_state.get("staff", {})
	if not staff_table.has(staff_id):
		return
		
	var staff_member: Dictionary = staff_table[staff_id]
	var current_consumption: float = float(staff_member.get("actual_consumption", 0.0))
	staff_member["actual_consumption"] = clamp(current_consumption + delta, 0.0, 1.0)

## Ambient Heartbeat: Evaluates loyalty threshold via ConditionEvaluator
static func process_ambient(world_state: Dictionary) -> void:
	_ensure_config_loaded()
	var staff_table: Dictionary = world_state.get("staff", {})
	
	for staff_id in staff_table.keys():
		var staff_member: Dictionary = staff_table[staff_id]
		var loyalty: float = float(staff_member.get("loyalty", 1.0))
		
		# Agnostic gate evaluation processed by systems/
		var should_consume: bool = ConditionEvaluator.evaluate(loyalty, _loyalty_threshold, _loyalty_operator)
		
		if should_consume:
			var current_consumption: float = float(staff_member.get("actual_consumption", 0.0))
			staff_member["actual_consumption"] = clamp(current_consumption + _ambient_increment, 0.0, 1.0)