# res://scenes/ui/shell_host/ui_action_command.gd
class_name UIActionCommand
extends RefCounted

enum CommandType {
	ROUTE_REQUEST,
	ITEM_SELECTED,
	ACTION_CLICKED,
	SLIP_FILED
}

var type: CommandType
var domain: String = ""
var action_code: String = ""
var payload: Dictionary = {}

func _init(p_type: CommandType, p_domain: String = "", p_action_code: String = "", p_payload: Dictionary = {}) -> void:
	type = p_type
	domain = p_domain
	action_code = p_action_code
	payload = p_payload