# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/action_planner.json
class_name GenActionPlanner
extends VBoxContainer

signal directive_staged(directive)
signal execute_shift_requested(staged_directives)
signal action_clicked(action_code)

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

var _value_labels: Dictionary = {}

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

	var btn_btn_open_order_pad := Button.new()
	btn_btn_open_order_pad.text = tr("UI_BTN_OPEN_ORDER_PAD")
	btn_btn_open_order_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_open_order_pad.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_open_order_pad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_open_order_pad.add_theme_font_override("font", mono_font)
	btn_btn_open_order_pad.pressed.connect(func(): action_clicked.emit("OPEN_PAD"))
	_value_labels["btn_open_order_pad"] = btn_btn_open_order_pad
	add_child(btn_btn_open_order_pad)

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
	box_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_queue_list.add_theme_constant_override("separation", 4)
	var list_queue_list := ItemList.new()
	list_queue_list.custom_minimum_size = Vector2(0, 140)
	list_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_queue_list.add_theme_font_override("font", mono_font)
	box_queue_list.add_child(list_queue_list)
	_value_labels["queue_list"] = list_queue_list
	var bar_queue_list := HBoxContainer.new()
	bar_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_queue_list.add_theme_constant_override("separation", 6)
	var btn_up_queue_list := Button.new()
	btn_up_queue_list.text = "▲"
	btn_up_queue_list.focus_mode = Control.FOCUS_NONE
	btn_up_queue_list.add_theme_font_override("font", mono_font)
	btn_up_queue_list.pressed.connect(func(): action_clicked.emit("MOVE_UP"))
	bar_queue_list.add_child(btn_up_queue_list)
	var btn_dn_queue_list := Button.new()
	btn_dn_queue_list.text = "▼"
	btn_dn_queue_list.focus_mode = Control.FOCUS_NONE
	btn_dn_queue_list.add_theme_font_override("font", mono_font)
	btn_dn_queue_list.pressed.connect(func(): action_clicked.emit("MOVE_DOWN"))
	bar_queue_list.add_child(btn_dn_queue_list)
	var btn_rm_queue_list := Button.new()
	btn_rm_queue_list.text = "✖"
	btn_rm_queue_list.focus_mode = Control.FOCUS_NONE
	btn_rm_queue_list.add_theme_font_override("font", mono_font)
	btn_rm_queue_list.pressed.connect(func(): action_clicked.emit("REMOVE_ORDER"))
	bar_queue_list.add_child(btn_rm_queue_list)
	var btn_tg_queue_list := Button.new()
	btn_tg_queue_list.text = "✓"
	btn_tg_queue_list.focus_mode = Control.FOCUS_NONE
	btn_tg_queue_list.add_theme_font_override("font", mono_font)
	btn_tg_queue_list.pressed.connect(func(): action_clicked.emit("TOGGLE_SELECT"))
	bar_queue_list.add_child(btn_tg_queue_list)
	box_queue_list.add_child(bar_queue_list)
	add_child(box_queue_list)

	var btn_btn_select_all := Button.new()
	btn_btn_select_all.text = tr("UI_BTN_SELECT_ALL")
	btn_btn_select_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_select_all.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_select_all.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_select_all.add_theme_font_override("font", mono_font)
	btn_btn_select_all.pressed.connect(func(): action_clicked.emit("SELECT_ALL"))
	_value_labels["btn_select_all"] = btn_btn_select_all
	add_child(btn_btn_select_all)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("queue_list") and data.has("staged_queue"):
		var ctrl = _value_labels["queue_list"]
		if ctrl is ItemList:
			ctrl.clear()
			var items: Array = data.get("staged_queue", [])
			for item in items:
				ctrl.add_item(str(item))
