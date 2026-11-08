# res://tools/ui_compiler/widgets/emit_option_dropdown.gd
@tool
class_name UIEmitOptionDropdown
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")
	var r_token: String = row.get("token", "")
	var wrap_enabled: bool = bool(row.get("autowrap", true))

	lines.append("\tvar row_" + r_id + " := HBoxContainer.new()")
	lines.append("\trow_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\trow_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	
	lines.append("\tvar lbl_" + r_id + " := Label.new()")
	lines.append("\tlbl_" + r_id + ".text = tr(\"" + r_token + "\")")
	lines.append("\tlbl_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	if wrap_enabled:
		lines.append("\tlbl_" + r_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
	lines.append("\trow_" + r_id + ".add_child(lbl_" + r_id + ")")
	
	lines.append("\tvar opt_" + r_id + " := OptionButton.new()")
	lines.append("\topt_" + r_id + ".name = \"" + r_id + "_opt\"")
	lines.append("\topt_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	
	var opts: Array = row.get("options", [])
	for opt_item in opts:
		lines.append("\topt_" + r_id + ".add_item(\"" + str(opt_item) + "\")")
		
	lines.append("\trow_" + r_id + ".add_child(opt_" + r_id + ")")
	lines.append("\t_value_labels[\"" + r_id + "\"] = opt_" + r_id)
	lines.append("\tadd_child(row_" + r_id + ")\n")

	return lines