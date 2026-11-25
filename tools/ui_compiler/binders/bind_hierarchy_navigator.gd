# res://tools/ui_compiler/binders/bind_hierarchy_navigator.gd
@tool
class_name UIBindHierarchyNavigator
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = str(row.get("id", "hierarchy_nav")).strip_edges()
	var f_name: String = str(row.get("field", "")).strip_edges()
	if r_id.is_empty() or f_name.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + r_id + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + r_id + "\"]")
	lines.append("\t\tif ctrl != null and ctrl.has_method(\"set_tree_root\"):")
	lines.append("\t\t\tvar tree_data = data.get(\"" + f_name + "\", {})")
	lines.append("\t\t\tctrl.set_tree_root(tree_data if tree_data is Dictionary else {})")

	return lines