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

	# 1. Specialized Control: HEADER_BLOCK
	if r_type == "HEADER_BLOCK":
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

	lines.append("\tif _value_labels.has(\"" + r_id + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + r_id + "\"]")

	# 2. Specialized Control: SPIN_INPUT
	if r_type == "SPIN_INPUT":
		lines.append("\t\tif ctrl is SpinBox:")
		lines.append("\t\t\tif data.has(\"" + f_name + "\") and data[\"" + f_name + "\"] != null:")
		lines.append("\t\t\t\tctrl.value = float(data[\"" + f_name + "\"])")
		lines.append("\t\t\telse:")
		lines.append("\t\t\t\tctrl.value = " + str(row.get("default_value", 0)))
		return lines

	# 3. Specialized Control: ITEM_LIST / LIST
	if r_type == "ITEM_LIST" or r_type == "LIST":
		lines.append("\t\tif ctrl is ItemList:")
		lines.append("\t\t\tctrl.clear()")
		lines.append("\t\t\tif data.has(\"" + f_name + "\") and data[\"" + f_name + "\"] is Array:")
		lines.append("\t\t\t\tvar items: Array = data[\"" + f_name + "\"]")
		lines.append("\t\t\t\tfor item in items:")
		lines.append("\t\t\t\t\tctrl.add_item(str(item))")
		return lines

	# 4. Specialized Control: LINKED_LIST / CIVIC_SUMMARY
	if r_type == "LINKED_LIST" or r_type == "CIVIC_SUMMARY":
		var target_route: String = row.get("target_route", "ESTABLISHMENT_DETAIL")
		var route_field: String = str(row.get("route_field", "")).strip_edges()
		var key_field: String = row.get("key_field", "establishment_id")
		var label_field: String = row.get("label_field", "name")
		var sublabel_field: String = row.get("sublabel_field", "category_title")
		var action_signal: String = row.get("action_signal", "item_selected")

		lines.append("\t\tif ctrl is Container:")
		lines.append("\t\t\tfor c in ctrl.get_children():")
		lines.append("\t\t\t\tc.queue_free()")
		lines.append("\t\t\tvar clr_m: Color = RETRO_THEME.get_ink_color(\"muted\")")
		lines.append("\t\t\tvar clr_b: Color = RETRO_THEME.get_ink_color(\"body\")")
		lines.append("\t\t\tvar mono_f: Font = RETRO_THEME.get_monospace_font()")
		lines.append("\t\t\tvar items: Array = data.get(\"" + f_name + "\", [])")
		lines.append("\t\t\tif items.is_empty():")
		lines.append("\t\t\t\tvar empty_lbl := Label.new()")
		lines.append("\t\t\t\tempty_lbl.text = tr(\"UI_INTEL_MASKED_BLANK\")")
		lines.append("\t\t\t\tempty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\t\t\t\tempty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
		lines.append("\t\t\t\tempty_lbl.add_theme_font_override(\"font\", mono_f)")
		lines.append("\t\t\t\tempty_lbl.add_theme_color_override(\"font_color\", clr_m)")
		lines.append("\t\t\t\tctrl.add_child(empty_lbl)")
		lines.append("\t\t\telse:")
		lines.append("\t\t\t\tfor item in items:")
		lines.append("\t\t\t\t\tassert(item is Dictionary, \"[UI CONTRACT ERROR] Expected Dictionary in list payload for: " + f_name + "\")")
		lines.append("\t\t\t\t\tassert(item.has(\"" + key_field + "\"), \"[UI CONTRACT ERROR] Missing required key '" + key_field + "' in item: \" + str(item))")
		lines.append("\t\t\t\t\tvar key_val = item[\"" + key_field + "\"]")
		lines.append("\t\t\t\t\tvar main_txt: String = str(item.get(\"" + label_field + "\", \"Unnamed\"))")
		lines.append("\t\t\t\t\tvar sub_txt: String = str(item.get(\"" + sublabel_field + "\", \"\"))")
		lines.append("\t\t\t\t\tvar display_txt: String = \"• \" + main_txt")
		lines.append("\t\t\t\t\tif not sub_txt.is_empty():")
		lines.append("\t\t\t\t\t\tdisplay_txt += \" (\" + sub_txt + \")\"")
		lines.append("\t\t\t\t\tvar btn := Button.new()")
		lines.append("\t\t\t\t\tbtn.text = display_txt")
		lines.append("\t\t\t\t\tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\t\t\t\t\tbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT")
		lines.append("\t\t\t\t\tbtn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
		lines.append("\t\t\t\t\tbtn.add_theme_font_override(\"font\", mono_f)")
		lines.append("\t\t\t\t\tbtn.add_theme_font_size_override(\"font_size\", 11)")
		lines.append("\t\t\t\t\tbtn.add_theme_color_override(\"font_color\", clr_b)")
		if not route_field.is_empty():
			lines.append("\t\t\t\t\tvar dest_route: String = str(item.get(\"" + route_field + "\", \"" + target_route + "\"))")
			lines.append("\t\t\t\t\tif dest_route.is_empty():")
			lines.append("\t\t\t\t\t\tdest_route = \"" + target_route + "\"")
			lines.append("\t\t\t\t\tbtn.pressed.connect(func(): " + action_signal + ".emit(dest_route, key_val))")
		else:
			lines.append("\t\t\t\t\tbtn.pressed.connect(func(): " + action_signal + ".emit(\"" + target_route + "\", key_val))")
		lines.append("\t\t\t\t\tctrl.add_child(btn)")
		return lines

	# 5. Null or Missing Guard for Standard Metric Controls (Snapshot Reset)
	lines.append("\t\tif not data.has(\"" + f_name + "\") or data[\"" + f_name + "\"] == null:")
	lines.append("\t\t\tctrl.text = tr(\"UI_INTEL_MASKED_BLANK\")")
	lines.append("\t\telse:")

	# 6. Dynamic Locale & Era-Driven Formats (delegated to ui_strings.csv)
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