# res://scenes/ui/components/sticky_order_pad.gd
class_name StickyOrderPad
extends PanelContainer

signal order_pinned(directive: Dictionary)
signal directive_committed(directive: Dictionary)
signal pad_closed

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const ShellRegistryScript = preload("res://scenes/ui/shell_host/shell_registry.gd")
const DirectiveComposerControllerScript = preload("res://systems/directive_composer_controller.gd")
const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")

var drag_handle: Label
var btn_close: Button

# Generic Slot Containers
var slot_action: PanelContainer
var slot_target: PanelContainer
var slot_scalar: PanelContainer
var slot_actor: PanelContainer
var slot_location: PanelContainer
var slot_telemetry: PanelContainer

# Input Controls
var opt_verb: OptionButton
var opt_category: OptionButton
var opt_target: OptionButton
var spin_amount: SpinBox
var opt_rail: OptionButton
var opt_postal: OptionButton
var opt_who: OptionButton
var opt_where_filter: OptionButton
var opt_where: OptionButton
var opt_contact: OptionButton
var lbl_estimate: Label

# Explicit Slot Headers
var lbl_hdr_action: Label
var lbl_hdr_target: Label
var lbl_hdr_scalar: Label
var lbl_hdr_actor: Label
var lbl_hdr_location: Label
var lbl_hdr_telemetry: Label

var btn_pin: Button
var btn_tear: Button

var _target_search_edit: LineEdit
var _location_search_edit: LineEdit
var _lbl_standing_warning: Label

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _cached_targets_for_verb: Array[Dictionary] = []
var _cached_locations: Array[Dictionary] = []
var _active_district_id: String = ""
var _injected_world_state: Dictionary = {}

func _enter_tree() -> void:
	_bind_and_assert_nodes()

