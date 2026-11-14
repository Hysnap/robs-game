# res://systems/ui_commands/cmd_select_all_directives.gd
extends RefCounted

## Toggles selection across all staged directives in the active Action Planner
static func execute(_payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var planner = context_refs.get("action_planner", view_host.get_action_component() if view_host != null else null)
	if planner != null and planner.has_method("toggle_all_directives"):
		planner.toggle_all_directives()