# res://tools/ui_compiler/widgets/emit_hierarchy_navigator.gd
@tool
class_name UIEmitHierarchyNavigator
extends RefCounted

static func emit_build(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = str(row.get("id", "hierarchy_nav")).strip_edges()
	var item_sig: String = str(row.get("item_signal", "item_selected")).strip_edges()
	var action_sig: String = str(row.get("action_signal", "action_clicked")).strip_edges()

	lines.append("\tvar nav_script_" + r_id + " := preload(\"res://scenes/ui/components/hierarchy_navigator.gd\")")
	lines.append("\tvar nav_" + r_id + " := nav_script_" + r_id + ".new()")
	lines.append("\tnav_" + r_id + ".name = \"" + r_id + "\"")
	lines.append("\tnav_" + r_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	if not item_sig.is_empty():
		lines.append("\tif has_signal(\"" + item_sig + "\"):")
		lines.append("\t\tnav_" + r_id + ".item_selected.connect(func(route: String, key: Variant) -> void: emit_signal(\"" + item_sig + "\", route, key))")
	if not action_sig.is_empty():
		lines.append("\tif has_signal(\"" + action_sig + "\"):")
		lines.append("\t\tnav_" + r_id + ".action_clicked.connect(func(code: String, payload: Dictionary) -> void: emit_signal(\"" + action_sig + "\", code, payload))")
	lines.append("\t_value_labels[\"" + r_id + "\"] = nav_" + r_id)
	lines.append("\tadd_child(nav_" + r_id + ")\n")

	return lines