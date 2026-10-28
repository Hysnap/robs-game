# res://scenes/ui/filofax/outer_shell.gd
class_name OuterShell
extends PanelContainer

signal close_requested

@onready var drag_handle: Control = get_node_or_null("Layout/HeaderBar/DragHandle")
@onready var close_btn: Button = get_node_or_null("Layout/HeaderBar/BtnClose")
@onready var spread_holder: MarginContainer = get_node_or_null("Layout/SpreadHolder")

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _active_spread: Node = null

func _ready() -> void:
	if close_btn != null:
		close_btn.pressed.connect(func(): close_requested.emit())
	if drag_handle:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_handle.gui_input.connect(_on_drag_input)

## Mounts an era presentation shell (e.g. FilofaxSpread or Apple2CrtSpread)
func set_spread_wrapper(spread_node: Node) -> void:
	var holder: MarginContainer = spread_holder
	if holder == null:
		holder = get_node_or_null("Layout/SpreadHolder")
	
	if holder == null:
		push_error("[OuterShell] SpreadHolder not found in Layout!")
		return

	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()

	_active_spread = spread_node
	holder.add_child(spread_node)

## Resolves slot node from the active spread wrapper
func get_slot(slot_name: String) -> Control:
	if _active_spread == null:
		# Fallback: check if SpreadHolder has a child wrapper already
		var holder: MarginContainer = spread_holder if spread_holder else get_node_or_null("Layout/SpreadHolder")
		if holder and holder.get_child_count() > 0:
			_active_spread = holder.get_child(0)

	if _active_spread != null and _active_spread.has_method("get_slot"):
		return _active_spread.get_slot(slot_name)
	return null

## Mounts a Control node into a named slot, clearing existing children immediately
func mount_view(slot_name: String, view_node: Control) -> void:
	var target_slot: Control = get_slot(slot_name)
	if target_slot == null:
		push_error("[OuterShell] Unknown or missing slot: %s" % slot_name)
		return

	if view_node.get_parent() == target_slot:
		return

	if view_node.get_parent() != null:
		view_node.get_parent().remove_child(view_node)

	for child in target_slot.get_children():
		target_slot.remove_child(child)
		 # child.queue_free()

	target_slot.add_child(view_node)

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