# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/action_planner.json
class_name GenActionPlanner
extends VBoxContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

signal directive_staged(directive)
signal execute_shift_requested(staged_directives)
signal action_clicked(action_code)

var _value_labels: Dictionary = {}
var _inscribed_entries_container: VBoxContainer = null

func _init() -> void:
	build_ui()

func build_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	# --- Section: UI_HDR_OPERATIONS ---
	var hdr_operational_docket := Label.new()
	hdr_operational_docket.text = tr("UI_HDR_OPERATIONS")
	hdr_operational_docket.add_theme_font_override("font", mono_font)
	hdr_operational_docket.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	add_child(hdr_operational_docket)

	var row_verb_selector := HBoxContainer.new()
	var lbl_verb_selector := Label.new()
	lbl_verb_selector.text = tr("UI_LBL_ACTION")
	lbl_verb_selector.add_theme_font_override("font", mono_font)
	lbl_verb_selector.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_verb_selector.add_child(lbl_verb_selector)
	var opt_verb_selector := OptionButton.new()
	opt_verb_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_verb_selector.add_theme_font_override("font", mono_font)
	opt_verb_selector.add_item("BUY")
	opt_verb_selector.add_item("SELL")
	opt_verb_selector.add_item("MAKE")
	opt_verb_selector.add_item("SCOUT")
	row_verb_selector.add_child(opt_verb_selector)
	_value_labels["verb_selector"] = opt_verb_selector
	add_child(row_verb_selector)

	var row_item_selector := HBoxContainer.new()
	var lbl_item_selector := Label.new()
	lbl_item_selector.text = tr("UI_LBL_COMMODITY")
	lbl_item_selector.add_theme_font_override("font", mono_font)
	lbl_item_selector.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_item_selector.add_child(lbl_item_selector)
	var opt_item_selector := OptionButton.new()
	opt_item_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_item_selector.add_theme_font_override("font", mono_font)
	opt_item_selector.add_item("BEER_STRONG_LAGER")
	opt_item_selector.add_item("CIGARETTES_SMUGGLED")
	row_item_selector.add_child(opt_item_selector)
	_value_labels["item_selector"] = opt_item_selector
	add_child(row_item_selector)

	var row_quantity_spinner := HBoxContainer.new()
	var lbl_quantity_spinner := Label.new()
	lbl_quantity_spinner.text = tr("UI_LBL_QTY")
	lbl_quantity_spinner.add_theme_font_override("font", mono_font)
	lbl_quantity_spinner.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	row_quantity_spinner.add_child(lbl_quantity_spinner)
	var spin_quantity_spinner := SpinBox.new()
	spin_quantity_spinner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_quantity_spinner.min_value = 1.0
	spin_quantity_spinner.max_value = 100.0
	spin_quantity_spinner.step = 1.0
	spin_quantity_spinner.value = 10.0
	row_quantity_spinner.add_child(spin_quantity_spinner)
	_value_labels["quantity_spinner"] = spin_quantity_spinner
	add_child(row_quantity_spinner)

	var btn_btn_stage_order := Button.new()
	btn_btn_stage_order.text = tr("UI_BTN_STAGE_ORDER")
	btn_btn_stage_order.add_theme_font_override("font", mono_font)
	btn_btn_stage_order.pressed.connect(func(): action_clicked.emit("STAGE"))
	_value_labels["btn_stage_order"] = btn_btn_stage_order
	add_child(btn_btn_stage_order)

	# --- Section: UI_HDR_STAGED_QUEUE ---
	var hdr_staging_ledger := Label.new()
	hdr_staging_ledger.text = tr("UI_HDR_STAGED_QUEUE")
	hdr_staging_ledger.add_theme_font_override("font", mono_font)
	hdr_staging_ledger.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	add_child(hdr_staging_ledger)

	var list_queue_list := ItemList.new()
	list_queue_list.custom_minimum_size = Vector2(0, 120)
	list_queue_list.add_theme_font_override("font", mono_font)
	_value_labels["queue_list"] = list_queue_list
	add_child(list_queue_list)

	var btn_btn_execute_shift := Button.new()
	btn_btn_execute_shift.text = tr("UI_BTN_EXECUTE_SHIFT")
	btn_btn_execute_shift.add_theme_font_override("font", mono_font)
	btn_btn_execute_shift.pressed.connect(func(): action_clicked.emit("COMMIT_SHIFT"))
	_value_labels["btn_execute_shift"] = btn_btn_execute_shift
	add_child(btn_btn_execute_shift)


func bind_data(data: Dictionary) -> void:
	if _value_labels.has("verb_selector") and data.has("selected_verb"):
		_value_labels["verb_selector"].text = str(data["selected_verb"]) + ""
	if _value_labels.has("item_selector") and data.has("selected_item"):
		_value_labels["item_selector"].text = str(data["selected_item"]) + ""
	if _value_labels.has("quantity_spinner") and data.has("quantity"):
		_value_labels["quantity_spinner"].text = str(data["quantity"]) + ""
	if _value_labels.has("queue_list") and data.has("staged_queue"):
		_value_labels["queue_list"].text = str(data["staged_queue"]) + ""

var _staged_orders: Array[Dictionary] = []

func stage_current_selection(target_node_id: String) -> Dictionary:
	var opt_verb = _value_labels.get("verb_selector") as OptionButton
	var opt_item = _value_labels.get("item_selector") as OptionButton
	var spin_qty = _value_labels.get("quantity_spinner") as SpinBox
	var list_queue = _value_labels.get("queue_list") as ItemList

	if not opt_verb or not opt_item or not spin_qty:
		return {}

	var verb_txt := opt_verb.get_item_text(opt_verb.selected)
	var item_txt := opt_item.get_item_text(opt_item.selected)
	var qty_val := float(spin_qty.value)

	var directive := {
		"verb": verb_txt,
		"initiator_id": "PLAYER",
		"counterparty_id": "WHOLESALER_01" if verb_txt == "BUY" else "MARKET_CONSUMERS_ASTON",
		"target_item": item_txt,
		"amount": qty_val,
		"target_node_id": target_node_id,
		"config": {"unit_price": 3.50, "unit_cost": 2.00}
	}

	_staged_orders.append(directive)
	if list_queue:
		var display_line := "[" + verb_txt + "] " + item_txt + " x" + str(int(qty_val))
		list_queue.add_item(display_line)
	directive_staged.emit(directive)
	return directive

func clear_staged_orders() -> void:
	_staged_orders.clear()
	var list_queue = _value_labels.get("queue_list") as ItemList
	if list_queue:
		list_queue.clear()

func get_staged_orders() -> Array[Dictionary]:
	return _staged_orders
