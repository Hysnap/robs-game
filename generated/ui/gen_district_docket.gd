# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/district_docket.json
class_name GenDistrictDocket
extends VBoxContainer

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

	# --- Header Block ---
	var box_docket_header := VBoxContainer.new()
	box_docket_header.name = "docket_header"
	box_docket_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_docket_header.add_theme_constant_override("separation", 0)
	var title_docket_header := Label.new()
	title_docket_header.name = "docket_header_title"
	title_docket_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_docket_header.theme_type_variation = &"HeaderTitle"
	title_docket_header.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	title_docket_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_docket_header.add_child(title_docket_header)
	_value_labels["docket_header_title"] = title_docket_header
	var sub_docket_header := Label.new()
	sub_docket_header.name = "docket_header_subtitle"
	sub_docket_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_docket_header.theme_type_variation = &"HeaderSubtitle"
	sub_docket_header.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	sub_docket_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_docket_header.add_child(sub_docket_header)
	_value_labels["docket_header_subtitle"] = sub_docket_header
	box_docket_header.add_child(HSeparator.new())
	add_child(box_docket_header)

	# --- Section: intel_status_header ---
	var sec_intel_status_header := VBoxContainer.new()
	sec_intel_status_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_intel_status_header.add_theme_constant_override("separation", 2)
	var hdr_intel_status_header := Label.new()
	hdr_intel_status_header.text = "[ " + tr("UI_HDR_SURVEY_INTELLIGENCE").to_upper() + " ]"
	hdr_intel_status_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_intel_status_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_intel_status_header.add_theme_font_override("font", mono_font)
	hdr_intel_status_header.add_theme_color_override("font_color", clr_blue)
	sec_intel_status_header.add_child(hdr_intel_status_header)
	var sep_intel_status_header := HSeparator.new()
	sec_intel_status_header.add_child(sep_intel_status_header)
	add_child(sec_intel_status_header)

	var badge_survey_badge := PanelContainer.new()
	badge_survey_badge.name = "survey_badge"
	badge_survey_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_survey_badge := Label.new()
	val_survey_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_survey_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_survey_badge.theme_type_variation = &"BadgeStatus"
	val_survey_badge.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_survey_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge_survey_badge.add_child(val_survey_badge)
	_value_labels["survey_badge"] = val_survey_badge
	add_child(badge_survey_badge)

	# --- Section: demographics_overview ---
	var sec_demographics_overview := VBoxContainer.new()
	sec_demographics_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_demographics_overview.add_theme_constant_override("separation", 2)
	var hdr_demographics_overview := Label.new()
	hdr_demographics_overview.text = "[ " + tr("UI_HDR_WARD_DEMOGRAPHICS").to_upper() + " ]"
	hdr_demographics_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_demographics_overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_demographics_overview.add_theme_font_override("font", mono_font)
	hdr_demographics_overview.add_theme_color_override("font_color", clr_blue)
	sec_demographics_overview.add_child(hdr_demographics_overview)
	var sep_demographics_overview := HSeparator.new()
	sec_demographics_overview.add_child(sep_demographics_overview)
	add_child(sec_demographics_overview)

	var row_pop := HBoxContainer.new()
	row_pop.name = "pop"
	row_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_pop := Label.new()
	lbl_pop.text = tr("UI_LBL_ACTIVE_POPULATION")
	lbl_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_pop.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_pop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_pop.add_child(lbl_pop)
	var val_pop := Label.new()
	val_pop.name = "pop_value"
	val_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_pop.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_pop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_pop.add_child(val_pop)
	_value_labels["pop"] = val_pop
	add_child(row_pop)

	var row_households := HBoxContainer.new()
	row_households.name = "households"
	row_households.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_households := Label.new()
	lbl_households.text = tr("UI_LBL_TOTAL_HOUSEHOLDS")
	lbl_households.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_households.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_households.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_households.add_child(lbl_households)
	var val_households := Label.new()
	val_households.name = "households_value"
	val_households.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_households.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_households.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_households.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_households.add_child(val_households)
	_value_labels["households"] = val_households
	add_child(row_households)

	var row_unemployment_tier := HBoxContainer.new()
	row_unemployment_tier.name = "unemployment_tier"
	row_unemployment_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_unemployment_tier := Label.new()
	lbl_unemployment_tier.text = tr("UI_LBL_UNEMPLOYMENT_TIER")
	lbl_unemployment_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_unemployment_tier.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_unemployment_tier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_unemployment_tier.add_child(lbl_unemployment_tier)
	var val_unemployment_tier := Label.new()
	val_unemployment_tier.name = "unemployment_tier_value"
	val_unemployment_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_unemployment_tier.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_unemployment_tier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_unemployment_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_unemployment_tier.add_child(val_unemployment_tier)
	_value_labels["unemployment_tier"] = val_unemployment_tier
	add_child(row_unemployment_tier)

	var row_income := HBoxContainer.new()
	row_income.name = "income"
	row_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_income := Label.new()
	lbl_income.text = tr("UI_LBL_DISPOSABLE_INCOME")
	lbl_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_income.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_income.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_income.add_child(lbl_income)
	var val_income := Label.new()
	val_income.name = "income_value"
	val_income.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_income.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_income.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_income.add_child(val_income)
	_value_labels["income"] = val_income
	add_child(row_income)

	# --- Section: civic_infrastructure ---
	var sec_civic_infrastructure := VBoxContainer.new()
	sec_civic_infrastructure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_civic_infrastructure.add_theme_constant_override("separation", 2)
	var hdr_civic_infrastructure := Label.new()
	hdr_civic_infrastructure.text = "[ " + tr("UI_HDR_CIVIC_FEATURES").to_upper() + " ]"
	hdr_civic_infrastructure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_civic_infrastructure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_civic_infrastructure.add_theme_font_override("font", mono_font)
	hdr_civic_infrastructure.add_theme_color_override("font_color", clr_blue)
	sec_civic_infrastructure.add_child(hdr_civic_infrastructure)
	var sep_civic_infrastructure := HSeparator.new()
	sec_civic_infrastructure.add_child(sep_civic_infrastructure)
	add_child(sec_civic_infrastructure)

	var civic_box_civic_features := VBoxContainer.new()
	civic_box_civic_features.name = "civic_features"
	civic_box_civic_features.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_civic_features.add_theme_constant_override("separation", 2)
	_value_labels["civic_features"] = civic_box_civic_features
	add_child(civic_box_civic_features)

	# --- Section: security_environment ---
	var sec_security_environment := VBoxContainer.new()
	sec_security_environment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_security_environment.add_theme_constant_override("separation", 2)
	var hdr_security_environment := Label.new()
	hdr_security_environment.text = "[ " + tr("UI_HDR_SECURITY_ENVIRONMENT").to_upper() + " ]"
	hdr_security_environment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_security_environment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_security_environment.add_theme_font_override("font", mono_font)
	hdr_security_environment.add_theme_color_override("font_color", clr_blue)
	sec_security_environment.add_child(hdr_security_environment)
	var sep_security_environment := HSeparator.new()
	sec_security_environment.add_child(sep_security_environment)
	add_child(sec_security_environment)

	var row_zhi := HBoxContainer.new()
	row_zhi.name = "zhi"
	row_zhi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_zhi := Label.new()
	lbl_zhi.text = tr("UI_LBL_ZONE_HEALTH")
	lbl_zhi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_zhi.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_zhi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_zhi.add_child(lbl_zhi)
	var val_zhi := Label.new()
	val_zhi.name = "zhi_value"
	val_zhi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_zhi.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_zhi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_zhi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_zhi.add_child(val_zhi)
	_value_labels["zhi"] = val_zhi
	add_child(row_zhi)

	var row_heat := HBoxContainer.new()
	row_heat.name = "heat"
	row_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_heat := Label.new()
	lbl_heat.text = tr("UI_LBL_POLICE_HEAT")
	lbl_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_heat.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_heat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_heat.add_child(lbl_heat)
	var val_heat := Label.new()
	val_heat.name = "heat_value"
	val_heat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_heat.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_heat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_heat.add_child(val_heat)
	_value_labels["heat"] = val_heat
	add_child(row_heat)

	# --- Section: field_observations ---
	var sec_field_observations := VBoxContainer.new()
	sec_field_observations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_field_observations.add_theme_constant_override("separation", 2)
	var hdr_field_observations := Label.new()
	hdr_field_observations.text = "[ " + tr("UI_SEC_FIELD_OBSERVATIONS").to_upper() + " ]"
	hdr_field_observations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_field_observations.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_field_observations.add_theme_font_override("font", mono_font)
	hdr_field_observations.add_theme_color_override("font_color", clr_blue)
	sec_field_observations.add_child(hdr_field_observations)
	var sep_field_observations := HSeparator.new()
	sec_field_observations.add_child(sep_field_observations)
	add_child(sec_field_observations)

	# --- Inscriptions Container ---
	var insc_box_observations_box := VBoxContainer.new()
	insc_box_observations_box.name = "observations_box"
	insc_box_observations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["__inscriptions__"] = insc_box_observations_box
	add_child(insc_box_observations_box)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("docket_header_title"):
		if data.has("display_name") and data["display_name"] != null:
			_value_labels["docket_header_title"].text = str(data["display_name"]).to_upper()
		else:
			_value_labels["docket_header_title"].text = "--- UNNAMED ---"
	if _value_labels.has("docket_header_subtitle"):
		if data.has("type_title") and data["type_title"] != null:
			_value_labels["docket_header_subtitle"].text = str(data["type_title"]).to_upper()
		else:
			_value_labels["docket_header_subtitle"].text = ""
	if _value_labels.has("survey_badge"):
		var ctrl = _value_labels["survey_badge"]
		if not data.has("intel_status_token") or data["intel_status_token"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = tr(str(data["intel_status_token"])) + ""
	if _value_labels.has("pop"):
		var ctrl = _value_labels["pop"]
		if not data.has("active_population") or data["active_population"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["active_population"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + " citizens"
	if _value_labels.has("households"):
		var ctrl = _value_labels["households"]
		if not data.has("total_households") or data["total_households"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["total_households"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + " households"
	if _value_labels.has("unemployment_tier"):
		var ctrl = _value_labels["unemployment_tier"]
		if not data.has("unemployment_bucket_token") or data["unemployment_bucket_token"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = tr(str(data["unemployment_bucket_token"])) + ""
	if _value_labels.has("income"):
		var ctrl = _value_labels["income"]
		if not data.has("income_bucket_token") or data["income_bucket_token"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = tr(str(data["income_bucket_token"])) + ""
	if _value_labels.has("civic_features"):
		var ctrl = _value_labels["civic_features"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var mono_f: Font = RETRO_THEME.get_monospace_font()
			var items: Array = data.get("establishments_summary", [])
			if items.is_empty():
				pass
			else:
				for item in items:
					assert(item is Dictionary, "[UI CONTRACT ERROR] Expected Dictionary in list payload for: establishments_summary")
					assert(item.has("establishment_id"), "[UI CONTRACT ERROR] Missing required key 'establishment_id' in item: " + str(item))
					var key_val = item["establishment_id"]
					var main_txt: String = str(item.get("name", "Unnamed"))
					var sub_txt: String = str(item.get("category_title", ""))
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
					var dest_route: String = str(item.get("detail_route", "ESTABLISHMENT_DOCKET"))
					if dest_route.is_empty():
						dest_route = "ESTABLISHMENT_DOCKET"
					btn.pressed.connect(func(): item_selected.emit(dest_route, key_val))
					ctrl.add_child(btn)
	if _value_labels.has("zhi"):
		var ctrl = _value_labels["zhi"]
		if not data.has("zone_health_bucket_token") or data["zone_health_bucket_token"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = tr(str(data["zone_health_bucket_token"])) + ""
	if _value_labels.has("heat"):
		var ctrl = _value_labels["heat"]
		if not data.has("heat_bucket_token") or data["heat_bucket_token"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = tr(str(data["heat_bucket_token"])) + ""

func inscribe_entry(entry: Dictionary) -> void:
	if not _value_labels.has("__inscriptions__") and not _value_labels.has("observations_box"):
		return
	var target_box = _value_labels.get("__inscriptions__", _value_labels.get("observations_box"))
	if not target_box is Container:
		return
	var author: String = str(entry.get("author", ""))
	var text_content: String = str(entry.get("text", ""))
	var note_lbl := Label.new()
	if not author.is_empty():
		note_lbl.text = "[" + author + "] " + text_content
	else:
		note_lbl.text = text_content
	note_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.add_theme_font_override("font", RETRO_THEME.get_monospace_font())
	note_lbl.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	target_box.add_child(note_lbl)
