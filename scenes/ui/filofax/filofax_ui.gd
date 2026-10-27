# res://scenes/ui/filofax/filofax_ui.gd
extends PanelContainer
class_name FilofaxUI

const FILOFAX_MGR = preload("res://systems/filofax_manager.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")
const RETRO_THEME = preload("res://scenes/ui/filofax/retro_theme.gd")

# --- Left Divider Tabs (Macro Groupings) ---
@onready var tab_diary_btn: Button = get_node_or_null("BinderContent/LeftDividerTabs/TabDiary")
@onready var tab_dossier_btn: Button = get_node_or_null("BinderContent/LeftDividerTabs/TabDossier")
@onready var tab_roster_btn: Button = get_node_or_null("BinderContent/LeftDividerTabs/TabRoster")
@onready var tab_finance_btn: Button = get_node_or_null("BinderContent/LeftDividerTabs/TabFinance")
@onready var tab_styles_btn: Button = get_node_or_null("BinderContent/LeftDividerTabs/TabStyles")
@onready var tab_close_btn: Button = get_node_or_null("BinderContent/LeftDividerTabs/TabClose")

# --- Top Horizontal Tabs (Sub-Sections within active Macro) ---
@onready var sub_section_bar: HBoxContainer = get_node_or_null("BinderContent/PageSpread/LeftPage_Ledger/PageVBox/SubSectionTabs")
@onready var ledger_stack: TabContainer = get_node_or_null("BinderContent/PageSpread/LeftPage_Ledger/PageVBox/LedgerStack")

# --- Content Panes ---
@onready var telemetry_tab: Control = get_node_or_null("BinderContent/PageSpread/LeftPage_Ledger/PageVBox/LedgerStack/TelemetryTab")
@onready var roster_list: Control = get_node_or_null("BinderContent/PageSpread/LeftPage_Ledger/PageVBox/LedgerStack/RosterTab/RosterList")
@onready var financial_list: Control = get_node_or_null("BinderContent/PageSpread/LeftPage_Ledger/PageVBox/LedgerStack/FinancialsTab/FinancialList")

@onready var memo_list: Control = get_node_or_null("BinderContent/PageSpread/RingSpike_Center/MemoScroll/MemoList")
@onready var directive_queue: ItemList = get_node_or_null("BinderContent/PageSpread/RightPage_Planner/Operational/DirectiveQueue")
@onready var add_order_button: Button = get_node_or_null("BinderContent/PageSpread/RightPage_Planner/Operational/ActionButtons/AddOrderButton")
@onready var execute_turn_button: Button = get_node_or_null("BinderContent/PageSpread/RightPage_Planner/Operational/ExecuteTurnButton")

# Popups
@onready var customizer_popup: FilofaxCustomizer = get_node_or_null("../FilofaxCustomizer") if has_node("../FilofaxCustomizer") else get_node_or_null("FilofaxCustomizer")
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
@onready var btn_move_up: Button = get_node_or_null("BinderContent/PageSpread/RightPage_Planner/Operational/ActionButtons/BtnMoveUp")
@onready var btn_move_down: Button = get_node_or_null("BinderContent/PageSpread/RightPage_Planner/Operational/ActionButtons/BtnMoveDown")

var _docket_controller: FilofaxDistrictDocket = null
var _world_state: Dictionary = {}
var _filofax_cache: Dictionary = {}
var _staged_directives: Array = []
var _is_binder_dragging: bool = false
var _binder_drag_offset: Vector2 = Vector2.ZERO
var _current_macro_domain: String = "DOSSIER"
var _active_sub_tab_index: int = 0

