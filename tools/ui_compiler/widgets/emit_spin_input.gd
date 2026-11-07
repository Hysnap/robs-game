# res://tools/ui_compiler/widgets/emit_spin_input.gd
@tool
class_name UIEmitSpinInput
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
	
	lines.append("\tvar spin_" + r_id + " := SpinBox.new()")
	lines.append("\tspin_" + r_id + ".name = \"" + r_id + "_spin\"")
	lines.append("\tspin_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\tspin_" + r_id + ".min_value = " + str(row.get("min", 1)))
	lines.append("\tspin_" + r_id + ".max_value = " + str(row.get("max", 100)))
	lines.append("\tspin_" + r_id + ".step = " + str(row.get("step", 1)))
	lines.append("\tspin_" + r_id + ".value = " + str(row.get("default_value", 10)))
	lines.append("\trow_" + r_id + ".add_child(spin_" + r_id + ")")
	
	lines.append("\t_value_labels[\"" + r_id + "\"] = spin_" + r_id)
	lines.append("\tadd_child(row_" + r_id + ")\n")

	return lines