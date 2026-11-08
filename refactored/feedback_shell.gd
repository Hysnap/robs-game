# res://scenes/ui/shell_host/feedback_shell.gd
class_name FeedbackShell
extends PanelContainer

signal closed
signal top_card_action(action_id, card_payload)

@onready var drag_handle: Label = $VBox/Header/DragHandle
@onready var count_label: Label = $VBox/Header/CountLabel
@onready var btn_close: Button = $VBox/Header/BtnClose
@onready var slot: Control = $VBox/StackSlot
@onready var card_stack: StaggeredCardStack = $VBox/StackSlot/CardStack

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _stack_module: StaggeredCardStack = null

func _ready() -> void:
	if drag_handle:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_handle.gui_input.connect(_on_drag_input)
	if btn_close:
		btn_close.pressed.connect(func(): 
			visible = false
			closed.emit()
		)
	if card_stack:
		if card_stack.has_signal("stack_count_changed"):
			card_stack.stack_count_changed.connect(_on_count_changed)
		if card_stack.has_signal("top_card_action"):
			card_stack.top_card_action.connect(func(a, p): top_card_action.emit(a, p))
		_on_count_changed(card_stack.get_card_count())

## Mounts the functional card stack into the shell's slot
func mount_stack_module(stack: StaggeredCardStack) -> void:
	_stack_module = stack
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
		
	slot.add_child(stack)
	
	if not _stack_module.stack_count_changed.is_connected(_on_count_changed):
		_stack_module.stack_count_changed.connect(_on_count_changed)
	
	_on_count_changed(_stack_module.get_card_count())

func _on_count_changed(unread_count: int) -> void:
	if count_label:
		count_label.text = "[ %d UNREAD ]" % unread_count
	visible = (unread_count > 0)

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

func push_cards(cards: Array) -> void:
	if card_stack:
		card_stack.push_cards(cards)
		visible = true
