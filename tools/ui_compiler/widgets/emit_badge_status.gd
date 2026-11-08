# res://tools/ui_compiler/widgets/emit_badge_status.gd
@tool
class_name UIEmitBadgeStatus
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var wrap_enabled: bool = bool(row.get("autowrap", true))
	var color_token: String = str(row.get("color", "")).strip_edges()

	lines.append("\tvar badge_" + r_id + " := PanelContainer.new()")
	lines.append("\tbadge_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tbadge_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	
	lines.append("\tvar val_" + r_id + " := Label.new()")
	lines.append("\tval_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\tval_" + r_id + ".horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER")
	lines.append("\tval_" + r_id + ".theme_type_variation = &\"BadgeStatus\"")
	if not color_token.is_empty():
		lines.append(
            "\tval_" + r_id + ".add_theme_color_override(\"font_color\", RETRO_THEME.get_ink_color(\"" + color_token + "\"))"
        )
	if wrap_enabled:
		lines.append("\tval_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
		
	lines.append("\tbadge_" + r_id + ".add_child(val_" + r_id + ")")
	lines.append("\t_value_labels[\"" + r_id + "\"] = val_" + r_id)
	lines.append("\tadd_child(badge_" + r_id + ")\n")

	return lines