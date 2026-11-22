# res://scenes/ui/components/mandate_allocator_panel.gd
class_name MandateAllocatorPanel
extends VBoxContainer

signal action_clicked(action_code: String, payload: Dictionary)

var _catalog: Dictionary = {}
var _review_data: Dictionary = {}
var _is_composer_open: bool = false

var _selected_axes: Dictionary = {
	"spatial": ["*"],
	"premises": ["*"],
	"commodities": ["*"],
	"verbs": ["*"]
}

var _review_panel: PanelContainer
var _review_title: Label
var _review_metrics: Label
var _review_recon_note: Label
var _review_actions: HBoxContainer

var _toggle_composer_btn: Button
var _composer_panel: PanelContainer
var _title_edit: LineEdit
var _assignee_opt: OptionButton
var _mode_opt: OptionButton
var _horizon_opt: OptionButton
var _remittance_spin: SpinBox
var _float_spin: SpinBox
var _heat_spin: SpinBox
var _axis_containers: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_layout()
	_refresh_review_panel()
	_rebuild_composer_options()

func _build_layout() -> void:
	# 1. Selected Mandate Review & Intervention Card
	_review_panel = PanelContainer.new()
	_review_panel.name = "SelectedMandateReviewPanel"
	_review_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review_panel.visible = false
	add_child(_review_panel)

	var rev_vbox := VBoxContainer.new()
	rev_vbox.add_theme_constant_override("separation", 6)
	_review_panel.add_child(rev_vbox)

	_review_title = Label.new()
	_review_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rev_vbox.add_child(_review_title)

	_review_metrics = Label.new()
	_review_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rev_vbox.add_child(_review_metrics)

	_review_recon_note = Label.new()
	_review_recon_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_recon_note.add_theme_color_override("font_color", Color("#facc15"))
	rev_vbox.add_child(_review_recon_note)

	_review_actions = HBoxContainer.new()
	_review_actions.add_theme_constant_override("separation", 10)
	rev_vbox.add_child(_review_actions)

	# 2. Toggle Button for 4-Axis Cohort Mandate Allocator
	_toggle_composer_btn = Button.new()
	_toggle_composer_btn.name = "BtnToggleMandateAllocator"
	_toggle_composer_btn.text = tr("UI_BTN_NEW_COHORT_MANDATE")
	_toggle_composer_btn.focus_mode = Control.FOCUS_NONE
	_toggle_composer_btn.pressed.connect(func() -> void:
		_is_composer_open = not _is_composer_open
		if _composer_panel != null:
			_composer_panel.visible = _is_composer_open
	)
	add_child(_toggle_composer_btn)

	# 3. Collapsible 4-Axis Cohort Mandate Allocator Panel
	_composer_panel = PanelContainer.new()
	_composer_panel.name = "MandateCohortComposerPanel"
	_composer_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composer_panel.visible = _is_composer_open
	add_child(_composer_panel)

	var comp_vbox := VBoxContainer.new()
	comp_vbox.add_theme_constant_override("separation", 8)
	_composer_panel.add_child(comp_vbox)

	# Title & Assignee Row
	var top_grid := GridContainer.new()
	top_grid.columns = 2
	top_grid.add_theme_constant_override("h_separation", 10)
	top_grid.add_theme_constant_override("v_separation", 6)
	comp_vbox.add_child(top_grid)

	var lbl_title := Label.new()
	lbl_title.text = tr("UI_LBL_MANDATE_TITLE")
	top_grid.add_child(lbl_title)

	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = tr("UI_ORG_MANDATE_DEFAULT_TITLE")
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_grid.add_child(_title_edit)

	var lbl_assignee := Label.new()
	lbl_assignee.text = tr("UI_LBL_ASSIGNED_MANAGER")
	top_grid.add_child(lbl_assignee)

	_assignee_opt = OptionButton.new()
	_assignee_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_assignee_opt.focus_mode = Control.FOCUS_NONE
	top_grid.add_child(_assignee_opt)

	var lbl_mode := Label.new()
	lbl_mode.text = tr("UI_LBL_MANDATE_MODE")
	top_grid.add_child(lbl_mode)

	_mode_opt = OptionButton.new()
	_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_opt.focus_mode = Control.FOCUS_NONE
	top_grid.add_child(_mode_opt)

	var lbl_horizon := Label.new()
	lbl_horizon.text = tr("UI_LBL_PLANNING_HORIZON")
	top_grid.add_child(lbl_horizon)

	_horizon_opt = OptionButton.new()
	_horizon_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_horizon_opt.focus_mode = Control.FOCUS_NONE
	top_grid.add_child(_horizon_opt)

	var lbl_remit := Label.new()
	lbl_remit.text = tr("UI_LBL_REMITTANCE_TARGET")
	top_grid.add_child(lbl_remit)

	_remittance_spin = SpinBox.new()
	_remittance_spin.min_value = 0.0
	_remittance_spin.max_value = 100000.0
	_remittance_spin.step = 25.0
	_remittance_spin.value = 250.0
	top_grid.add_child(_remittance_spin)

	var lbl_float := Label.new()
	lbl_float.text = tr("UI_LBL_OPERATING_FLOAT")
	top_grid.add_child(lbl_float)

	_float_spin = SpinBox.new()
	_float_spin.min_value = 0.0
	_float_spin.max_value = 50000.0
	_float_spin.step = 25.0
	_float_spin.value = 150.0
	top_grid.add_child(_float_spin)

	var lbl_heat := Label.new()
	lbl_heat.text = tr("UI_LBL_HEAT_CEILING")
	top_grid.add_child(lbl_heat)

	_heat_spin = SpinBox.new()
	_heat_spin.min_value = 0.05
	_heat_spin.max_value = 1.0
	_heat_spin.step = 0.05
	_heat_spin.value = 0.65
	top_grid.add_child(_heat_spin)

	# 4-Axis Cohort Multi-Select Sections
	var axis_defs: Array[Dictionary] = [
		{"axis": "spatial", "header_token": "UI_AXIS_SPATIAL_HDR"},
		{"axis": "premises", "header_token": "UI_AXIS_PREMISES_HDR"},
		{"axis": "commodities", "header_token": "UI_AXIS_COMMODITIES_HDR"},
		{"axis": "verbs", "header_token": "UI_AXIS_VERBS_HDR"}
	]
	for a_def in axis_defs:
		var axis_key: String = str(a_def["axis"])
		var ax_lbl := Label.new()
		ax_lbl.text = tr(str(a_def["header_token"]))
		comp_vbox.add_child(ax_lbl)

		var flow := HFlowContainer.new()
		flow.name = "AxisFlow_%s" % axis_key
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		comp_vbox.add_child(flow)
		_axis_containers[axis_key] = flow

	var submit_btn := Button.new()
	submit_btn.name = "BtnSubmitCohortMandate"
	submit_btn.text = tr("UI_BTN_ISSUE_MANDATE")
	submit_btn.focus_mode = Control.FOCUS_NONE
	submit_btn.pressed.connect(_on_submit_mandate_pressed)
	comp_vbox.add_child(submit_btn)

