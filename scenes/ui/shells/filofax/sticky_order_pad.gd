# res://scenes/ui/shells/filofax/sticky_order_pad.gd
class_name StickyOrderPad
extends PanelContainer

signal order_pinned(directive: Dictionary)
signal directive_committed(directive: Dictionary)
signal pad_closed

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")
const StationeryRegistryScript = preload("res://scenes/ui/feedback/stationery_registry.gd")
const ShellRegistryScript = preload("res://scenes/ui/shell_host/shell_registry.gd")

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
	assert(drag_handle != null, "FATAL: [StickyOrderPad] DragHandle node missing from scene hierarchy.")
	assert(btn_pin != null, "FATAL: [StickyOrderPad] SaveNoteBtn node missing from scene hierarchy.")
	assert(opt_verb != null, "FATAL: [StickyOrderPad] VerbOption node missing from scene hierarchy.")
	assert(opt_target != null, "FATAL: [StickyOrderPad] TargetOption node missing from scene hierarchy.")
	assert(opt_where != null, "FATAL: [StickyOrderPad] WhereOption node missing from scene hierarchy.")

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

	_populate_default_verbs()
	_sync_simulation_data()
	_apply_sticky_note_skins()
	_recalculate_estimate()

func open_for_district(district_id: String) -> void:
	assert(not district_id.is_empty(), "FATAL: [StickyOrderPad] Cannot open order pad with empty district_id.")
	visible = true
	move_to_front()
	_active_district_id = district_id
	_sync_simulation_data()
	_select_where_by_id(district_id)
	_recalculate_estimate()

func open_for_context(context: Dictionary) -> void:
	assert(context.has("target_district_id"), "FATAL: [StickyOrderPad] Context missing required key 'target_district_id'.")
	var target_dist: String = str(context["target_district_id"])
	assert(not target_dist.is_empty(), "FATAL: [StickyOrderPad] 'target_district_id' in context cannot be empty.")
	open_for_district(target_dist)

## Populates verbs dynamically from VerbRouter (Rule 1 & Rule 5)
func _populate_default_verbs() -> void:
	if opt_verb == null:
		return
	opt_verb.clear()

	var registered: Array[String] = VerbRouterScript.get_registered_verbs()
	if registered.is_empty():
		push_error("[StickyOrderPad FATAL] VerbRouter has 0 registered verbs mounted.")
		return

	var idx: int = 0
	for verb_code in registered:
		var token_key := "UI_VERB_" + verb_code
		var display_label := tr(token_key)
		if display_label == token_key:
			token_key = "VERB_" + verb_code
			display_label = tr(token_key)
			if display_label == token_key:
				display_label = verb_code.to_upper()

		opt_verb.add_item(display_label, idx)
		opt_verb.set_item_metadata(idx, verb_code)
		idx += 1

## Ingests live staff and catalog state from GameState (Fail-Noisy Validation)
func _sync_simulation_data() -> void:
	var gs = ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [StickyOrderPad] GameState or world_state is unmounted.")
	var ws: Dictionary = gs.world_state

	# 1. Populate Responsible Party (WHO)
	_populate_staff_options(ws.get("staff", {}))

	# 2. Populate Target Items (WHAT) dynamically from TargetDomainRegistry
	_refresh_targets_for_active_verb(ws)

	# 3. Assemble and Populate Location Options (WHERE) dynamically filtered by verb target_scopes
	_refresh_where_filters_for_active_verb()
	_rebuild_location_cache(ws)
	_apply_location_filter()

	# 4. Populate Contact Options based on selected location
	_refresh_contact_options()

func _populate_staff_options(staff_dict: Dictionary) -> void:
	if opt_who == null:
		return
	opt_who.clear()

	if staff_dict.is_empty():
		push_warning("[StickyOrderPad] world_state['staff'] is empty; defaulting operative to PLAYER.")
		var leader_lbl := tr("UI_STAFF_PLAYER_LEADER")
		if leader_lbl == "UI_STAFF_PLAYER_LEADER":
			leader_lbl = "Player (Leader)"
		opt_who.add_item(leader_lbl, 0)
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