func _bind_and_assert_nodes() -> void:
	drag_handle = get_node("VBox/Header/DragHandle") as Label
	btn_close = get_node("VBox/Header/BtnClose") as Button

	slot_action = get_node("VBox/NotesGrid/Slot_Action") as PanelContainer
	slot_target = get_node("VBox/NotesGrid/Slot_Target") as PanelContainer
	slot_scalar = get_node("VBox/NotesGrid/Slot_Scalar") as PanelContainer
	slot_actor = get_node("VBox/NotesGrid/Slot_Actor") as PanelContainer
	slot_location = get_node("VBox/NotesGrid/Slot_Location") as PanelContainer
	slot_telemetry = get_node("VBox/NotesGrid/Slot_Telemetry") as PanelContainer

	opt_verb = get_node("VBox/NotesGrid/Slot_Action/VBox/VerbOption") as OptionButton
	opt_category = get_node("VBox/NotesGrid/Slot_Target/VBox/CategoryOption") as OptionButton
	opt_target = get_node("VBox/NotesGrid/Slot_Target/VBox/TargetOption") as OptionButton
	spin_amount = get_node("VBox/NotesGrid/Slot_Scalar/VBox/AmountSpin") as SpinBox
	opt_rail = get_node("VBox/NotesGrid/Slot_Scalar/VBox/RailOption") as OptionButton
	opt_postal = get_node("VBox/NotesGrid/Slot_Scalar/VBox/PostalOption") as OptionButton
	opt_who = get_node("VBox/NotesGrid/Slot_Actor/VBox/WhoOption") as OptionButton
	opt_where_filter = get_node("VBox/NotesGrid/Slot_Location/VBox/WhereFilterOption") as OptionButton
	opt_where = get_node("VBox/NotesGrid/Slot_Location/VBox/WhereOption") as OptionButton
	opt_contact = get_node("VBox/NotesGrid/Slot_Location/VBox/ContactOption") as OptionButton
	lbl_estimate = get_node("VBox/NotesGrid/Slot_Telemetry/VBox/EstimatedCostLabel") as Label

	lbl_hdr_action = get_node("VBox/NotesGrid/Slot_Action/VBox/SlotHeader_Action") as Label
	lbl_hdr_target = get_node("VBox/NotesGrid/Slot_Target/VBox/SlotHeader_Target") as Label
	lbl_hdr_scalar = get_node("VBox/NotesGrid/Slot_Scalar/VBox/SlotHeader_Scalar") as Label
	lbl_hdr_actor = get_node("VBox/NotesGrid/Slot_Actor/VBox/SlotHeader_Actor") as Label
	lbl_hdr_location = get_node("VBox/NotesGrid/Slot_Location/VBox/SlotHeader_Location") as Label
	lbl_hdr_telemetry = get_node("VBox/NotesGrid/Slot_Telemetry/VBox/SlotHeader_Telemetry") as Label

	btn_pin = get_node("VBox/ButtonBox/SaveNoteBtn") as Button
	btn_tear = get_node("VBox/ButtonBox/DiscardBtn") as Button

	# Core Rule 4: Fail Early, Fail Loud
	assert(drag_handle != null, "FATAL: [StickyOrderPad] DragHandle node missing from scene hierarchy.")
	assert(btn_pin != null, "FATAL: [StickyOrderPad] SaveNoteBtn node missing from scene hierarchy.")
	assert(opt_verb != null, "FATAL: [StickyOrderPad] VerbOption node missing from scene hierarchy.")
	assert(opt_category != null, "FATAL: [StickyOrderPad] CategoryOption node missing from scene hierarchy.")
	assert(opt_target != null, "FATAL: [StickyOrderPad] TargetOption node missing from scene hierarchy.")
	assert(opt_where != null, "FATAL: [StickyOrderPad] WhereOption node missing from scene hierarchy.")
	assert(spin_amount != null, "FATAL: [StickyOrderPad] AmountSpin node missing from scene hierarchy.")
	assert(opt_rail != null, "FATAL: [StickyOrderPad] RailOption node missing from scene hierarchy.")
	assert(opt_postal != null, "FATAL: [StickyOrderPad] PostalOption node missing from scene hierarchy.")
	assert(slot_action != null, "FATAL: [StickyOrderPad] Slot_Action missing from scene hierarchy.")
	assert(slot_target != null, "FATAL: [StickyOrderPad] Slot_Target missing from scene hierarchy.")
	assert(slot_scalar != null, "FATAL: [StickyOrderPad] Slot_Scalar missing from scene hierarchy.")
	assert(slot_actor != null, "FATAL: [StickyOrderPad] Slot_Actor missing from scene hierarchy.")
	assert(slot_location != null, "FATAL: [StickyOrderPad] Slot_Location missing from scene hierarchy.")
	assert(slot_telemetry != null, "FATAL: [StickyOrderPad] Slot_Telemetry missing from scene hierarchy.")

func _ready() -> void:
	top_level = true
	z_index = 100

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
	if opt_rail:
		opt_rail.item_selected.connect(_on_rail_selected)
	if opt_verb:
		opt_verb.item_selected.connect(_on_verb_selected)
	if opt_category:
		opt_category.item_selected.connect(_on_category_selected)
	if opt_target:
		opt_target.item_selected.connect(func(_idx): _recalculate_estimate())
	if opt_who:
		opt_who.item_selected.connect(func(_idx): _refresh_standing_order_warning())
	if opt_where_filter:
		opt_where_filter.item_selected.connect(_on_where_filter_selected)
	if opt_where:
		opt_where.item_selected.connect(_on_where_location_selected)

	_ensure_dynamic_filter_controls()
	_configure_scrollable_popups()
	_populate_default_verbs()

	_populate_default_verbs()
	_sync_simulation_data()
	_apply_sticky_note_skins()
	_apply_form_layout_for_verb(_get_active_verb())
	_recalculate_estimate()

func open_for_district(district_id: String) -> void:
	assert(not district_id.is_empty(), "FATAL: [StickyOrderPad] Cannot open order pad with empty district_id.")
	_active_district_id = district_id
	_apply_sticky_note_skins()
	_sync_simulation_data()
	_select_where_by_id(district_id)
	_apply_form_layout_for_verb(_get_active_verb())
	_recalculate_estimate()

	visible = true
	move_to_front()
	_center_on_screen()