func set_allocator_catalog(catalog: Dictionary) -> void:
	_catalog = catalog
	if _assignee_opt != null:
		_rebuild_composer_options()

func set_selected_mandate_review(review: Dictionary) -> void:
	_review_data = review
	if _review_panel != null:
		_refresh_review_panel()

func _refresh_review_panel() -> void:
	if _review_panel == null:
		return
	if _review_data.is_empty():
		_review_panel.visible = false
		return

	_review_panel.visible = true
	var m_id: int = int(_review_data.get("mandate_id", 0))
	var m_title: String = str(_review_data.get("title", ""))
	var m_mode: String = str(_review_data.get("mandate_mode", "CASHFLOW"))
	var m_hor: String = str(_review_data.get("planning_horizon", "MONTH"))
	var lock_tok: String = "UI_STATUS_ASSISTANCE_OPEN" if bool(_review_data.get("assistance_open", false)) else ("UI_STATUS_LOCKED" if bool(_review_data.get("is_locked", false)) else "UI_STATUS_OPEN")

	_review_title.text = "#%d %s  [%s | %s | %s]" % [m_id, m_title, m_mode, m_hor, tr(lock_tok)]
	_review_metrics.text = "%s: £%.0f  |  %s: £%.0f  |  %s: %.0f%%" % [
		tr("UI_LBL_REMITTANCE_TARGET"),
		float(_review_data.get("remittance_target", 0.0)),
		tr("UI_LBL_OPERATING_FLOAT"),
		float(_review_data.get("operating_float", 0.0)),
		tr("UI_LBL_HEAT_CEILING"),
		float(_review_data.get("heat_ceiling", 0.65)) * 100.0
	]

	var unscouted: Array = _review_data.get("unscouted_districts", []) if _review_data.get("unscouted_districts", null) is Array else []
	if unscouted.is_empty():
		_review_recon_note.visible = false
	else:
		var names: PackedStringArray = []
		for u in unscouted:
			names.append(str(u))
		_review_recon_note.text = "%s: %s" % [tr("UI_WARN_UNSCOUTED_MANDATE_RECON"), ", ".join(names)]
		_review_recon_note.visible = true

	for c in _review_actions.get_children():
		_review_actions.remove_child(c)
		c.queue_free()

	var btn_assist := Button.new()
	btn_assist.text = tr("UI_BTN_GRANT_ASSISTANCE")
	btn_assist.focus_mode = Control.FOCUS_NONE
	btn_assist.pressed.connect(func() -> void:
		action_clicked.emit("grant_mandate_assistance", {"mandate_id": m_id})
	)
	_review_actions.add_child(btn_assist)

	var btn_revoke := Button.new()
	btn_revoke.text = tr("UI_BTN_REVOKE_MANDATE")
	btn_revoke.focus_mode = Control.FOCUS_NONE
	btn_revoke.pressed.connect(func() -> void:
		action_clicked.emit("revoke_org_mandate", {"mandate_id": m_id})
	)
	_review_actions.add_child(btn_revoke)

