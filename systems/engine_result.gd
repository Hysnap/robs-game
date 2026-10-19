# res://systems/engine_result.gd
class_name EngineResult extends RefCounted

enum ErrorCode {
	OK = 0,
	ENTITY_NOT_FOUND = 1,
	INSUFFICIENT_RESOURCE = 2,
	UNKNOWN_COMMODITY = 3,
	INVALID_DIRECTIVE = 4,
	ROUTER_UNMAPPED_VERB = 5,
	SINK_REGISTRATION_MISSING = 6,
	# Extended codes for supply-chain & schedule friction
	OUTSIDE_HOURS = 7,
	PAYMENT_REQUIRED = 8,
	NO_SHIPMENT_PENDING = 9,
	OPERATOR_BURNOUT = 10
}

var error_code: int = ErrorCode.OK
var success: bool = true
var verb: String = ""
var message: String = ""
var impact_deltas: Dictionary = {}
var amount: float = 0.0
var target_node: String = ""
var context: Dictionary = {}

func _init(p_success: bool = true, 
	p_error_code: int = ErrorCode.OK, 
	p_verb: String = "", 
	p_message: String = "", 
	p_deltas: Dictionary = {}, 
	p_amount: float = 0.0, 
	p_target_node: String = "",
	p_context: Dictionary = {}
) -> void:
	success = p_success
	error_code = p_error_code
	verb = p_verb.to_upper()
	message = p_message
	impact_deltas = p_deltas
	amount = p_amount
	target_node = p_target_node
	context = p_context

	# Ensure basic parameters are always available to the dialogue resolver
	if not context.has("amount"): context["amount"] = amount
	if not context.has("target_location"): context["target_location"] = target_node
	if not context.has("verb"): context["verb"] = verb

## Returns the uppercase string name of the error code for JSON feedback lookup
func get_code_string() -> String:
	if error_code == ErrorCode.OK:
		return "SUCCESS"
	if error_code >= 0 and error_code < ErrorCode.size():
		return ErrorCode.keys()[error_code]
	return "UNKNOWN_ERROR"

## Preserves backward-compatibility with Dictionary-expecting callers
func to_dict() -> Dictionary:
	return {
"success": success,
		"error_code": error_code,
		"code": get_code_string(),
		"verb": verb,
		"message": message,
		"impact_deltas": impact_deltas,
		"amount": amount,
		"target_node_id": target_node,
		"context": context
	}

# --- Convenience Constructors ---

static func ok(
	p_verb: String, 
	p_message: String = "", 
	p_deltas: Dictionary = {}, 
	p_amount: float = 0.0, 
	p_target_node: String = "",
	p_extra_context: Dictionary = {}
) -> EngineResult:
	return EngineResult.new(true, ErrorCode.OK, p_verb, p_message, p_deltas, p_amount, p_target_node, p_extra_context)

static func fail(
	p_error_code: int, 
	p_verb: String, 
	p_message: String = "", 
	p_target_node: String = "",
	p_extra_context: Dictionary = {}
) -> EngineResult:
	return EngineResult.new(false, p_error_code, p_verb, p_message, {}, 0.0, p_target_node, p_extra_context)