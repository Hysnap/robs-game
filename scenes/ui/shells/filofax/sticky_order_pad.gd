# res://scenes/ui/shells/filofax/sticky_order_pad.gd
class_name StickyOrderPad
extends PanelContainer

signal order_pinned(directive: Dictionary)
signal directive_committed(directive: Dictionary)
signal pad_closed

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const SocietyQueriesScript = preload("res://systems/society_queries.gd")

@onready var drag_handle: Label = $VBox/Header/DragHandle
@onready var btn_close: Button = $VBox/Header/BtnClose
@onready var opt_verb: OptionButton = $VBox/NotesGrid/StickyNote_Action/VBox/VerbOption
@onready var opt_target: OptionButton = $VBox/NotesGrid/StickyNote_What/VBox/TargetOption
@onready var spin_amount: SpinBox = $VBox/NotesGrid/StickyNote_Amount/VBox/AmountSpin
@onready var opt_who: OptionButton = $VBox/NotesGrid/StickyNote_Who/VBox/WhoOption
@onready var opt_where_filter: OptionButton = $VBox/NotesGrid/StickyNote_Where/VBox/WhereFilterOption
@onready var opt_where: OptionButton = $VBox/NotesGrid/StickyNote_Where/VBox/WhereOption
@onready var opt_contact: OptionButton = $VBox/NotesGrid/StickyNote_Where/VBox/ContactOption
@onready var lbl_estimate: Label = $VBox/NotesGrid/StickyNote_Estimate/VBox/EstimatedCostLabel
@onready var btn_pin: Button = $VBox/ButtonBox/SaveNoteBtn
@onready var btn_tear: Button = $VBox/ButtonBox/DiscardBtn

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _cached_locations: Array[Dictionary] = []
var _active_district_id: String = ""

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
		opt_verb.item_selected.connect(_on_verb_selected)
	if opt_where_filter:
		opt_where_filter.item_selected.connect(_on_where_filter_selected)
	if opt_where:
		opt_where.item_selected.connect(_on_where_location_selected)
	if opt_target:
		opt_target.item_selected.connect(func(_idx): _recalculate_estimate())

	_setup_where_filters()
	_populate_default_verbs()
	_sync_simulation_data()
	_apply_sticky_note_skins()
	_recalculate_estimate()

func open_for_district(district_id: String) -> void:
	visible = true
	move_to_front()
	_active_district_id = district_id
	_sync_simulation_data()
	_select_where_by_id(district_id)
	_recalculate_estimate()

func open_for_context(context: Dictionary) -> void:
	var target_dist: String = str(context.get("target_district_id", ""))
	assert(not target_dist.is_empty(), "FATAL: [StickyOrderPad] Context missing 'target_district_id'.")
	open_for_district(target_dist)

func _setup_where_filters() -> void:
	if opt_where_filter and opt_where_filter.item_count == 0:
		opt_where_filter.add_item("All Scopes", 0)
		opt_where_filter.set_item_metadata(0, "ALL")
		opt_where_filter.add_item("Districts Only", 1)
		opt_where_filter.set_item_metadata(1, "DISTRICT")
		opt_where_filter.add_item("Workplaces & Venues", 2)
		opt_where_filter.set_item_metadata(2, "WORKPLACE")
		opt_where_filter.add_item("Residential Units", 3)
		opt_where_filter.set_item_metadata(3, "RESIDENTIAL")

func _populate_default_verbs() -> void:
	if opt_verb and opt_verb.item_count == 0:
		opt_verb.add_item("BUY", 0)
		opt_verb.set_item_metadata(0, "BUY")
		opt_verb.add_item("SELL", 1)
		opt_verb.set_item_metadata(1, "SELL")
		opt_verb.add_item("MAKE", 2)
		opt_verb.set_item_metadata(2, "MAKE")
		opt_verb.add_item("SCOUT", 3)
		opt_verb.set_item_metadata(3, "SCOUT")
		opt_verb.add_item("INVESTIGATE", 4)
		opt_verb.set_item_metadata(4, "INVESTIGATE")

## Ingests live staff and catalog state from GameState single-source-of-truth
func _sync_simulation_data() -> void:
	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if gs != null and "world_state" in gs else {}

	# 1. Populate Responsible Party (WHO)
	_populate_staff_options(ws.get("staff", {}))

	# 2. Populate Target Items (WHAT) based on selected verb
	_refresh_targets_for_active_verb(ws)

	# 3. Assemble and Populate Location Options (WHERE)
	_rebuild_location_cache(ws)
	_apply_location_filter()

	# 4. Populate Contact Options based on selected location
	_refresh_contact_options()

