# res://tools/ui_compiler/binders/bind_header_block.gd
@tool
class_name UIBindHeaderBlock
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "")
	var f_name: String = row.get("field", "")

	if f_name.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + r_id + "_title\"):")
	lines.append("\t\tif data.has(\"" + f_name + "\") and data[\"" + f_name + "\"] != null:")
	lines.append("\t\t\t_value_labels[\"" + r_id + "_title\"].text = str(data[\"" + f_name + "\"]).to_upper()")
	lines.append("\t\telse:")
	lines.append("\t\t\t_value_labels[\"" + r_id + "_title\"].text = \"--- UNNAMED ---\"")

	if row.has("subtitle_field"):
		var sub_field := str(row.get("subtitle_field"))
		lines.append("\tif _value_labels.has(\"" + r_id + "_subtitle\"):")
		lines.append("\t\tif data.has(\"" + sub_field + "\") and data[\"" + sub_field + "\"] != null:")
		lines.append("\t\t\t_value_labels[\"" + r_id + "_subtitle\"].text = str(data[\"" + sub_field + "\"]).to_upper()")
		lines.append("\t\telse:")
		lines.append("\t\t\t_value_labels[\"" + r_id + "_subtitle\"].text = \"\"")

	return lines