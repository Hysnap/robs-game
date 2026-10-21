# res://scenes/ui/filofax/filofax_ui.gd
extends PanelContainer
class_name FilofaxUI

const FILOFAX_MGR = preload("res://systems/filofax_manager.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")

@onready var current_date_label: Label = $"Binder Shell/HeaderBar/CurrentDateLabel"
@onready var comms_device_icon: Label = $"Binder Shell/HeaderBar/CommsDeviceIcon"
@onready var close_button: Button = $"Binder Shell/HeaderBar/CloseButton"

@onready var telemetry_tab: VBoxContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/TelemetryTab"
@onready var roster_tab: VBoxContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/RosterTab"
@onready var financials_tab: VBoxContainer = $"Binder Shell/PageSpread/LeftPage_Ledger/TabContainer/FinancialsTab"

@onready var memo_list: VBoxContainer = $"Binder Shell/PageSpread/RingSpike_Center/MemoScroll/MemoList"
@onready var directive_queue: ItemList = $"Binder Shell/PageSpread/RightPage_Planner/Operational/DirectiveQueue"
@onready var add_order_button: Button = $"Binder Shell/PageSpread/RightPage_Planner/Operational/ActionButtons/AddOrderButton"
@onready var execute_turn_button: Button = $"Binder Shell/PageSpread/RightPage_Planner/Operational/ExecuteTurnButton"

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
var _district_ui_labels: Dictionary = {}

func _ready() -> void:
	_load_district_ui_labels()
	
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
	if not sticky_popup:
		return
	# 1. Pastel Color Styling
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Action"), Color("#FFF899"))
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_What"), Color("#BAE1FF"))
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Amount"), Color("#FFDFBA"))
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Who"), Color("#BFFCC6"))
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Where"), Color("#E8C5FF"))
	_color_note(get_node("../StickyNotePopup/VBoxContainer/NotesGrid/StickyNote_Estimate"), Color("#FFB3BA"))

	# 2. Window Dragging
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

	var ink_color := Color(0.1, 0.1, 0.1, 1.0)
	_apply_text_color_recursive(panel, ink_color)

func _apply_text_color_recursive(node: Node, color: Color) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", color)
	elif node is OptionButton or node is Button:
		node.add_theme_color_override("font_color", color)
		node.add_theme_color_override("font_pressed_color", color)
		node.add_theme_color_override("font_hover_color", color)
		node.add_theme_color_override("font_focus_color", color)
		if node is OptionButton:
			var popup: PopupMenu = node.get_popup()
			popup.add_theme_color_override("font_color", color)
			popup.add_theme_color_override("font_hover_color", color)
	elif node is SpinBox:
		var line_edit: LineEdit = node.get_line_edit()
		line_edit.add_theme_color_override("font_color", color)
		line_edit.add_theme_color_override("font_selected_color", color)
	
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
	
	# Populate Where Options dynamically from registered districts
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

	for child in telemetry_tab.get_children():
		child.queue_free()
	for dist_id in cache.get("districts", {}).keys():
		var data: Dictionary = cache["districts"][dist_id]
		var row := HBoxContainer.new()
		var n_lbl := Label.new()
		n_lbl.text = "%s: " % data.get("display_name", dist_id)
		row.add_child(n_lbl)
		var s_lbl := Label.new()
		s_lbl.text = "Heat %d%% | ZHI %d%%" % [int(data.get("inked_police_heat", 0.0) * 100), int(data.get("inked_zone_health", 100.0))]
		s_lbl.modulate = Color.GREEN if data.get("data_age_ticks", 0) <= 2 else Color.DARK_ORANGE
		row.add_child(s_lbl)
		telemetry_tab.add_child(row)

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

