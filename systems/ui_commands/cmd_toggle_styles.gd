# res://systems/ui_commands/cmd_toggle_styles.gd
extends RefCounted

## Toggles the Shell Customizer overlay visibility and brings it to front
static func execute(_payload: Dictionary, _view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var customizer = context_refs.get("shell_customizer", null)
	assert(customizer != null and is_instance_valid(customizer),
		"FATAL: [CmdToggleStyles] Missing or invalid 'shell_customizer' in context_refs.")

	customizer.visible = not customizer.visible
	if customizer.visible:
		customizer.move_to_front()