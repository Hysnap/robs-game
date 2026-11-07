# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/residential_docket.json
class_name GenResidentialDocket
extends VBoxContainer

signal route_requested(domain_token: String, target_page_name: String)

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

	var btn_btn_back := Button.new()
	btn_btn_back.name = "btn_back"
	btn_btn_back.text = tr("UI_BTN_BACK_DOSSIER")
	btn_btn_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_back.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_back.add_theme_font_override("font", mono_font)
	btn_btn_back.pressed.connect(func(): route_requested.emit("DOSSIER", ""))
	_value_labels["btn_back"] = btn_btn_back
	add_child(btn_btn_back)

	# --- Header Block ---
	var box_tenancy_header := VBoxContainer.new()
	box_tenancy_header.name = "tenancy_header"
	box_tenancy_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_tenancy_header.add_theme_constant_override("separation", 0)
	var title_tenancy_header := Label.new()
	title_tenancy_header.name = "tenancy_header_title"
	title_tenancy_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_tenancy_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_tenancy_header.add_theme_font_override("font", mono_font)
	title_tenancy_header.add_theme_font_size_override("font_size", 18)
	title_tenancy_header.add_theme_color_override("font_color", clr_blue)
	box_tenancy_header.add_child(title_tenancy_header)
	_value_labels["tenancy_header_title"] = title_tenancy_header
	var sub_tenancy_header := Label.new()
	sub_tenancy_header.name = "tenancy_header_subtitle"
	sub_tenancy_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_tenancy_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_tenancy_header.add_theme_font_override("font", mono_font)
	sub_tenancy_header.add_theme_font_size_override("font_size", 12)
	sub_tenancy_header.add_theme_color_override("font_color", clr_muted)
	box_tenancy_header.add_child(sub_tenancy_header)
	_value_labels["tenancy_header_subtitle"] = sub_tenancy_header
	box_tenancy_header.add_child(HSeparator.new())
	add_child(box_tenancy_header)

	# --- Section: tenancy_details ---
	var sec_tenancy_details := VBoxContainer.new()
	sec_tenancy_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_tenancy_details.add_theme_constant_override("separation", 2)
	var hdr_tenancy_details := Label.new()
	hdr_tenancy_details.text = "[ " + tr("UI_HDR_TENANCY_STATUS").to_upper() + " ]"
	hdr_tenancy_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_tenancy_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_tenancy_details.add_theme_font_override("font", mono_font)
	hdr_tenancy_details.add_theme_color_override("font_color", clr_blue)
	sec_tenancy_details.add_child(hdr_tenancy_details)
	var sep_tenancy_details := HSeparator.new()
	sec_tenancy_details.add_child(sep_tenancy_details)
	add_child(sec_tenancy_details)

	var row_door_num := HBoxContainer.new()
	row_door_num.name = "door_num"
	row_door_num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_door_num := Label.new()
	lbl_door_num.text = tr("UI_LBL_DOOR_NUMBER")
	lbl_door_num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_door_num.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_door_num.add_theme_font_override("font", mono_font)
	lbl_door_num.add_theme_color_override("font_color", clr_muted)
	row_door_num.add_child(lbl_door_num)
	var val_door_num := Label.new()
	val_door_num.name = "door_num_value"
	val_door_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_door_num.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_door_num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_door_num.add_theme_font_override("font", mono_font)
	val_door_num.add_theme_color_override("font_color", clr_black)
	row_door_num.add_child(val_door_num)
	_value_labels["door_num"] = val_door_num
	add_child(row_door_num)

	var row_ward := HBoxContainer.new()
	row_ward.name = "ward"
	row_ward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_ward := Label.new()
	lbl_ward.text = tr("UI_LBL_DISTRICT_WARD")
	lbl_ward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_ward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_ward.add_theme_font_override("font", mono_font)
	lbl_ward.add_theme_color_override("font_color", clr_muted)
	row_ward.add_child(lbl_ward)
	var val_ward := Label.new()
	val_ward.name = "ward_value"
	val_ward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_ward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_ward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_ward.add_theme_font_override("font", mono_font)
	val_ward.add_theme_color_override("font_color", clr_black)
	row_ward.add_child(val_ward)
	_value_labels["ward"] = val_ward
	add_child(row_ward)

	var row_local_pub := HBoxContainer.new()
	row_local_pub.name = "local_pub"
	row_local_pub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_local_pub := Label.new()
	lbl_local_pub.text = tr("UI_LBL_LOCAL_TAPROOM")
	lbl_local_pub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_local_pub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_local_pub.add_theme_font_override("font", mono_font)
	lbl_local_pub.add_theme_color_override("font_color", clr_muted)
	row_local_pub.add_child(lbl_local_pub)
	var val_local_pub := Label.new()
	val_local_pub.name = "local_pub_value"
	val_local_pub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_local_pub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_local_pub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_local_pub.add_theme_font_override("font", mono_font)
	val_local_pub.add_theme_color_override("font_color", clr_black)
	row_local_pub.add_child(val_local_pub)
	_value_labels["local_pub"] = val_local_pub
	add_child(row_local_pub)

	# --- Section: residents_roster ---
	var sec_residents_roster := VBoxContainer.new()
	sec_residents_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_residents_roster.add_theme_constant_override("separation", 2)
	var hdr_residents_roster := Label.new()
	hdr_residents_roster.text = "[ " + tr("UI_HDR_HOUSEHOLD_RESIDENTS").to_upper() + " ]"
	hdr_residents_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_residents_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_residents_roster.add_theme_font_override("font", mono_font)
	hdr_residents_roster.add_theme_color_override("font_color", clr_blue)
	sec_residents_roster.add_child(hdr_residents_roster)
	var sep_residents_roster := HSeparator.new()
	sec_residents_roster.add_child(sep_residents_roster)
	add_child(sec_residents_roster)

	var list_occupants_list := ItemList.new()
	list_occupants_list.name = "occupants_list"
	list_occupants_list.custom_minimum_size = Vector2(0, 120)
	list_occupants_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_occupants_list.add_theme_font_override("font", mono_font)
	_value_labels["occupants_list"] = list_occupants_list
	add_child(list_occupants_list)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("tenancy_header_title"):
		if data.has("name") and data["name"] != null:
			_value_labels["tenancy_header_title"].text = str(data["name"]).to_upper()
		else:
			_value_labels["tenancy_header_title"].text = "--- UNNAMED ---"
	if _value_labels.has("tenancy_header_subtitle"):
		if data.has("residence_type") and data["residence_type"] != null:
			_value_labels["tenancy_header_subtitle"].text = str(data["residence_type"]).to_upper()
		else:
			_value_labels["tenancy_header_subtitle"].text = ""
	if _value_labels.has("door_num"):
		var ctrl = _value_labels["door_num"]
		if not data.has("unit_door_number") or data["unit_door_number"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["unit_door_number"]) + ""
	if _value_labels.has("ward"):
		var ctrl = _value_labels["ward"]
		if not data.has("district_name") or data["district_name"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["district_name"]) + ""
	if _value_labels.has("local_pub"):
		var ctrl = _value_labels["local_pub"]
		if not data.has("local_pub_name") or data["local_pub_name"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["local_pub_name"]) + ""
	if _value_labels.has("occupants_list"):
		var ctrl = _value_labels["occupants_list"]
		if ctrl is ItemList:
			ctrl.clear()
			if data.has("residents_summary") and data["residents_summary"] is Array:
				var items: Array = data["residents_summary"]
				for item in items:
					ctrl.add_item(str(item))
