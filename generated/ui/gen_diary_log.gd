# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/diary_log.json
class_name GenDiaryLog
extends VBoxContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")


var _value_labels: Dictionary = {}
var _inscribed_entries_container: VBoxContainer = null

func _init() -> void:
	build_ui()

func build_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	# --- Section: UI_SEC_DISPATCH_DIARY ---
	var hdr_diary_header := Label.new()
	hdr_diary_header.text = tr("UI_SEC_DISPATCH_DIARY")
	hdr_diary_header.add_theme_font_override("font", mono_font)
	hdr_diary_header.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	add_child(hdr_diary_header)

	var row_current_week := HBoxContainer.new()
	var lbl_current_week := Label.new()
	lbl_current_week.text = tr("UI_LBL_CURRENT_WEEK")
	lbl_current_week.add_theme_font_override("font", mono_font)
	lbl_current_week.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_current_week.add_child(lbl_current_week)
	var val_current_week := Label.new()
	val_current_week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_current_week.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_current_week.add_theme_font_override("font", mono_font)
	val_current_week.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_current_week.add_child(val_current_week)
	_value_labels["current_week"] = val_current_week
	add_child(row_current_week)

	var row_dispatched_count := HBoxContainer.new()
	var lbl_dispatched_count := Label.new()
	lbl_dispatched_count.text = tr("UI_LBL_DISPATCH_COUNT")
	lbl_dispatched_count.add_theme_font_override("font", mono_font)
	lbl_dispatched_count.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_dispatched_count.add_child(lbl_dispatched_count)
	var val_dispatched_count := Label.new()
	val_dispatched_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_dispatched_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_dispatched_count.add_theme_font_override("font", mono_font)
	val_dispatched_count.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_dispatched_count.add_child(val_dispatched_count)
	_value_labels["dispatched_count"] = val_dispatched_count
	add_child(row_dispatched_count)


func bind_data(data: Dictionary) -> void:
	if _value_labels.has("current_week") and data.has("current_week_tick"):
		_value_labels["current_week"].text = str(int(data["current_week_tick"])) + ""
	if _value_labels.has("dispatched_count") and data.has("total_dispatched_orders"):
		_value_labels["dispatched_count"].text = str(int(data["total_dispatched_orders"])) + " directives"
