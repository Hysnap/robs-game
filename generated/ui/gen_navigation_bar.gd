# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/navigation_bar.json
class_name GenNavBar
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

	var btn_diary := Button.new()
	btn_diary.text = tr("UI_TAB_MACRO_DIARY")
	btn_diary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_diary.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_diary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_diary.add_theme_font_override("font", mono_font)
	btn_diary.pressed.connect(func(): route_requested.emit("DIARY", "DiaryTab"))
	_value_labels["diary"] = btn_diary
	add_child(btn_diary)

	var btn_dossier := Button.new()
	btn_dossier.text = tr("UI_TAB_MACRO_DOSSIER")
	btn_dossier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_dossier.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_dossier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_dossier.add_theme_font_override("font", mono_font)
	btn_dossier.pressed.connect(func(): route_requested.emit("DOSSIER", "TelemetryTab"))
	_value_labels["dossier"] = btn_dossier
	add_child(btn_dossier)

	var btn_roster := Button.new()
	btn_roster.text = tr("UI_TAB_MACRO_ROSTER")
	btn_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_roster.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_roster.add_theme_font_override("font", mono_font)
	btn_roster.pressed.connect(func(): route_requested.emit("ROSTER", "RosterTab"))
	_value_labels["roster"] = btn_roster
	add_child(btn_roster)

	var btn_finance := Button.new()
	btn_finance.text = tr("UI_TAB_MACRO_FINANCE")
	btn_finance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_finance.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_finance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_finance.add_theme_font_override("font", mono_font)
	btn_finance.pressed.connect(func(): route_requested.emit("FINANCE", "FinancialsTab"))
	_value_labels["finance"] = btn_finance
	add_child(btn_finance)

func bind_data(data: Dictionary) -> void:
	pass
