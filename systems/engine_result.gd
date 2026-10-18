# res://systems/engine_result.gd
class_name EngineResult extends RefCounted

enum ErrorCode {
	OK = 0,
	ENTITY_NOT_FOUND = 1,
	INSUFFICIENT_RESOURCE = 2,
	UNKNOWN_COMMODITY = 3,
	INVALID_DIRECTIVE = 4,
	ROUTER_UNMAPPED_VERB = 5,
	SINK_REGISTRATION_MISSING = 6
}

var success: bool = true
var code: int = ErrorCode.OK
var verb: String = ""
var message: String = ""
var target_id: String = ""
var units_transacted: float = 0.0
var impact_deltas: Dictionary = {}
var telemetry_payload: Dictionary = {}

static func ok(p_verb: String, p_msg: String, p_deltas: Dictionary = {}, p_units: float = 0.0, p_target: String = "") -> EngineResult:
	var res = EngineResult.new()
	res.success = true
	res.code = ErrorCode.OK
	res.verb = p_verb
	res.message = p_msg
	res.impact_deltas = p_deltas
	res.units_transacted = p_units
	res.target_id = p_target
	return res

static func fail(p_code: int, p_verb: String, p_msg: String, p_target: String = "") -> EngineResult:
	var res = EngineResult.new()
	res.success = false
	res.code = p_code
	res.verb = p_verb
	res.message = p_msg
	res.target_id = p_target
	# Centralized error reporting / terminal trace
	push_warning("[ENGINE ERROR %d][%s] Target: '%s' -> %s" % [p_code, p_verb, p_target, p_msg])
	return res

func to_dict() -> Dictionary:
	return {
		"success": success,
		"code": code,
		"verb": verb,
		"message": message,
		"target_node_id": target_id,
		"units_transacted": units_transacted,
		"impact_deltas": impact_deltas
	}