# res://scenes/ui/filofax/filofax_ui.gd
extends PanelContainer
class_name FilofaxUI

const FILOFAX_MGR = preload("res://systems/filofax_manager.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")

# Window & Page Hierarchy
@onready var header_bar: HBoxContainer = $"Binder Shell/HeaderBar"
@onready var close_button: Button = $"Binder Shell/HeaderBar/CloseButton"
@onready var current_date_label: Label = $"Binder Shell/HeaderBar/CurrentDateLabel"
@onready var comms_device_icon: Label = $"Binder Shell/HeaderBar/CommsDeviceIcon"

@onready var tab_container: TabContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer"
@onready var telemetry_tab: ScrollContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/TelemetryTab"
@onready var roster_tab: ScrollContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/RosterTab"
@onready var financials_tab: ScrollContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/FinancialsTab"

@onready var memo_list: ScrollContainer = $"Binder Shell/PageSpread/RingSpike_Center/MemoScroll"
@onready var directive_queue: ItemList = $"Binder Shell/PageSpread/RightPage_Planner/Operational/DirectiveQueue"
@onready var add_order_button: Button = $"Binder Shell/PageSpread/RightPage_Planner/Operational/ActionButtons/AddOrderButton"
@onready var execute_turn_button: Button = $"Binder Shell/PageSpread/RightPage_Planner/Operational/ExecuteTurnButton"

# Floating Sticky Note Hub
@onready var sticky_popup: PanelContainer = get_node_or_null("../StickyNotePopup") if has_node("../StickyNotePopup") else get_node_or_null("StickyNotePopup")
@onready var drag_handle: Label = get_node_or_null("../StickyNotePopup/VBoxContainer/StickyHeader/DragHandle")
@onready var close_note_btn: Button = get_node_or_null("../StickyNotePopup/VBoxContainer/StickyHeader/CloseNoteButton")

@onready var verb_opt: OptionButton = get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Action/VBox/VerbOption")
@onready var target_opt: OptionButton = get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_What/VBox/TargetOption")
@onready var amount_spin: SpinBox = get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Amount/VBox/AmountSpin")
@onready var who_opt: OptionButton = get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Who/VBox/WhoOption")
@onready var where_opt: OptionButton = get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Where/VBox/WhereOption")
@onready var est_label: Label = get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Estimate/VBox/EstimatedCostLabel")

@onready var pin_btn: Button = get_node_or_null("../StickyNotePopup/VBoxContainer/ButtonBox/SaveNoteBtn")
@onready var discard_btn: Button = get_node_or_null("../StickyNotePopup/VBoxContainer/ButtonBox/DiscardBtn")

# Autonomous Docket Sub-Component
var _docket_controller: FilofaxDistrictDocket = null

var _world_state: Dictionary = {}
var _filofax_cache: Dictionary = {}
var _staged_directives: Array = []
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _is_binder_dragging: bool = false
var _binder_drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	_setup_binder_dragging()
	_setup_docket_controller()
	_setup_sticky_note_buttons()
	_setup_drag_and_theming()

func initialize(world_state: Dictionary, filofax_cache: Dictionary) -> void:
	_world_state = world_state
	_filofax_cache = filofax_cache
	update_display(_filofax_cache)

## Resolves or instantiates the docket controller once
func _setup_docket_controller() -> void:
	if telemetry_tab == null:
		return
	
	# Look for an existing child in the scene tree
	_docket_controller = telemetry_tab.find_child("DocketContent", true, false) as FilofaxDistrictDocket
	
	# If not placed in the .tscn, instantiate it as a permanent child
	if _docket_controller == null:
		_docket_controller = FilofaxDistrictDocket.new()
		_docket_controller.name = "DocketContent"
		telemetry_tab.add_child(_docket_controller)

func _setup_sticky_note_buttons() -> void:
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	if execute_turn_button:
		execute_turn_button.pressed.connect(_on_commit_orders_pressed)
	if add_order_button:
		add_order_button.pressed.connect(_open_sticky_pad)
	if close_note_btn:
		close_note_btn.pressed.connect(func(): sticky_popup.visible = false)
	if discard_btn:
		discard_btn.pressed.connect(func(): sticky_popup.visible = false)
	if pin_btn:
		pin_btn.pressed.connect(_on_pin_directive)

	if verb_opt:
		verb_opt.item_selected.connect(_on_verb_changed)
	if target_opt:
		target_opt.item_selected.connect(_recalculate_estimate)
	if amount_spin:
		amount_spin.value_changed.connect(_recalculate_estimate)

