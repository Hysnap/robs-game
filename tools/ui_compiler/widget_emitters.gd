# res://tools/ui_compiler/widget_emitters.gd
@tool
class_name UIWidgetEmitters
extends RefCounted

## Emits GDScript lines for instantiating and mounting UI widgets inside build_ui()
static func emit_widget_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var r_type: String = row.get("type", "TEXT_METRIC").to_upper()
	var r_token: String = row.get("token", "")
	var wrap_enabled: bool = bool(row.get("autowrap", true))

	match r_type:
		"HEADER_BLOCK":
			var title_sz: int = int(row.get("title_font_size", 18))
			var sub_sz: int = int(row.get("subtitle_font_size", 12))
			lines.append("\t# --- Header Block ---")
			lines.append("\tvar box_" + r_id + " := VBoxContainer.new()")
			lines.append("\tbox_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tbox_" + r_id + ".add_theme_constant_override(\"separation\", 0)")
			lines.append("\tvar title_" + r_id + " := Label.new()")
			lines.append("\ttitle_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			if wrap_enabled:
				lines.append("\ttitle_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
			lines.append("\ttitle_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\ttitle_" + r_id + ".add_theme_font_size_override(\"font_size\", " + str(title_sz) + ")")
			lines.append("\ttitle_" + r_id + ".add_theme_color_override(\"font_color\", clr_blue)")
			lines.append("\tbox_" + r_id + ".add_child(title_" + r_id + ")")
			lines.append("\t_value_labels[\"" + r_id + "_title\"] = title_" + r_id)
			
			if row.has("subtitle_field"):
				lines.append("\tvar sub_" + r_id + " := Label.new()")
				lines.append("\tsub_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
				if wrap_enabled:
					lines.append("\tsub_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
				lines.append("\tsub_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\tsub_" + r_id + ".add_theme_font_size_override(\"font_size\", " + str(sub_sz) + ")")
				lines.append("\tsub_" + r_id + ".add_theme_color_override(\"font_color\", clr_muted)")
				lines.append("\tbox_" + r_id + ".add_child(sub_" + r_id + ")")
				lines.append("\t_value_labels[\"" + r_id + "_subtitle\"] = sub_" + r_id)
				
			if bool(row.get("show_separator", true)):
				lines.append("\tbox_" + r_id + ".add_child(HSeparator.new())")
			lines.append("\tadd_child(box_" + r_id + ")\n")

		"BADGE_STATUS":
			lines.append("\tvar badge_" + r_id + " := PanelContainer.new()")
			lines.append("\tbadge_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tvar val_" + r_id + " := Label.new()")
			lines.append("\tval_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tval_" + r_id + ".horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER")
			if wrap_enabled:
				lines.append("\tval_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
			lines.append("\tval_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tval_" + r_id + ".add_theme_color_override(\"font_color\", clr_blue)")
			lines.append("\tbadge_" + r_id + ".add_child(val_" + r_id + ")")
			lines.append("\t_value_labels[\"" + r_id + "\"] = val_" + r_id)
			lines.append("\tadd_child(badge_" + r_id + ")\n")

		"CIVIC_SUMMARY", "LINKED_LIST":
			lines.append("\tvar civic_box_" + r_id + " := VBoxContainer.new()")
			lines.append("\tcivic_box_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tcivic_box_" + r_id + ".add_theme_constant_override(\"separation\", 2)")
			lines.append("\t_value_labels[\"" + r_id + "\"] = civic_box_" + r_id)
			lines.append("\tadd_child(civic_box_" + r_id + ")\n")

		"BUTTON":
			lines.append("\tvar btn_" + r_id + " := Button.new()")
			lines.append("\tbtn_" + r_id + ".text = tr(\"" + r_token + "\")")
			lines.append("\tbtn_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tbtn_" + r_id + ".alignment = HORIZONTAL_ALIGNMENT_LEFT")
			if wrap_enabled:
				lines.append("\tbtn_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
			lines.append("\tbtn_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			var action_signal: String = row.get("action_signal", "action_clicked")
			var emit_args: String = str(row.get("emit_args", ""))
			if not emit_args.is_empty():
				lines.append("\tbtn_" + r_id + ".pressed.connect(func(): " + action_signal + ".emit(" + emit_args + "))")
			else:
				lines.append("\tbtn_" + r_id + ".pressed.connect(func(): " + action_signal + ".emit())")
			lines.append("\t_value_labels[\"" + r_id + "\"] = btn_" + r_id)
			lines.append("\tadd_child(btn_" + r_id + ")\n")

		"ITEM_LIST", "LIST":
			var is_reorderable: bool = bool(row.get("reorderable", false))
			var min_h: int = int(row.get("min_height", 120))

			if is_reorderable:
				lines.append("\tvar box_" + r_id + " := VBoxContainer.new()")
				lines.append("\tbox_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
				lines.append("\tbox_" + r_id + ".add_theme_constant_override(\"separation\", 4)")
				lines.append("\tvar list_" + r_id + " := ItemList.new()")
				lines.append("\tlist_" + r_id + ".custom_minimum_size = Vector2(0, " + str(min_h) + ")")
				lines.append("\tlist_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
				lines.append("\tlist_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\tbox_" + r_id + ".add_child(list_" + r_id + ")")
				lines.append("\t_value_labels[\"" + r_id + "\"] = list_" + r_id)

				lines.append("\tvar bar_" + r_id + " := HBoxContainer.new()")
				lines.append("\tbar_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
				lines.append("\tbar_" + r_id + ".add_theme_constant_override(\"separation\", 6)")

				# Button ▲ (Move Up)
				lines.append("\tvar btn_up_" + r_id + " := Button.new()")
				lines.append("\tbtn_up_" + r_id + ".text = \"▲\"")
				lines.append("\tbtn_up_" + r_id + ".focus_mode = Control.FOCUS_NONE")
				lines.append("\tbtn_up_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\tbtn_up_" + r_id + ".pressed.connect(func(): action_clicked.emit(\"MOVE_UP\"))")
				lines.append("\tbar_" + r_id + ".add_child(btn_up_" + r_id + ")")

				# Button ▼ (Move Down)
				lines.append("\tvar btn_dn_" + r_id + " := Button.new()")
				lines.append("\tbtn_dn_" + r_id + ".text = \"▼\"")
				lines.append("\tbtn_dn_" + r_id + ".focus_mode = Control.FOCUS_NONE")
				lines.append("\tbtn_dn_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\tbtn_dn_" + r_id + ".pressed.connect(func(): action_clicked.emit(\"MOVE_DOWN\"))")
				lines.append("\tbar_" + r_id + ".add_child(btn_dn_" + r_id + ")")

				# Button ✖ (Remove Order)
				lines.append("\tvar btn_rm_" + r_id + " := Button.new()")
				lines.append("\tbtn_rm_" + r_id + ".text = \"✖\"")
				lines.append("\tbtn_rm_" + r_id + ".focus_mode = Control.FOCUS_NONE")
				lines.append("\tbtn_rm_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\tbtn_rm_" + r_id + ".pressed.connect(func(): action_clicked.emit(\"REMOVE_ORDER\"))")
				lines.append("\tbar_" + r_id + ".add_child(btn_rm_" + r_id + ")")

				# Button ✓ (Toggle Select)
				lines.append("\tvar btn_tg_" + r_id + " := Button.new()")
				lines.append("\tbtn_tg_" + r_id + ".text = \"✓\"")
				lines.append("\tbtn_tg_" + r_id + ".focus_mode = Control.FOCUS_NONE")
				lines.append("\tbtn_tg_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\tbtn_tg_" + r_id + ".pressed.connect(func(): action_clicked.emit(\"TOGGLE_SELECT\"))")
				lines.append("\tbar_" + r_id + ".add_child(btn_tg_" + r_id + ")")

				lines.append("\tbox_" + r_id + ".add_child(bar_" + r_id + ")")
				lines.append("\tadd_child(box_" + r_id + ")\n")
			else:
				lines.append("\tvar list_" + r_id + " := ItemList.new()")
				lines.append("\tlist_" + r_id + ".custom_minimum_size = Vector2(0, " + str(min_h) + ")")
				lines.append("\tlist_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
				lines.append("\tlist_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\t_value_labels[\"" + r_id + "\"] = list_" + r_id)
				lines.append("\tadd_child(list_" + r_id + ")\n")

		"OPTION_DROPDOWN", "DROPDOWN":
			lines.append("\tvar row_" + r_id + " := HBoxContainer.new()")
			lines.append("\trow_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tvar lbl_" + r_id + " := Label.new()")
			lines.append("\tlbl_" + r_id + ".text = tr(\"" + r_token + "\")")
			lines.append("\tlbl_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			if wrap_enabled:
				lines.append("\tlbl_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
			lines.append("\tlbl_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tlbl_" + r_id + ".add_theme_color_override(\"font_color\", clr_muted)")
			lines.append("\trow_" + r_id + ".add_child(lbl_" + r_id + ")")
			lines.append("\tvar opt_" + r_id + " := OptionButton.new()")
			lines.append("\topt_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\topt_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			var opts: Array = row.get("options", [])
			for opt_item in opts:
				lines.append("\topt_" + r_id + ".add_item(\"" + str(opt_item) + "\")")
			lines.append("\trow_" + r_id + ".add_child(opt_" + r_id + ")")
			lines.append("\t_value_labels[\"" + r_id + "\"] = opt_" + r_id)
			lines.append("\tadd_child(row_" + r_id + ")\n")

		"SPIN_INPUT":
			lines.append("\tvar row_" + r_id + " := HBoxContainer.new()")
			lines.append("\trow_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tvar lbl_" + r_id + " := Label.new()")
			lines.append("\tlbl_" + r_id + ".text = tr(\"" + r_token + "\")")
			lines.append("\tlbl_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			if wrap_enabled:
				lines.append("\tlbl_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
			lines.append("\tlbl_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tlbl_" + r_id + ".add_theme_color_override(\"font_color\", clr_muted)")
			lines.append("\trow_" + r_id + ".add_child(lbl_" + r_id + ")")
			lines.append("\tvar spin_" + r_id + " := SpinBox.new()")
			lines.append("\tspin_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tspin_" + r_id + ".min_value = " + str(row.get("min", 1)))
			lines.append("\tspin_" + r_id + ".max_value = " + str(row.get("max", 100)))
			lines.append("\tspin_" + r_id + ".step = " + str(row.get("step", 1)))
			lines.append("\tspin_" + r_id + ".value = " + str(row.get("default_value", 10)))
			lines.append("\trow_" + r_id + ".add_child(spin_" + r_id + ")")
			lines.append("\t_value_labels[\"" + r_id + "\"] = spin_" + r_id)
			lines.append("\tadd_child(row_" + r_id + ")\n")

		_: # Default: TEXT_METRIC
			lines.append("\tvar row_" + r_id + " := HBoxContainer.new()")
			lines.append("\trow_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tvar lbl_" + r_id + " := Label.new()")
			lines.append("\tlbl_" + r_id + ".text = tr(\"" + r_token + "\")")
			lines.append("\tlbl_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			if wrap_enabled:
				lines.append("\tlbl_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
			lines.append("\tlbl_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tlbl_" + r_id + ".add_theme_color_override(\"font_color\", clr_muted)")
			lines.append("\trow_" + r_id + ".add_child(lbl_" + r_id + ")")
			lines.append("\tvar val_" + r_id + " := Label.new()")
			lines.append("\tval_" + r_id + ".horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT")
			if wrap_enabled:
				lines.append("\tval_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
				lines.append("\tval_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tval_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tval_" + r_id + ".add_theme_color_override(\"font_color\", clr_black)")
			lines.append("\trow_" + r_id + ".add_child(val_" + r_id + ")")
			lines.append("\t_value_labels[\"" + r_id + "\"] = val_" + r_id)
			lines.append("\tadd_child(row_" + r_id + ")\n")

	return lines