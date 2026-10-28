# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/cashbook_ledger.json
class_name GenCashbookLedger
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

	# --- Section: UI_SEC_VAULT_RESERVES ---
	var hdr_vault_summary := Label.new()
	hdr_vault_summary.text = tr("UI_SEC_VAULT_RESERVES")
	hdr_vault_summary.add_theme_font_override("font", mono_font)
	hdr_vault_summary.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	add_child(hdr_vault_summary)

	var row_liquid_cash := HBoxContainer.new()
	var lbl_liquid_cash := Label.new()
	lbl_liquid_cash.text = tr("UI_LBL_LIQUID_CASH")
	lbl_liquid_cash.add_theme_font_override("font", mono_font)
	lbl_liquid_cash.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_liquid_cash.add_child(lbl_liquid_cash)
	var val_liquid_cash := Label.new()
	val_liquid_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_liquid_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_liquid_cash.add_theme_font_override("font", mono_font)
	val_liquid_cash.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_liquid_cash.add_child(val_liquid_cash)
	_value_labels["liquid_cash"] = val_liquid_cash
	add_child(row_liquid_cash)

	var row_filed_receipts_total := HBoxContainer.new()
	var lbl_filed_receipts_total := Label.new()
	lbl_filed_receipts_total.text = tr("UI_LBL_EXPENSE_TOTAL")
	lbl_filed_receipts_total.add_theme_font_override("font", mono_font)
	lbl_filed_receipts_total.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_filed_receipts_total.add_child(lbl_filed_receipts_total)
	var val_filed_receipts_total := Label.new()
	val_filed_receipts_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_filed_receipts_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_filed_receipts_total.add_theme_font_override("font", mono_font)
	val_filed_receipts_total.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_filed_receipts_total.add_child(val_filed_receipts_total)
	_value_labels["filed_receipts_total"] = val_filed_receipts_total
	add_child(row_filed_receipts_total)


func bind_data(data: Dictionary) -> void:
	if _value_labels.has("liquid_cash") and data.has("reported_cash"):
		_value_labels["liquid_cash"].text = "£" + str("%.2f" % float(data["reported_cash"])) + ""
	if _value_labels.has("filed_receipts_total") and data.has("total_filed_expenses"):
		_value_labels["filed_receipts_total"].text = "£" + str("%.2f" % float(data["total_filed_expenses"])) + ""
