# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/cashbook_ledger.json
class_name GenCashbookLedger
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

	# --- Section: vault_summary ---
	var sec_vault_summary := VBoxContainer.new()
	sec_vault_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_vault_summary.add_theme_constant_override("separation", 2)
	var hdr_vault_summary := Label.new()
	hdr_vault_summary.text = "[ " + tr("UI_SEC_VAULT_RESERVES").to_upper() + " ]"
	hdr_vault_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_vault_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_vault_summary.add_theme_font_override("font", mono_font)
	hdr_vault_summary.add_theme_color_override("font_color", clr_blue)
	sec_vault_summary.add_child(hdr_vault_summary)
	var sep_vault_summary := HSeparator.new()
	sec_vault_summary.add_child(sep_vault_summary)
	add_child(sec_vault_summary)

	var row_liquid_cash := HBoxContainer.new()
	row_liquid_cash.name = "liquid_cash"
	row_liquid_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_liquid_cash := Label.new()
	lbl_liquid_cash.text = tr("UI_LBL_LIQUID_CASH")
	lbl_liquid_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_liquid_cash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_liquid_cash.add_theme_font_override("font", mono_font)
	lbl_liquid_cash.add_theme_color_override("font_color", clr_muted)
	row_liquid_cash.add_child(lbl_liquid_cash)
	var val_liquid_cash := Label.new()
	val_liquid_cash.name = "liquid_cash_value"
	val_liquid_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_liquid_cash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_liquid_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_liquid_cash.add_theme_font_override("font", mono_font)
	val_liquid_cash.add_theme_color_override("font_color", clr_black)
	row_liquid_cash.add_child(val_liquid_cash)
	_value_labels["liquid_cash"] = val_liquid_cash
	add_child(row_liquid_cash)

	var row_filed_receipts_total := HBoxContainer.new()
	row_filed_receipts_total.name = "filed_receipts_total"
	row_filed_receipts_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_filed_receipts_total := Label.new()
	lbl_filed_receipts_total.text = tr("UI_LBL_EXPENSE_TOTAL")
	lbl_filed_receipts_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_filed_receipts_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_filed_receipts_total.add_theme_font_override("font", mono_font)
	lbl_filed_receipts_total.add_theme_color_override("font_color", clr_muted)
	row_filed_receipts_total.add_child(lbl_filed_receipts_total)
	var val_filed_receipts_total := Label.new()
	val_filed_receipts_total.name = "filed_receipts_total_value"
	val_filed_receipts_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_filed_receipts_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_filed_receipts_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_filed_receipts_total.add_theme_font_override("font", mono_font)
	val_filed_receipts_total.add_theme_color_override("font_color", clr_black)
	row_filed_receipts_total.add_child(val_filed_receipts_total)
	_value_labels["filed_receipts_total"] = val_filed_receipts_total
	add_child(row_filed_receipts_total)

	# --- Inscriptions Container: receipts_inscriptions ---
	var hdr_receipts_inscriptions := Label.new()
	hdr_receipts_inscriptions.text = "[ " + tr("UI_SEC_FILED_RECEIPTS").to_upper() + " ]"
	hdr_receipts_inscriptions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_receipts_inscriptions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_receipts_inscriptions.add_theme_font_override("font", mono_font)
	hdr_receipts_inscriptions.add_theme_color_override("font_color", clr_blue)
	add_child(hdr_receipts_inscriptions)
	var insc_list_receipts_inscriptions := VBoxContainer.new()
	insc_list_receipts_inscriptions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["__inscriptions__"] = insc_list_receipts_inscriptions
	add_child(insc_list_receipts_inscriptions)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("liquid_cash"):
		var ctrl = _value_labels["liquid_cash"]
		if not data.has("reported_cash") or data["reported_cash"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := "%.2f" % float(data["reported_cash"])
			ctrl.text = tr("FMT_CURRENCY").replace("{val}", val_str) + ""
	if _value_labels.has("filed_receipts_total"):
		var ctrl = _value_labels["filed_receipts_total"]
		if not data.has("total_filed_expenses") or data["total_filed_expenses"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := "%.2f" % float(data["total_filed_expenses"])
			ctrl.text = tr("FMT_CURRENCY").replace("{val}", val_str) + ""

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
