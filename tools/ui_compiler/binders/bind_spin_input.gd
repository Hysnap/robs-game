# res://tools/ui_compiler/binders/bind_spin_input.gd
@tool
class_name UIBindSpinInput
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "")
	var f_name: String = row.get("field", "")

	if f_name.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + r_id + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + r_id + "\"]")
	lines.append("\t\tif ctrl is SpinBox:")
	lines.append("\t\t\tif data.has(\"" + f_name + "\") and data[\"" + f_name + "\"] != null:")
	lines.append("\t\t\t\tctrl.value = float(data[\"" + f_name + "\"])")
	lines.append("\t\t\telse:")
	lines.append("\t\t\t\tctrl.value = " + str(row.get("default_value", 0)))

	return lines