func _rebuild_composer_options() -> void:
	if _assignee_opt == null:
		return

	_assignee_opt.clear()
	var assignees: Array = _catalog.get("assignees", []) if _catalog.get("assignees", null) is Array else []
	for i in range(assignees.size()):
		var item = assignees[i]
		if item is Dictionary:
			_assignee_opt.add_item(str(item.get("label", "")), i)
			_assignee_opt.set_item_metadata(i, item)

	_mode_opt.clear()
	var modes: Array = _catalog.get("mandate_modes", ["CASHFLOW", "SUPPLY", "EXPAND", "CONSOLIDATE"])
	for i in range(modes.size()):
		var m_str: String = str(modes[i])
		_mode_opt.add_item(m_str, i)
		_mode_opt.set_item_metadata(i, m_str)

	_horizon_opt.clear()
	var horizons: Array = _catalog.get("planning_horizons", ["DAY", "WEEK", "MONTH", "QUARTER"])
	for i in range(horizons.size()):
		var h_str: String = str(horizons[i])
		_horizon_opt.add_item(h_str, i)
		_horizon_opt.set_item_metadata(i, h_str)
		if h_str == "MONTH":
			_horizon_opt.select(i)

	for axis_key in _axis_containers.keys():
		var flow: HFlowContainer = _axis_containers[axis_key]
		for child in flow.get_children():
			flow.remove_child(child)
			child.queue_free()

		var options: Array = _catalog.get(axis_key, []) if _catalog.get(axis_key, null) is Array else []
		var active_list: Array = _selected_axes.get(axis_key, ["*"])

		for opt in options:
			if not (opt is Dictionary):
				continue
			var opt_id = opt.get("id", "*")
			var is_unscouted: bool = bool(opt.get("is_unscouted", false))
			var base_label: String = tr(str(opt["label_token"])) if opt.has("label_token") else str(opt.get("label", opt_id))
			if is_unscouted:
				base_label = "[?] %s (%s)" % [base_label, tr("UI_TAG_UNSCOUTED")]

			var chip := Button.new()
			chip.toggle_mode = true
			chip.button_pressed = active_list.has(opt_id)
			chip.text = base_label
			chip.focus_mode = Control.FOCUS_NONE
			if is_unscouted:
				chip.add_theme_color_override("font_color", Color("#facc15"))

			var bound_axis: String = axis_key
			var bound_id = opt_id
			chip.pressed.connect(func() -> void:
				_toggle_axis_value(bound_axis, bound_id)
				_rebuild_composer_options()
			)
			flow.add_child(chip)

func _toggle_axis_value(axis_key: String, val: Variant) -> void:
	var current: Array = _selected_axes.get(axis_key, ["*"]).duplicate()
	if str(val) == "*":
		_selected_axes[axis_key] = ["*"]
		return

	current.erase("*")
	if current.has(val):
		current.erase(val)
	else:
		current.append(val)

	if current.is_empty():
		current = ["*"]
	_selected_axes[axis_key] = current

func _on_submit_mandate_pressed() -> void:
	var title_txt: String = _title_edit.text.strip_edges() if _title_edit != null else ""
	var spec: Dictionary = {
		"title": title_txt,
		"mandate_mode": str(_mode_opt.get_selected_metadata()) if _mode_opt.selected >= 0 else "CASHFLOW",
		"planning_horizon": str(_horizon_opt.get_selected_metadata()) if _horizon_opt.selected >= 0 else "MONTH",
		"heat_ceiling": float(_heat_spin.value) if _heat_spin != null else 0.65,
		"target_metrics": {
			"remittance_target": float(_remittance_spin.value) if _remittance_spin != null else 250.0,
			"operating_float": float(_float_spin.value) if _float_spin != null else 150.0
		},
		"scope_filter": {
			"spatial": _selected_axes.get("spatial", ["*"]).duplicate(),
			"premises": _selected_axes.get("premises", ["*"]).duplicate(),
			"commodities": _selected_axes.get("commodities", ["*"]).duplicate(),
			"verbs": _selected_axes.get("verbs", ["*"]).duplicate()
		}
	}

	if _assignee_opt != null and _assignee_opt.selected >= 0:
		var assignee_meta = _assignee_opt.get_selected_metadata()
		if assignee_meta is Dictionary:
			if str(assignee_meta.get("type", "")) == "ORG":
				spec["target_org_id"] = str(assignee_meta.get("id", ""))
			else:
				spec["manager_resident_id"] = int(assignee_meta.get("id", 0))

	action_clicked.emit("create_org_mandate", spec)