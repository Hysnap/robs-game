# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/operative_dossier.json
extends VBoxContainer

signal action_clicked(action_code: String, payload: Dictionary)

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

	# --- Section: header_section ---
	var sec_header_section := VBoxContainer.new()
	sec_header_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_header_section.add_theme_constant_override("separation", 2)
	var hdr_header_section := Label.new()
	hdr_header_section.text = "[ " + tr("UI_HDR_OPERATIVE_DOSSIER").to_upper() + " ]"
	hdr_header_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_header_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_header_section.add_theme_font_override("font", mono_font)
	hdr_header_section.add_theme_color_override("font_color", clr_blue)
	sec_header_section.add_child(hdr_header_section)
	var sep_header_section := HSeparator.new()
	sec_header_section.add_child(sep_header_section)
	add_child(sec_header_section)

	# --- Header Block ---
	var box_operative_header := VBoxContainer.new()
	box_operative_header.name = "operative_header"
	box_operative_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_operative_header.add_theme_constant_override("separation", 0)
	var title_operative_header := Label.new()
	title_operative_header.name = "operative_header_title"
	title_operative_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_operative_header.theme_type_variation = &"HeaderTitle"
	title_operative_header.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	title_operative_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_operative_header.add_child(title_operative_header)
	_value_labels["operative_header_title"] = title_operative_header
	var sub_operative_header := Label.new()
	sub_operative_header.name = "operative_header_subtitle"
	sub_operative_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_operative_header.theme_type_variation = &"HeaderSubtitle"
	sub_operative_header.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	sub_operative_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_operative_header.add_child(sub_operative_header)
	_value_labels["operative_header_subtitle"] = sub_operative_header
	box_operative_header.add_child(HSeparator.new())
	add_child(box_operative_header)

	# --- Section: status_section ---
	var sec_status_section := VBoxContainer.new()
	sec_status_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_status_section.add_theme_constant_override("separation", 2)
	var hdr_status_section := Label.new()
	hdr_status_section.text = "[ " + tr("UI_HDR_OPERATIONS").to_upper() + " ]"
	hdr_status_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_status_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_status_section.add_theme_font_override("font", mono_font)
	hdr_status_section.add_theme_color_override("font_color", clr_blue)
	sec_status_section.add_child(hdr_status_section)
	var sep_status_section := HSeparator.new()
	sec_status_section.add_child(sep_status_section)
	add_child(sec_status_section)

	var row_current_location_row := HBoxContainer.new()
	row_current_location_row.name = "current_location_row"
	row_current_location_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_current_location_row := Label.new()
	lbl_current_location_row.text = tr("UI_LBL_CURRENT_LOCATION")
	lbl_current_location_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_current_location_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_current_location_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_current_location_row.add_child(lbl_current_location_row)
	var val_current_location_row := Label.new()
	val_current_location_row.name = "current_location_row_value"
	val_current_location_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_current_location_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_current_location_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_current_location_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_current_location_row.add_child(val_current_location_row)
	_value_labels["current_location_row"] = val_current_location_row
	add_child(row_current_location_row)

	var row_base_location_row := HBoxContainer.new()
	row_base_location_row.name = "base_location_row"
	row_base_location_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_base_location_row := Label.new()
	lbl_base_location_row.text = tr("UI_LBL_BASE_LOCATION")
	lbl_base_location_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_base_location_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_base_location_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_base_location_row.add_child(lbl_base_location_row)
	var val_base_location_row := Label.new()
	val_base_location_row.name = "base_location_row_value"
	val_base_location_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_base_location_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_base_location_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_base_location_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_base_location_row.add_child(val_base_location_row)
	_value_labels["base_location_row"] = val_base_location_row
	add_child(row_base_location_row)

	var row_return_to_base_row := HBoxContainer.new()
	row_return_to_base_row.name = "return_to_base_row"
	row_return_to_base_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_return_to_base_row := Label.new()
	lbl_return_to_base_row.text = tr("UI_LBL_RETURN_TO_BASE")
	lbl_return_to_base_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_return_to_base_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_return_to_base_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_return_to_base_row.add_child(lbl_return_to_base_row)
	var val_return_to_base_row := Label.new()
	val_return_to_base_row.name = "return_to_base_row_value"
	val_return_to_base_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_return_to_base_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_return_to_base_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_return_to_base_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_return_to_base_row.add_child(val_return_to_base_row)
	_value_labels["return_to_base_row"] = val_return_to_base_row
	add_child(row_return_to_base_row)

	var row_fatigue_row := HBoxContainer.new()
	row_fatigue_row.name = "fatigue_row"
	row_fatigue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_fatigue_row := Label.new()
	lbl_fatigue_row.text = tr("UI_LBL_FATIGUE")
	lbl_fatigue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_fatigue_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_fatigue_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_fatigue_row.add_child(lbl_fatigue_row)
	var val_fatigue_row := Label.new()
	val_fatigue_row.name = "fatigue_row_value"
	val_fatigue_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_fatigue_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_fatigue_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_fatigue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_fatigue_row.add_child(val_fatigue_row)
	_value_labels["fatigue_row"] = val_fatigue_row
	add_child(row_fatigue_row)

	var row_cash_row := HBoxContainer.new()
	row_cash_row.name = "cash_row"
	row_cash_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_cash_row := Label.new()
	lbl_cash_row.text = tr("UI_LBL_CASH_HELD")
	lbl_cash_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_cash_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_cash_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_cash_row.add_child(lbl_cash_row)
	var val_cash_row := Label.new()
	val_cash_row.name = "cash_row_value"
	val_cash_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_cash_row.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_cash_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_cash_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_cash_row.add_child(val_cash_row)
	_value_labels["cash_row"] = val_cash_row
	add_child(row_cash_row)

	# --- Section: inventory_section ---
	var sec_inventory_section := VBoxContainer.new()
	sec_inventory_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_inventory_section.add_theme_constant_override("separation", 2)
	var hdr_inventory_section := Label.new()
	hdr_inventory_section.text = "[ " + tr("UI_HDR_PERSONAL_INVENTORY").to_upper() + " ]"
	hdr_inventory_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_inventory_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_inventory_section.add_theme_font_override("font", mono_font)
	hdr_inventory_section.add_theme_color_override("font_color", clr_blue)
	sec_inventory_section.add_child(hdr_inventory_section)
	var sep_inventory_section := HSeparator.new()
	sec_inventory_section.add_child(sep_inventory_section)
	add_child(sec_inventory_section)

	var list_inventory_list := ItemList.new()
	list_inventory_list.name = "inventory_list"
	list_inventory_list.custom_minimum_size = Vector2(0, 120)
	list_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["inventory_list"] = list_inventory_list
	add_child(list_inventory_list)

	# --- Section: navigation_section ---
	var sec_navigation_section := VBoxContainer.new()
	sec_navigation_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_navigation_section.add_theme_constant_override("separation", 2)
	var hdr_navigation_section := Label.new()
	hdr_navigation_section.text = "[ " + tr("UI_HDR_CREW_DOSSIER").to_upper() + " ]"
	hdr_navigation_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_navigation_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_navigation_section.add_theme_font_override("font", mono_font)
	hdr_navigation_section.add_theme_color_override("font_color", clr_blue)
	sec_navigation_section.add_child(hdr_navigation_section)
	var sep_navigation_section := HSeparator.new()
	sec_navigation_section.add_child(sep_navigation_section)
	add_child(sec_navigation_section)

	var btn_btn_back := Button.new()
	btn_btn_back.name = "btn_back"
	btn_btn_back.text = tr("UI_BTN_BACK_ROSTER")
	btn_btn_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_back.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_back.pressed.connect(func(): self.action_clicked.emit("open_roster", {}))
	_value_labels["btn_back"] = btn_btn_back
	add_child(btn_btn_back)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("operative_header_title"):
		if data.has("operative_name") and data["operative_name"] != null:
			_value_labels["operative_header_title"].text = str(data["operative_name"]).to_upper()
		else:
			_value_labels["operative_header_title"].text = "--- UNNAMED ---"
	if _value_labels.has("operative_header_subtitle"):
		if data.has("role_title") and data["role_title"] != null:
			_value_labels["operative_header_subtitle"].text = str(data["role_title"]).to_upper()
		else:
			_value_labels["operative_header_subtitle"].text = ""
	if _value_labels.has("current_location_row"):
		var ctrl = _value_labels["current_location_row"]
		if not data.has("current_location_name") or data["current_location_name"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["current_location_name"]) + ""
	if _value_labels.has("base_location_row"):
		var ctrl = _value_labels["base_location_row"]
		if not data.has("base_location_name") or data["base_location_name"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["base_location_name"]) + ""
	if _value_labels.has("return_to_base_row"):
		var ctrl = _value_labels["return_to_base_row"]
		if not data.has("return_to_base_status") or data["return_to_base_status"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["return_to_base_status"]) + ""
	if _value_labels.has("fatigue_row"):
		var ctrl = _value_labels["fatigue_row"]
		if not data.has("fatigue_display") or data["fatigue_display"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["fatigue_display"]) + ""
	if _value_labels.has("cash_row"):
		var ctrl = _value_labels["cash_row"]
		if not data.has("cash_display") or data["cash_display"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["cash_display"]) + ""
	if _value_labels.has("inventory_list"):
		var ctrl = _value_labels["inventory_list"]
		if ctrl is ItemList:
			ctrl.clear()
			if data.has("inventory_lines") and data["inventory_lines"] is Array:
				var items: Array = data["inventory_lines"]
				for item in items:
					ctrl.add_item(str(item))
