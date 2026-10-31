@tool
class_name UIWidgetEmitters
extends RefCounted

## Emits GDScript lines for instantiating and mounting UI widgets inside build_ui()
static func emit_widget_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var r_type: String = row.get("type", "TEXT_METRIC").to_upper()
	var r_token: String = row.get("token", "")

	match r_type:
		"HEADER_BLOCK":
			var title_sz: int = int(row.get("title_font_size", 18))
			var sub_sz: int = int(row.get("subtitle_font_size", 12))
			lines.append("\t# --- Header Block ---")
			lines.append("\tvar box_%s := VBoxContainer.new()" % r_id)
			lines.append("\tbox_%s.add_theme_constant_override(\"separation\", 0)" % r_id)
			lines.append("\tvar title_%s := Label.new()" % r_id)
			lines.append("\ttitle_%s.add_theme_font_override(\"font\", mono_font)" % r_id)
			lines.append("\ttitle_%s.add_theme_font_size_override(\"font_size\", %d)" % [title_sz])
			lines.append("\ttitle_%s.add_theme_color_override(\"font_color\", clr_blue)" % r_id)
			lines.append("\tbox_%s.add_child(title_%s)" % [r_id, r_id])
			lines.append("\t_value_labels[\"%s_title\"] = title_%s" % [r_id, r_id])
			
			if row.has("subtitle_field"):
				lines.append("\tvar sub_%s := Label.new()" % r_id)
				lines.append("\tsub_%s.add_theme_font_override(\"font\", mono_font)" % r_id)
				lines.append("\tsub_%s.add_theme_font_size_override(\"font_size\", %d)" % [sub_sz])
				lines.append("\tsub_%s.add_theme_color_override(\"font_color\", clr_muted)" % r_id)
				lines.append("\tbox_%s.add_child(sub_%s)" % [r_id, r_id])
				lines.append("\t_value_labels[\"%s_subtitle\"] = sub_%s" % [r_id, r_id])
				
			if bool(row.get("show_separator", true)):
				lines.append("\tbox_%s.add_child(HSeparator.new())" % r_id)
			lines.append("\tadd_child(box_%s)\n" % r_id)

		"BADGE_STATUS":
			lines.append("\tvar badge_%s := PanelContainer.new()" % r_id)
			lines.append("\tbadge_%s.size_flags_horizontal = Control.SIZE_EXPAND_FILL" % r_id)
			lines.append("\tvar val_%s := Label.new()" % r_id)
			lines.append("\tval_%s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER" % r_id)
			lines.append("\tval_%s.add_theme_font_override(\"font\", mono_font)" % r_id)
			lines.append("\tval_%s.add_theme_color_override(\"font_color\", clr_blue)" % r_id)
			lines.append("\tbadge_%s.add_child(val_%s)" % [r_id, r_id])
			lines.append("\t_value_labels[\"%s\"] = val_%s" % [r_id, r_id])
			lines.append("\tadd_child(badge_%s)\n" % r_id)

		"CIVIC_SUMMARY":
			lines.append("\tvar civic_box_%s := VBoxContainer.new()" % r_id)
			lines.append("\tcivic_box_%s.size_flags_horizontal = Control.SIZE_EXPAND_FILL" % r_id)
			lines.append("\tcivic_box_%s.add_theme_constant_override(\"separation\", 2)" % r_id)
			lines.append("\t_value_labels[\"%s\"] = civic_box_%s" % [r_id, r_id])
			lines.append("\tadd_child(civic_box_%s)\n" % r_id)

		"BUTTON":
			lines.append("\tvar btn_" + r_id + " := Button.new()")
			lines.append("\tbtn_" + r_id + ".text = tr(\"" + r_token + "\")")
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
			lines.append("\tvar list_" + r_id + " := ItemList.new()")
			var min_h: int = int(row.get("min_height", 120))
			lines.append("\tlist_" + r_id + ".custom_minimum_size = Vector2(0, " + str(min_h) + ")")
			lines.append("\tlist_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\t_value_labels[\"" + r_id + "\"] = list_" + r_id)
			lines.append("\tadd_child(list_" + r_id + ")\n")

		"OPTION_DROPDOWN", "DROPDOWN":
			lines.append("\tvar row_" + r_id + " := HBoxContainer.new()")
			lines.append("\tvar lbl_" + r_id + " := Label.new()")
			lines.append("\tlbl_" + r_id + ".text = tr(\"" + r_token + "\")")
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
			lines.append("\tvar lbl_" + r_id + " := Label.new()")
			lines.append("\tlbl_" + r_id + ".text = tr(\"" + r_token + "\")")
			lines.append("\tlbl_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tlbl_%s.add_theme_color_override(\"font_color\", clr_muted)" % r_id)
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
			lines.append("\tlbl_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tlbl_" + r_id + ".add_theme_color_override(\"font_color\", clr_muted)")
			lines.append("\trow_" + r_id + ".add_child(lbl_" + r_id + ")")
			lines.append("\tvar val_" + r_id + " := Label.new()")
			lines.append("\tval_" + r_id + ".horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT")
			lines.append("\tval_" + r_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\tval_" + r_id + ".add_theme_color_override(\"font_color\", clr_black)")
			lines.append("\trow_" + r_id + ".add_child(val_" + r_id + ")")
			lines.append("\t_value_labels[\"" + r_id + "\"] = val_" + r_id)
			lines.append("\tadd_child(row_" + r_id + ")\n")

	return lines