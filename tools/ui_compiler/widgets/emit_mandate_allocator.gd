# res://tools/ui_compiler/widgets/emit_mandate_allocator.gd
@tool
class_name UIEmitMandateAllocator
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = str(row.get("id", "mandate_allocator")).strip_edges()
	var action_sig: String = str(row.get("action_signal", "action_clicked")).strip_edges()

	lines.append("\tvar alloc_script_" + r_id + " := preload(\"res://scenes/ui/components/mandate_allocator_panel.gd\")")
	lines.append("\tvar alloc_" + r_id + " := alloc_script_" + r_id + ".new()")
	lines.append("\talloc_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\talloc_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	if not action_sig.is_empty():
		lines.append("\tif has_signal(\"" + action_sig + "\"):")
		lines.append("\t\talloc_" + r_id + ".action_clicked.connect(func(code: String, payload: Dictionary) -> void: emit_signal(\"" + action_sig + "\", code, payload))")
	lines.append("\t_value_labels[\"" + r_id + "\"] = alloc_" + r_id)
	lines.append("\tadd_child(alloc_" + r_id + ")\n")

	return lines