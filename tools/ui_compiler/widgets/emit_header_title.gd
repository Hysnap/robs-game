# res://tools/ui_compiler/widgets/emit_header_title.gd
@tool
class_name UIEmitHeaderTitle
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var wrap_enabled: bool = bool(row.get("autowrap", true))

	lines.append("\t# --- Header Title ---")
	lines.append("\tvar title_" + r_id + " := Label.new()")
	lines.append("\ttitle_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\ttitle_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\ttitle_" + r_id + ".theme_type_variation = &\"HeaderTitle\"")
	if wrap_enabled:
		lines.append("\ttitle_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
	lines.append("\t_value_labels[\"" + r_id + "\"] = title_" + r_id)
	lines.append("\tadd_child(title_" + r_id + ")\n")

	return lines