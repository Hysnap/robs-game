# res://tools/ui_compiler/widgets/emit_header_block.gd
@tool
class_name UIEmitHeaderBlock
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var wrap_enabled: bool = bool(row.get("autowrap", true))
	var title_color_token: String = str(row.get("title_color", "")).strip_edges()
	var subtitle_color_token: String = str(row.get("subtitle_color", "")).strip_edges()

	lines.append("\t# --- Header Block ---")
	lines.append("\tvar box_" + r_id + " := VBoxContainer.new()")
	lines.append("\tbox_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tbox_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\tbox_" + r_id + ".add_theme_constant_override(\"separation\", 0)")
	
	lines.append("\tvar title_" + r_id + " := Label.new()")
	lines.append("\ttitle_" + r_id + ".name = \"" + r_id + "_title\"")
	lines.append("\ttitle_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\ttitle_" + r_id + ".theme_type_variation = &\"HeaderTitle\"")
	if not title_color_token.is_empty():
		lines.append(
        	"\ttitle_" + r_id + ".add_theme_color_override(\"font_color\", RETRO_THEME.get_ink_color(\"" + title_color_token + "\"))"
    	)
	if wrap_enabled:
		lines.append("\ttitle_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
	lines.append("\tbox_" + r_id + ".add_child(title_" + r_id + ")")
	lines.append("\t_value_labels[\"" + r_id + "_title\"] = title_" + r_id)
	
	if row.has("subtitle_field"):
		lines.append("\tvar sub_" + r_id + " := Label.new()")
		lines.append("\tsub_" + r_id + ".name = \"" + r_id + "_subtitle\"")
		lines.append("\tsub_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\tsub_" + r_id + ".theme_type_variation = &\"HeaderSubtitle\"")
		if not subtitle_color_token.is_empty():
			lines.append(
	        	"\tsub_" + r_id + ".add_theme_color_override(\"font_color\", RETRO_THEME.get_ink_color(\"" + subtitle_color_token + "\"))"
    		)
		if wrap_enabled:
			lines.append("\tsub_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
		lines.append("\tbox_" + r_id + ".add_child(sub_" + r_id + ")")
		lines.append("\t_value_labels[\"" + r_id + "_subtitle\"] = sub_" + r_id)
		
	if bool(row.get("show_separator", true)):
		lines.append("\tbox_" + r_id + ".add_child(HSeparator.new())")
		
	lines.append("\tadd_child(box_" + r_id + ")\n")

	return lines