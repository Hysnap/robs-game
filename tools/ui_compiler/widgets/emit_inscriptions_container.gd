# res://tools/ui_compiler/widgets/emit_inscriptions.gd
@tool
class_name UIEmitInscriptions
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "inscriptions")

	lines.append("\t# --- Inscriptions Container ---")
	lines.append("\tvar insc_box_" + r_id + " := VBoxContainer.new()")
	lines.append("\tinsc_box_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tinsc_box_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\t_value_labels[\"__inscriptions__\"] = insc_box_" + r_id)
	lines.append("\tadd_child(insc_box_" + r_id + ")\n")

	return lines