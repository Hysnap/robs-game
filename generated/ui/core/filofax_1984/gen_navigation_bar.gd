# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/filofax_1984/navigation_bar.json
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

	var btn_diary := Button.new()
	btn_diary.name = "diary"
	btn_diary.text = tr("UI_TAB_MACRO_DIARY")
	btn_diary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_diary.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_diary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_diary.pressed.connect(func(): self.action_clicked.emit("NAV_ROUTE", {"domain": "DIARY"}))
	_value_labels["diary"] = btn_diary
	add_child(btn_diary)

	var btn_dossier := Button.new()
	btn_dossier.name = "dossier"
	btn_dossier.text = tr("UI_TAB_MACRO_DOSSIER")
	btn_dossier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_dossier.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_dossier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_dossier.pressed.connect(func(): self.action_clicked.emit("NAV_ROUTE", {"domain": "DOSSIER"}))
	_value_labels["dossier"] = btn_dossier
	add_child(btn_dossier)

	var btn_roster := Button.new()
	btn_roster.name = "roster"
	btn_roster.text = tr("UI_TAB_MACRO_ROSTER")
	btn_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_roster.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_roster.pressed.connect(func(): self.action_clicked.emit("NAV_ROUTE", {"domain": "ROSTER"}))
	_value_labels["roster"] = btn_roster
	add_child(btn_roster)

	var btn_finance := Button.new()
	btn_finance.name = "finance"
	btn_finance.text = tr("UI_TAB_MACRO_FINANCE")
	btn_finance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_finance.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_finance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_finance.pressed.connect(func(): self.action_clicked.emit("NAV_ROUTE", {"domain": "FINANCE"}))
	_value_labels["finance"] = btn_finance
	add_child(btn_finance)

	var btn_styles := Button.new()
	btn_styles.name = "styles"
	btn_styles.text = tr("UI_TAB_MACRO_STYLES")
	btn_styles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_styles.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_styles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_styles.pressed.connect(func(): self.action_clicked.emit("NAV_ROUTE", {"domain": "STYLES"}))
	_value_labels["styles"] = btn_styles
	add_child(btn_styles)

func bind_data(data: Dictionary) -> void:
	pass
