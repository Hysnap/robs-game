# res://scenes/ui/components/hierarchy_navigator.gd
class_name HierarchyNavigator
extends VBoxContainer

signal node_selected(node_data: Dictionary)
signal item_selected(target_route: String, filter_key: Variant)
signal action_clicked(action_code: String, payload: Dictionary)

const INDENT_STEP_PX := 20.0

var _root_node: Dictionary = {}
var _collapsed_node_ids: Dictionary = {}
var _selected_node_id: String = ""

var _tree_list_box: VBoxContainer
var _inspector_panel: PanelContainer
var _inspector_title: Label
var _inspector_metrics: Label
var _inspector_feedback_box: VBoxContainer
var _inspector_actions_box: HBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_layout()
	if not _root_node.is_empty():
		_rebuild_tree_rows()

func _build_layout() -> void:
	_tree_list_box = VBoxContainer.new()
	_tree_list_box.name = "HierarchyTreeRows"
	_tree_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_list_box.add_theme_constant_override("separation", 4)
	add_child(_tree_list_box)

	_inspector_panel = PanelContainer.new()
	_inspector_panel.name = "HierarchyInspectorPanel"
	_inspector_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_panel.visible = false
	add_child(_inspector_panel)

	var insp_vbox := VBoxContainer.new()
	insp_vbox.add_theme_constant_override("separation", 6)
	_inspector_panel.add_child(insp_vbox)

	_inspector_title = Label.new()
	_inspector_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	insp_vbox.add_child(_inspector_title)

	_inspector_metrics = Label.new()
	_inspector_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	insp_vbox.add_child(_inspector_metrics)

	_inspector_feedback_box = VBoxContainer.new()
	_inspector_feedback_box.add_theme_constant_override("separation", 3)
	insp_vbox.add_child(_inspector_feedback_box)

	_inspector_actions_box = HBoxContainer.new()
	_inspector_actions_box.add_theme_constant_override("separation", 10)
	insp_vbox.add_child(_inspector_actions_box)

## Binds a normalized root dictionary produced by HierarchyTreeProjector
func set_tree_root(root_node: Dictionary) -> void:
	_root_node = root_node
	if _selected_node_id.is_empty() and not _root_node.is_empty():
		_selected_node_id = str(_root_node.get("node_id", ""))
	if _tree_list_box != null:
		_rebuild_tree_rows()

func get_selected_node_id() -> String:
	return _selected_node_id

func _rebuild_tree_rows() -> void:
	if _tree_list_box == null:
		return

	for child in _tree_list_box.get_children():
		_tree_list_box.remove_child(child)
		child.queue_free()

	if _root_node.is_empty():
		_inspector_panel.visible = false
		return

	var selected_payload: Dictionary = {}
	_render_node_recursive(_root_node, selected_payload)

	if not selected_payload.is_empty():
		_render_inspector(selected_payload)
	else:
		_render_inspector(_root_node)

func _render_node_recursive(node: Dictionary, out_selected: Dictionary) -> void:
	var node_id: String = str(node.get("node_id", ""))
	var depth: int = int(node.get("depth", 0))
	var node_type: String = str(node.get("node_type", "KNOWN")).to_upper()
	var children: Array = node.get("children", []) if node.get("children", null) is Array else []
	var has_children: bool = not children.is_empty()
	var is_collapsed: bool = bool(_collapsed_node_ids.get(node_id, false))
	var is_selected: bool = (node_id == _selected_node_id)

	if is_selected and out_selected.is_empty():
		for k in node.keys():
			out_selected[k] = node[k]

	var row_hbox := HBoxContainer.new()
	row_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_hbox.add_theme_constant_override("separation", 6)
	_tree_list_box.add_child(row_hbox)

	# Indentation spacer
	if depth > 0:
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(float(depth) * INDENT_STEP_PX, 0.0)
		row_hbox.add_child(indent)

	# Collapse / Expand button
	if has_children:
		var toggle_btn := Button.new()
		toggle_btn.text = "[+]" if is_collapsed else "[-]"
		toggle_btn.custom_minimum_size = Vector2(34, 28)
		toggle_btn.focus_mode = Control.FOCUS_NONE
		var bound_id: String = node_id
		toggle_btn.pressed.connect(func() -> void:
			_collapsed_node_ids[bound_id] = not bool(_collapsed_node_ids.get(bound_id, false))
			_rebuild_tree_rows()
		)
		row_hbox.add_child(toggle_btn)
	else:
		var leaf_pad := Label.new()
		leaf_pad.text = " • " if node_type != "TBC_LEAF" else " ? "
		leaf_pad.custom_minimum_size = Vector2(34, 28)
		leaf_pad.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		leaf_pad.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_hbox.add_child(leaf_pad)

	# Node selection button
	var node_btn := Button.new()
	node_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node_btn.focus_mode = Control.FOCUS_NONE

	var raw_label: String = str(node.get("label_text", ""))
	var raw_sub: String = str(node.get("sublabel_text", ""))
	var display_label: String = tr(raw_label) if not raw_label.is_empty() else ""
	var display_sub: String = tr(raw_sub) if not raw_sub.is_empty() else ""

	var prefix: String = ""
	if node_type == "TBC_BRIDGE":
		prefix = "[//] "
	elif node_type == "TBC_LEAF":
		prefix = "[TBC] "
	elif node_type == "STALE":
		prefix = "[!] "

	node_btn.text = prefix + display_label
	if not display_sub.is_empty():
		node_btn.text += "  —  " + display_sub

	if is_selected:
		node_btn.add_theme_color_override("font_color", Color("#facc15"))
	elif node_type == "STALE":
		node_btn.add_theme_color_override("font_color", Color("#e67e22"))
	elif node_type == "TBC_BRIDGE" or node_type == "TBC_LEAF":
		node_btn.add_theme_color_override("font_color", Color("#94a3b8"))

	var bound_node: Dictionary = node
	node_btn.pressed.connect(func() -> void:
		_selected_node_id = str(bound_node.get("node_id", ""))
		_rebuild_tree_rows()
		node_selected.emit(bound_node)
	)
	row_hbox.add_child(node_btn)

	if has_children and not is_collapsed:
		for child_node in children:
			if child_node is Dictionary:
				_render_node_recursive(child_node, out_selected)

