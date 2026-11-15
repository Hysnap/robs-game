# res://systems/ui_commands/cmd_commit_turn_cycle.gd
extends RefCounted

const OperationsControllerScript = preload("res://systems/operations_controller.gd")

## Extracts staged orders from the active Action Planner and executes a simulation turn cycle
static func execute(_payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var staged: Array = []
	var planner = context_refs.get("action_planner", null)
	if planner != null and planner.has_method("get_staged_directives"):
		staged = planner.get_staged_directives()

	OperationsControllerScript.execute_staged_cycle(staged, view_host)