func open_for_context(context: Dictionary) -> void:
	if context.has("world_state") and context["world_state"] is Dictionary:
		_injected_world_state = context["world_state"]
	var target_dist: String = str(context.get("target_district_id", ""))
	if target_dist.is_empty():
		var ws := _get_world_state()
		target_dist = str(ws.get("selected_district_id", ws.get("player_knowledge", {}).get("home_district_id", "")))

	assert(not target_dist.is_empty(), "FATAL: [StickyOrderPad] Could not resolve a valid district for order context.")
	open_for_district(target_dist)

func _get_world_state() -> Dictionary:
	if not _injected_world_state.is_empty():
		return _injected_world_state
	var gs = ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [StickyOrderPad] GameState or world_state is unmounted.")
	return gs.world_state

func _center_on_screen() -> void:
	var vp_rect := get_viewport_rect()
	var pad_size := size
	if pad_size.x <= 0 or pad_size.y <= 0:
		pad_size = get_combined_minimum_size()
	global_position = (vp_rect.size - pad_size) * 0.5

## Populates verbs dynamically from controller
func _populate_default_verbs() -> void:
	if opt_verb == null:
		return
	opt_verb.clear()

	var registered := DirectiveComposerControllerScript.get_registered_verbs()
	if registered.is_empty():
		push_error("[StickyOrderPad FATAL] DirectiveComposerController has 0 registered verbs mounted.")
		return

	var verb_entries: Array[Dictionary] = []
	for verb_code in registered:
		var token_key := "UI_VERB_" + verb_code
		var display_label := tr(token_key)
		if display_label.is_empty() or display_label == token_key:
			token_key = "VERB_" + verb_code
			display_label = tr(token_key)
			if display_label.is_empty() or display_label == token_key:
				display_label = verb_code.replace("_", " ").capitalize()
		verb_entries.append({"code": verb_code, "label": display_label})

	verb_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["label"]).nocasecmp_to(str(b["label"])) < 0
	)

	var idx: int = 0
	for entry in verb_entries:
		opt_verb.add_item(str(entry["label"]), idx)
		opt_verb.set_item_metadata(idx, str(entry["code"]))
		idx += 1

## Dynamically adapts form slot visibility, labels, and bounds based on verb layout config
func _apply_form_layout_for_verb(verb_token: String) -> void:
	if verb_token.is_empty():
		return

	var layout: Dictionary = DirectiveComposerControllerScript.get_form_layout(verb_token)

	# 1. Target Slot (Commodity / Entity / Obligation)
	var target_cfg: Dictionary = layout.get("target_section", {})
	var target_visible: bool = bool(target_cfg.get("visible", true))
	slot_target.visible = target_visible

	if lbl_hdr_target and target_cfg.has("label_token"):
		var token: String = str(target_cfg["label_token"])
		lbl_hdr_target.text = tr(token)

	# 2. Scalar Slot (Amount / Duration)
	var amount_cfg: Dictionary = layout.get("amount_section", {})
	var amount_visible: bool = bool(amount_cfg.get("visible", true))
	slot_scalar.visible = amount_visible

	if lbl_hdr_scalar and amount_cfg.has("label_token"):
		var token: String = str(amount_cfg["label_token"])
		lbl_hdr_scalar.text = tr(token)

	spin_amount.min_value = float(amount_cfg.get("min_value", 1.0))
	spin_amount.max_value = float(amount_cfg.get("max_value", 999.0))
	spin_amount.step = float(amount_cfg.get("step", 1.0))
	spin_amount.value = float(amount_cfg.get("default_value", spin_amount.min_value))

	# 2b. Settlement Rail & Postal Delivery Sub-Selectors
	var rail_cfg: Dictionary = layout.get("rail_section", {})
	var rail_visible: bool = bool(rail_cfg.get("visible", false))
	opt_rail.visible = rail_visible
	if rail_visible:
		_refresh_rail_options(_get_world_state(), rail_cfg)
		_sync_postal_visibility_for_selected_rail(_get_world_state())
	else:
		opt_postal.visible = false

	# 3. Location Slot
	var loc_cfg: Dictionary = layout.get("location_section", {})
	slot_location.visible = bool(loc_cfg.get("visible", true))

	if lbl_hdr_location and loc_cfg.has("label_token"):
		var token: String = str(loc_cfg["label_token"])
		lbl_hdr_location.text = tr(token)

	# 4. Contact Selector
	var contact_cfg: Dictionary = layout.get("contact_section", {})
	opt_contact.visible = bool(contact_cfg.get("visible", false))

	# 5. Telemetry Slot
	slot_telemetry.visible = DirectiveComposerControllerScript.should_show_telemetry(verb_token)

