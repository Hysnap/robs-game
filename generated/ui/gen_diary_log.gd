# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/diary_log.json
class_name GenDiaryLog
extends VBoxContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

var _value_labels: Dictionary = {}
var _inscribed_entries_container: VBoxContainer = null

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_ui()

func build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_value_labels.clear()
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	# --- Section: diary_header ---
	var sec_diary_header := VBoxContainer.new()
	sec_diary_header.add_theme_constant_override("separation", 4)
	var hdr_diary_header := Label.new()
	hdr_diary_header.text = "[ " + tr("UI_SEC_DISPATCH_DIARY").to_upper() + " ]"
	hdr_diary_header.add_theme_font_override("font", mono_font)
	hdr_diary_header.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	sec_diary_header.add_child(hdr_diary_header)
	var sep_diary_header := HSeparator.new()
	sec_diary_header.add_child(sep_diary_header)
	add_child(sec_diary_header)

	var row_current_week := HBoxContainer.new()
	row_current_week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_current_week := Label.new()
	lbl_current_week.text = tr("UI_LBL_CURRENT_WEEK")
	lbl_current_week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_current_week.add_theme_font_override("font", mono_font)
	lbl_current_week.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_current_week.add_child(lbl_current_week)
	var val_current_week := Label.new()
	val_current_week.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_current_week.add_theme_font_override("font", mono_font)
	val_current_week.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_current_week.add_child(val_current_week)
	_value_labels["current_week"] = val_current_week
	sec_diary_header.add_child(row_current_week)

	var row_dispatched_count := HBoxContainer.new()
	row_dispatched_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_dispatched_count := Label.new()
	lbl_dispatched_count.text = tr("UI_LBL_DISPATCH_COUNT")
	lbl_dispatched_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_dispatched_count.add_theme_font_override("font", mono_font)
	lbl_dispatched_count.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_dispatched_count.add_child(lbl_dispatched_count)
	var val_dispatched_count := Label.new()
	val_dispatched_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_dispatched_count.add_theme_font_override("font", mono_font)
	val_dispatched_count.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_dispatched_count.add_child(val_dispatched_count)
	_value_labels["dispatched_count"] = val_dispatched_count
	sec_diary_header.add_child(row_dispatched_count)

	# Ruled Inscriptions Container
	var inscribe_header := Label.new()
	inscribe_header.text = "\n[ " + tr("UI_SEC_DISPATCH_INSCRIPTIONS").to_upper() + " ]"
	inscribe_header.add_theme_font_override("font", mono_font)
	inscribe_header.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	add_child(inscribe_header)
	add_child(HSeparator.new())
	_inscribed_entries_container = VBoxContainer.new()
	_inscribed_entries_container.add_theme_constant_override("separation", 6)
	_inscribed_entries_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_inscribed_entries_container)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("current_week") and data.has("current_week_tick"):
		_value_labels["current_week"].text = str(int(data["current_week_tick"])) + ""
	if _value_labels.has("dispatched_count") and data.has("total_dispatched_orders"):
		_value_labels["dispatched_count"].text = str(int(data["total_dispatched_orders"])) + " directives"

func inscribe_entry(entry_data: Dictionary) -> void:
	if _inscribed_entries_container == null: return
	var mono_font: Font = RETRO_THEME.get_monospace_font()
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var hdr := Label.new()
	hdr.text = "[ WK %02d ] • %s" % [int(entry_data.get("tick", 1)), str(entry_data.get("author", "Dispatch"))]
	hdr.add_theme_font_override("font", mono_font)
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	row.add_child(hdr)
	var body := Label.new()
	body.text = "  " + str(entry_data.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("font", mono_font)
	body.add_theme_font_size_override("font_size", 10)
	body.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row.add_child(body)
	var sep := HSeparator.new()
	sep.modulate = RETRO_THEME.color_ruled_line
	row.add_child(sep)
	_inscribed_entries_container.add_child(row)