# --- Two-Tier Hierarchy Definition ---
const SUB_SECTIONS: Dictionary = {
	"DIARY": [
		{"token": "UI_SUBTAB_CALENDAR", "page_index": 0},
		{"token": "UI_SUBTAB_FUTURE_EVENTS", "page_index": 0},
		{"token": "UI_SUBTAB_APPOINTMENTS", "page_index": 0}
	],
	"DOSSIER": [
		{"token": "UI_SUBTAB_CENSUS", "page_index": 0},
		{"token": "UI_SUBTAB_ESTABLISHMENTS", "page_index": 0},
		{"token": "UI_SUBTAB_HEAT", "page_index": 0}
	],
	"ROSTER": [
		{"token": "UI_SUBTAB_ACTIVE_AGENTS", "page_index": 1},
		{"token": "UI_SUBTAB_PAYROLL_CUTS", "page_index": 1},
		{"token": "UI_SUBTAB_RECRUITS", "page_index": 1}
	],
	"FINANCE": [
		{"token": "UI_SUBTAB_VAULT_LEDGER", "page_index": 2},
		{"token": "UI_SUBTAB_DEBT_ARREARS", "page_index": 2},
		{"token": "UI_SUBTAB_WHOLESALE_TARIFFS", "page_index": 2}
	]
}

func _ready() -> void:
	RETRO_THEME.load_all_profiles()
	_setup_binder_dragging()
	_setup_docket_controller()
	_setup_macro_tabs()
	_setup_sticky_note_buttons()
	_setup_drag_and_theming()
	_apply_filofax_stationery_theme()
	_setup_directive_queue_reordering()
	
	# Initial navigation state
	select_macro_domain("DOSSIER")

func initialize(world_state: Dictionary, filofax_cache: Dictionary) -> void:
	_world_state = world_state
	_filofax_cache = filofax_cache
	update_display(_filofax_cache)

func _setup_binder_dragging() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(_on_binder_gui_input):
		gui_input.connect(_on_binder_gui_input)

func _on_binder_gui_input(event: InputEvent) -> void:
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

func _setup_macro_tabs() -> void:
	if tab_diary_btn:   tab_diary_btn.pressed.connect(func(): select_macro_domain("DIARY"))
	if tab_dossier_btn: tab_dossier_btn.pressed.connect(func(): select_macro_domain("DOSSIER"))
	if tab_roster_btn:  tab_roster_btn.pressed.connect(func(): select_macro_domain("ROSTER"))
	if tab_finance_btn: tab_finance_btn.pressed.connect(func(): select_macro_domain("FINANCE"))
	if tab_styles_btn:  tab_styles_btn.pressed.connect(_toggle_customizer)
	if tab_close_btn:   tab_close_btn.pressed.connect(_on_close_button_pressed)

	if customizer_popup:
		customizer_popup.colors_updated.connect(_on_colors_live_updated)

## Selects a left-hand macro divider and rebuilds the top sub-section tabs
func select_macro_domain(domain_key: String) -> void:
	_current_macro_domain = domain_key
	_rebuild_top_sub_section_tabs()
	_update_macro_tab_visual_selection()

func _rebuild_top_sub_section_tabs() -> void:
	if sub_section_bar == null:
		return

	# Clear previous sub-tabs
	for child in sub_section_bar.get_children():
		child.queue_free()

	var sections: Array = SUB_SECTIONS.get(_current_macro_domain, [])
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	for i in range(sections.size()):
		var sec_data: Dictionary = sections[i]
		var sub_btn := Button.new()
		sub_btn.text = tr(sec_data.get("token", "UI_SUBTAB_SECTION"))
		sub_btn.focus_mode = Control.FOCUS_NONE
		sub_btn.add_theme_font_override("font", mono_font)
		sub_btn.add_theme_font_size_override("font_size", 10)
		
		# Top-rounded tab styling
		var style := StyleBoxFlat.new()
		style.bg_color = RETRO_THEME.color_page_bg
		style.set_corner_radius_all(0)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.set_content_margin_all(4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.border_color = RETRO_THEME.color_ruled_line
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 0
		
		sub_btn.add_theme_stylebox_override("normal", style)
		sub_btn.add_theme_stylebox_override("hover", style)
		sub_btn.add_theme_stylebox_override("pressed", style)
		sub_btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)

		var page_target: int = int(sec_data.get("page_index", 0))
		sub_btn.pressed.connect(_on_sub_tab_selected.bind(i, page_target))
		sub_section_bar.add_child(sub_btn)

	# Auto-select the first sub-section
	if not sections.is_empty():
		_on_sub_tab_selected(0, int(sections[0].get("page_index", 0)))