## Ingests simulation state and populates form elements
func _sync_simulation_data() -> void:
	var ws: Dictionary = _get_world_state()

	# 1. Responsible Party (Actor Slot from canonical crew residents)
	_populate_actor_options(ws)

	# 2. Target Items & Category Drill-Down (Target Slot)
	_refresh_targets_for_active_verb(ws)

	# 3. Location Options (Location Slot)
	_refresh_where_filters_for_active_verb()
	_cached_locations = DirectiveComposerControllerScript.build_locations_cache(_get_active_verb(), _active_district_id, ws)
	_apply_location_filter()

	# 4. Contacts
	_refresh_contact_options()

func _refresh_rail_options(ws: Dictionary, rail_cfg: Dictionary = {}) -> void:
	if opt_rail == null:
		return
	opt_rail.clear()

	var rails := TargetDomainRegistryScript.resolve_domain("SETTLEMENT_RAIL", ws, rail_cfg)
	var idx: int = 0
	for rail in rails:
		var token: String = str(rail.get("label_token", rail.get("id", "")))
		opt_rail.add_item(tr(token), idx)
		opt_rail.set_item_metadata(idx, rail)
		idx += 1

func _sync_postal_visibility_for_selected_rail(ws: Dictionary) -> void:
	if opt_postal == null or opt_rail == null or not opt_rail.visible or opt_rail.item_count == 0:
		if opt_postal:
			opt_postal.visible = false
		return

	var rail_meta = opt_rail.get_item_metadata(opt_rail.selected)
	var can_post: bool = (rail_meta is Dictionary) and bool(rail_meta.get("can_post", false))
	opt_postal.visible = can_post
	if not can_post:
		return

	opt_postal.clear()
	var postal_opts := TargetDomainRegistryScript.resolve_domain("POSTAL_CLASS", ws, {})
	var idx: int = 0
	for p_opt in postal_opts:
		var token: String = str(p_opt.get("label_token", p_opt.get("id", "")))
		opt_postal.add_item(tr(token), idx)
		opt_postal.set_item_metadata(idx, p_opt)
		idx += 1

func _on_rail_selected(_idx: int) -> void:
	_sync_postal_visibility_for_selected_rail(_get_world_state())

func _populate_actor_options(ws: Dictionary) -> void:
	if opt_who == null:
		return
	opt_who.clear()

	var crew_actors := DirectiveComposerControllerScript.get_crew_actors(ws)
	if crew_actors.is_empty():
		opt_who.add_item(tr("UI_STAFF_PLAYER_LEADER"), 0)
		opt_who.set_item_metadata(0, "PLAYER")
		return

	var sorted_actors: Array[Dictionary] = crew_actors.duplicate()
	sorted_actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)

	var idx: int = 0
	for actor in sorted_actors:
		var a_name: String = str(actor.get("name", ""))
		var a_role: String = str(actor.get("role", ""))
		var display_str: String = "%s (%s)" % [a_name, a_role.capitalize()] if not a_role.is_empty() else a_name
		opt_who.add_item(display_str, idx)
		opt_who.set_item_metadata(idx, str(actor.get("id", "")))
		idx += 1

	_refresh_standing_order_warning()