func _populate_staff_options(staff_dict: Dictionary) -> void:
	if opt_who == null:
		return
	opt_who.clear()

	if staff_dict.is_empty():
		opt_who.add_item("Player (Leader)", 0)
		opt_who.set_item_metadata(0, "PLAYER")
		return

	var idx: int = 0
	for staff_id in staff_dict.keys():
		var staff_member = staff_dict[staff_id]
		if staff_member is Dictionary:
			var s_name: String = str(staff_member.get("name", staff_id))
			var s_role: String = str(staff_member.get("role", "OPERATIVE")).capitalize()
			opt_who.add_item("%s (%s)" % [s_name, s_role], idx)
			opt_who.set_item_metadata(idx, str(staff_id))
			idx += 1

func _refresh_targets_for_active_verb(ws: Dictionary) -> void:
	if opt_target == null or opt_verb == null or opt_verb.item_count == 0:
		return
	opt_target.clear()

	var verb_token: String = str(opt_verb.get_item_metadata(opt_verb.selected))
	if verb_token.is_empty():
		verb_token = opt_verb.get_item_text(opt_verb.selected)

	var idx: int = 0
	match verb_token:
		"BUY", "SELL":
			var commodities: Dictionary = ws.get("commodity_registry", {})
			if not commodities.is_empty():
				for c_id in commodities.keys():
					opt_target.add_item(str(c_id), idx)
					opt_target.set_item_metadata(idx, str(c_id))
					idx += 1
			else:
				var fallbacks: Array = ["BEER_STRONG_LAGER", "CIGARETTES_SMUGGLED", "SPIRITS_GIN"]
				for item in fallbacks:
					opt_target.add_item(item, idx)
					opt_target.set_item_metadata(idx, item)
					idx += 1
		"MAKE":
			var recipes: Dictionary = ws.get("recipe_registry", {})
			if not recipes.is_empty():
				for r_id in recipes.keys():
					opt_target.add_item(str(r_id), idx)
					opt_target.set_item_metadata(idx, str(r_id))
					idx += 1
			else:
				opt_target.add_item("RECIPE_BREW_ALE", 0)
				opt_target.set_item_metadata(0, "RECIPE_BREW_ALE")
		_:
			opt_target.add_item("GENERAL_SURVEY", 0)
			opt_target.set_item_metadata(0, "GENERAL_SURVEY")
			opt_target.add_item("ESTABLISHMENTS_SWEEP", 1)
			opt_target.set_item_metadata(1, "ESTABLISHMENTS_SWEEP")

func _rebuild_location_cache(ws: Dictionary) -> void:
	_cached_locations.clear()

	# A. Districts Known to Player
	var known_districts: Array = ws.get("player_knowledge", {}).get("known_districts", [])
	if not _active_district_id.is_empty() and not _active_district_id in known_districts:
		known_districts.append(_active_district_id)

	for dist_id in known_districts:
		var d_name: String = str(dist_id).capitalize().replace("_", " ")
		_cached_locations.append({
			"id": str(dist_id),
			"type": "DISTRICT",
			"category": "DISTRICT",
			"sector": "DISTRICT",
			"display": "[Dist] %s" % d_name
		})

	# B. Establishments in active district
	if not _active_district_id.is_empty():
		var estabs: Array = SocietyQueriesScript.get_district_establishments(_active_district_id)
		for e in estabs:
			var e_id: Variant = e.get("establishment_id", "")
			var e_name: String = str(e.get("name", "Unnamed Venue"))
			var cat_code: String = str(e.get("category_code", ""))

			# Binary distinction: Domestic Residence vs. Operational Workplace/Venue
			var is_residential: bool = (cat_code == "RESIDENTIAL_UNIT" or cat_code.begins_with("RESIDENTIAL"))
			var sector: String = "RESIDENTIAL" if is_residential else "WORKPLACE"
			var prefix: String = "[Res]" if is_residential else "[Biz]"

			_cached_locations.append({
				"id": str(e_id),
				"type": "ESTABLISHMENT",
				"category": cat_code,
				"sector": sector,
				"display": "%s %s" % [prefix, e_name]
			})

func _apply_location_filter() -> void:
	if opt_where == null or opt_where_filter == null:
		return
	opt_where.clear()

	var filter_type: String = str(opt_where_filter.get_item_metadata(opt_where_filter.selected))
	var idx: int = 0
	for loc in _cached_locations:
		var match_filter: bool = false
		if filter_type == "ALL" or filter_type.is_empty():
			match_filter = true
		elif filter_type == "DISTRICT" and loc["type"] == "DISTRICT":
			match_filter = true
		elif loc["type"] == "ESTABLISHMENT" and loc["sector"] == filter_type:
			match_filter = true

		if match_filter:
			opt_where.add_item(loc["display"], idx)
			opt_where.set_item_metadata(idx, loc)
			idx += 1

	if opt_where.item_count == 0:
		opt_where.add_item("[No Locations in Selected Scope]", 0)
		opt_where.set_item_metadata(0, {"id": "", "type": "NONE", "category": "NONE", "sector": "NONE"})

