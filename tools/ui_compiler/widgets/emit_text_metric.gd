# res://tools/ui_compiler/widgets/emit_text_metric.gd
@tool
class_name UIEmitTextMetric
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var r_token: String = row.get("token", "")
	var wrap_enabled: bool = bool(row.get("autowrap", true))
	var color_token: String = str(row.get("color", "")).strip_edges()

	lines.append("\tvar row_" + r_id + " := HBoxContainer.new()")
	lines.append("\trow_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\trow_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	
	lines.append("\tvar lbl_" + r_id + " := Label.new()")
	lines.append("\tlbl_" + r_id + ".text = tr(\"" + r_token + "\")")
	lines.append("\tlbl_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	if not color_token.is_empty():
		lines.append(
            "\tlbl_" + r_id + ".add_theme_color_override(\"font_color\", RETRO_THEME.get_ink_color(\"" + color_token + "\"))"
        )
	if wrap_enabled:
		lines.append("\tlbl_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
	lines.append("\trow_" + r_id + ".add_child(lbl_" + r_id + ")")
	
	lines.append("\tvar val_" + r_id + " := Label.new()")
	lines.append("\tval_" + r_id + ".name = \"" + r_id + "_value\"")
	lines.append("\tval_" + r_id + ".horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT")
	if not color_token.is_empty():
		lines.append(
            "\tval_" + r_id + ".add_theme_color_override(\"font_color\", RETRO_THEME.get_ink_color(\"" + color_token + "\"))"
        )
	if wrap_enabled:
		lines.append("\tval_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
		lines.append("\tval_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\trow_" + r_id + ".add_child(val_" + r_id + ")")
	
	lines.append("\t_value_labels[\"" + r_id + "\"] = val_" + r_id)
	lines.append("\tadd_child(row_" + r_id + ")\n")

	return lines