# res://tools/ui_compiler/binders/bind_linked_list.gd
@tool
class_name UIBindLinkedList
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var f_name: String = row.get("field", "")
	var target_route: String = row.get("target_route", "ESTABLISHMENT_DETAIL")
	var route_field: String = str(row.get("route_field", "")).strip_edges()
	var key_field: String = row.get("key_field", "establishment_id")
	var label_field: String = row.get("label_field", "name")
	var sublabel_field: String = row.get("sublabel_field", "category_title")
	var action_signal: String = row.get("action_signal", "item_selected")

	if f_name.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + row.get("id", "") + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + row.get("id", "") + "\"]")
	lines.append("\t\tif ctrl is Container:")
	lines.append("\t\t\tfor c in ctrl.get_children():")
	lines.append("\t\t\t\tc.free()")
	lines.append("\t\t\tvar clr_m: Color = RETRO_THEME.get_ink_color(\"muted\")")
	lines.append("\t\t\tvar clr_b: Color = RETRO_THEME.get_ink_color(\"body\")")
	lines.append("\t\t\tvar mono_f: Font = RETRO_THEME.get_monospace_font()")
	lines.append("\t\t\tvar items: Array = data.get(\"" + f_name + "\", [])")
	lines.append("\t\t\tif items.is_empty():")
	lines.append("\t\t\t\tpass")
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