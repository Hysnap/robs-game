# res://tools/ui_compiler/binders/bind_item_list.gd
@tool
class_name UIBindItemList
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "")
	var f_name: String = row.get("field", "")

	if f_name.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + r_id + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + r_id + "\"]")
	lines.append("\t\tif ctrl is ItemList:")
	lines.append("\t\t\tctrl.clear()")
	lines.append("\t\t\tif data.has(\"" + f_name + "\") and data[\"" + f_name + "\"] is Array:")
	lines.append("\t\t\t\tvar items: Array = data[\"" + f_name + "\"]")
	lines.append("\t\t\t\tfor item in items:")
	lines.append("\t\t\t\t\tctrl.add_item(str(item))")

	return lines