func _on_sub_tab_selected(sub_tab_idx: int, target_page: int) -> void:
	_active_sub_tab_index = sub_tab_idx
	if ledger_stack:
		ledger_stack.current_tab = target_page

	# Highlight active sub-tab
	if sub_section_bar != null:
		for i in range(sub_section_bar.get_child_count()):
			var btn := sub_section_bar.get_child(i) as Button
			if btn:
				if i == sub_tab_idx:
					btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
				else:
					btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)

func _update_macro_tab_visual_selection() -> void:
	var map := {
		"DIARY": tab_diary_btn,
		"DOSSIER": tab_dossier_btn,
		"ROSTER": tab_roster_btn,
		"FINANCE": tab_finance_btn
	}
	for key in map.keys():
		var btn: Button = map[key]
		if btn:
			if key == _current_macro_domain:
				btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
			else:
				btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)

func _setup_docket_controller() -> void:
	if telemetry_tab == null:
		return
	_docket_controller = telemetry_tab.find_child("DocketContent", true, false) as FilofaxDistrictDocket
	if _docket_controller == null:
		_docket_controller = FilofaxDistrictDocket.new()
		_docket_controller.name = "DocketContent"
		telemetry_tab.add_child(_docket_controller)

## Public API: External district raycast selection
func display_district_docket(block_id: String) -> void:
	select_macro_domain("DOSSIER")
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

func _toggle_customizer() -> void:
	if customizer_popup == null:
		customizer_popup = get_tree().current_scene.find_child("FilofaxCustomizer", true, false) as FilofaxCustomizer
		if customizer_popup and not customizer_popup.colors_updated.is_connected(_on_colors_live_updated):
			customizer_popup.colors_updated.connect(_on_colors_live_updated)

	if customizer_popup != null:
		customizer_popup.visible = not customizer_popup.visible
		if customizer_popup.visible:
			customizer_popup.move_to_front()
			# If spawned off-screen or too far left, snap to default visible coordinates
			if customizer_popup.global_position.x < 100:
				customizer_popup.global_position = Vector2(520, 100)
	else:
		push_error("[FilofaxUI] Could not find FilofaxCustomizer node in tree!")

func _on_colors_live_updated() -> void:
	_apply_filofax_stationery_theme()
	_rebuild_top_sub_section_tabs()
	if _docket_controller != null and not GameState.selected_district_id.is_empty():
		_docket_controller.display_district(GameState.selected_district_id)

func _on_close_button_pressed() -> void:
	visible = false
	var canvas := get_parent()
	while canvas != null and not (canvas is CanvasLayer):
		canvas = canvas.get_parent()
	if canvas is CanvasLayer:
		canvas.visible = false

func _apply_filofax_stationery_theme() -> void:
	var binder_style := RETRO_THEME.create_paper_page_style(
		RETRO_THEME.color_binder_cover, 12, 12, RETRO_THEME.color_binder_trim
	)
	add_theme_stylebox_override("panel", binder_style)

	var left_page: Control = get_node_or_null("BinderContent/PageSpread/LeftPage_Ledger")
	var right_page: Control = get_node_or_null("BinderContent/PageSpread/RightPage_Planner")
	var paper_style := RETRO_THEME.create_paper_page_style(
		RETRO_THEME.color_page_bg, 14, 14, RETRO_THEME.color_ruled_line
	)
	if left_page:  left_page.add_theme_stylebox_override("panel", paper_style)
	if right_page: right_page.add_theme_stylebox_override("panel", paper_style)

	_style_vertical_divider_tabs()
	RETRO_THEME.apply_stationery_styling(self, RETRO_THEME.color_ink_body)

