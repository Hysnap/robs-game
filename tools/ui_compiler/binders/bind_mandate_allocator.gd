# res://tools/ui_compiler/binders/bind_mandate_allocator.gd
@tool
class_name UIBindMandateAllocator
extends RefCounted

static func emit_binding(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var r_id: String = str(row.get("id", "mandate_allocator")).strip_edges()
	var catalog_field: String = str(row.get("catalog_field", "allocator_catalog")).strip_edges()
	var review_field: String = str(row.get("review_field", "selected_mandate_review")).strip_edges()
	if r_id.is_empty():
		return lines

	lines.append("\tif _value_labels.has(\"" + r_id + "\"):")
	lines.append("\t\tvar ctrl = _value_labels[\"" + r_id + "\"]")
	lines.append("\t\tif ctrl != null:")
	if not catalog_field.is_empty():
		lines.append("\t\t\tif ctrl.has_method(\"set_allocator_catalog\"):")
		lines.append("\t\t\t\tvar cat_data = data.get(\"" + catalog_field + "\", {})")
		lines.append("\t\t\t\tctrl.set_allocator_catalog(cat_data if cat_data is Dictionary else {})")
	if not review_field.is_empty():
		lines.append("\t\t\tif ctrl.has_method(\"set_selected_mandate_review\"):")
		lines.append("\t\t\t\tvar rev_data = data.get(\"" + review_field + "\", {})")
		lines.append("\t\t\t\tctrl.set_selected_mandate_review(rev_data if rev_data is Dictionary else {})")

	return lines