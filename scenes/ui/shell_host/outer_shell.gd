# res://scenes/ui/shell_host/outer_shell.gd
class_name OuterShell
extends PanelContainer

signal close_requested
signal shell_switch_requested(shell_id: String)

const DEFAULT_SHELL_SIZE := Vector2(980.0, 560.0)

@onready var drag_handle: Control = get_node_or_null("Layout/HeaderBar/DragHandle")
@onready var shell_option: OptionButton = get_node_or_null("Layout/HeaderBar/ShellOption")
@onready var close_btn: Button = get_node_or_null("Layout/HeaderBar/BtnClose")
@onready var spread_holder: MarginContainer = get_node_or_null("Layout/SpreadHolder")

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _active_spread: Node = null
var _is_populating_shells: bool = false

func _ready() -> void:
	if close_btn != null:
		close_btn.pressed.connect(func(): close_requested.emit())
	if shell_option != null:
		shell_option.item_selected.connect(_on_shell_option_selected)
	if drag_handle:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_handle.gui_input.connect(_on_drag_input)

## Resizes OuterShell window frame from the active shell_manifest.json window_size entry
func apply_shell_window_size(manifest: Dictionary) -> void:
	var target_size: Vector2 = DEFAULT_SHELL_SIZE
	var raw_size = manifest.get("window_size", null)
	if raw_size is Array and raw_size.size() >= 2:
		target_size = Vector2(float(raw_size[0]), float(raw_size[1]))

	custom_minimum_size = target_size
	size = target_size

	var vp := get_viewport()
	if vp != null:
		var vp_size: Vector2 = vp.get_visible_rect().size
		if vp_size.x > 0.0 and vp_size.y > 0.0:
			global_position = Vector2(
				maxf(20.0, (vp_size.x - target_size.x) * 0.5),
				maxf(60.0, (vp_size.y - target_size.y) * 0.5)
			)

## Populates the header shell selector from year-unlocked shell definitions
func populate_shell_options(shells: Array[Dictionary], active_shell_id: String) -> void:
	var opt: OptionButton = shell_option if shell_option != null else get_node_or_null("Layout/HeaderBar/ShellOption") as OptionButton
	if opt == null:
		return

	_is_populating_shells = true
	opt.clear()

	var target_id: String = active_shell_id.strip_edges().to_lower()
	var selected_idx: int = 0

	for i in range(shells.size()):
		var entry: Dictionary = shells[i]
		var s_id: String = str(entry.get("shell_id", "")).strip_edges().to_lower()
		var display_name: String = str(entry.get("display_name", s_id.capitalize()))
		opt.add_item(display_name, i)
		opt.set_item_metadata(i, s_id)
		if s_id == target_id:
			selected_idx = i

	if opt.item_count > 0:
		opt.select(selected_idx)
	opt.visible = opt.item_count > 1
	_is_populating_shells = false

func _on_shell_option_selected(index: int) -> void:
	if _is_populating_shells:
		return
	var opt: OptionButton = shell_option if shell_option != null else get_node_or_null("Layout/HeaderBar/ShellOption") as OptionButton
	if opt == null:
		return
	var selected_id: String = str(opt.get_item_metadata(index)).strip_edges().to_lower()
	if not selected_id.is_empty():
		shell_switch_requested.emit(selected_id)

## Mounts an era presentation shell (e.g. PocketbooksSpread, FilofaxSpread, or Apple2CrtSpread)
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
		var holder: MarginContainer = spread_holder if spread_holder else get_node_or_null("Layout/SpreadHolder")
		if holder and holder.get_child_count() > 0:
			_active_spread = holder.get_child(0)

	if _active_spread != null and _active_spread.has_method("get_slot"):
		return _active_spread.get_slot(slot_name)
	return null

## Mounts a Control node into a named slot, clearing existing children immediately
func mount_view(
	slot_name: String,
	view_node: Control,
	free_existing: bool = true
) -> void:
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
		if free_existing:
			child.queue_free()

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