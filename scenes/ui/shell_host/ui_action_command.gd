# res://scenes/ui/shell_host/ui_action_command.gd
class_name UIActionCommand
extends RefCounted

var action_code: String = ""
var payload: Dictionary = {}

func _init(p_action_code: String = "", p_payload: Dictionary = {}) -> void:
	action_code = p_action_code.strip_edges().to_lower()
	payload = p_payload