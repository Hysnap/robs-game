# res://tools/ui_compiler/widgets/emit_linked_list.gd
@tool
class_name UIEmitLinkedList
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = row.get("id", "widget")

	lines.append("\tvar civic_box_" + r_id + " := VBoxContainer.new()")
	lines.append("\tcivic_box_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tcivic_box_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\tcivic_box_" + r_id + ".add_theme_constant_override(\"separation\", 2)")
	lines.append("\t_value_labels[\"" + r_id + "\"] = civic_box_" + r_id)
	lines.append("\tadd_child(civic_box_" + r_id + ")\n")

	return lines