# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/roster.json
class_name GenRoster
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

	# --- Section: ROSTER_summary ---
	var sec_ROSTER_summary := VBoxContainer.new()
	sec_ROSTER_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_ROSTER_summary.add_theme_constant_override("separation", 2)
	var hdr_ROSTER_summary := Label.new()
	hdr_ROSTER_summary.text = "[ " + tr("UI_SEC_ROSTER_LIST").to_upper() + " ]"
	hdr_ROSTER_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_ROSTER_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_ROSTER_summary.add_theme_font_override("font", mono_font)
	hdr_ROSTER_summary.add_theme_color_override("font_color", clr_blue)
	sec_ROSTER_summary.add_child(hdr_ROSTER_summary)
	var sep_ROSTER_summary := HSeparator.new()
	sec_ROSTER_summary.add_child(sep_ROSTER_summary)
	add_child(sec_ROSTER_summary)

	var row_address_book_family := HBoxContainer.new()
	row_address_book_family.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_address_book_family := Label.new()
	lbl_address_book_family.text = tr("UI_LBL_LIQUID_CASH")
	lbl_address_book_family.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_address_book_family.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_address_book_family.add_theme_font_override("font", mono_font)
	lbl_address_book_family.add_theme_color_override("font_color", clr_muted)
	row_address_book_family.add_child(lbl_address_book_family)
	var val_address_book_family := Label.new()
	val_address_book_family.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_address_book_family.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_address_book_family.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_address_book_family.add_theme_font_override("font", mono_font)
	val_address_book_family.add_theme_color_override("font_color", clr_black)
	row_address_book_family.add_child(val_address_book_family)
	_value_labels["address_book_family"] = val_address_book_family
	add_child(row_address_book_family)

	var row_address_book_friends := HBoxContainer.new()
	row_address_book_friends.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_address_book_friends := Label.new()
	lbl_address_book_friends.text = tr("UI_LBL_EXPENSE_TOTAL")
	lbl_address_book_friends.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_address_book_friends.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_address_book_friends.add_theme_font_override("font", mono_font)
	lbl_address_book_friends.add_theme_color_override("font_color", clr_muted)
	row_address_book_friends.add_child(lbl_address_book_friends)
	var val_address_book_friends := Label.new()
	val_address_book_friends.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_address_book_friends.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_address_book_friends.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_address_book_friends.add_theme_font_override("font", mono_font)
	val_address_book_friends.add_theme_color_override("font_color", clr_black)
	row_address_book_friends.add_child(val_address_book_friends)
	_value_labels["address_book_friends"] = val_address_book_friends
	add_child(row_address_book_friends)

	# --- Inscriptions Container ---
	var hdr_insc := Label.new()
	hdr_insc.text = "[ " + tr("UI_SEC_ROSTER").to_upper() + " ]"
	hdr_insc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_insc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_insc.add_theme_font_override("font", mono_font)
	hdr_insc.add_theme_color_override("font_color", clr_blue)
	add_child(hdr_insc)
	var insc_list := VBoxContainer.new()
	insc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["__inscriptions__"] = insc_list
	add_child(insc_list)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("address_book_family") and data.has("reported_cash"):
		var ctrl = _value_labels["address_book_family"]
		if data["reported_cash"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var num_str := String.num(float(data["reported_cash"]), 2)
			ctrl.text = tr("FMT_CURRENCY").replace("{val}", num_str) + ""
	if _value_labels.has("address_book_friends") and data.has("total_filed_expenses"):
		var ctrl = _value_labels["address_book_friends"]
		if data["total_filed_expenses"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var num_str := String.num(float(data["total_filed_expenses"]), 2)
			ctrl.text = tr("FMT_CURRENCY").replace("{val}", num_str) + ""

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