func _style_vertical_divider_tabs() -> void:
	var mono_font: Font = RETRO_THEME.get_monospace_font()
	var tabs := [tab_diary_btn, tab_dossier_btn, tab_roster_btn, tab_finance_btn, tab_styles_btn, tab_close_btn]

	for btn in tabs:
		if btn == null:
			continue
		var tab_style := StyleBoxFlat.new()
		tab_style.bg_color = RETRO_THEME.color_page_bg.darkened(0.08)
		tab_style.set_corner_radius_all(0)
		tab_style.corner_radius_top_left = 6
		tab_style.corner_radius_bottom_left = 6
		tab_style.set_content_margin_all(8)
		tab_style.content_margin_left = 10
		tab_style.content_margin_right = 6
		tab_style.border_color = RETRO_THEME.color_ruled_line
		tab_style.border_width_left = 1
		tab_style.border_width_top = 1
		tab_style.border_width_bottom = 1
		tab_style.border_width_right = 0

		btn.add_theme_stylebox_override("normal", tab_style)
		btn.add_theme_stylebox_override("hover", tab_style)
		btn.add_theme_stylebox_override("pressed", tab_style)
		btn.add_theme_font_override("font", mono_font)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)

	if tab_close_btn:
		tab_close_btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_warning)

func _setup_sticky_note_buttons() -> void:
	if execute_turn_button:
		execute_turn_button.pressed.connect(_on_execute_turn_pressed)
		_refresh_turn_button_label()
	if add_order_button:    add_order_button.pressed.connect(_open_sticky_pad)
	if close_note_btn:       close_note_btn.pressed.connect(func(): sticky_popup.visible = false)
	if discard_btn:          discard_btn.pressed.connect(func(): sticky_popup.visible = false)
	if pin_btn:              pin_btn.pressed.connect(_on_pin_directive)

	if verb_opt:     verb_opt.item_selected.connect(_on_verb_changed)
	if target_opt:   target_opt.item_selected.connect(_recalculate_estimate)
	if amount_spin:  amount_spin.value_changed.connect(_recalculate_estimate)

	if btn_move_up:
		btn_move_up.pressed.connect(func():
			var selected = directive_queue.get_selected_items()
			if selected.size() > 0 and selected[0] > 0:
				move_directive(selected[0], selected[0] - 1)
		)
	if btn_move_down:
		btn_move_down.pressed.connect(func():
			var selected = directive_queue.get_selected_items()
			if selected.size() > 0 and selected[0] < _staged_directives.size() - 1:
				move_directive(selected[0], selected[0] + 1)
		)

func _on_execute_turn_pressed() -> void:
	# 1. Delegate entire turn progression and execution to the simulation engine
	var incoming_slips: Array = SIM_CONTROLLER.process_turn_cycle(_world_state, _staged_directives)

	# 2. Reset the staged UI queue
	_staged_directives.clear()
	_refresh_directive_list()

	# 3. Synchronize Perceptions & Redraw View
	FILOFAX_MGR.refresh_cache_instant(_world_state, _filofax_cache)
	update_display(_filofax_cache)
	_refresh_turn_button_label()

	# 4. Route Physical Slips to Desktop Workspace
	var desktop_inbox: DesktopSlipStack = get_tree().current_scene.find_child("DesktopSlipStack", true, false) as DesktopSlipStack
	if desktop_inbox != null and not incoming_slips.is_empty():
		desktop_inbox.push_slips(incoming_slips)
		desktop_inbox.visible = true
		desktop_inbox.move_to_front()

	if execute_turn_button:
		execute_turn_button.set_pressed_no_signal(false)