func _refresh_targets_for_active_verb(ws: Dictionary) -> void:
	var verb := _get_active_verb()
	_cached_targets_for_verb = DirectiveComposerControllerScript.resolve_targets_for_verb(verb, ws)
	_populate_category_options()
	_apply_category_filter()

func _populate_category_options() -> void:
	if opt_category == null:
		return
	opt_category.clear()

	var categories := DirectiveComposerControllerScript.extract_target_categories(_cached_targets_for_verb)
	
	# Index 0: ALL
	opt_category.add_item(tr("UI_CAT_ALL"), 0)
	opt_category.set_item_metadata(0, "ALL")

	var idx: int = 1
	for cat in categories:
		opt_category.add_item(_format_category_hierarchy_label(cat), idx)
		opt_category.set_item_metadata(idx, cat)
		idx += 1

func _apply_category_filter() -> void:
	if opt_target == null or opt_category == null:
		return
	opt_target.clear()

	var selected_cat := "ALL"
	if opt_category.item_count > 0:
		selected_cat = str(opt_category.get_item_metadata(opt_category.selected))

	var query: String = _target_search_edit.text.strip_edges().to_lower() if _target_search_edit != null else ""
	var filtered := DirectiveComposerControllerScript.filter_targets_by_category(_cached_targets_for_verb, selected_cat)

	var decorated: Array[Dictionary] = []
	for item in filtered:
		var token: String = str(item.get("label_token", item.get("id", "")))
		var label_str: String = str(item.get("display", "")).strip_edges()
		if label_str.is_empty():
			var translated := tr(token)
			label_str = translated if (not translated.is_empty() and translated != token) else str(item.get("id", "")).replace("_", " ").capitalize()
		if not query.is_empty() and not label_str.to_lower().contains(query):
			continue
		decorated.append({"label": label_str, "item": item})

	if decorated.is_empty():
		opt_target.add_item(tr("UI_TARGET_NONE_AVAILABLE"), 0)
		opt_target.set_item_metadata(0, {"id": "", "unit_cost": 0.0})
		_recalculate_estimate()
		return

	decorated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["label"]).nocasecmp_to(str(b["label"])) < 0
	)

	var idx: int = 0
	for entry in decorated:
		opt_target.add_item(str(entry["label"]), idx)
		opt_target.set_item_metadata(idx, entry["item"])
		idx += 1

	_recalculate_estimate()

func _refresh_where_filters_for_active_verb() -> void:
	if opt_where_filter == null or opt_verb == null or opt_verb.item_count == 0:
		return
	opt_where_filter.clear()

	var allowed_scopes := DirectiveComposerControllerScript.get_allowed_scopes(_get_active_verb())

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

func _apply_location_filter() -> void:
	if opt_where == null or opt_where_filter == null:
		return
	opt_where.clear()

	var filter_type := "ALL"
	if opt_where_filter.item_count > 0:
		filter_type = str(opt_where_filter.get_item_metadata(opt_where_filter.selected))

	var query: String = _location_search_edit.text.strip_edges().to_lower() if _location_search_edit != null else ""
	var filtered := DirectiveComposerControllerScript.filter_locations(_cached_locations, filter_type)
	var idx: int = 0
	for loc in filtered:
		var disp: String = str(loc.get("display", ""))
		if not query.is_empty() and not disp.to_lower().contains(query):
			continue
		opt_where.add_item(disp, idx)
		opt_where.set_item_metadata(idx, loc)
		idx += 1

	if opt_where.item_count == 0:
		opt_where.add_item(tr("UI_NO_LOCATIONS_IN_SCOPE"), 0)
		opt_where.set_item_metadata(0, {"id": "", "type": "NONE", "category": "NONE", "sector": "NONE"})

