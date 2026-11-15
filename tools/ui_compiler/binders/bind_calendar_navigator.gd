# res://tools/ui_compiler/binders/bind_calendar_navigator.gd
@tool
class_name UIBindCalendarNavigator
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var r_id: String = row.get("id", "calendar_nav")
	var field_name: String = str(row.get("field", "calendar_payload")).strip_edges()

	return [
		"\tif _value_labels.has(\"" + r_id + "\") and data.has(\"" + field_name + "\"):",
		"\t\tvar cal_widget = _value_labels[\"" + r_id + "\"]",
		"\t\tif cal_widget is CalendarNavigator and data[\"" + field_name + "\"] is Dictionary:",
		"\t\t\tcal_widget.bind_calendar(data[\"" + field_name + "\"])"
	]