func _render_inspector(node: Dictionary) -> void:
	if _inspector_panel == null:
		return

	_inspector_panel.visible = true
	var node_type: String = str(node.get("node_type", "KNOWN")).to_upper()
	var label_str: String = tr(str(node.get("label_text", "")))
	var badge_tok: String = str(node.get("badge_token", ""))
	var badge_str: String = tr(badge_tok) if not badge_tok.is_empty() else ""

	_inspector_title.text = "%s  [%s]" % [label_str, badge_str] if not badge_str.is_empty() else label_str

	var metrics: Dictionary = node.get("metrics", {}) if node.get("metrics", null) is Dictionary else {}
	if metrics.is_empty():
		var sub_str: String = str(node.get("sublabel_text", ""))
		_inspector_metrics.text = tr(sub_str) if not sub_str.is_empty() else ""
		_inspector_metrics.visible = not _inspector_metrics.text.is_empty()
	else:
		var parts: PackedStringArray = []
		if metrics.has("headcount"):
			parts.append("%s: %d" % [tr("UI_LBL_HEADCOUNT"), int(metrics["headcount"])])
		if metrics.has("mean_loyalty"):
			parts.append("%s: %.0f%%" % [tr("UI_LBL_LOYALTY"), float(metrics["mean_loyalty"]) * 100.0])
		if metrics.has("mean_fatigue"):
			parts.append("%s: %.0f%%" % [tr("UI_LBL_FATIGUE"), float(metrics["mean_fatigue"]) * 100.0])
		if metrics.has("remittance_target") and float(metrics["remittance_target"]) > 0.0:
			parts.append("%s: £%.0f" % [tr("UI_LBL_REMITTANCE_TARGET"), float(metrics["remittance_target"])])
		if metrics.has("operating_float") and float(metrics["operating_float"]) > 0.0:
			parts.append("%s: £%.0f" % [tr("UI_LBL_OPERATING_FLOAT"), float(metrics["operating_float"])])
		_inspector_metrics.text = "  |  ".join(parts)
		_inspector_metrics.visible = not _inspector_metrics.text.is_empty()

	for f_child in _inspector_feedback_box.get_children():
		_inspector_feedback_box.remove_child(f_child)
		f_child.queue_free()

	var digests: Array = node.get("feedback_digests", []) if node.get("feedback_digests", null) is Array else []
	for d_tok in digests:
		var d_lbl := Label.new()
		d_lbl.text = "• " + tr(str(d_tok))
		d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector_feedback_box.add_child(d_lbl)

	for a_child in _inspector_actions_box.get_children():
		_inspector_actions_box.remove_child(a_child)
		a_child.queue_free()

	var detail_route: String = str(node.get("detail_route", "")).strip_edges()
	var entity_id: String = str(node.get("entity_id", "")).strip_edges()
	var is_drillable: bool = bool(node.get("drillable", false))

	if is_drillable and not detail_route.is_empty() and not entity_id.is_empty():
		var inspect_btn := Button.new()
		inspect_btn.text = tr("UI_BTN_INSPECT_RECORD")
		inspect_btn.focus_mode = Control.FOCUS_NONE
		inspect_btn.pressed.connect(func() -> void:
			var parsed_key: Variant = entity_id
			if entity_id.is_valid_int():
				parsed_key = int(entity_id)
			item_selected.emit(detail_route, parsed_key)
		)
		_inspector_actions_box.add_child(inspect_btn)

	if node_type == "TBC_BRIDGE":
		var recon_btn := Button.new()
		recon_btn.text = tr("UI_BTN_INVESTIGATE_BRIDGE")
		recon_btn.focus_mode = Control.FOCUS_NONE
		var bound_bridge: Dictionary = node
		recon_btn.pressed.connect(func() -> void:
			action_clicked.emit("INVESTIGATE_BRIDGE", bound_bridge)
		)
		_inspector_actions_box.add_child(recon_btn)