func _refresh_contact_options() -> void:
	if opt_contact == null:
		return
	opt_contact.clear()

	opt_contact.add_item(tr("UI_CONTACT_ANYONE_AVAILABLE"), 0)
	opt_contact.set_item_metadata(0, "")

	if opt_where == null or opt_where.item_count == 0:
		return

	var loc_meta = opt_where.get_item_metadata(opt_where.selected)
	if loc_meta is Dictionary:
		var ws: Dictionary = _get_world_state()
		var contacts := DirectiveComposerControllerScript.resolve_contacts_for_location(loc_meta, ws)
		var idx: int = 1
		for c in contacts:
			opt_contact.add_item("%s (%s)" % [c["name"], c["role"]], idx)
			opt_contact.set_item_metadata(idx, c["id"])
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
	if _target_search_edit:
		_target_search_edit.text = ""
	if _location_search_edit:
		_location_search_edit.text = ""
	var verb := _get_active_verb()
	var ws: Dictionary = _get_world_state()
	_apply_form_layout_for_verb(verb)
	_refresh_targets_for_active_verb(ws)
	_refresh_where_filters_for_active_verb()
	_cached_locations = DirectiveComposerControllerScript.build_locations_cache(verb, _active_district_id, ws)
	_apply_location_filter()
	_refresh_contact_options()
	_recalculate_estimate()

func _on_category_selected(_idx: int) -> void:
	_apply_category_filter()

func _on_where_filter_selected(_idx: int) -> void:
	_apply_location_filter()
	_refresh_contact_options()

func _on_where_location_selected(_idx: int) -> void:
	_refresh_contact_options()
	_recalculate_estimate()

func _recalculate_estimate() -> void:
	if lbl_estimate == null or spin_amount == null:
		return

	var qty: float = float(spin_amount.value)
	var target_meta: Dictionary = {}
	if opt_target and opt_target.item_count > 0:
		var meta = opt_target.get_item_metadata(opt_target.selected)
		if meta is Dictionary:
			target_meta = meta

	var location_meta: Dictionary = {}
	if opt_where and opt_where.item_count > 0:
		var meta = opt_where.get_item_metadata(opt_where.selected)
		if meta is Dictionary:
			location_meta = meta

	var ws: Dictionary = _get_world_state()
	var est_data: Dictionary = DirectiveComposerControllerScript.calculate_estimate_with_intel(
		qty, 
		target_meta, 
		location_meta, 
		ws
	)

	var total_val: float = float(est_data.get("estimated_total", 0.0))
	var is_exact: bool = bool(est_data.get("is_exact", true))
	var num_str := String.num(total_val, 2)

	var fmt_key := "FMT_CURRENCY" if is_exact else "FMT_CURRENCY_ESTIMATE"
	var fmt_template := tr(fmt_key)
	lbl_estimate.text = fmt_template.replace("{val}", num_str)

