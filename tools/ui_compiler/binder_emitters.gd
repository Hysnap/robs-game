# res://tools/ui_compiler/binder_emitters.gd
@tool
class_name UIBinderEmitters
extends RefCounted

## Emits GDScript lines for value extraction and presentation inside bind_data(data: Dictionary)
static func emit_binding_logic(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "")
	var f_name: String = row.get("field", "")
	var r_type: String = row.get("type", "TEXT_METRIC").to_upper()
	var fmt: String = row.get("format", "STRING").to_upper()
	var suffix: String = row.get("suffix", "")

	if f_name.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + r_id + "\") and data.has(\"" + f_name + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + r_id + "\"]")

	# 1. Specialized Controls
	if r_type == "HEADER_BLOCK":
		lines.append("\tif _value_labels.has(\"" + r_id + "_title\") and data.has(\"" + f_name + "\"):")
		lines.append("\t\t_value_labels[\"" + r_id + "_title\"].text = str(data.get(\"" + f_name + "\", \"--- UNNAMED ---\")).to_upper()")
		if row.has("subtitle_field"):
			var sub_field := str(row.get("subtitle_field"))
			lines.append("\tif _value_labels.has(\"" + r_id + "_subtitle\") and data.has(\"" + sub_field + "\"):")
			lines.append("\t\t_value_labels[\"" + r_id + "_subtitle\"].text = str(data.get(\"" + sub_field + "\", \"\")).to_upper()")
		return lines

	if r_type == "SPIN_INPUT":
		lines.append("\t\tif ctrl is SpinBox:")
		lines.append("\t\t\tctrl.value = float(data[\"" + f_name + "\"])")
		return lines

	if r_type == "ITEM_LIST" or r_type == "LIST":
		lines.append("\t\tif ctrl is ItemList:")
		lines.append("\t\t\tctrl.clear()")
		lines.append("\t\t\tvar items: Array = data.get(\"" + f_name + "\", [])")
		lines.append("\t\t\tfor item in items:")
		lines.append("\t\t\t\tctrl.add_item(str(item))")
		return lines

	if r_type == "CIVIC_SUMMARY":
		lines.append("\t\tif ctrl is Container:")
		lines.append("\t\t\tfor c in ctrl.get_children():")
		lines.append("\t\t\t\tc.queue_free()")
		lines.append("\t\t\tvar clr_m: Color = RETRO_THEME.get_ink_color(\"muted\")")
		lines.append("\t\t\tvar clr_b: Color = RETRO_THEME.get_ink_color(\"body\")")
		lines.append("\t\t\tvar features: Array = data.get(\"" + f_name + "\", [])")
		lines.append("\t\t\tif features.is_empty():")
		lines.append("\t\t\t\tvar empty_lbl := Label.new()")
		lines.append("\t\t\t\tempty_lbl.text = tr(\"UI_INTEL_MASKED_BLANK\")")
		lines.append("\t\t\t\tempty_lbl.add_theme_font_override(\"font\", RETRO_THEME.get_monospace_font())")
		lines.append("\t\t\t\tempty_lbl.add_theme_color_override(\"font_color\", clr_m)")
		lines.append("\t\t\t\tctrl.add_child(empty_lbl)")
		lines.append("\t\t\telse:")
		lines.append("\t\t\t\tfor f in features:")
		lines.append("\t\t\t\t\tvar f_lbl := Label.new()")
		lines.append("\t\t\t\t\tif f is Dictionary:")
		lines.append("\t\t\t\t\t\tvar fn: String = str(f.get(\"name\", \"\"))")
		lines.append("\t\t\t\t\t\tvar fc: String = str(f.get(\"category_title\", f.get(\"category_code\", \"\")))")
		lines.append("\t\t\t\t\t\tif not fc.is_empty():")
		lines.append("\t\t\t\t\t\t\tf_lbl.text = \"• \" + fn + \" (\" + fc + \")\"")
		lines.append("\t\t\t\t\t\telse:")
		lines.append("\t\t\t\t\t\t\tf_lbl.text = \"• \" + fn")
		lines.append("\t\t\t\t\telse:")
		lines.append("\t\t\t\t\t\tf_lbl.text = \"• \" + str(f)")
		lines.append("\t\t\t\t\tf_lbl.add_theme_font_override(\"font\", RETRO_THEME.get_monospace_font())")
		lines.append("\t\t\t\t\tf_lbl.add_theme_color_override(\"font_color\", clr_b)")
		lines.append("\t\t\t\t\tctrl.add_child(f_lbl)")
		return lines

	# 2. Null Guard
	lines.append("\t\tif data[\"" + f_name + "\"] == null:")
	lines.append("\t\t\tctrl.text = tr(\"UI_INTEL_MASKED_BLANK\")")
	lines.append("\t\telse:")

	# 3. Dynamic Formats
	match fmt:
		"CURRENCY":
			lines.append("\t\t\tvar num_str := String.num(float(data[\"" + f_name + "\"]), 2)")
			lines.append("\t\t\tctrl.text = tr(\"FMT_CURRENCY\").replace(\"{val}\", num_str) + \"" + suffix + "\"")
		"PERCENT":
			lines.append("\t\t\tvar pct_str := String.num(float(data[\"" + f_name + "\"]) * 100.0, 1)")
			lines.append("\t\t\tctrl.text = tr(\"FMT_PERCENT\").replace(\"{val}\", pct_str) + \"" + suffix + "\"")
		"INT":
			lines.append("\t\t\tctrl.text = str(int(data[\"" + f_name + "\"])) + \"" + suffix + "\"")
		"FLOAT":
			lines.append("\t\t\tctrl.text = String.num(float(data[\"" + f_name + "\"]), 1) + \"" + suffix + "\"")
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
	