## Updates the button text dynamically according to the operational horizon
func _refresh_turn_button_label() -> void:
	if not execute_turn_button:
		return
		
	# Determine temporal horizon: defaults to "day" at Tier 1, can be "shift", "week", etc.
	var horizon: String = _world_state.get("metadata", {}).get("time_horizon", "day").to_lower()
	match horizon:
		"shift":
			execute_turn_button.text = tr("UI_BTN_EXECUTE_SHIFT")
		"day":
			execute_turn_button.text = tr("UI_BTN_EXECUTE_DAY")
		"week":
			execute_turn_button.text = tr("UI_BTN_EXECUTE_WEEK")
		_:
			execute_turn_button.text = tr("UI_BTN_EXECUTE_TURN")


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
			_is_binder_dragging = false
			_staged_directives = _staged_directives # no-op guard
			accept_event()
		else:
			accept_event()

func _open_sticky_pad() -> void:
	if sticky_popup == null:
		sticky_popup = get_tree().current_scene.find_child("StickyNotePopup", true, false) as PanelContainer
		if sticky_popup:
			_setup_drag_and_theming()

	if not sticky_popup:
		push_error("[FilofaxUI] Could not find StickyNotePopup node in tree!")
		return

	sticky_popup.visible = true
	sticky_popup.move_to_front()

	verb_opt.clear()
	verb_opt.add_item(tr("UI_ACTION_BUY"))
	verb_opt.set_item_metadata(verb_opt.item_count - 1, "BUY")
	verb_opt.add_item(tr("UI_ACTION_SELL"))
	verb_opt.set_item_metadata(verb_opt.item_count - 1, "SELL")
	verb_opt.add_item(tr("UI_ACTION_MAKE"))
	verb_opt.set_item_metadata(verb_opt.item_count - 1, "MAKE")
	
	where_opt.clear()
	for dist_id in _world_state.get("districts", {}).keys():
		var d: Dictionary = _world_state["districts"][dist_id]
		where_opt.add_item(d.get("display_name", dist_id))
		where_opt.set_item_metadata(where_opt.item_count - 1, dist_id)
		
	_on_verb_changed(0)

func _on_verb_changed(idx: int) -> void:
	var verb: String = str(verb_opt.get_item_metadata(idx))
	target_opt.clear()
	who_opt.clear()

	if verb == "MAKE":
		who_opt.add_item(tr("UI_LOCAL_WORKSHOP_STAFF"))
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
	var verb: String = str(verb_opt.get_item_metadata(verb_opt.selected))
	var qty := amount_spin.value
	var target_id = target_opt.get_selected_metadata()

	if verb == "MAKE":
		est_label.text = tr("UI_ESTIMATE_YIELD").replace("{amount}", "%.0f" % qty)
	else:
		var base: float = _world_state.get("commodity_registry", {}).get(target_id, {}).get("base_cost", 1.0)
		var total: float = qty * base * (1.5 if verb == "SELL" else 1.0)
		est_label.text = tr("UI_ESTIMATE_CURRENCY").replace("{currency}", "£").replace(
			"{amount}", "%.2f" % total
		)

