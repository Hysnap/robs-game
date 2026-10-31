# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/district_docket.json
class_name GenDistrictDocket
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

	# --- Section: intel_status_header ---
	var sec_intel_status_header := VBoxContainer.new()
	sec_intel_status_header.add_theme_constant_override("separation", 2)
	var hdr_intel_status_header := Label.new()
	hdr_intel_status_header.text = "[ " + tr("UI_HDR_SURVEY_INTELLIGENCE").to_upper() + " ]"
	hdr_intel_status_header.add_theme_font_override("font", mono_font)
	hdr_intel_status_header.add_theme_color_override("font_color", clr_blue)
	sec_intel_status_header.add_child(hdr_intel_status_header)
	var sep_intel_status_header := HSeparator.new()
	sec_intel_status_header.add_child(sep_intel_status_header)
	add_child(sec_intel_status_header)

	var badge_survey_badge := PanelContainer.new()
	badge_survey_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_survey_badge := Label.new()
	val_survey_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_survey_badge.add_theme_font_override("font", mono_font)
	val_survey_badge.add_theme_color_override("font_color", clr_blue)
	badge_survey_badge.add_child(val_survey_badge)
	_value_labels["survey_badge"] = val_survey_badge
	add_child(badge_survey_badge)

	# --- Section: demographics_overview ---
	var sec_demographics_overview := VBoxContainer.new()
	sec_demographics_overview.add_theme_constant_override("separation", 2)
	var hdr_demographics_overview := Label.new()
	hdr_demographics_overview.text = "[ " + tr("UI_HDR_WARD_DEMOGRAPHICS").to_upper() + " ]"
	hdr_demographics_overview.add_theme_font_override("font", mono_font)
	hdr_demographics_overview.add_theme_color_override("font_color", clr_blue)
	sec_demographics_overview.add_child(hdr_demographics_overview)
	var sep_demographics_overview := HSeparator.new()
	sec_demographics_overview.add_child(sep_demographics_overview)
	add_child(sec_demographics_overview)

	var row_pop := HBoxContainer.new()
	row_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_pop := Label.new()
	lbl_pop.text = tr("UI_LBL_ACTIVE_POPULATION")
	lbl_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_pop.add_theme_font_override("font", mono_font)
	lbl_pop.add_theme_color_override("font_color", clr_muted)
	row_pop.add_child(lbl_pop)
	var val_pop := Label.new()
	val_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_pop.add_theme_font_override("font", mono_font)
	val_pop.add_theme_color_override("font_color", clr_black)
	row_pop.add_child(val_pop)
	_value_labels["pop"] = val_pop
	add_child(row_pop)

	var row_households := HBoxContainer.new()
	row_households.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_households := Label.new()
	lbl_households.text = tr("UI_LBL_TOTAL_HOUSEHOLDS")
	lbl_households.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_households.add_theme_font_override("font", mono_font)
	lbl_households.add_theme_color_override("font_color", clr_muted)
	row_households.add_child(lbl_households)
	var val_households := Label.new()
	val_households.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_households.add_theme_font_override("font", mono_font)
	val_households.add_theme_color_override("font_color", clr_black)
	row_households.add_child(val_households)
	_value_labels["households"] = val_households
	add_child(row_households)

	var row_unemployment_tier := HBoxContainer.new()
	row_unemployment_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_unemployment_tier := Label.new()
	lbl_unemployment_tier.text = tr("UI_LBL_UNEMPLOYMENT_TIER")
	lbl_unemployment_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_unemployment_tier.add_theme_font_override("font", mono_font)
	lbl_unemployment_tier.add_theme_color_override("font_color", clr_muted)
	row_unemployment_tier.add_child(lbl_unemployment_tier)
	var val_unemployment_tier := Label.new()
	val_unemployment_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_unemployment_tier.add_theme_font_override("font", mono_font)
	val_unemployment_tier.add_theme_color_override("font_color", clr_black)
	row_unemployment_tier.add_child(val_unemployment_tier)
	_value_labels["unemployment_tier"] = val_unemployment_tier
	add_child(row_unemployment_tier)

	var row_income := HBoxContainer.new()
	row_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_income := Label.new()
	lbl_income.text = tr("UI_LBL_DISPOSABLE_INCOME")
	lbl_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_income.add_theme_font_override("font", mono_font)
	lbl_income.add_theme_color_override("font_color", clr_muted)
	row_income.add_child(lbl_income)
	var val_income := Label.new()
	val_income.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_income.add_theme_font_override("font", mono_font)
	val_income.add_theme_color_override("font_color", clr_black)
	row_income.add_child(val_income)
	_value_labels["income"] = val_income
	add_child(row_income)

	# --- Section: civic_infrastructure ---
	var sec_civic_infrastructure := VBoxContainer.new()
	sec_civic_infrastructure.add_theme_constant_override("separation", 2)
	var hdr_civic_infrastructure := Label.new()
	hdr_civic_infrastructure.text = "[ " + tr("UI_HDR_CIVIC_FEATURES").to_upper() + " ]"
	hdr_civic_infrastructure.add_theme_font_override("font", mono_font)
	hdr_civic_infrastructure.add_theme_color_override("font_color", clr_blue)
	sec_civic_infrastructure.add_child(hdr_civic_infrastructure)
	var sep_civic_infrastructure := HSeparator.new()
	sec_civic_infrastructure.add_child(sep_civic_infrastructure)
	add_child(sec_civic_infrastructure)

	var civic_box_civic_features := VBoxContainer.new()
	civic_box_civic_features.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_civic_features.add_theme_constant_override("separation", 2)
	_value_labels["civic_features"] = civic_box_civic_features
	add_child(civic_box_civic_features)

	# --- Section: security_environment ---
	var sec_security_environment := VBoxContainer.new()
	sec_security_environment.add_theme_constant_override("separation", 2)
	var hdr_security_environment := Label.new()
	hdr_security_environment.text = "[ " + tr("UI_HDR_SECURITY_ENVIRONMENT").to_upper() + " ]"
	hdr_security_environment.add_theme_font_override("font", mono_font)
	hdr_security_environment.add_theme_color_override("font_color", clr_blue)
	sec_security_environment.add_child(hdr_security_environment)
	var sep_security_environment := HSeparator.new()
	sec_security_environment.add_child(sep_security_environment)
	add_child(sec_security_environment)

	var row_zhi := HBoxContainer.new()
	row_zhi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_zhi := Label.new()
	lbl_zhi.text = tr("UI_LBL_ZONE_HEALTH")
	lbl_zhi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_zhi.add_theme_font_override("font", mono_font)
	lbl_zhi.add_theme_color_override("font_color", clr_muted)
	row_zhi.add_child(lbl_zhi)
	var val_zhi := Label.new()
	val_zhi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_zhi.add_theme_font_override("font", mono_font)
	val_zhi.add_theme_color_override("font_color", clr_black)
	row_zhi.add_child(val_zhi)
	_value_labels["zhi"] = val_zhi
	add_child(row_zhi)

	var row_heat := HBoxContainer.new()
	row_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_heat := Label.new()
	lbl_heat.text = tr("UI_LBL_POLICE_HEAT")
	lbl_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_heat.add_theme_font_override("font", mono_font)
	lbl_heat.add_theme_color_override("font_color", clr_muted)
	row_heat.add_child(lbl_heat)
	var val_heat := Label.new()
	val_heat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_heat.add_theme_font_override("font", mono_font)
	val_heat.add_theme_color_override("font_color", clr_black)
	row_heat.add_child(val_heat)
	_value_labels["heat"] = val_heat
	add_child(row_heat)

	# --- Inscriptions Container ---
	var hdr_insc := Label.new()
	hdr_insc.text = "[ " + tr("UI_SEC_FIELD_OBSERVATIONS").to_upper() + " ]"
	hdr_insc.add_theme_font_override("font", mono_font)
	hdr_insc.add_theme_color_override("font_color", clr_blue)
	add_child(hdr_insc)
	var insc_list := VBoxContainer.new()
	insc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["__inscriptions__"] = insc_list
	add_child(insc_list)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("survey_badge") and data.has("intel_status_token"):
		var ctrl = _value_labels["survey_badge"]
		if data["intel_status_token"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = tr(str(data["intel_status_token"])) + ""
	if _value_labels.has("pop") and data.has("active_population"):
		var ctrl = _value_labels["pop"]
		if data["active_population"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(int(data["active_population"])) + " citizens"
	if _value_labels.has("households") and data.has("total_households"):
		var ctrl = _value_labels["households"]
		if data["total_households"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = str(int(data["total_households"])) + " households"
	if _value_labels.has("unemployment_tier") and data.has("unemployment_semantic_token"):
		var ctrl = _value_labels["unemployment_tier"]
		if data["unemployment_semantic_token"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = tr(str(data["unemployment_semantic_token"])) + ""
	if _value_labels.has("income") and data.has("avg_disposable_income"):
		var ctrl = _value_labels["income"]
		if data["avg_disposable_income"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var num_str := String.num(float(data["avg_disposable_income"]), 2)
			ctrl.text = tr("FMT_CURRENCY").replace("{val}", num_str) + " / wk"
	if _value_labels.has("civic_features") and data.has("civic_features_list"):
		var ctrl = _value_labels["civic_features"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.queue_free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var features: Array = data.get("civic_features_list", [])
			if features.is_empty():
				var empty_lbl := Label.new()
				empty_lbl.text = tr("UI_INTEL_MASKED_BLANK")
				empty_lbl.add_theme_font_override("font", RETRO_THEME.get_monospace_font())
				empty_lbl.add_theme_color_override("font_color", clr_m)
				ctrl.add_child(empty_lbl)
			else:
				for f in features:
					var f_lbl := Label.new()
					f_lbl.text = "• " + str(f)
					f_lbl.add_theme_font_override("font", RETRO_THEME.get_monospace_font())
					f_lbl.add_theme_color_override("font_color", clr_b)
					ctrl.add_child(f_lbl)
	if _value_labels.has("zhi") and data.has("zone_health_index"):
		var ctrl = _value_labels["zhi"]
		if data["zone_health_index"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			ctrl.text = String.num(float(data["zone_health_index"]), 1) + " / 100"
	if _value_labels.has("heat") and data.has("actual_police_heat"):
		var ctrl = _value_labels["heat"]
		if data["actual_police_heat"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var pct_str := String.num(float(data["actual_police_heat"]) * 100.0, 1)
			ctrl.text = tr("FMT_PERCENT").replace("{val}", pct_str) + ""