## De-hardcoded target population via TargetDomainRegistry (Rules 1, 2, & 5)
func _refresh_targets_for_active_verb(ws: Dictionary) -> void:
	if opt_target == null or opt_verb == null or opt_verb.item_count == 0:
		return
	opt_target.clear()

	var verb_token: String = str(opt_verb.get_item_metadata(opt_verb.selected))
	if verb_token.is_empty():
		verb_token = opt_verb.get_item_text(opt_verb.selected)

	var targets: Array[Dictionary] = TargetDomainRegistryScript.resolve_targets(verb_token, ws)
	if targets.is_empty():
		var none_token := "UI_TARGET_NONE_AVAILABLE"
		var none_label := tr(none_token)
		if none_label == none_token:
			none_label = "[NO TARGETS IN SCOPE]"
		opt_target.add_item(none_label, 0)
		opt_target.set_item_metadata(0, {"id": "", "unit_cost": 0.0})
		return

	var idx: int = 0
	for item in targets:
		var token: String = str(item.get("label_token", item.get("id", "")))
		var label_str: String = tr(token)
		if label_str == token:
			label_str = str(item.get("id")).capitalize().replace("_", " ")

		opt_target.add_item(label_str, idx)
		opt_target.set_item_metadata(idx, item)
		idx += 1

## Updates allowed WHERE filter scopes based on active verb's target_scope.json
func _refresh_where_filters_for_active_verb() -> void:
	if opt_where_filter == null or opt_verb == null or opt_verb.item_count == 0:
		return
	opt_where_filter.clear()

	var verb_token: String = str(opt_verb.get_item_metadata(opt_verb.selected))
	var allowed_scopes: Array[String] = TargetDomainRegistryScript.get_allowed_scopes(verb_token)

	var idx := 0
	opt_where_filter.add_item(tr("UI_FILTER_ALL_SCOPES"), idx)
	opt_where_filter.set_item_metadata(idx, "ALL")
	idx += 1

	if allowed_scopes.has("DISTRICT"):
		opt_where_filter.add_item(tr("UI_FILTER_DISTRICTS_ONLY"), idx)
		opt_where_filter.set_item_metadata(idx, "DISTRICT")
		idx += 1

	if allowed_scopes.has("ESTABLISHMENT"):
		opt_where_filter.add_item(tr("UI_FILTER_WORKPLACES"), idx)
		opt_where_filter.set_item_metadata(idx, "WORKPLACE")
		idx += 1
		opt_where_filter.add_item(tr("UI_FILTER_RESIDENTIAL"), idx)
		opt_where_filter.set_item_metadata(idx, "RESIDENTIAL")
		idx += 1

func _rebuild_location_cache(ws: Dictionary) -> void:
	_cached_locations.clear()

	var verb_token: String = str(opt_verb.get_item_metadata(opt_verb.selected)) if opt_verb and opt_verb.item_count > 0 else ""
	var allowed_scopes: Array[String] = TargetDomainRegistryScript.get_allowed_scopes(verb_token)

	# A. Districts Known to Player (if allowed by verb)
	if allowed_scopes.is_empty() or allowed_scopes.has("DISTRICT"):
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

	# B. Establishments in active district (if allowed by verb)
	if (allowed_scopes.is_empty() or allowed_scopes.has("ESTABLISHMENT")) and not _active_district_id.is_empty():
		var estabs: Array = SocietyQueriesScript.get_district_establishments(_active_district_id)
		for e in estabs:
			var e_id: Variant = e.get("establishment_id", "")
			var e_name: String = str(e.get("name", "Unnamed Venue"))
			var cat_code: String = str(e.get("category_code", ""))

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
		opt_where.add_item(tr("UI_NO_LOCATIONS_IN_SCOPE"), 0)
		opt_where.set_item_metadata(0, {"id": "", "type": "NONE", "category": "NONE", "sector": "NONE"})

func _refresh_contact_options() -> void:
	if opt_contact == null:
		return
	opt_contact.clear()

	var default_contact := tr("UI_CONTACT_ANYONE_AVAILABLE")
	if default_contact == "UI_CONTACT_ANYONE_AVAILABLE":
		default_contact = "[ANYONE AVAILABLE]"
	opt_contact.add_item(default_contact, 0)
	opt_contact.set_item_metadata(0, "")

	if opt_where == null or opt_where.item_count == 0:
		return

	var loc_meta = opt_where.get_item_metadata(opt_where.selected)
	if loc_meta is Dictionary and loc_meta.get("type") == "ESTABLISHMENT":
		var estab_id: int = int(loc_meta.get("id", 0))
		if estab_id > 0:
			var docket: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id)
			var idx: int = 1
			var employees: Array = docket.get("employees", [])
			for emp in employees:
				var emp_name: String = str(emp.get("full_name", ""))
				var emp_role: String = str(emp.get("role_title", ""))
				if not emp_name.is_empty():
					opt_contact.add_item("%s (%s)" % [emp_name, emp_role], idx)
					opt_contact.set_item_metadata(idx, str(emp.get("resident_id", emp_name)))
					idx += 1
			var residents: Array = docket.get("residents", [])
			for res in residents:
				var res_name: String = str(res.get("full_name", ""))
				if not res_name.is_empty():
					opt_contact.add_item("%s (%s)" % [res_name, tr("UI_CONTACT_OCCUPANT")], idx)
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
	_refresh_where_filters_for_active_verb()
	_rebuild_location_cache(ws)
	_apply_location_filter()
	_refresh_contact_options()
	_recalculate_estimate()