func _on_pin_directive() -> void:
	var verb: String = str(verb_opt.get_item_metadata(verb_opt.selected))
	var target_id = target_opt.get_selected_metadata()
	var where_id = where_opt.get_selected_metadata()
	var qty := amount_spin.value

	var directive := {
		"verb": verb,
		"target_item": target_id,
		"amount": qty,
		"target_node_id": where_id,
		"staged_index": _staged_directives.size() # Tracks creation order (0, 1, 2...)
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
		directive_queue.add_item(tr("UI_DIRECTIVE_ENTRY").replace("{index}", str(i + 1)).replace(
			"{verb}", str(cmd.get("verb", ""))
		).replace("{target}", str(cmd.get("target_item", ""))).replace(
			"{amount}", "%.0f" % float(cmd.get("amount", 1))
		).replace("{location}", str(cmd.get("target_node_id", ""))))

func _on_commit_orders_pressed() -> void:
	if _staged_directives.is_empty():
		return

	var incoming_slips: Array = []
	var cur_tick: int = _world_state.get("metadata", {}).get("current_week_tick", 1)

	for directive in _staged_directives:
		# 1. Execute reality in the backend
		var res: Dictionary = SIM_CONTROLLER.execute_directive(_world_state, directive)

		# 2. Generate a tactile slip representation
		var slip := {
			"tick": cur_tick,
			"verb": directive.get("verb", "TASK"),
			"text": res.get("message", "Task completed."),
			"author": directive.get("counterparty_id", "Street Runner"),
			"destination": "team_feedback", # Modular destination
			"directive_snapshot": directive.duplicate(true)
		}
		incoming_slips.append(slip)

	_staged_directives.clear()
	_refresh_directive_list()

	# 3. Advance simulation world state
	SIM_CONTROLLER.process_ambient_heartbeat(_world_state)
	FILOFAX_MGR.refresh_cache_instant(_world_state, _filofax_cache)
	update_display(_filofax_cache)

	execute_turn_button.set_pressed_no_signal(false)

func update_display(cache: Dictionary) -> void:
	_filofax_cache = cache

	if financial_list:
		for child in financial_list.get_children():
			child.queue_free()
		var c_lbl := Label.new()
		c_lbl.text = tr("UI_FINANCE_VAULT_CASH").replace("{currency}", "£").replace(
			"{amount}", "%.2f" % cache.get("finances", {}).get("reported_cash", 0.0)
		)
		financial_list.add_child(c_lbl)

	if memo_list:
		for child in memo_list.get_children():
			child.queue_free()
		for memo in cache.get("pinned_memos", []):
			var slip := Label.new()
			slip.text = tr("UI_MEMO_WEEK").replace("{week}", str(memo.get("tick", 0))).replace(
				"{text}", str(memo.get("text", ""))
			)
			memo_list.add_child(slip)

## Called when the player chooses to permanently record the slip into their binder
func _on_slip_filed_to_filofax(slip: Dictionary, destination: String) -> void:
	if not _filofax_cache.has("filed_records"):
		_filofax_cache["filed_records"] = {}
	if not _filofax_cache["filed_records"].has(destination):
		_filofax_cache["filed_records"][destination] = []

	# Ingest into the organizer ledger under the chosen category
	_filofax_cache["filed_records"][destination].append(slip)
	print("[Filofax] Filed slip under '%s': %s" % [destination, slip.get("text", "")])

## Called when the player throws the slip away
func _on_slip_discarded(slip: Dictionary) -> void:
	# The event already happened in simulation reality, but the player has no record of it
	print("[Filofax] Discarded slip into wastebasket: %s" % slip.get("text", ""))

func _setup_directive_queue_reordering() -> void:
	if directive_queue == null:
		return
		
	# Allow selecting and dragging items within the queue
	directive_queue.select_mode = ItemList.SELECT_SINGLE
	
	# Connect drag-and-drop or reorder helpers
	directive_queue.item_activated.connect(_on_directive_item_double_clicked)

## Moving directives in memory
func move_directive(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or from_idx >= _staged_directives.size():
		return
	if to_idx < 0 or to_idx >= _staged_directives.size():
		return
	if from_idx == to_idx:
		return

	var moved_item: Dictionary = _staged_directives.pop_at(from_idx)
	_staged_directives.insert(to_idx, moved_item)
	
	# Update staged priority/index markers
	for i in range(_staged_directives.size()):
		_staged_directives[i]["staged_index"] = i
		_staged_directives[i]["priority"] = _staged_directives.size() - i # Top = Highest Priority
		
	_refresh_directive_list()
	directive_queue.select(to_idx)

## Double-clicking an item in the queue allows removing or promoting it
func _on_directive_item_double_clicked(index: int) -> void:
	# For convenience, double-clicking the top item can swap with the one below, 
	# or prompt removal
	pass