## Displays a specific district's docket on the left Telemetry tab using district_ui.json tokens
func display_district_docket(district_id: String) -> void:
	if _district_ui_labels.is_empty():
		_load_district_ui_labels()

	if not telemetry_tab:
		return
		
	for child in telemetry_tab.get_children():
		child.queue_free()
		
	var cache_data: Dictionary = GameState.get_district_filofax(district_id)
	if cache_data.is_empty():
		var blank_lbl := Label.new()
		blank_lbl.text = "No records found for district: %s" % district_id
		telemetry_tab.add_child(blank_lbl)
		return

	var is_surveyed: bool = (cache_data.get("survey_status", "UNSURVEYED") == "SURVEYED")
	var disp_name: String = cache_data.get("display_name", district_id)

	# 1. Header with dynamic title token
	var title_tpl: String = _district_ui_labels.get("ward_dossier_title", "WARD DOSSIER: {name}")
	var title := Label.new()
	title.text = title_tpl.replace("{name}", disp_name)
	title.add_theme_font_size_override("font_size", 16)
	telemetry_tab.add_child(title)
	
	var separator := HSeparator.new()
	telemetry_tab.add_child(separator)
	
	if not is_surveyed:
		# --- UNSURVEYED FOG VIEW ---
		var fog_box := VBoxContainer.new()
		
		var warn_lbl := Label.new()
		warn_lbl.text = _district_ui_labels.get("unsurveyed_header", "[!] UNSURVEYED TERRITORY")
		warn_lbl.modulate = Color(0.9, 0.7, 0.2)
		fog_box.add_child(warn_lbl)
		
		var note_lbl := Label.new()
		note_lbl.text = "\n" + _district_ui_labels.get("unsurveyed_subtext", "Requires physical reconnaissance on foot.")
		note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		fog_box.add_child(note_lbl)
		
		var scout_btn := Button.new()
		var btn_tpl: String = _district_ui_labels.get("dispatch_scout_btn", "Dispatch Runner to Walk Parade ({cost})")
		scout_btn.text = btn_tpl.replace("{cost}", "£5.00")
		scout_btn.pressed.connect(func(): _on_scout_district_pressed(district_id))
		fog_box.add_child(scout_btn)
		
		telemetry_tab.add_child(fog_box)
	else:
		# --- SURVEYED INKED VIEW ---
		var dossier_box := VBoxContainer.new()
		var age: int = cache_data.get("data_age_ticks", 0)
		
		var age_lbl := Label.new()
		var age_tpl: String = _district_ui_labels.get("data_age", "Field Notes Age: {age} week(s) old")
		age_lbl.text = age_tpl.replace("{age}", str(age))
		if age > 4:
			age_lbl.text += " " + _district_ui_labels.get("stale_warning", "[STALE PENCIL INTELLIGENCE]")
			age_lbl.modulate = Color.DARK_ORANGE
		else:
			age_lbl.modulate = Color.GREEN
		dossier_box.add_child(age_lbl)
		
		var type_lbl := Label.new()
		var type_tpl: String = _district_ui_labels.get("type_label", "Classification: {type}")
		type_lbl.text = type_tpl.replace("{type}", cache_data.get("district_type", "Residential"))
		dossier_box.add_child(type_lbl)
		
		var stats_lbl := Label.new()
		stats_lbl.text = "Reported Police Heat: %d%% | Zone Health: %d%%" % [
			int(cache_data.get("inked_police_heat", 0.0) * 100),
			int(cache_data.get("inked_zone_health", 0.0))
		]
		dossier_box.add_child(stats_lbl)
		
		var notes_lbl := Label.new()
		notes_lbl.text = "\nRunner Notes:\n\"%s\"" % cache_data.get("notes", "")
		notes_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		dossier_box.add_child(notes_lbl)
		
		telemetry_tab.add_child(dossier_box)

	# Auto-sync sticky note "Where" dropdown to clicked district
	_sync_sticky_note_location(district_id)

func _on_scout_district_pressed(district_id: String) -> void:
	var cash: float = GameState.world_state.get("finances", {}).get("liquid_cash", 0.0)
	if cash < 5.00:
		var warn_msg: String = _district_ui_labels.get("insufficient_funds", "Cannot dispatch runner: insufficient cash.")
		print("[FILOFAX] %s" % warn_msg)
		return
		
	GameState.world_state["finances"]["liquid_cash"] = cash - 5.00
	
	var truth: Dictionary = GameState.get_district_truth(district_id)
	var cache_entry: Dictionary = GameState.get_district_filofax(district_id)
	
	cache_entry["survey_status"] = "SURVEYED"
	cache_entry["district_type"] = truth.get("district_type", "Residential")
	cache_entry["inked_police_heat"] = truth.get("actual_police_heat", 0.20)
	cache_entry["inked_zone_health"] = truth.get("zone_health_index", 50.0)
	cache_entry["data_age_ticks"] = 0
	cache_entry["last_verified_tick"] = GameState.world_state.get("metadata", {}).get("current_week_tick", 1)
	cache_entry["notes"] = "Pavements walked. Commercial parade and local footfall catalogued."
	
	display_district_docket(district_id)
	print("[FILOFAX] Runner dispatched. Inked survey notes pinned for: %s" % cache_entry.get("display_name"))

func _sync_sticky_note_location(district_id: String) -> void:
	# Matches WhereOption declared on sticky note pad
	if where_opt:
		for i in range(where_opt.get_item_count()):
			if where_opt.get_item_metadata(i) == district_id:
				where_opt.selected = i
				break

func _load_district_ui_labels(path: String = "res://data_modules/core/feedback/spatial/district_ui.json") -> void:
	if not FileAccess.file_exists(path):
		push_error("[FILOFAX] UI definition file missing: %s" % path)
		return
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_district_ui_labels = json.data.get("filofax_labels", {})