func _on_where_filter_selected(_idx: int) -> void:
	_apply_location_filter()
	_refresh_contact_options()

func _on_where_location_selected(_idx: int) -> void:
	_refresh_contact_options()

## Format-free, catalog-driven estimate recalculation (Driven strictly by selected item metadata)
func _recalculate_estimate() -> void:
	if lbl_estimate == null or spin_amount == null:
		return
	var qty: float = float(spin_amount.value)

	var unit_cost := 0.0
	if opt_target and opt_target.item_count > 0:
		var target_meta = opt_target.get_item_metadata(opt_target.selected)
		if target_meta is Dictionary:
			unit_cost = float(target_meta.get("unit_cost", 0.0))

	var total_est := qty * unit_cost
	var num_str := String.num(total_est, 2)
	var fmt_template := tr("FMT_CURRENCY")
	if fmt_template == "FMT_CURRENCY":
		fmt_template = "£{val}"
	lbl_estimate.text = fmt_template.replace("{val}", num_str)

## Validates directive parameters strictly before emitting (Fail-Noisy Guard Rails)
func _on_pin_pressed() -> void:
	assert(opt_verb != null and opt_verb.item_count > 0, "FATAL: [StickyOrderPad] Cannot pin order: no verbs available.")
	var verb_meta: Variant = opt_verb.get_item_metadata(opt_verb.selected)
	var verb: String = str(verb_meta) if verb_meta != null else ""
	assert(not verb.is_empty(), "FATAL: [StickyOrderPad] Selected verb has empty metadata.")

	assert(opt_target != null and opt_target.item_count > 0, "FATAL: [StickyOrderPad] Cannot pin order: no target items available.")
	var target_meta = opt_target.get_item_metadata(opt_target.selected)
	var target_item: String = ""
	var unit_cost: float = 0.0
	if target_meta is Dictionary:
		target_item = str(target_meta.get("id", ""))
		unit_cost = float(target_meta.get("unit_cost", 0.0))
	elif target_meta != null:
		target_item = str(target_meta)
	
	if target_item.is_empty():
		push_error("[StickyOrderPad REJECTED] Cannot pin order: no valid target item selected.")
		return

	var qty: float = float(spin_amount.value) if spin_amount else 1.0
	if qty <= 0.0:
		push_error("[StickyOrderPad REJECTED] Quantity must be greater than zero.")
		return

	var who_meta: Variant = opt_who.get_item_metadata(opt_who.selected) if opt_who and opt_who.item_count > 0 else "PLAYER"
	var who_id: String = str(who_meta) if who_meta != null and not str(who_meta).is_empty() else "PLAYER"
	var who_name: String = opt_who.get_item_text(opt_who.selected) if opt_who and opt_who.item_count > 0 else "Player"

	var loc_meta: Variant = opt_where.get_item_metadata(opt_where.selected) if opt_where and opt_where.item_count > 0 else null
	var target_node_id: String = ""
	var target_scope: String = "DISTRICT"
	if loc_meta is Dictionary:
		target_node_id = str(loc_meta.get("id", ""))
		target_scope = str(loc_meta.get("type", "DISTRICT"))
		if target_node_id.is_empty():
			push_error("[StickyOrderPad REJECTED] Cannot pin order: invalid location selected.")
			return
	else:
		push_error("[StickyOrderPad REJECTED] Cannot pin order: location metadata missing.")
		return

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
		"config": {
			"unit_cost": unit_cost,
			"exposure_modifier": 1.0
		}
	}

	order_pinned.emit(directive)
	directive_committed.emit(directive)
	visible = false

func _on_close_pressed() -> void:
	visible = false
	pad_closed.emit()

