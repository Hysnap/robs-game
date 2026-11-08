# res://tools/ui_compiler/widgets/emit_header_subtitle.gd
@tool
class_name UIEmitHeaderSubtitle
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var wrap_enabled: bool = bool(row.get("autowrap", true))

	lines.append("\t# --- Header Subtitle ---")
	lines.append("\tvar sub_" + r_id + " := Label.new()")
	lines.append("\tsub_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tsub_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\tsub_" + r_id + ".theme_type_variation = &\"HeaderSubtitle\"")
	if wrap_enabled:
		lines.append("\tsub_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
	lines.append("\t_value_labels[\"" + r_id + "\"] = sub_" + r_id)
	lines.append("\tadd_child(sub_" + r_id + ")")
	lines.append("\tadd_child(HSeparator.new())\n")

	return lines