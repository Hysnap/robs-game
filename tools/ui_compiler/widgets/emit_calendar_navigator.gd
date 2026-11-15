# res://tools/ui_compiler/widgets/emit_calendar_navigator.gd
@tool
class_name UIEmitCalendarNavigator
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "calendar_nav")
	var sig_name: String = str(row.get("action_signal", "action_clicked")).strip_edges()

	lines.append("\tvar cal_" + r_id + " := CalendarNavigator.new()")
	lines.append("\tcal_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tcal_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	if not sig_name.is_empty():
		lines.append("\tif has_signal(\"" + sig_name + "\"):")
		lines.append("\t\tcal_" + r_id + ".action_clicked.connect(func(code: String, payload: Dictionary): emit_signal(\"" + sig_name + "\", code, payload))")
	lines.append("\t_value_labels[\"" + r_id + "\"] = cal_" + r_id)
	lines.append("\tadd_child(cal_" + r_id + ")\n")

	return lines