# res://scenes/ui/components/sticky_order_pad.gd
class_name StickyOrderPad
extends PanelContainer

signal order_pinned(directive: Dictionary)
signal directive_committed(directive: Dictionary)
signal pad_closed

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const ShellRegistryScript = preload("res://scenes/ui/shell_host/shell_registry.gd")
const DirectiveComposerControllerScript = preload("res://systems/directive_composer_controller.gd")

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

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _cached_targets_for_verb: Array[Dictionary] = []
var _cached_locations: Array[Dictionary] = []
var _active_district_id: String = ""

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
	if opt_verb:
		opt_verb.item_selected.connect(_on_verb_selected)
	if opt_category:
		opt_category.item_selected.connect(_on_category_selected)
	if opt_target:
		opt_target.item_selected.connect(func(_idx): _recalculate_estimate())
	if opt_where_filter:
		opt_where_filter.item_selected.connect(_on_where_filter_selected)
	if opt_where:
		opt_where.item_selected.connect(_on_where_location_selected)

	_populate_default_verbs()
	_sync_simulation_data()
	_apply_sticky_note_skins()
	_apply_form_layout_for_verb(_get_active_verb())
	_recalculate_estimate()

func open_for_district(district_id: String) -> void:
	assert(not district_id.is_empty(), "FATAL: [StickyOrderPad] Cannot open order pad with empty district_id.")
	_active_district_id = district_id
	_sync_simulation_data()
	_select_where_by_id(district_id)
	_apply_form_layout_for_verb(_get_active_verb())
	_recalculate_estimate()

	visible = true
	move_to_front()
	_center_on_screen()

func open_for_context(context: Dictionary) -> void:
	var target_dist: String = str(context.get("target_district_id", ""))
	if target_dist.is_empty():
		var gs = ScenarioManifestManager.get_game_state()
		if gs != null:
			if gs.has_method("get_selected_district_id"):
				target_dist = gs.get_selected_district_id()
			if target_dist.is_empty() and "world_state" in gs:
				target_dist = str(gs.world_state.get("player_knowledge", {}).get("home_district_id", ""))

	assert(not target_dist.is_empty(), "FATAL: [StickyOrderPad] Could not resolve a valid district for order context.")
	open_for_district(target_dist)

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

## Dynamically adapts form slot visibility, labels, and bounds based on verb layout config
func _apply_form_layout_for_verb(verb_token: String) -> void:
	if verb_token.is_empty():
		return

	var layout: Dictionary = DirectiveComposerControllerScript.get_form_layout(verb_token)

	# 1. Target Slot (Commodity / Entity)
	var target_cfg: Dictionary = layout.get("target_section", {})
	var target_visible: bool = bool(target_cfg.get("visible", true))
	slot_target.visible = target_visible

	if lbl_hdr_target and target_cfg.has("label_token") and target_cfg["label_token"] != null:
		lbl_hdr_target.text = tr(str(target_cfg["label_token"]))

	# 2. Scalar Slot (Amount / Duration)
	var amount_cfg: Dictionary = layout.get("amount_section", {})
	var amount_visible: bool = bool(amount_cfg.get("visible", true))
	slot_scalar.visible = amount_visible

	if lbl_hdr_scalar and amount_cfg.has("label_token") and amount_cfg["label_token"] != null:
		lbl_hdr_scalar.text = tr(str(amount_cfg["label_token"]))

	spin_amount.min_value = float(amount_cfg.get("min_value", 1.0))
	spin_amount.max_value = float(amount_cfg.get("max_value", 999.0))
	spin_amount.step = float(amount_cfg.get("step", 1.0))
	spin_amount.value = float(amount_cfg.get("default_value", spin_amount.min_value))

	# 3. Location Slot
	var loc_cfg: Dictionary = layout.get("location_section", {})
	slot_location.visible = bool(loc_cfg.get("visible", true))

	if lbl_hdr_location and loc_cfg.has("label_token") and loc_cfg["label_token"] != null:
		lbl_hdr_location.text = tr(str(loc_cfg["label_token"]))

