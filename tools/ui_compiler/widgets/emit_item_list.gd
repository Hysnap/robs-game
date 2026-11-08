# res://tools/ui_compiler/widgets/emit_item_list.gd
@tool
class_name UIEmitItemList
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var is_reorderable: bool = bool(row.get("reorderable", false))
	var min_h: int = int(row.get("min_height", 120))

	if is_reorderable:
		lines.append("\tvar box_" + r_id + " := VBoxContainer.new()")
		lines.append("\tbox_" + r_id + ".name = \"" + r_id + "\"")
		lines.append("\tbox_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\tbox_" + r_id + ".add_theme_constant_override(\"separation\", 4)")
		
		lines.append("\tvar list_" + r_id + " := ItemList.new()")
		lines.append("\tlist_" + r_id + ".name = \"" + r_id + "_list\"")
		lines.append("\tlist_" + r_id + ".custom_minimum_size = Vector2(0, " + str(min_h) + ")")
		lines.append("\tlist_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\tbox_" + r_id + ".add_child(list_" + r_id + ")")
		lines.append("\t_value_labels[\"" + r_id + "\"] = list_" + r_id)

		lines.append("\tvar bar_" + r_id + " := HBoxContainer.new()")
		lines.append("\tbar_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\tbar_" + r_id + ".add_theme_constant_override(\"separation\", 6)")

		# Button ▲ (Move Up)
		lines.append("\tvar btn_up_" + r_id + " := Button.new()")
		lines.append("\tbtn_up_" + r_id + ".text = \"▲\"")
		lines.append("\tbtn_up_" + r_id + ".focus_mode = Control.FOCUS_NONE")
		lines.append("\tbtn_up_" + r_id + ".pressed.connect(func():")
		lines.append("\t\tvar sel = list_" + r_id + ".get_selected_items()")
		lines.append("\t\tif sel.size() > 0 and \"_queue\" in self:")
		lines.append("\t\t\tvar n_idx = self._queue.move_directive(sel[0], -1)")
		lines.append("\t\t\tif n_idx >= 0: list_" + r_id + ".select(n_idx)")
		lines.append("\t)")
		lines.append("\tbar_" + r_id + ".add_child(btn_up_" + r_id + ")")

		# Button ▼ (Move Down)
		lines.append("\tvar btn_dn_" + r_id + " := Button.new()")
		lines.append("\tbtn_dn_" + r_id + ".text = \"▼\"")
		lines.append("\tbtn_dn_" + r_id + ".focus_mode = Control.FOCUS_NONE")
		lines.append("\tbtn_dn_" + r_id + ".pressed.connect(func():")
		lines.append("\t\tvar sel = list_" + r_id + ".get_selected_items()")
		lines.append("\t\tif sel.size() > 0 and \"_queue\" in self:")
		lines.append("\t\t\tvar n_idx = self._queue.move_directive(sel[0], 1)")
		lines.append("\t\t\tif n_idx >= 0: list_" + r_id + ".select(n_idx)")
		lines.append("\t)")
		lines.append("\tbar_" + r_id + ".add_child(btn_dn_" + r_id + ")")

		# Button ✖ (Remove Order)
		lines.append("\tvar btn_rm_" + r_id + " := Button.new()")
		lines.append("\tbtn_rm_" + r_id + ".text = \"✖\"")
		lines.append("\tbtn_rm_" + r_id + ".focus_mode = Control.FOCUS_NONE")
		lines.append("\tbtn_rm_" + r_id + ".pressed.connect(func():")
		lines.append("\t\tvar sel = list_" + r_id + ".get_selected_items()")
		lines.append("\t\tif sel.size() > 0 and \"_queue\" in self:")
		lines.append("\t\t\tvar n_idx = self._queue.remove_directive(sel[0])")
		lines.append("\t\t\tif n_idx >= 0: list_" + r_id + ".select(n_idx)")
		lines.append("\t)")
		lines.append("\tbar_" + r_id + ".add_child(btn_rm_" + r_id + ")")

		# Button ✓ (Toggle Select)
		lines.append("\tvar btn_tg_" + r_id + " := Button.new()")
		lines.append("\tbtn_tg_" + r_id + ".text = \"✓\"")
		lines.append("\tbtn_tg_" + r_id + ".focus_mode = Control.FOCUS_NONE")
		lines.append("\tbtn_tg_" + r_id + ".pressed.connect(func():")
		lines.append("\t\tvar sel = list_" + r_id + ".get_selected_items()")
		lines.append("\t\tif sel.size() > 0 and \"_queue\" in self:")
		lines.append("\t\t\tself._queue.toggle_selection(sel[0])")
		lines.append("\t\t\tlist_" + r_id + ".select(sel[0])")
		lines.append("\t)")
		lines.append("\tbar_" + r_id + ".add_child(btn_tg_" + r_id + ")")

		lines.append("\tbox_" + r_id + ".add_child(bar_" + r_id + ")")
		lines.append("\tadd_child(box_" + r_id + ")\n")
	else:
		lines.append("\tvar list_" + r_id + " := ItemList.new()")
		lines.append("\tlist_" + r_id + ".name = \"" + r_id + "\"")
		lines.append("\tlist_" + r_id + ".custom_minimum_size = Vector2(0, " + str(min_h) + ")")
		lines.append("\tlist_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\t_value_labels[\"" + r_id + "\"] = list_" + r_id)
		lines.append("\tadd_child(list_" + r_id + ")\n")

	return lines