func _on_pin_pressed() -> void:
	var target_meta = opt_target.get_item_metadata(opt_target.selected) if opt_target and opt_target.item_count > 0 else {}
	var loc_meta = opt_where.get_item_metadata(opt_where.selected) if opt_where and opt_where.item_count > 0 else {}
	var contact_meta = opt_contact.get_item_metadata(opt_contact.selected) if opt_contact and opt_contact.item_count > 0 else null
	var who_meta = opt_who.get_item_metadata(opt_who.selected) if opt_who and opt_who.item_count > 0 else "PLAYER"
	var actor_id: Variant = who_meta if who_meta != null and str(who_meta) != "" else "PLAYER"

	var rail_code: String = ""
	if opt_rail and opt_rail.visible and opt_rail.item_count > 0:
		var r_meta = opt_rail.get_item_metadata(opt_rail.selected)
		rail_code = str(r_meta.get("id", "")) if r_meta is Dictionary else str(r_meta)

	var postal_class: String = ""
	if opt_postal and opt_postal.visible and opt_postal.item_count > 0:
		var p_meta = opt_postal.get_item_metadata(opt_postal.selected)
		postal_class = str(p_meta.get("id", "")) if p_meta is Dictionary else str(p_meta)

	var raw_node_id: Variant = loc_meta.get("id", "") if loc_meta is Dictionary else ""
	var raw_contact_id: Variant = contact_meta if contact_meta != null and str(contact_meta) != "" else ""

	var form_data: Dictionary = {
		"verb": _get_active_verb(),
		"initiator_id": actor_id,
		"assigned_to": actor_id,
		"assigned_to_name": opt_who.get_item_text(opt_who.selected) if opt_who and opt_who.item_count > 0 else "",
		"counterparty_id": raw_contact_id,
		"target_item": str(target_meta.get("id", "")) if target_meta is Dictionary else str(target_meta),
		"amount": float(spin_amount.value) if spin_amount else 1.0,
		"rail_code": rail_code,
		"postal_class": postal_class,
		"target_node_id": raw_node_id,
		"target_node_name": str(loc_meta.get("display", loc_meta.get("id", ""))) if loc_meta is Dictionary else "",
		"target_scope": str(loc_meta.get("type", "DISTRICT")) if loc_meta is Dictionary else "DISTRICT",
		"unit_cost": float(target_meta.get("unit_cost", 0.0)) if target_meta is Dictionary else 0.0,
		"exposure_modifier": 1.0
	}

	var directive: Dictionary = DirectiveComposerControllerScript.build_and_validate_directive(form_data)
	if directive.is_empty():
		return

	order_pinned.emit(directive)
	directive_committed.emit(directive)
	visible = false

func _on_close_pressed() -> void:
	visible = false
	pad_closed.emit()

func _get_active_verb() -> String:
	if opt_verb == null or opt_verb.item_count == 0:
		return ""
	var meta = opt_verb.get_item_metadata(opt_verb.selected)
	return str(meta) if meta != null else opt_verb.get_item_text(opt_verb.selected)

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
	var border_conf: Dictionary = def_json.get("border", {})
	var border_width: int = int(border_conf.get("width", 1))
	var border_color := Color(str(border_conf.get("color", "#4a4a4a")))
	var shadow_conf: Dictionary = def_json.get("shadow", {})
	var shadow_size: int = int(shadow_conf.get("size", 5))
	var shadow_offset_arr: Array = shadow_conf.get("offset", [2.0, 3.0])
	var shadow_offset := Vector2(float(shadow_offset_arr[0]), float(shadow_offset_arr[1]))
	var shadow_alpha: float = float(shadow_conf.get("alpha", 0.28))
	var palettes: Dictionary = def_json.get("palettes", {})
	assert(!palettes.is_empty(), "FATAL: [StickyOrderPad] Stationery definition missing 'palettes' dictionary: %s" % def_path)

	var cover_sb: StyleBoxFlat = RETRO_THEME.create_cover_style()
	cover_sb.set_corner_radius_all(corner_radius + 2)
	cover_sb.set_content_margin_all(padding)
	cover_sb.shadow_size = shadow_size + 2
	cover_sb.shadow_offset = shadow_offset
	cover_sb.shadow_color = Color(0, 0, 0, shadow_alpha)
	add_theme_stylebox_override("panel", cover_sb)

	var header_node := get_node_or_null("VBox/Header")
	if header_node != null:
		_apply_ink_color_recursive(header_node, RETRO_THEME.color_page_bg)

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
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
		sb.set_corner_radius_all(corner_radius)
		sb.set_content_margin_all(padding)
		sb.shadow_size = shadow_size
		sb.shadow_offset = shadow_offset
		sb.shadow_color = Color(0, 0, 0, shadow_alpha)
		p.add_theme_stylebox_override("panel", sb)

		_apply_ink_color_recursive(p, ink_color)

