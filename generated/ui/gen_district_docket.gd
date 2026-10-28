# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/district_docket.json
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

	# --- Section: demographics ---
	var sec_demographics := VBoxContainer.new()
	sec_demographics.add_theme_constant_override("separation", 4)
	var hdr_demographics := Label.new()
	hdr_demographics.text = "[ " + tr("UI_SEC_MUNICIPAL_CENSUS").to_upper() + " ]"
	hdr_demographics.add_theme_font_override("font", mono_font)
	hdr_demographics.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	sec_demographics.add_child(hdr_demographics)
	var sep_demographics := HSeparator.new()
	sec_demographics.add_child(sep_demographics)
	add_child(sec_demographics)

	var row_pop := HBoxContainer.new()
	row_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_pop := Label.new()
	lbl_pop.text = tr("UI_LBL_POPULATION")
	lbl_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_pop.add_theme_font_override("font", mono_font)
	lbl_pop.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_pop.add_child(lbl_pop)
	var val_pop := Label.new()
	val_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_pop.add_theme_font_override("font", mono_font)
	val_pop.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_pop.add_child(val_pop)
	_value_labels["pop"] = val_pop
	sec_demographics.add_child(row_pop)

	var row_households := HBoxContainer.new()
	row_households.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_households := Label.new()
	lbl_households.text = tr("UI_LBL_HOUSEHOLDS")
	lbl_households.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_households.add_theme_font_override("font", mono_font)
	lbl_households.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_households.add_child(lbl_households)
	var val_households := Label.new()
	val_households.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_households.add_theme_font_override("font", mono_font)
	val_households.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_households.add_child(val_households)
	_value_labels["households"] = val_households
	sec_demographics.add_child(row_households)

	var row_employed := HBoxContainer.new()
	row_employed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_employed := Label.new()
	lbl_employed.text = tr("UI_LBL_EMPLOYED")
	lbl_employed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_employed.add_theme_font_override("font", mono_font)
	lbl_employed.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_employed.add_child(lbl_employed)
	var val_employed := Label.new()
	val_employed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_employed.add_theme_font_override("font", mono_font)
	val_employed.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_employed.add_child(val_employed)
	_value_labels["employed"] = val_employed
	sec_demographics.add_child(row_employed)

	var row_informal := HBoxContainer.new()
	row_informal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_informal := Label.new()
	lbl_informal.text = tr("UI_LBL_INFORMAL")
	lbl_informal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_informal.add_theme_font_override("font", mono_font)
	lbl_informal.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_informal.add_child(lbl_informal)
	var val_informal := Label.new()
	val_informal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_informal.add_theme_font_override("font", mono_font)
	val_informal.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_informal.add_child(val_informal)
	_value_labels["informal"] = val_informal
	sec_demographics.add_child(row_informal)

	# --- Section: telemetry ---
	var sec_telemetry := VBoxContainer.new()
	sec_telemetry.add_theme_constant_override("separation", 4)
	var hdr_telemetry := Label.new()
	hdr_telemetry.text = "[ " + tr("UI_SEC_WARD_TELEMETRY").to_upper() + " ]"
	hdr_telemetry.add_theme_font_override("font", mono_font)
	hdr_telemetry.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	sec_telemetry.add_child(hdr_telemetry)
	var sep_telemetry := HSeparator.new()
	sec_telemetry.add_child(sep_telemetry)
	add_child(sec_telemetry)

	var row_income := HBoxContainer.new()
	row_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_income := Label.new()
	lbl_income.text = tr("UI_LBL_DISPOSABLE_INCOME")
	lbl_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_income.add_theme_font_override("font", mono_font)
	lbl_income.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_income.add_child(lbl_income)
	var val_income := Label.new()
	val_income.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_income.add_theme_font_override("font", mono_font)
	val_income.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_income.add_child(val_income)
	_value_labels["income"] = val_income
	sec_telemetry.add_child(row_income)

	var row_zhi := HBoxContainer.new()
	row_zhi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_zhi := Label.new()
	lbl_zhi.text = tr("UI_LBL_ZHI")
	lbl_zhi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_zhi.add_theme_font_override("font", mono_font)
	lbl_zhi.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_zhi.add_child(lbl_zhi)
	var val_zhi := Label.new()
	val_zhi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_zhi.add_theme_font_override("font", mono_font)
	val_zhi.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_zhi.add_child(val_zhi)
	_value_labels["zhi"] = val_zhi
	sec_telemetry.add_child(row_zhi)

	var row_heat := HBoxContainer.new()
	row_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_heat := Label.new()
	lbl_heat.text = tr("UI_LBL_POLICE_HEAT")
	lbl_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_heat.add_theme_font_override("font", mono_font)
	lbl_heat.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_heat.add_child(lbl_heat)
	var val_heat := Label.new()
	val_heat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_heat.add_theme_font_override("font", mono_font)
	val_heat.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_heat.add_child(val_heat)
	_value_labels["heat"] = val_heat
	sec_telemetry.add_child(row_heat)

	var row_unemployment := HBoxContainer.new()
	row_unemployment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_unemployment := Label.new()
	lbl_unemployment.text = tr("UI_LBL_UNEMPLOYMENT")
	lbl_unemployment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_unemployment.add_theme_font_override("font", mono_font)
	lbl_unemployment.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_unemployment.add_child(lbl_unemployment)
	var val_unemployment := Label.new()
	val_unemployment.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_unemployment.add_theme_font_override("font", mono_font)
	val_unemployment.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_unemployment.add_child(val_unemployment)
	_value_labels["unemployment"] = val_unemployment
	sec_telemetry.add_child(row_unemployment)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("pop") and data.has("active_population"):
		_value_labels["pop"].text = str(int(data["active_population"])) + " citizens"
	if _value_labels.has("households") and data.has("total_households"):
		_value_labels["households"].text = str(int(data["total_households"])) + " homes"
	if _value_labels.has("employed") and data.has("formally_employed_count"):
		_value_labels["employed"].text = str(int(data["formally_employed_count"])) + " workers"
	if _value_labels.has("informal") and data.has("street_informal_count"):
		_value_labels["informal"].text = str(int(data["street_informal_count"])) + " claimants"
	if _value_labels.has("income") and data.has("avg_disposable_income"):
		_value_labels["income"].text = "£" + ("%.2f" % float(data["avg_disposable_income"])) + " / wk"
	if _value_labels.has("zhi") and data.has("zone_health_index"):
		_value_labels["zhi"].text = ("%.1f" % float(data["zone_health_index"])) + " / 100"
	if _value_labels.has("heat") and data.has("actual_police_heat"):
		_value_labels["heat"].text = ("%.1f" % (float(data["actual_police_heat"]) * 100.0)) + "%" + ""
	if _value_labels.has("unemployment") and data.has("unemployment_rate"):
		_value_labels["unemployment"].text = ("%.1f" % (float(data["unemployment_rate"]) * 100.0)) + "%" + ""

