# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/navigation_bar.json
class_name GenNavBar
extends VBoxContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

signal route_requested(domain_token: String, target_page_name: String)

var _value_labels: Dictionary = {}
var _inscribed_entries_container: VBoxContainer = null

func _init() -> void:
	build_ui()

func build_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	var btn_diary := Button.new()
	btn_diary.text = tr("UI_TAB_MACRO_DIARY")
	btn_diary.add_theme_font_override("font", mono_font)
	btn_diary.pressed.connect(func(): route_requested.emit("DIARY", "DiaryTab"))
	_value_labels["diary"] = btn_diary
	add_child(btn_diary)

	var btn_dossier := Button.new()
	btn_dossier.text = tr("UI_TAB_MACRO_DOSSIER")
	btn_dossier.add_theme_font_override("font", mono_font)
	btn_dossier.pressed.connect(func(): route_requested.emit("DOSSIER", "TelemetryTab"))
	_value_labels["dossier"] = btn_dossier
	add_child(btn_dossier)

	var btn_roster := Button.new()
	btn_roster.text = tr("UI_TAB_MACRO_ROSTER")
	btn_roster.add_theme_font_override("font", mono_font)
	btn_roster.pressed.connect(func(): route_requested.emit("ROSTER", "RosterTab"))
	_value_labels["roster"] = btn_roster
	add_child(btn_roster)

	var btn_finance := Button.new()
	btn_finance.text = tr("UI_TAB_MACRO_FINANCE")
	btn_finance.add_theme_font_override("font", mono_font)
	btn_finance.pressed.connect(func(): route_requested.emit("FINANCE", "FinancialsTab"))
	_value_labels["finance"] = btn_finance
	add_child(btn_finance)


func bind_data(data: Dictionary) -> void:
	pass
