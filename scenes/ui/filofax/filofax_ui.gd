# res://scenes/ui/filofax/filofax_ui.gd
extends PanelContainer
class_name FilofaxUI

const FILOFAX_MGR = preload("res://systems/filofax_manager.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")

@onready var current_date_label: Label = $"Binder Shell/HeaderBar/CurrentDateLabel"
@onready var comms_device_icon: Label = $"Binder Shell/HeaderBar/CommsDeviceIcon"
@onready var close_button: CheckButton = $"Binder Shell/HeaderBar/CloseButton"

@onready var telemetry_tab: VBoxContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/TelemetryTab"
@onready var roster_tab: VBoxContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/RosterTab"
@onready var financials_tab: VBoxContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/FinancialsTab"

@onready var memo_list: VBoxContainer = $"Binder Shell/PageSpread/RingSpike_Center/MemoScroll/MemoList"
@onready var directive_queue: ItemList = $"Binder Shell/PageSpread/RightPage_Planner/Operational/DirectiveQueue"
@onready var add_order_button: Button = $"Binder Shell/PageSpread/RightPage_Planner/Operational/ActionButtons/AddOrderButton"
@onready var execute_turn_button: CheckButton = $"Binder Shell/PageSpread/RightPage_Planner/Operational/ExecuteTurnButton"

# Floating Sticky Note Hub
@onready var sticky_popup: PanelContainer = get_node("../StickyNotePopup")
@onready var drag_handle: Label = get_node("../StickyNotePopup/VBoxContainer/StickyHeader/DragHandle")
@onready var close_note_btn: Button = get_node("../StickyNotePopup/VBoxContainer/StickyHeader/CloseNoteButton")

@onready var verb_opt: OptionButton = get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Action/VBox/VerbOption")
@onready var target_opt: OptionButton = get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_What/VBox/TargetOption")
@onready var amount_spin: SpinBox = get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Amount/VBox/AmountSpin")
@onready var who_opt: OptionButton = get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Who/VBox/WhoOption")
@onready var where_opt: OptionButton = get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Where/VBox/WhereOption")
@onready var est_label: Label = get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Estimate/VBox/EstimatedCostLabel")

@onready var pin_btn: Button = get_node("../StickyNotePopup/VBoxContainer/ButtonBox/SaveNoteBtn")
@onready var discard_btn: Button = get_node("../StickyNotePopup/VBoxContainer/ButtonBox/DiscardBtn")

var _world_state: Dictionary = {}
var _filofax_cache: Dictionary = {}
var _staged_directives: Array = []
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	if close_button:
		close_button.toggled.connect(func(pressed): visible = not pressed)
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

	_setup_drag_and_theming()

func initialize(world_state: Dictionary, filofax_cache: Dictionary) -> void:
	_world_state = world_state
	_filofax_cache = filofax_cache
	update_display(_filofax_cache)

func _setup_drag_and_theming() -> void:
	# 1. Pastel Color Styling
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Action"), Color("#FFF899"))    # Yellow
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_What"), Color("#BAE1FF"))      # Blue
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Amount"), Color("#FFDFBA"))    # Peach
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Who"), Color("#BFFCC6"))       # Mint
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Where"), Color("#E8C5FF"))     # Lavender
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Estimate"), Color("#FFB3BA"))  # Rose

	# 2. Window Dragging
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.gui_input.connect(_on_drag_handle_input)

func _color_note(panel: PanelContainer, col: Color) -> void:
	#Apply background style
	var sb = StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 4
	panel.add_theme_stylebox_override("panel", sb)

	#Set all inner labels, buttons, and dropdowns to black ink
	var ink_color = Color(0.1, 0.1, 0.1, 1.0)
	_apply_text_color_recursive(panel, ink_color)

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
	sticky_popup.visible = true
	verb_opt.clear()
	verb_opt.add_item("BUY")
	verb_opt.add_item("SELL")
	verb_opt.add_item("MAKE")
	
	# Populate Where Options dynamically from registered districts
	where_opt.clear()
	for dist_id in _world_state.get("districts", {}).keys():
		var d = _world_state["districts"][dist_id]
		where_opt.add_item(d.get("display_name", dist_id))
		where_opt.set_item_metadata(where_opt.item_count - 1, dist_id)
		
	_on_verb_changed(0)