## Ingests styling dynamically from the active order composer manifest and atomic definition (Rules 1, 2, & 8)
func _apply_sticky_note_skins() -> void:
	var composer_path: String = ShellRegistryScript.get_active_order_composer_manifest_path()
	assert(FileAccess.file_exists(composer_path), "FATAL: [StickyOrderPad] Composer manifest missing: %s" % composer_path)
	
	var composer_file := FileAccess.open(composer_path, FileAccess.READ)
	assert(composer_file != null, "FATAL: [StickyOrderPad] Cannot read composer manifest: %s" % composer_path)
	var composer_manifest = JSON.parse_string(composer_file.get_as_text())
	composer_file.close()
	assert(composer_manifest is Dictionary, "FATAL: [StickyOrderPad] Composer manifest is not a valid JSON Dictionary.")

	var def_path: String = str(composer_manifest.get("stationery_definition", ""))
	assert(!def_path.is_empty() and FileAccess.file_exists(def_path),
		"FATAL: [StickyOrderPad] Composer manifest points to invalid stationery definition: '%s'" % def_path)

	var def_file := FileAccess.open(def_path, FileAccess.READ)
	assert(def_file != null, "FATAL: [StickyOrderPad] Cannot open stationery definition: %s" % def_path)
	var def_json = JSON.parse_string(def_file.get_as_text())
	def_file.close()
	assert(def_json is Dictionary, "FATAL: [StickyOrderPad] Stationery definition is not a valid JSON Dictionary: %s" % def_path)

	var corner_radius: int = int(def_json.get("corner_radius", 2))
	var padding: int = int(def_json.get("padding", 8))
	var shadow_conf: Dictionary = def_json.get("shadow", {})
	var shadow_size: int = int(shadow_conf.get("size", 5))
	var shadow_offset_arr: Array = shadow_conf.get("offset", [2.0, 3.0])
	var shadow_offset := Vector2(float(shadow_offset_arr[0]), float(shadow_offset_arr[1]))
	var shadow_alpha: float = float(shadow_conf.get("alpha", 0.28))
	var palettes: Dictionary = def_json.get("palettes", {})
	assert(!palettes.is_empty(), "FATAL: [StickyOrderPad] Stationery definition missing 'palettes' dictionary: %s" % def_path)

	var node_palette_keys: Dictionary = composer_manifest.get("palette_slots", {})
	assert(!node_palette_keys.is_empty(), "FATAL: [StickyOrderPad] Composer manifest missing 'palette_slots' mapping.")

	for node_name in node_palette_keys.keys():
		var p := find_child(node_name, true, false) as PanelContainer
		if p == null:
			push_warning("[StickyOrderPad] Missing expected panel node: %s" % node_name)
			continue

		var pal_key: String = str(node_palette_keys[node_name])
		assert(palettes.has(pal_key), "FATAL: [StickyOrderPad] Palette key '%s' missing from %s!" % [pal_key, def_path])
		var pal_data: Dictionary = palettes[pal_key]
		assert(pal_data.has("bg") and pal_data.has("ink"), "FATAL: [StickyOrderPad] Palette '%s' missing 'bg' or 'ink' values." % pal_key)

		var bg_color := Color(str(pal_data["bg"]))
		var ink_color := Color(str(pal_data["ink"]))

		var sb := StyleBoxFlat.new()
		sb.bg_color = bg_color
		sb.set_corner_radius_all(corner_radius)
		sb.set_content_margin_all(padding)
		sb.shadow_size = shadow_size
		sb.shadow_offset = shadow_offset
		sb.shadow_color = Color(0, 0, 0, shadow_alpha)
		p.add_theme_stylebox_override("panel", sb)

		_apply_ink_color_recursive(p, ink_color)

func _apply_ink_color_recursive(node: Node, ink_color: Color) -> void:
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	if node is Label:
		node.add_theme_color_override("font_color", ink_color)
		if mono_font:
			node.add_theme_font_override("font", mono_font)

	elif node is OptionButton or node is Button:
		node.add_theme_color_override("font_color", ink_color)
		node.add_theme_color_override("font_pressed_color", ink_color)
		node.add_theme_color_override("font_hover_color", ink_color)
		node.add_theme_color_override("font_focus_color", ink_color)
		if mono_font:
			node.add_theme_font_override("font", mono_font)

		if node is OptionButton:
			var popup: PopupMenu = node.get_popup()
			if popup:
				popup.add_theme_color_override("font_color", ink_color)
				popup.add_theme_color_override("font_hover_color", ink_color)
				if mono_font:
					popup.add_theme_font_override("font", mono_font)

	elif node is SpinBox:
		var line_edit: LineEdit = node.get_line_edit()
		if line_edit:
			line_edit.add_theme_color_override("font_color", ink_color)
			line_edit.add_theme_color_override("font_selected_color", ink_color)
			if mono_font:
				line_edit.add_theme_font_override("font", mono_font)

	for child in node.get_children():
		_apply_ink_color_recursive(child, ink_color)

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