## Public API: Displays a specific district's docket on the left Telemetry tab
func display_district_docket(block_id: String) -> void:
	if tab_container != null:
		tab_container.current_tab = 0

	if _docket_controller != null:
		_docket_controller.display_district(block_id)

	_sync_sticky_note_location(block_id)

func _sync_sticky_note_location(target_block_id: String) -> void:
	if where_opt == null or target_block_id.is_empty():
		return
	for i in range(where_opt.item_count):
		var meta = where_opt.get_item_metadata(i)
		if meta == target_block_id or where_opt.get_item_text(i) == target_block_id:
			where_opt.select(i)
			return

# --- BINDER DRAGGING ---
func _setup_binder_dragging() -> void:
	if header_bar:
		header_bar.mouse_filter = Control.MOUSE_FILTER_STOP
		header_bar.gui_input.connect(_on_header_bar_gui_input)

func _on_header_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			_is_binder_dragging = true
			_binder_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_is_binder_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _is_binder_dragging:
		global_position = get_global_mouse_position() + _binder_drag_offset
		accept_event()

# --- STICKY NOTE HUB LOGIC ---
func _setup_drag_and_theming() -> void:
	if not sticky_popup:
		return
	_color_note(get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Action"), Color("#FFF899"))
	_color_note(get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_What"), Color("#BAE1FF"))
	_color_note(get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Amount"), Color("#FFDFBA"))
	_color_note(get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Who"), Color("#BFFCC6"))
	_color_note(get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Where"), Color("#E8C5FF"))
	_color_note(get_node_or_null("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Estimate"), Color("#FFB3BA"))

	if drag_handle:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_handle.gui_input.connect(_on_drag_handle_input)

func _color_note(panel: PanelContainer, col: Color) -> void:
	if not panel: return
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 4
	panel.add_theme_stylebox_override("panel", sb)
	_apply_text_color_recursive(panel, Color(0.1, 0.1, 0.1, 1.0))

func _apply_text_color_recursive(node: Node, color: Color) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", color)
	elif node is OptionButton or node is Button:
		node.add_theme_color_override("font_color", color)
		node.add_theme_color_override("font_pressed_color", color)
		node.add_theme_color_override("font_hover_color", color)
		node.add_theme_color_override("font_focus_color", color)
		if node is OptionButton:
			node.get_popup().add_theme_color_override("font_color", color)
	elif node is SpinBox:
		node.get_line_edit().add_theme_color_override("font_color", color)
	for child in node.get_children():
		_apply_text_color_recursive(child, color)

func _on_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			_is_dragging = true
			_drag_offset = sticky_popup.global_position - get_global_mouse_position()
		else:
			_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		sticky_popup.global_position = get_global_mouse_position() + _drag_offset

func _open_sticky_pad() -> void:
	if not sticky_popup: return
	sticky_popup.visible = true
	verb_opt.clear()
	verb_opt.add_item("BUY")
	verb_opt.add_item("SELL")
	verb_opt.add_item("MAKE")
	
	where_opt.clear()
	for dist_id in _world_state.get("districts", {}).keys():
		var d: Dictionary = _world_state["districts"][dist_id]
		where_opt.add_item(d.get("display_name", dist_id))
		where_opt.set_item_metadata(where_opt.item_count - 1, dist_id)
		
	_on_verb_changed(0)

func _on_verb_changed(idx: int) -> void:
	var verb := verb_opt.get_item_text(idx)
	target_opt.clear()
	who_opt.clear()

	if verb == "MAKE":
		who_opt.add_item("Local Workshop Staff")
		who_opt.set_item_metadata(0, "PLAYER_CREW")
		for r_id in _world_state.get("recipe_registry", {}).keys():
			var r: Dictionary = _world_state["recipe_registry"][r_id]
			target_opt.add_item(r.get("display_name", r_id))
			target_opt.set_item_metadata(target_opt.item_count - 1, r_id)
	else:
		for c_id in _world_state.get("commodity_registry", {}).keys():
			var c: Dictionary = _world_state["commodity_registry"][c_id]
			target_opt.add_item(c.get("display_name", c_id))
			target_opt.set_item_metadata(target_opt.item_count - 1, c_id)

		for cp_id in _world_state.get("counterparties", {}).keys():
			var cp: Dictionary = _world_state["counterparties"][cp_id]
			who_opt.add_item(cp.get("display_name", cp_id))
			who_opt.set_item_metadata(who_opt.item_count - 1, cp_id)

	_recalculate_estimate(0)

func _recalculate_estimate(_val) -> void:
	var verb := verb_opt.get_item_text(verb_opt.selected)
	var qty := amount_spin.value
	var target_id = target_opt.get_selected_metadata()

	if verb == "MAKE":
		est_label.text = "Yield: %.0f units" % qty
	else:
		var base: float = _world_state.get("commodity_registry", {}).get(target_id, {}).get("base_cost", 1.0)
		var total: float = qty * base * (1.5 if verb == "SELL" else 1.0)
		est_label.text = "£%.2f" % total

func _on_pin_directive() -> void:
	var verb := verb_opt.get_item_text(verb_opt.selected)
	var target_id = target_opt.get_selected_metadata()
	var where_id = where_opt.get_selected_metadata()
	var qty := amount_spin.value

	var directive := {
		"verb": verb,
		"target_item": target_id,
		"amount": qty,
		"target_node_id": where_id
	}

	if verb != "MAKE":
		directive["initiator_id"] = "PLAYER"
		directive["counterparty_id"] = who_opt.get_selected_metadata()
		var base: float = _world_state["commodity_registry"][target_id].get("base_cost", 1.0)
		directive["config"] = {
			"unit_cost": base,
			"unit_price": base * 1.5,
			"exposure_modifier": 1.0
		}

	_staged_directives.append(directive)
	_refresh_directive_list()
	sticky_popup.visible = false

func _refresh_directive_list() -> void:
	directive_queue.clear()
	for i in range(_staged_directives.size()):
		var cmd: Dictionary = _staged_directives[i]
		directive_queue.add_item("%d. [%s] %s x%.0f @ %s" % [
			i + 1, cmd.get("verb", ""), cmd.get("target_item", ""), float(cmd.get("amount", 1)), cmd.get("target_node_id", "")
		])

func _on_commit_orders_pressed() -> void:
	if _staged_directives.is_empty():
		return

	for directive in _staged_directives:
		var res: Dictionary = SIM_CONTROLLER.execute_directive(_world_state, directive)
		_filofax_cache["pinned_memos"].append({
			"tick": _world_state.get("metadata", {}).get("current_week_tick", 1),
			"text": res.get("message", "Executed %s" % directive.get("verb", ""))
		})

	_staged_directives.clear()
	_refresh_directive_list()

	SIM_CONTROLLER.process_ambient_heartbeat(_world_state)
	FILOFAX_MGR.refresh_cache_instant(_world_state, _filofax_cache)
	update_display(_filofax_cache)
	execute_turn_button.set_pressed_no_signal(false)

func update_display(cache: Dictionary) -> void:
	var tick: int = cache.get("metadata", {}).get("viewed_tick", 1)
	current_date_label.text = "WEEK %d - 1988" % tick
	comms_device_icon.text = "[%s]" % cache.get("metadata", {}).get("active_hardware", "DIRECT_DESK")

	for child in financials_tab.get_children():
		child.queue_free()
	var c_lbl := Label.new()
	c_lbl.text = "VAULT CASH: £%.2f" % cache.get("finances", {}).get("reported_cash", 0.0)
	financials_tab.add_child(c_lbl)

	for child in memo_list.get_children():
		child.queue_free()
	for memo in cache.get("pinned_memos", []):
		var slip := Label.new()
		slip.text = "[Wk %d]: %s" % [memo.get("tick", 0), memo.get("text", "")]
		memo_list.add_child(slip)

func _on_close_button_pressed() -> void:
	# Hide this binder panel
	visible = false

	# Also hide the parent CanvasLayer if we are nested inside one (e.g. FilofaxCanvas in city_view)
	var canvas := get_parent()
	while canvas != null and not (canvas is CanvasLayer):
		canvas = canvas.get_parent()

	if canvas is CanvasLayer:
		canvas.visible = false
