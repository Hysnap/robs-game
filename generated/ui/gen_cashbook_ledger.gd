# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/cashbook_ledger.json
class_name GenCashbookLedger
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

	# --- Section: vault_summary ---
	var sec_vault_summary := VBoxContainer.new()
	sec_vault_summary.add_theme_constant_override("separation", 4)
	var hdr_vault_summary := Label.new()
	hdr_vault_summary.text = "[ " + tr("UI_SEC_VAULT_RESERVES").to_upper() + " ]"
	hdr_vault_summary.add_theme_font_override("font", mono_font)
	hdr_vault_summary.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	sec_vault_summary.add_child(hdr_vault_summary)
	var sep_vault_summary := HSeparator.new()
	sec_vault_summary.add_child(sep_vault_summary)
	add_child(sec_vault_summary)

	var row_liquid_cash := HBoxContainer.new()
	row_liquid_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_liquid_cash := Label.new()
	lbl_liquid_cash.text = tr("UI_LBL_LIQUID_CASH")
	lbl_liquid_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_liquid_cash.add_theme_font_override("font", mono_font)
	lbl_liquid_cash.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_liquid_cash.add_child(lbl_liquid_cash)
	var val_liquid_cash := Label.new()
	val_liquid_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_liquid_cash.add_theme_font_override("font", mono_font)
	val_liquid_cash.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_liquid_cash.add_child(val_liquid_cash)
	_value_labels["liquid_cash"] = val_liquid_cash
	sec_vault_summary.add_child(row_liquid_cash)

	var row_filed_receipts_total := HBoxContainer.new()
	row_filed_receipts_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_filed_receipts_total := Label.new()
	lbl_filed_receipts_total.text = tr("UI_LBL_EXPENSE_TOTAL")
	lbl_filed_receipts_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_filed_receipts_total.add_theme_font_override("font", mono_font)
	lbl_filed_receipts_total.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	row_filed_receipts_total.add_child(lbl_filed_receipts_total)
	var val_filed_receipts_total := Label.new()
	val_filed_receipts_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_filed_receipts_total.add_theme_font_override("font", mono_font)
	val_filed_receipts_total.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_filed_receipts_total.add_child(val_filed_receipts_total)
	_value_labels["filed_receipts_total"] = val_filed_receipts_total
	sec_vault_summary.add_child(row_filed_receipts_total)

	# Ruled Inscriptions Container
	var inscribe_header := Label.new()
	inscribe_header.text = "\n[ " + tr("UI_SEC_FILED_RECEIPTS").to_upper() + " ]"
	inscribe_header.add_theme_font_override("font", mono_font)
	inscribe_header.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	add_child(inscribe_header)
	add_child(HSeparator.new())
	_inscribed_entries_container = VBoxContainer.new()
	_inscribed_entries_container.add_theme_constant_override("separation", 6)
	_inscribed_entries_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_inscribed_entries_container)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("liquid_cash") and data.has("reported_cash"):
		_value_labels["liquid_cash"].text = "£" + ("%.2f" % float(data["reported_cash"])) + ""
	if _value_labels.has("filed_receipts_total") and data.has("total_filed_expenses"):
		_value_labels["filed_receipts_total"].text = "£" + ("%.2f" % float(data["total_filed_expenses"])) + ""

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

