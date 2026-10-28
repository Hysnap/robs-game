# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/navigation_bar.json
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

	# --- Section: macro_tabs ---
	var sec_macro_tabs := VBoxContainer.new()
	sec_macro_tabs.add_theme_constant_override("separation", 4)
	add_child(sec_macro_tabs)

	var btn_diary := Button.new()
	btn_diary.text = tr("UI_TAB_MACRO_DIARY")
	btn_diary.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_diary.custom_minimum_size = Vector2(0, 36)
	btn_diary.focus_mode = Control.FOCUS_NONE
	btn_diary.add_theme_font_override("font", mono_font)
	btn_diary.add_theme_font_size_override("font_size", 11)
	btn_diary.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	btn_diary.pressed.connect(func(): route_requested.emit("DIARY", "DiaryTab"))
	sec_macro_tabs.add_child(btn_diary)
	_value_labels["diary"] = btn_diary

	var btn_dossier := Button.new()
	btn_dossier.text = tr("UI_TAB_MACRO_DOSSIER")
	btn_dossier.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_dossier.custom_minimum_size = Vector2(0, 36)
	btn_dossier.focus_mode = Control.FOCUS_NONE
	btn_dossier.add_theme_font_override("font", mono_font)
	btn_dossier.add_theme_font_size_override("font_size", 11)
	btn_dossier.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	btn_dossier.pressed.connect(func(): route_requested.emit("DOSSIER", "TelemetryTab"))
	sec_macro_tabs.add_child(btn_dossier)
	_value_labels["dossier"] = btn_dossier

	var btn_roster := Button.new()
	btn_roster.text = tr("UI_TAB_MACRO_ROSTER")
	btn_roster.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_roster.custom_minimum_size = Vector2(0, 36)
	btn_roster.focus_mode = Control.FOCUS_NONE
	btn_roster.add_theme_font_override("font", mono_font)
	btn_roster.add_theme_font_size_override("font_size", 11)
	btn_roster.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	btn_roster.pressed.connect(func(): route_requested.emit("ROSTER", "RosterTab"))
	sec_macro_tabs.add_child(btn_roster)
	_value_labels["roster"] = btn_roster

	var btn_finance := Button.new()
	btn_finance.text = tr("UI_TAB_MACRO_FINANCE")
	btn_finance.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_finance.custom_minimum_size = Vector2(0, 36)
	btn_finance.focus_mode = Control.FOCUS_NONE
	btn_finance.add_theme_font_override("font", mono_font)
	btn_finance.add_theme_font_size_override("font_size", 11)
	btn_finance.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	btn_finance.pressed.connect(func(): route_requested.emit("FINANCE", "FinancialsTab"))
	sec_macro_tabs.add_child(btn_finance)
	_value_labels["finance"] = btn_finance

func bind_data(data: Dictionary) -> void:
	pass