## Ingests simulation state and populates form elements
func _sync_simulation_data() -> void:
	var gs = ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [StickyOrderPad] GameState or world_state is unmounted.")
	var ws: Dictionary = gs.world_state

	# 1. Responsible Party (Actor Slot)
	_populate_staff_options(ws.get("staff", {}))

	# 2. Target Items & Category Drill-Down (Target Slot)
	_refresh_targets_for_active_verb(ws)

	# 3. Location Options (Location Slot)
	_refresh_where_filters_for_active_verb()
	_cached_locations = DirectiveComposerControllerScript.build_locations_cache(_get_active_verb(), _active_district_id, ws)
	_apply_location_filter()

	# 4. Contacts
	_refresh_contact_options()

func _populate_staff_options(staff_dict: Dictionary) -> void:
	if opt_who == null:
		return
	opt_who.clear()

	if staff_dict.is_empty():
		opt_who.add_item(tr("UI_STAFF_PLAYER_LEADER"), 0)
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
	var all_label := tr("UI_CAT_ALL")
	if all_label == "UI_CAT_ALL":
		all_label = "All Categories"
	opt_category.add_item(all_label, 0)
	opt_category.set_item_metadata(0, "ALL")

	var idx: int = 1
	for cat in categories:
		var token_key := "UI_CAT_" + cat
		var cat_label := tr(token_key)
		if cat_label == token_key:
			cat_label = cat.capitalize().replace("_", " ")

		opt_category.add_item(cat_label, idx)
		opt_category.set_item_metadata(idx, cat)
		idx += 1

func _apply_category_filter() -> void:
	if opt_target == null or opt_category == null:
		return
	opt_target.clear()

	var selected_cat := "ALL"
	if opt_category.item_count > 0:
		selected_cat = str(opt_category.get_item_metadata(opt_category.selected))

	var filtered := DirectiveComposerControllerScript.filter_targets_by_category(_cached_targets_for_verb, selected_cat)
	if filtered.is_empty():
		opt_target.add_item(tr("UI_TARGET_NONE_AVAILABLE"), 0)
		opt_target.set_item_metadata(0, {"id": "", "unit_cost": 0.0})
		_recalculate_estimate()
		return

	var idx: int = 0
	for item in filtered:
		var token: String = str(item.get("label_token", item.get("id", "")))
		opt_target.add_item(tr(token), idx)
		opt_target.set_item_metadata(idx, item)
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

	var filtered := DirectiveComposerControllerScript.filter_locations(_cached_locations, filter_type)
	var idx: int = 0
	for loc in filtered:
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

	opt_contact.add_item(tr("UI_CONTACT_ANYONE_AVAILABLE"), 0)
	opt_contact.set_item_metadata(0, "")

	if opt_where == null or opt_where.item_count == 0:
		return

	var loc_meta = opt_where.get_item_metadata(opt_where.selected)
	if loc_meta is Dictionary:
		var contacts := DirectiveComposerControllerScript.resolve_contacts_for_location(loc_meta)
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
	var verb := _get_active_verb()
	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if gs != null and "world_state" in gs else {}
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

	var gs = ScenarioManifestManager.get_game_state()
	var ws: Dictionary = gs.world_state if gs != null and "world_state" in gs else {}

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
	if fmt_template == fmt_key:
		fmt_template = "£{val}" if is_exact else "~£{val}"

	lbl_estimate.text = fmt_template.replace("{val}", num_str)

func _on_pin_pressed() -> void:
	var target_meta = opt_target.get_item_metadata(opt_target.selected) if opt_target and opt_target.item_count > 0 else {}
	var loc_meta = opt_where.get_item_metadata(opt_where.selected) if opt_where and opt_where.item_count > 0 else {}
	var contact_meta = opt_contact.get_item_metadata(opt_contact.selected) if opt_contact and opt_contact.item_count > 0 else ""
	var who_meta = opt_who.get_item_metadata(opt_who.selected) if opt_who and opt_who.item_count > 0 else "PLAYER"

	var form_data: Dictionary = {
		"verb": _get_active_verb(),
		"initiator_id": str(who_meta),
		"assigned_to": opt_who.get_item_text(opt_who.selected) if opt_who and opt_who.item_count > 0 else "Player",
		"counterparty_id": str(contact_meta) if contact_meta != null else "",
		"target_item": str(target_meta.get("id", "")) if target_meta is Dictionary else str(target_meta),
		"amount": float(spin_amount.value) if spin_amount else 1.0,
		"target_node_id": str(loc_meta.get("id", "")) if loc_meta is Dictionary else "",
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