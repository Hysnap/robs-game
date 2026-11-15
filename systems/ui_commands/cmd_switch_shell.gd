# res://systems/ui_commands/cmd_switch_shell.gd
extends RefCounted

## Hot-swaps the active OuterShell workspace manifest while preserving staged directives
static func execute(payload: Dictionary, _view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var target_shell_id: String = str(payload.get("shell_id", "")).strip_edges()
	var switch_cb: Variant = context_refs.get("on_shell_switch", Callable())
	assert(switch_cb is Callable and (switch_cb as Callable).is_valid(),
		"FATAL: [CmdSwitchShell] Missing or invalid 'on_shell_switch' Callable in context_refs.")
	(switch_cb as Callable).call(target_shell_id)