# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/street_residences_docket.json
extends VBoxContainer

signal action_clicked(action_code: String, payload: Dictionary)
signal item_selected(target_route, filter_key)

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
	btn_btn_back.pressed.connect(func(): self.action_clicked.emit("open_dossier", {}))
	_value_labels["btn_back"] = btn_btn_back
	add_child(btn_btn_back)

	# --- Header Block ---
	var box_street_header := VBoxContainer.new()
	box_street_header.name = "street_header"
	box_street_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_street_header.add_theme_constant_override("separation", 0)
	var title_street_header := Label.new()
	title_street_header.name = "street_header_title"
	title_street_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_street_header.theme_type_variation = &"HeaderTitle"
	title_street_header.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	title_street_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_street_header.add_child(title_street_header)
	_value_labels["street_header_title"] = title_street_header
	var sub_street_header := Label.new()
	sub_street_header.name = "street_header_subtitle"
	sub_street_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_street_header.theme_type_variation = &"HeaderSubtitle"
	sub_street_header.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	sub_street_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_street_header.add_child(sub_street_header)
	_value_labels["street_header_subtitle"] = sub_street_header
	box_street_header.add_child(HSeparator.new())
	add_child(box_street_header)

	# --- Section: units_directory ---
	var sec_units_directory := VBoxContainer.new()
	sec_units_directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_units_directory.add_theme_constant_override("separation", 2)
	var hdr_units_directory := Label.new()
	hdr_units_directory.text = "[ " + tr("UI_HDR_STREET_PROPERTIES").to_upper() + " ]"
	hdr_units_directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_units_directory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_units_directory.add_theme_font_override("font", mono_font)
	hdr_units_directory.add_theme_color_override("font_color", clr_blue)
	sec_units_directory.add_child(hdr_units_directory)
	var sep_units_directory := HSeparator.new()
	sec_units_directory.add_child(sep_units_directory)
	add_child(sec_units_directory)

	var civic_box_street_units := VBoxContainer.new()
	civic_box_street_units.name = "street_units"
	civic_box_street_units.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_street_units.add_theme_constant_override("separation", 2)
	_value_labels["street_units"] = civic_box_street_units
	add_child(civic_box_street_units)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("street_header_title"):
		if data.has("street_name") and data["street_name"] != null:
			_value_labels["street_header_title"].text = str(data["street_name"]).to_upper()
		else:
			_value_labels["street_header_title"].text = "--- UNNAMED ---"
	if _value_labels.has("street_header_subtitle"):
		if data.has("district_name") and data["district_name"] != null:
			_value_labels["street_header_subtitle"].text = str(data["district_name"]).to_upper()
		else:
			_value_labels["street_header_subtitle"].text = ""
	if _value_labels.has("street_units"):
		var ctrl = _value_labels["street_units"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var mono_f: Font = RETRO_THEME.get_monospace_font()
			var items: Array = data.get("units_summary", [])
			if items.is_empty():
				pass
			else:
				for item in items:
					assert(item is Dictionary, "[UI CONTRACT ERROR] Expected Dictionary in list payload for: units_summary")
					assert(item.has("establishment_id"), "[UI CONTRACT ERROR] Missing required key 'establishment_id' in item: " + str(item))
					var key_val = item["establishment_id"]
					var main_txt: String = str(item.get("unit_door_number", "Unnamed"))
					var sub_txt: String = str(item.get("occupant_summary", ""))
					var display_txt: String = "• " + main_txt
					if not sub_txt.is_empty():
						display_txt += " (" + sub_txt + ")"
					var btn := Button.new()
					btn.text = display_txt
					btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
					btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					btn.add_theme_font_override("font", mono_f)
					btn.add_theme_font_size_override("font_size", 11)
					btn.add_theme_color_override("font_color", clr_b)
					btn.pressed.connect(func(): item_selected.emit("OPEN_RESIDENTIAL_DOCKET", key_val))
					ctrl.add_child(btn)
