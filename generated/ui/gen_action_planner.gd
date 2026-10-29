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

	var btn_btn_open_order_pad := Button.new()
	btn_btn_open_order_pad.text = tr("UI_BTN_OPEN_ORDER_PAD")
	btn_btn_open_order_pad.add_theme_font_override("font", mono_font)
	btn_btn_open_order_pad.pressed.connect(func(): action_clicked.emit("OPEN_PAD"))
	_value_labels["btn_open_order_pad"] = btn_btn_open_order_pad
	add_child(btn_btn_open_order_pad)

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
