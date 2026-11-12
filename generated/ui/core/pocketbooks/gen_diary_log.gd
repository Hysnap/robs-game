# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/pocketbooks/diary_log.json
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

	# --- Section: diary_header ---
	var sec_diary_header := VBoxContainer.new()
	sec_diary_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_diary_header.add_theme_constant_override("separation", 2)
	var hdr_diary_header := Label.new()
	hdr_diary_header.text = "[ " + tr("UI_SEC_DISPATCH_DIARY").to_upper() + " ]"
	hdr_diary_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_diary_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_diary_header.add_theme_font_override("font", mono_font)
	hdr_diary_header.add_theme_color_override("font_color", clr_blue)
	sec_diary_header.add_child(hdr_diary_header)
	var sep_diary_header := HSeparator.new()
	sec_diary_header.add_child(sep_diary_header)
	add_child(sec_diary_header)

	var row_current_week := HBoxContainer.new()
	row_current_week.name = "current_week"
	row_current_week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_current_week := Label.new()
	lbl_current_week.text = tr("UI_LBL_CURRENT_WEEK")
	lbl_current_week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_current_week.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_current_week.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_current_week.add_child(lbl_current_week)
	var val_current_week := Label.new()
	val_current_week.name = "current_week_value"
	val_current_week.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_current_week.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_current_week.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_current_week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_current_week.add_child(val_current_week)
	_value_labels["current_week"] = val_current_week
	add_child(row_current_week)

	var row_dispatched_count := HBoxContainer.new()
	row_dispatched_count.name = "dispatched_count"
	row_dispatched_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_dispatched_count := Label.new()
	lbl_dispatched_count.text = tr("UI_LBL_DISPATCH_COUNT")
	lbl_dispatched_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_dispatched_count.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	lbl_dispatched_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_dispatched_count.add_child(lbl_dispatched_count)
	var val_dispatched_count := Label.new()
	val_dispatched_count.name = "dispatched_count_value"
	val_dispatched_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_dispatched_count.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	val_dispatched_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_dispatched_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_dispatched_count.add_child(val_dispatched_count)
	_value_labels["dispatched_count"] = val_dispatched_count
	add_child(row_dispatched_count)

	# --- Inscriptions Container: inscriptions ---
	var hdr_inscriptions := Label.new()
	hdr_inscriptions.text = "[ " + tr("UI_SEC_DISPATCH_INSCRIPTIONS").to_upper() + " ]"
	hdr_inscriptions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_inscriptions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_inscriptions.add_theme_font_override("font", mono_font)
	hdr_inscriptions.add_theme_color_override("font_color", clr_blue)
	add_child(hdr_inscriptions)
	var insc_list_inscriptions := VBoxContainer.new()
	insc_list_inscriptions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["__inscriptions__"] = insc_list_inscriptions
	add_child(insc_list_inscriptions)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("current_week"):
		var ctrl = _value_labels["current_week"]
		if not data.has("current_week_tick") or data["current_week_tick"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["current_week_tick"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + ""
	if _value_labels.has("dispatched_count"):
		var ctrl = _value_labels["dispatched_count"]
		if not data.has("total_dispatched_orders") or data["total_dispatched_orders"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["total_dispatched_orders"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + ""

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
