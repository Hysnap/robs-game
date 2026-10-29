# res://scenes/ui/shells/filofax/sticky_order_pad.gd
class_name StickyOrderPad
extends PanelContainer

signal order_pinned(directive: Dictionary)
signal directive_committed(directive: Dictionary)
signal pad_closed

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

@onready var drag_handle: Label = $VBox/Header/DragHandle
@onready var btn_close: Button = $VBox/Header/BtnClose
@onready var opt_verb: OptionButton = $VBox/NotesGrid/StickyNote_Action/VBox/VerbOption
@onready var opt_target: OptionButton = $VBox/NotesGrid/StickyNote_What/VBox/TargetOption
@onready var spin_amount: SpinBox = $VBox/NotesGrid/StickyNote_Amount/VBox/AmountSpin
@onready var opt_who: OptionButton = $VBox/NotesGrid/StickyNote_Who/VBox/WhoOption
@onready var opt_where: OptionButton = $VBox/NotesGrid/StickyNote_Where/VBox/WhereOption
@onready var lbl_estimate: Label = $VBox/NotesGrid/StickyNote_Estimate/VBox/EstimatedCostLabel
@onready var btn_pin: Button = $VBox/ButtonBox/SaveNoteBtn
@onready var btn_tear: Button = $VBox/ButtonBox/DiscardBtn

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	if drag_handle:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_handle.gui_input.connect(_on_drag_input)
	if btn_close:
		btn_close.pressed.connect(_on_close_pressed)
	if btn_tear:
		btn_tear.pressed.connect(_on_close_pressed)
	if btn_pin:
		btn_pin.pressed.connect(_on_pin_pressed)
		
	if spin_amount:
		spin_amount.value_changed.connect(func(_val): _recalculate_estimate())
	if opt_verb:
		opt_verb.item_selected.connect(func(_idx): _recalculate_estimate())

	_populate_default_options()
	_apply_sticky_note_skins()
	_recalculate_estimate()

func open_for_district(district_id: String) -> void:
	visible = true
	move_to_front()
	_sync_where_location(district_id)
	_recalculate_estimate()

func open_for_context(context: Dictionary) -> void:
	open_for_district(str(context.get("target_district_id", "")))

func _populate_default_options() -> void:
	if opt_verb and opt_verb.item_count == 0:
		opt_verb.add_item("BUY", 0)
		opt_verb.add_item("SELL", 1)
		opt_verb.add_item("MAKE", 2)
		opt_verb.add_item("SCOUT", 3)

	if opt_target and opt_target.item_count == 0:
		opt_target.add_item("BEER_STRONG_LAGER", 0)
		opt_target.add_item("CIGARETTES_SMUGGLED", 1)

	if opt_who and opt_who.item_count == 0:
		opt_who.add_item("WHOLESALER_01", 0)
		opt_who.add_item("STREET_RUNNER_BOB", 1)

func _sync_where_location(target_block_id: String) -> void:
	if opt_where == null or target_block_id.is_empty():
		return
	for i in range(opt_where.item_count):
		if opt_where.get_item_text(i) == target_block_id:
			opt_where.select(i)
			return
	opt_where.add_item(target_block_id)
	opt_where.select(opt_where.item_count - 1)

func _recalculate_estimate() -> void:
	if lbl_estimate == null or opt_verb == null or spin_amount == null:
		return
	var verb := opt_verb.get_item_text(opt_verb.selected)
	var qty: float = float(spin_amount.value)
	var unit_cost := 2.50 if verb == "BUY" else 0.50
	var total_est := qty * unit_cost
	lbl_estimate.text = "£%.2f" % total_est

func _on_pin_pressed() -> void:
	var verb := opt_verb.get_item_text(opt_verb.selected) if opt_verb else "BUY"
	var target_item := opt_target.get_item_text(opt_target.selected) if opt_target else "BEER_STRONG_LAGER"
	var qty: float = float(spin_amount.value) if spin_amount else 10.0
	var who := opt_who.get_item_text(opt_who.selected) if opt_who else "WHOLESALER_01"
	var where := opt_where.get_item_text(opt_where.selected) if opt_where else "DIST_ASTON_01"

	var directive := {
		"verb": verb,
		"initiator_id": "PLAYER",
		"counterparty_id": who,
		"target_item": target_item,
		"amount": qty,
		"target_node_id": where,
		"config": {"unit_price": 3.50, "unit_cost": 2.00}
	}

	order_pinned.emit(directive)
	directive_committed.emit(directive)
	visible = false

func _on_close_pressed() -> void:
	visible = false
	pad_closed.emit()

func _apply_sticky_note_skins() -> void:
	# Palette backgrounds matching the 6-note pad
	var colors := {
		"StickyNote_Action": Color("#fff9a6"),   # Canary Yellow
		"StickyNote_What": Color("#bae1ff"),     # Light Blue
		"StickyNote_Amount": Color("#ffd8b1"),   # Peach
		"StickyNote_Who": Color("#d4fcd6"),      # Mint Green
		"StickyNote_Where": Color("#e8dff5"),    # Soft Lavender
		"StickyNote_Estimate": Color("#ffd1d5")  # Rose Pink
	}
	for node_name in colors.keys():
		var p := find_child(node_name, true, false) as PanelContainer
		if p:
			var sb := StyleBoxFlat.new()
			sb.bg_color = colors[node_name]
			sb.set_corner_radius_all(2)
			sb.set_content_margin_all(8)
			p.add_theme_stylebox_override("panel", sb)

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			_is_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_is_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _is_dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()