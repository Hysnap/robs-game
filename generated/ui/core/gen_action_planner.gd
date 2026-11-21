# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/action_planner.json
extends VBoxContainer

signal directive_staged(directive)
signal execute_shift_requested(staged_directives)
signal action_clicked(action_code: String, payload: Dictionary)

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

var _value_labels: Dictionary = {}
var _queue: ActionQueuePresenter = ActionQueuePresenter.new()

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_ui()

func build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_value_labels.clear()
	var mono_font: Font = RETRO_THEME.get_monospace_font()
	assert(mono_font != null, "[UI FATAL] retro_theme.gd failed to supply monospace font.")
	var clr_blue: Color = RETRO_THEME.get_ink_color("accent")
	var clr_muted: Color = RETRO_THEME.get_ink_color("muted")
	var clr_black: Color = RETRO_THEME.get_ink_color("body")

	# --- Section: operational_docket ---
	var sec_operational_docket := VBoxContainer.new()
	sec_operational_docket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_operational_docket.add_theme_constant_override("separation", 2)
	var hdr_operational_docket := Label.new()
	hdr_operational_docket.text = "[ " + tr("UI_HDR_OPERATIONS").to_upper() + " ]"
	hdr_operational_docket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_operational_docket.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_operational_docket.add_theme_font_override("font", mono_font)
	hdr_operational_docket.add_theme_color_override("font_color", clr_blue)
	sec_operational_docket.add_child(hdr_operational_docket)
	var sep_operational_docket := HSeparator.new()
	sec_operational_docket.add_child(sep_operational_docket)
	add_child(sec_operational_docket)

	var row_active_operative_row := HBoxContainer.new()
	row_active_operative_row.name = "active_operative_row"
	row_active_operative_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_active_operative_row := Label.new()
	lbl_active_operative_row.text = tr("UI_LBL_ACTIVE_OPERATIVE")
	lbl_active_operative_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_active_operative_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_active_operative_row.add_child(lbl_active_operative_row)
	var val_active_operative_row := Label.new()
	val_active_operative_row.name = "active_operative_row_value"
	val_active_operative_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_active_operative_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_active_operative_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_active_operative_row.add_child(val_active_operative_row)
	_value_labels["active_operative_row"] = val_active_operative_row
	add_child(row_active_operative_row)

	var btn_btn_cycle_operative := Button.new()
	btn_btn_cycle_operative.name = "btn_cycle_operative"
	btn_btn_cycle_operative.text = tr("UI_BTN_SWITCH_OPERATIVE")
	btn_btn_cycle_operative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_cycle_operative.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_cycle_operative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_cycle_operative.pressed.connect(func(): self.action_clicked.emit("cycle_planner_operative"))
	_value_labels["btn_cycle_operative"] = btn_btn_cycle_operative
	add_child(btn_btn_cycle_operative)

	var row_return_to_base_row := HBoxContainer.new()
	row_return_to_base_row.name = "return_to_base_row"
	row_return_to_base_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_return_to_base_row := Label.new()
	lbl_return_to_base_row.text = tr("UI_LBL_RETURN_TO_BASE")
	lbl_return_to_base_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_return_to_base_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_return_to_base_row.add_child(lbl_return_to_base_row)
	var val_return_to_base_row := Label.new()
	val_return_to_base_row.name = "return_to_base_row_value"
	val_return_to_base_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_return_to_base_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_return_to_base_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_return_to_base_row.add_child(val_return_to_base_row)
	_value_labels["return_to_base_row"] = val_return_to_base_row
	add_child(row_return_to_base_row)

	var btn_btn_toggle_return_base := Button.new()
	btn_btn_toggle_return_base.name = "btn_toggle_return_base"
	btn_btn_toggle_return_base.text = tr("UI_BTN_TOGGLE_RETURN_BASE")
	btn_btn_toggle_return_base.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_toggle_return_base.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_toggle_return_base.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_toggle_return_base.pressed.connect(func(): self.action_clicked.emit("toggle_return_to_base"))
	_value_labels["btn_toggle_return_base"] = btn_btn_toggle_return_base
	add_child(btn_btn_toggle_return_base)

	var btn_btn_open_order_pad := Button.new()
	btn_btn_open_order_pad.name = "btn_open_order_pad"
	btn_btn_open_order_pad.text = tr("UI_BTN_OPEN_ORDER_PAD")
	btn_btn_open_order_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_open_order_pad.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_open_order_pad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_open_order_pad.pressed.connect(func(): self.action_clicked.emit("open_order_composer"))
	_value_labels["btn_open_order_pad"] = btn_btn_open_order_pad
	add_child(btn_btn_open_order_pad)

	var btn_btn_save_standing_order := Button.new()
	btn_btn_save_standing_order.name = "btn_save_standing_order"
	btn_btn_save_standing_order.text = tr("UI_BTN_SAVE_STANDING_ORDER")
	btn_btn_save_standing_order.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_save_standing_order.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_save_standing_order.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_save_standing_order.pressed.connect(func(): self.action_clicked.emit("save_standing_order"))
	_value_labels["btn_save_standing_order"] = btn_btn_save_standing_order
	add_child(btn_btn_save_standing_order)

	var btn_btn_pause_standing_orders := Button.new()
	btn_btn_pause_standing_orders.name = "btn_pause_standing_orders"
	btn_btn_pause_standing_orders.text = tr("UI_BTN_PAUSE_STANDING_ORDERS")
	btn_btn_pause_standing_orders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_pause_standing_orders.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_pause_standing_orders.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_pause_standing_orders.pressed.connect(func(): self.action_clicked.emit("pause_standing_orders"))
	_value_labels["btn_pause_standing_orders"] = btn_btn_pause_standing_orders
	add_child(btn_btn_pause_standing_orders)

	# --- Section: staging_ledger ---
	var sec_staging_ledger := VBoxContainer.new()
	sec_staging_ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_staging_ledger.add_theme_constant_override("separation", 2)
	var hdr_staging_ledger := Label.new()
	hdr_staging_ledger.text = "[ " + tr("UI_HDR_STAGED_QUEUE").to_upper() + " ]"
	hdr_staging_ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_staging_ledger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_staging_ledger.add_theme_font_override("font", mono_font)
	hdr_staging_ledger.add_theme_color_override("font_color", clr_blue)
	sec_staging_ledger.add_child(hdr_staging_ledger)
	var sep_staging_ledger := HSeparator.new()
	sec_staging_ledger.add_child(sep_staging_ledger)
	add_child(sec_staging_ledger)

	var box_queue_list := VBoxContainer.new()
	box_queue_list.name = "queue_list"
	box_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_queue_list.add_theme_constant_override("separation", 4)
	var list_queue_list := ItemList.new()
	list_queue_list.name = "queue_list_list"
	list_queue_list.custom_minimum_size = Vector2(0, 140)
	list_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_queue_list.add_child(list_queue_list)
	_value_labels["queue_list"] = list_queue_list
	var bar_queue_list := HBoxContainer.new()
	bar_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_queue_list.add_theme_constant_override("separation", 6)
	var btn_up_queue_list := Button.new()
	btn_up_queue_list.text = "▲"
	btn_up_queue_list.focus_mode = Control.FOCUS_NONE
	btn_up_queue_list.pressed.connect(func():
		var sel = list_queue_list.get_selected_items()
		if sel.size() > 0 and "_queue" in self:
			var n_idx = self._queue.move_directive(sel[0], -1)
			if n_idx >= 0: list_queue_list.select(n_idx)
	)
	bar_queue_list.add_child(btn_up_queue_list)
	var btn_dn_queue_list := Button.new()
	btn_dn_queue_list.text = "▼"
	btn_dn_queue_list.focus_mode = Control.FOCUS_NONE
	btn_dn_queue_list.pressed.connect(func():
		var sel = list_queue_list.get_selected_items()
		if sel.size() > 0 and "_queue" in self:
			var n_idx = self._queue.move_directive(sel[0], 1)
			if n_idx >= 0: list_queue_list.select(n_idx)
	)
	bar_queue_list.add_child(btn_dn_queue_list)
	var btn_rm_queue_list := Button.new()
	btn_rm_queue_list.text = "✖"
	btn_rm_queue_list.focus_mode = Control.FOCUS_NONE
	btn_rm_queue_list.pressed.connect(func():
		var sel = list_queue_list.get_selected_items()
		if sel.size() > 0 and "_queue" in self:
			var n_idx = self._queue.remove_directive(sel[0])
			if n_idx >= 0: list_queue_list.select(n_idx)
	)
	bar_queue_list.add_child(btn_rm_queue_list)
	var btn_tg_queue_list := Button.new()
	btn_tg_queue_list.text = "✓"
	btn_tg_queue_list.focus_mode = Control.FOCUS_NONE
	btn_tg_queue_list.pressed.connect(func():
		var sel = list_queue_list.get_selected_items()
		if sel.size() > 0 and "_queue" in self:
			self._queue.toggle_selection(sel[0])
			list_queue_list.select(sel[0])
	)
	bar_queue_list.add_child(btn_tg_queue_list)
	box_queue_list.add_child(bar_queue_list)
	add_child(box_queue_list)

	var btn_btn_select_all := Button.new()
	btn_btn_select_all.name = "btn_select_all"
	btn_btn_select_all.text = tr("UI_BTN_SELECT_ALL")
	btn_btn_select_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_select_all.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_select_all.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_select_all.pressed.connect(func(): self.action_clicked.emit("select_all_directives"))
	_value_labels["btn_select_all"] = btn_btn_select_all
	add_child(btn_btn_select_all)

	_queue.queue_changed.connect(_on_queue_changed)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("active_operative_row"):
		var ctrl = _value_labels["active_operative_row"]
		if not data.has("active_operative_display") or data["active_operative_display"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["active_operative_display"]) + ""
	if _value_labels.has("return_to_base_row"):
		var ctrl = _value_labels["return_to_base_row"]
		if not data.has("return_to_base_display") or data["return_to_base_display"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["return_to_base_display"]) + ""
	if _value_labels.has("queue_list"):
		var ctrl = _value_labels["queue_list"]
		if ctrl is ItemList:
			ctrl.clear()
			if data.has("staged_queue") and data["staged_queue"] is Array:
				var items: Array = data["staged_queue"]
				for item in items:
					ctrl.add_item(str(item))

func add_directive(directive: Dictionary) -> void:
	_queue.add_directive(directive)

func get_staged_directives() -> Array[Dictionary]:
	return _queue.get_staged_directives()

func consume_selected_directives() -> Array[Dictionary]:
	return _queue.consume_selected_directives()

func clear_staged_directives() -> void:
	_queue.clear()

func _on_queue_changed(display_lines: Array, _selected_index: int) -> void:
	if _value_labels.has("queue_list"):
		var lst = _value_labels["queue_list"]
		if lst is ItemList:
			lst.clear()
			for line in display_lines:
				lst.add_item(line)