func _apply_ink_color_recursive(node: Node, ink_color: Color) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", ink_color)

	elif node is OptionButton or node is Button:
		node.add_theme_color_override("font_color", ink_color)
		node.add_theme_color_override("font_pressed_color", ink_color)
		node.add_theme_color_override("font_hover_color", ink_color)
		node.add_theme_color_override("font_focus_color", ink_color)

		if node is OptionButton:
			var popup: PopupMenu = node.get_popup()
			if popup:
				popup.add_theme_color_override("font_color", ink_color)
				popup.add_theme_color_override("font_hover_color", ink_color)

	elif node is SpinBox:
		var line_edit: LineEdit = node.get_line_edit()
		if line_edit:
			line_edit.add_theme_color_override("font_color", ink_color)
			line_edit.add_theme_color_override("font_selected_color", ink_color)

	for child in node.get_children():
		_apply_ink_color_recursive(child, ink_color)

func _ensure_dynamic_filter_controls() -> void:
	var target_vbox := get_node_or_null("VBox/NotesGrid/Slot_Target/VBox") as VBoxContainer
	if target_vbox != null and _target_search_edit == null:
		_target_search_edit = LineEdit.new()
		_target_search_edit.placeholder_text = tr("UI_SEARCH_FILTER")
		_target_search_edit.clear_button_enabled = true
		_target_search_edit.text_changed.connect(func(_t: String): _apply_category_filter())
		target_vbox.add_child(_target_search_edit)
		target_vbox.move_child(_target_search_edit, opt_target.get_index())

	var loc_vbox := get_node_or_null("VBox/NotesGrid/Slot_Location/VBox") as VBoxContainer
	if loc_vbox != null and _location_search_edit == null:
		_location_search_edit = LineEdit.new()
		_location_search_edit.placeholder_text = tr("UI_SEARCH_FILTER")
		_location_search_edit.clear_button_enabled = true
		_location_search_edit.text_changed.connect(func(_t: String):
			_apply_location_filter()
			_refresh_contact_options()
		)
		loc_vbox.add_child(_location_search_edit)
		loc_vbox.move_child(_location_search_edit, opt_where.get_index())

	var actor_vbox := get_node_or_null("VBox/NotesGrid/Slot_Actor/VBox") as VBoxContainer
	if actor_vbox != null and _lbl_standing_warning == null:
		_lbl_standing_warning = Label.new()
		_lbl_standing_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lbl_standing_warning.visible = false
		_lbl_standing_warning.add_theme_color_override("font_color", Color("#9a3412"))
		actor_vbox.add_child(_lbl_standing_warning)

func _configure_scrollable_popups() -> void:
	const MAX_TEN_ITEM_POPUP_HEIGHT := 280
	var dropdowns: Array[OptionButton] = [
		opt_verb, opt_category, opt_target, opt_rail, opt_postal,
		opt_who, opt_where_filter, opt_where, opt_contact
	]
	for dd in dropdowns:
		if dd != null:
			var popup: PopupMenu = dd.get_popup()
			if popup != null:
				popup.max_size = Vector2i(0, MAX_TEN_ITEM_POPUP_HEIGHT)

func _format_category_hierarchy_label(cat_path: String) -> String:
	var segments: PackedStringArray = cat_path.split("/", false)
	var out: PackedStringArray = []
	for seg in segments:
		var clean: String = seg.strip_edges().to_upper()
		if clean.is_empty():
			continue
		var tok := "UI_CAT_" + clean
		var translated := tr(tok)
		if not translated.is_empty() and translated != tok:
			out.append(translated)
		else:
			out.append(clean.replace("_", " ").capitalize())
	return " / ".join(out)

func _refresh_standing_order_warning() -> void:
	if _lbl_standing_warning == null or opt_who == null or opt_who.item_count == 0:
		return
	var who_meta: Variant = opt_who.get_item_metadata(opt_who.selected)
	var normalized_id: Variant = DirectiveComposerControllerScript._normalize_entity_id(who_meta)
	var ws: Dictionary = _get_world_state()
	var sim_day: int = DirectiveComposerControllerScript._resolve_current_sim_day(ws)
	var has_so: bool = DirectiveComposerControllerScript._has_active_standing_orders_for_actor(ws, normalized_id, sim_day)
	_lbl_standing_warning.visible = has_so
	if has_so:
		_lbl_standing_warning.text = tr("UI_WARN_STANDING_ORDER_CONFLICT")

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