func _refresh_contact_options() -> void:
	if opt_contact == null:
		return
	opt_contact.clear()

	# Default Option 0: Anyone available / unrestricted
	opt_contact.add_item("[ANYONE AVAILABLE]", 0)
	opt_contact.set_item_metadata(0, "")

	if opt_where == null or opt_where.item_count == 0:
		return

	var loc_meta = opt_where.get_item_metadata(opt_where.selected)
	if loc_meta is Dictionary and loc_meta.get("type") == "ESTABLISHMENT":
		var estab_id: int = int(loc_meta.get("id", 0))
		if estab_id > 0:
			var docket: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id)
			var idx: int = 1
			# Workplace / Venue personnel
			var employees: Array = docket.get("employees", [])
			for emp in employees:
				var emp_name: String = str(emp.get("full_name", ""))
				var emp_role: String = str(emp.get("role_title", ""))
				if not emp_name.is_empty():
					opt_contact.add_item("%s (%s)" % [emp_name, emp_role], idx)
					opt_contact.set_item_metadata(idx, str(emp.get("resident_id", emp_name)))
					idx += 1
			# Residential occupants
			var residents: Array = docket.get("residents", [])
			for res in residents:
				var res_name: String = str(res.get("full_name", ""))
				if not res_name.is_empty():
					opt_contact.add_item("%s (Occupant)" % res_name, idx)
					opt_contact.set_item_metadata(idx, str(res.get("resident_id", res_name)))
					idx += 1

func _select_where_by_id(target_id: String) -> void:
	if opt_where == null or target_id.is_empty():
		return
	for i in range(opt_where.item_count):
		var meta = opt_where.get_item_metadata(i)
		if meta is Dictionary and str(meta.get("id")) == target_id:
			opt_where.select(i)
			_refresh_contact_options()
			return

func _on_verb_selected(_idx: int) -> void:
	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if gs != null and "world_state" in gs else {}
	_refresh_targets_for_active_verb(ws)
	_recalculate_estimate()

func _on_where_filter_selected(_idx: int) -> void:
	_apply_location_filter()
	_refresh_contact_options()

func _on_where_location_selected(_idx: int) -> void:
	_refresh_contact_options()

func _recalculate_estimate() -> void:
	if lbl_estimate == null or opt_verb == null or spin_amount == null:
		return
	var verb_meta: Variant = opt_verb.get_item_metadata(opt_verb.selected)
	var verb := str(verb_meta) if verb_meta != null and not str(verb_meta).is_empty() else opt_verb.get_item_text(opt_verb.selected)
	var qty: float = float(spin_amount.value)
	var unit_cost := 2.50 if verb == "BUY" else 0.50
	var total_est := qty * unit_cost
	lbl_estimate.text = "£%.2f" % total_est

func _on_pin_pressed() -> void:
	var verb_meta: Variant = opt_verb.get_item_metadata(opt_verb.selected) if opt_verb and opt_verb.item_count > 0 else "BUY"
	var verb: String = str(verb_meta) if verb_meta != null and not str(verb_meta).is_empty() else "BUY"

	var target_meta: Variant = opt_target.get_item_metadata(opt_target.selected) if opt_target and opt_target.item_count > 0 else "BEER_STRONG_LAGER"
	var target_item: String = str(target_meta) if target_meta != null and not str(target_meta).is_empty() else "BEER_STRONG_LAGER"

	var qty: float = float(spin_amount.value) if spin_amount else 10.0

	var who_meta: Variant = opt_who.get_item_metadata(opt_who.selected) if opt_who and opt_who.item_count > 0 else "PLAYER"
	var who_id: String = str(who_meta) if who_meta != null and not str(who_meta).is_empty() else "PLAYER"
	var who_name: String = opt_who.get_item_text(opt_who.selected) if opt_who and opt_who.item_count > 0 else "Player"

	var loc_meta: Variant = opt_where.get_item_metadata(opt_where.selected) if opt_where and opt_where.item_count > 0 else null
	var target_node_id: String = ""
	var target_scope: String = "DISTRICT"
	if loc_meta is Dictionary:
		target_node_id = str(loc_meta.get("id", ""))
		target_scope = str(loc_meta.get("type", "DISTRICT"))
	elif opt_where != null and opt_where.item_count > 0:
		target_node_id = opt_where.get_item_text(opt_where.selected)

	var contact_meta: Variant = opt_contact.get_item_metadata(opt_contact.selected) if opt_contact and opt_contact.item_count > 0 else ""
	var contact_id: String = str(contact_meta) if contact_meta != null else ""

	var directive := {
		"verb": verb,
		"initiator_id": who_id,
		"assigned_to": who_name,
		"counterparty_id": contact_id,
		"target_item": target_item,
		"amount": qty,
		"target_node_id": target_node_id,
		"target_scope": target_scope,
		"config": {"unit_price": 3.50, "unit_cost": 2.00}
	}

	order_pinned.emit(directive)
	directive_committed.emit(directive)
	visible = false

func _on_close_pressed() -> void:
	visible = false
	pad_closed.emit()

func _apply_sticky_note_skins() -> void:
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