# res://tools/ui_compiler/binders/bind_text_metric.gd
@tool
class_name UIBindTextMetric
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "")
	var f_name: String = row.get("field", "")
	var fmt: String = row.get("format", "STRING").to_upper()
	var suffix: String = row.get("suffix", "")

	if f_name.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + r_id + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + r_id + "\"]")
	lines.append("\t\tif not data.has(\"" + f_name + "\") or data[\"" + f_name + "\"] == null:")
	lines.append("\t\t\tctrl.text = tr(\"UI_INTEL_MASKED_BLANK\")")
	lines.append("\t\telse:")

	match fmt:
		"CURRENCY":
			lines.append("\t\t\tvar val_str := \"%.2f\" % float(data[\"" + f_name + "\"])")
			lines.append("\t\t\tctrl.text = tr(\"FMT_CURRENCY\").replace(\"{val}\", val_str) + \"" + suffix + "\"")
		"PERCENT":
			lines.append("\t\t\tvar val_str := String.num(float(data[\"" + f_name + "\"]) * 100.0, 1)")
			lines.append("\t\t\tctrl.text = tr(\"FMT_PERCENT\").replace(\"{val}\", val_str) + \"" + suffix + "\"")
		"INT":
			lines.append("\t\t\tvar val_str := str(int(data[\"" + f_name + "\"]))")
			lines.append("\t\t\tctrl.text = tr(\"FMT_INT\").replace(\"{val}\", val_str) + \"" + suffix + "\"")
		"FLOAT":
			lines.append("\t\t\tvar val_str := String.num(float(data[\"" + f_name + "\"]), 1)")
			lines.append("\t\t\tctrl.text = tr(\"FMT_FLOAT\").replace(\"{val}\", val_str) + \"" + suffix + "\"")
		"DATE":
			lines.append("\t\t\tvar raw_date = data[\"" + f_name + "\"]")
			lines.append("\t\t\tif raw_date is int or raw_date is float:")
			lines.append("\t\t\t\tctrl.text = CalendarHelper.format_day_localized(int(raw_date)) + \"" + suffix + "\"")
			lines.append("\t\t\telse:")
			lines.append("\t\t\t\tctrl.text = str(raw_date) + \"" + suffix + "\"")
		"TOKEN":
			lines.append("\t\t\tctrl.text = tr(str(data[\"" + f_name + "\"])) + \"" + suffix + "\"")
		_:
			lines.append("\t\t\tctrl.text = str(data[\"" + f_name + "\"]) + \"" + suffix + "\"")

	return lines