func _on_verb_changed(idx: int) -> void:
	var verb = verb_opt.get_item_text(idx)
	target_opt.clear()
	who_opt.clear()

	if verb == "MAKE":
		who_opt.add_item("Local Workshop Staff")
		who_opt.set_item_metadata(0, "PLAYER_CREW")
		for r_id in _world_state.get("recipe_registry", {}).keys():
			var r = _world_state["recipe_registry"][r_id]
			target_opt.add_item(r.get("display_name", r_id))
			target_opt.set_item_metadata(target_opt.item_count - 1, r_id)
	else:
		for c_id in _world_state.get("commodity_registry", {}).keys():
			var c = _world_state["commodity_registry"][c_id]
			target_opt.add_item(c.get("display_name", c_id))
			target_opt.set_item_metadata(target_opt.item_count - 1, c_id)

		for cp_id in _world_state.get("counterparties", {}).keys():
			var cp = _world_state["counterparties"][cp_id]
			who_opt.add_item(cp.get("display_name", cp_id))
			who_opt.set_item_metadata(who_opt.item_count - 1, cp_id)

	_recalculate_estimate(0)

func _recalculate_estimate(_val) -> void:
	var verb = verb_opt.get_item_text(verb_opt.selected)
	var qty = amount_spin.value
	var target_id = target_opt.get_selected_metadata()

	if verb == "MAKE":
		est_label.text = "Yield: %.0f units" % qty
	else:
		var base = _world_state.get("commodity_registry", {}).get(target_id, {}).get("base_cost", 1.0)
		var total = qty * base * (1.5 if verb == "SELL" else 1.0)
		est_label.text = "£%.2f" % total

func _on_pin_directive() -> void:
	var verb = verb_opt.get_item_text(verb_opt.selected)
	var target_id = target_opt.get_selected_metadata()
	var where_id = where_opt.get_selected_metadata()
	var qty = amount_spin.value

	var directive = {
		"verb": verb,
		"target_item": target_id,
		"amount": qty,
		"target_node_id": where_id
	}

	if verb != "MAKE":
		directive["initiator_id"] = "PLAYER"
		directive["counterparty_id"] = who_opt.get_selected_metadata()
		var base = _world_state["commodity_registry"][target_id].get("base_cost", 1.0)
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
		var cmd = _staged_directives[i]
		directive_queue.add_item("%d. [%s] %s x%.0f @ %s" % [
			i + 1, cmd.get("verb", ""), cmd.get("target_item", ""), float(cmd.get("amount", 1)), cmd.get("target_node_id", "")
		])

func _on_commit_orders_pressed() -> void:
	if _staged_directives.is_empty():
		return

	for directive in _staged_directives:
		var res = SIM_CONTROLLER.execute_directive(_world_state, directive)
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
	var tick = cache.get("metadata", {}).get("viewed_tick", 1)
	current_date_label.text = "WEEK %d - 1988" % tick
	comms_device_icon.text = "[%s]" % cache.get("metadata", {}).get("active_hardware", "DIRECT_DESK")

	for child in telemetry_tab.get_children():
		child.queue_free()
	for dist_id in cache.get("districts", {}).keys():
		var data = cache["districts"][dist_id]
		var row = HBoxContainer.new()
		var n_lbl = Label.new()
		n_lbl.text = "%s: " % data.get("display_name", dist_id)
		row.add_child(n_lbl)
		var s_lbl = Label.new()
		s_lbl.text = "Heat %d%% | ZHI %d%%" % [int(data.get("inked_police_heat", 0.0) * 100), int(data.get("inked_zone_health", 100.0))]
		s_lbl.modulate = Color.GREEN if data.get("data_age_ticks", 0) <= 2 else Color.DARK_ORANGE
		row.add_child(s_lbl)
		telemetry_tab.add_child(row)

	for child in financials_tab.get_children():
		child.queue_free()
	var c_lbl = Label.new()
	c_lbl.text = "VAULT CASH: £%.2f" % cache.get("finances", {}).get("reported_cash", 0.0)
	financials_tab.add_child(c_lbl)

	for child in memo_list.get_children():
		child.queue_free()
	for memo in cache.get("pinned_memos", []):
		var slip = Label.new()
		slip.text = "[Wk %d]: %s" % [memo.get("tick", 0), memo.get("text", "")]
		memo_list.add_child(slip)
	
func _apply_text_color_recursive(node: Node, color: Color) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", color)
		
	elif node is OptionButton or node is Button:
		node.add_theme_color_override("font_color", color)
		node.add_theme_color_override("font_pressed_color", color)
		node.add_theme_color_override("font_hover_color", color)
		node.add_theme_color_override("font_focus_color", color)
		# Style the popup dropdown list menu attached to the button
		if node is OptionButton:
			var popup = node.get_popup()
			popup.add_theme_color_override("font_color", color)
			popup.add_theme_color_override("font_hover_color", color)
			
	elif node is SpinBox:
		var line_edit = node.get_line_edit()
		line_edit.add_theme_color_override("font_color", color)
		line_edit.add_theme_color_override("font_selected_color", color)
	
	for child in node.get_children():
		_apply_text_color_recursive(child, color)