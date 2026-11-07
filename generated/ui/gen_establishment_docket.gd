# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/establishment_docket.json
class_name GenEstablishmentDocket
extends VBoxContainer

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
	btn_btn_back.pressed.connect(func(): self.route_requested.emit("DOSSIER", ""))
	_value_labels["btn_back"] = btn_btn_back
	add_child(btn_btn_back)

	# --- Header Block ---
	var box_estab_header := VBoxContainer.new()
	box_estab_header.name = "estab_header"
	box_estab_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_estab_header.add_theme_constant_override("separation", 0)
	var title_estab_header := Label.new()
	title_estab_header.name = "estab_header_title"
	title_estab_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_estab_header.theme_type_variation = &"HeaderTitle"
	title_estab_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_estab_header.add_child(title_estab_header)
	_value_labels["estab_header_title"] = title_estab_header
	var sub_estab_header := Label.new()
	sub_estab_header.name = "estab_header_subtitle"
	sub_estab_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_estab_header.theme_type_variation = &"HeaderSubtitle"
	sub_estab_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_estab_header.add_child(sub_estab_header)
	_value_labels["estab_header_subtitle"] = sub_estab_header
	box_estab_header.add_child(HSeparator.new())
	add_child(box_estab_header)

	# --- Section: location_and_scale ---
	var sec_location_and_scale := VBoxContainer.new()
	sec_location_and_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_location_and_scale.add_theme_constant_override("separation", 2)
	var hdr_location_and_scale := Label.new()
	hdr_location_and_scale.text = "[ " + tr("UI_HDR_VENUE_LOCATION").to_upper() + " ]"
	hdr_location_and_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_location_and_scale.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_location_and_scale.add_theme_font_override("font", mono_font)
	hdr_location_and_scale.add_theme_color_override("font_color", clr_blue)
	sec_location_and_scale.add_child(hdr_location_and_scale)
	var sep_location_and_scale := HSeparator.new()
	sec_location_and_scale.add_child(sep_location_and_scale)
	add_child(sec_location_and_scale)

	var row_ward := HBoxContainer.new()
	row_ward.name = "ward"
	row_ward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_ward := Label.new()
	lbl_ward.text = tr("UI_LBL_DISTRICT_WARD")
	lbl_ward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_ward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_ward.add_child(lbl_ward)
	var val_ward := Label.new()
	val_ward.name = "ward_value"
	val_ward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_ward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_ward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_ward.add_child(val_ward)
	_value_labels["ward"] = val_ward
	add_child(row_ward)

	var row_capacity := HBoxContainer.new()
	row_capacity.name = "capacity"
	row_capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_capacity := Label.new()
	lbl_capacity.text = tr("UI_LBL_VENUE_CAPACITY")
	lbl_capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_capacity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_capacity.add_child(lbl_capacity)
	var val_capacity := Label.new()
	val_capacity.name = "capacity_value"
	val_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_capacity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_capacity.add_child(val_capacity)
	_value_labels["capacity"] = val_capacity
	add_child(row_capacity)

	# --- Section: catchment_overview ---
	var sec_catchment_overview := VBoxContainer.new()
	sec_catchment_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_catchment_overview.add_theme_constant_override("separation", 2)
	var hdr_catchment_overview := Label.new()
	hdr_catchment_overview.text = "[ " + tr("UI_HDR_MARKET_CATCHMENT").to_upper() + " ]"
	hdr_catchment_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_catchment_overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_catchment_overview.add_theme_font_override("font", mono_font)
	hdr_catchment_overview.add_theme_color_override("font_color", clr_blue)
	sec_catchment_overview.add_child(hdr_catchment_overview)
	var sep_catchment_overview := HSeparator.new()
	sec_catchment_overview.add_child(sep_catchment_overview)
	add_child(sec_catchment_overview)

	var row_catchment_pop := HBoxContainer.new()
	row_catchment_pop.name = "catchment_pop"
	row_catchment_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_catchment_pop := Label.new()
	lbl_catchment_pop.text = tr("UI_LBL_CATCHMENT_POPULATION")
	lbl_catchment_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_catchment_pop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_catchment_pop.add_child(lbl_catchment_pop)
	var val_catchment_pop := Label.new()
	val_catchment_pop.name = "catchment_pop_value"
	val_catchment_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_catchment_pop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_catchment_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_catchment_pop.add_child(val_catchment_pop)
	_value_labels["catchment_pop"] = val_catchment_pop
	add_child(row_catchment_pop)

	var row_catchment_hh := HBoxContainer.new()
	row_catchment_hh.name = "catchment_hh"
	row_catchment_hh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_catchment_hh := Label.new()
	lbl_catchment_hh.text = tr("UI_LBL_CATCHMENT_HOUSEHOLDS")
	lbl_catchment_hh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_catchment_hh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_catchment_hh.add_child(lbl_catchment_hh)
	var val_catchment_hh := Label.new()
	val_catchment_hh.name = "catchment_hh_value"
	val_catchment_hh.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_catchment_hh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_catchment_hh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_catchment_hh.add_child(val_catchment_hh)
	_value_labels["catchment_hh"] = val_catchment_hh
	add_child(row_catchment_hh)

	var row_catchment_income := HBoxContainer.new()
	row_catchment_income.name = "catchment_income"
	row_catchment_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_catchment_income := Label.new()
	lbl_catchment_income.text = tr("UI_LBL_NEIGHBORHOOD_INCOME")
	lbl_catchment_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_catchment_income.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_catchment_income.add_child(lbl_catchment_income)
	var val_catchment_income := Label.new()
	val_catchment_income.name = "catchment_income_value"
	val_catchment_income.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_catchment_income.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_catchment_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_catchment_income.add_child(val_catchment_income)
	_value_labels["catchment_income"] = val_catchment_income
	add_child(row_catchment_income)

	# --- Section: personnel_overview ---
	var sec_personnel_overview := VBoxContainer.new()
	sec_personnel_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_personnel_overview.add_theme_constant_override("separation", 2)
	var hdr_personnel_overview := Label.new()
	hdr_personnel_overview.text = "[ " + tr("UI_HDR_ACTIVE_CONTRACTS").to_upper() + " ]"
	hdr_personnel_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_personnel_overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_personnel_overview.add_theme_font_override("font", mono_font)
	hdr_personnel_overview.add_theme_color_override("font_color", clr_blue)
	sec_personnel_overview.add_child(hdr_personnel_overview)
	var sep_personnel_overview := HSeparator.new()
	sec_personnel_overview.add_child(sep_personnel_overview)
	add_child(sec_personnel_overview)

	var list_personnel_list := ItemList.new()
	list_personnel_list.name = "personnel_list"
	list_personnel_list.custom_minimum_size = Vector2(0, 100)
	list_personnel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["personnel_list"] = list_personnel_list
	add_child(list_personnel_list)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("estab_header_title"):
		if data.has("name") and data["name"] != null:
			_value_labels["estab_header_title"].text = str(data["name"]).to_upper()
		else:
			_value_labels["estab_header_title"].text = "--- UNNAMED ---"
	if _value_labels.has("estab_header_subtitle"):
		if data.has("category_title") and data["category_title"] != null:
			_value_labels["estab_header_subtitle"].text = str(data["category_title"]).to_upper()
		else:
			_value_labels["estab_header_subtitle"].text = ""
	if _value_labels.has("ward"):
		var ctrl = _value_labels["ward"]
		if not data.has("district_name") or data["district_name"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(data["district_name"]) + ""
	if _value_labels.has("capacity"):
		var ctrl = _value_labels["capacity"]
		if not data.has("capacity") or data["capacity"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["capacity"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + ""
	if _value_labels.has("catchment_pop"):
		var ctrl = _value_labels["catchment_pop"]
		if not data.has("total_catchment_population") or data["total_catchment_population"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["total_catchment_population"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + ""
	if _value_labels.has("catchment_hh"):
		var ctrl = _value_labels["catchment_hh"]
		if not data.has("total_catchment_households") or data["total_catchment_households"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["total_catchment_households"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + ""
	if _value_labels.has("catchment_income"):
		var ctrl = _value_labels["catchment_income"]
		if not data.has("avg_neighbor_disposable_income") or data["avg_neighbor_disposable_income"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := "%.2f" % float(data["avg_neighbor_disposable_income"])
			ctrl.text = tr("FMT_CURRENCY").replace("{val}", val_str) + ""
	if _value_labels.has("personnel_list"):
		var ctrl = _value_labels["personnel_list"]
		if ctrl is ItemList:
			ctrl.clear()
			if data.has("personnel_summary") and data["personnel_summary"] is Array:
				var items: Array = data["personnel_summary"]
				for item in items:
					ctrl.add_item(str(item))
