# res://tools/ui_compiler/widgets/emit_button.gd
@tool
class_name UIEmitButton
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var r_token: String = row.get("token", "")
	var wrap_enabled: bool = bool(row.get("autowrap", true))

	lines.append("\tvar btn_" + r_id + " := Button.new()")
	lines.append("\tbtn_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tbtn_" + r_id + ".text = tr(\"" + r_token + "\")")
	lines.append("\tbtn_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\tbtn_" + r_id + ".alignment = HORIZONTAL_ALIGNMENT_LEFT")
	if wrap_enabled:
		lines.append("\tbtn_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
	
	var action_signal: String = row.get("action_signal", "action_clicked")
	var emit_args: String = str(row.get("emit_args", ""))
	
	if emit_args == "\"SELECT_ALL\"":
		lines.append("\tbtn_" + r_id + ".pressed.connect(func(): if \"_queue\" in self: self._queue.toggle_all())")
	elif not emit_args.is_empty():
		lines.append("\tbtn_" + r_id + ".pressed.connect(func(): self." + action_signal + ".emit(" + emit_args + "))")
	else:
		lines.append("\tbtn_" + r_id + ".pressed.connect(func(): self." + action_signal + ".emit())")
		
	lines.append("\t_value_labels[\"" + r_id + "\"] = btn_" + r_id)
	lines.append("\tadd_child(btn_" + r_id + ")\n")

	return lines