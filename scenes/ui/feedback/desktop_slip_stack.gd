# res://scenes/ui/feedback/desktop_slip_stack.gd
class_name DesktopSlipStack
extends PanelContainer

signal top_card_action(action_id: String, slip_data: Dictionary)
signal stack_count_changed(unread_count: int)

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const STATIONERY_REGISTRY = preload("res://scenes/ui/feedback/stationery_registry.gd")

@onready var drag_handle: Label = $VBoxContainer/Header/DragHandle
@onready var close_btn: Button = $VBoxContainer/Header/BtnMinimize
@onready var count_lbl: Label = $VBoxContainer/Header/CountLabel
@onready var card_slot: Control = $VBoxContainer/CardSlot
@onready var empty_lbl: Label = $VBoxContainer/EmptyLabel

var _pending_slips: Array[Dictionary] = []
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

var _presentation_order: String = ""
var _max_visible_stack: int = 0
var _max_rotation_degrees: float = 0.0
var _jitter_px: float = 0.0

func _ready() -> void:
	_load_manifest_rules()
	if drag_handle:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_handle.gui_input.connect(_on_drag_input)
	if close_btn:
		close_btn.pressed.connect(func(): visible = false)
	_refresh_display()

func _load_manifest_rules() -> void:
	STATIONERY_REGISTRY.initialize()
	var rules: Dictionary = STATIONERY_REGISTRY.get_stack_rules()
	assert(not rules.is_empty(), "FATAL: [DesktopSlipStack] Failed to load stack_rules from active inbox manifest.")

	_presentation_order = str(rules.get("presentation_order", "ISSUED_ORDER")).to_upper()
	_max_visible_stack = int(rules.get("max_visible_cards", rules.get("max_visible_stack", 4)))
	_max_rotation_degrees = float(rules.get("max_tilt_degrees", rules.get("max_rotation_degrees", 12.0)))
	_jitter_px = float(rules.get("jitter_offset_px", _jitter_px))

func push_cards(cards: Array) -> void:
	_load_manifest_rules()
	var new_batch: Array = []
	for card in cards:
		new_batch.append(_normalize_card_payload(card))

	match _presentation_order:
		"ISSUED_ORDER":
			new_batch.sort_custom(func(a, b):
				return int(a.get("staged_index", 0)) < int(b.get("staged_index", 0))
			)
		"COMPLETION_ORDER":
			new_batch.sort_custom(func(a, b):
				return int(a.get("completion_index", 0)) < int(b.get("completion_index", 0))
			)
		"RANDOM":
			new_batch.shuffle()

	for slip in new_batch:
		if not slip.has("tilt_degrees"):
			slip["tilt_degrees"] = randf_range(-_max_rotation_degrees, _max_rotation_degrees)
		if not slip.has("jitter_offset"):
			slip["jitter_offset"] = Vector2(randf_range(-_jitter_px, _jitter_px), randf_range(-_jitter_px, _jitter_px))

		_pending_slips.append(slip)

	_refresh_display()
	stack_count_changed.emit(_pending_slips.size())

func push_slips(slips: Array) -> void:
	push_cards(slips)

func get_unread_count() -> int:
	return _pending_slips.size()

func get_card_count() -> int:
	return _pending_slips.size()

func is_empty() -> bool:
	return _pending_slips.is_empty()

func get_top_card() -> Dictionary:
	return _pending_slips[0] if not _pending_slips.is_empty() else {}

func _refresh_display() -> void:
	if card_slot == null:
		return

	for child in card_slot.get_children():
		child.queue_free()

	var count := _pending_slips.size()
	if count_lbl:
		count_lbl.text = "[ %d UNREAD ]" % count

	if count == 0:
		empty_lbl.visible = true
		card_slot.visible = false
		return

	empty_lbl.visible = false
	card_slot.visible = true

	var visible_count: int = mini(_max_visible_stack, _pending_slips.size())

	# Render deepest index first; index 0 renders last on top
	for i in range(visible_count - 1, -1, -1):
		var slip: Dictionary = _pending_slips[i]
		var is_top_card: bool = (i == 0)
		_render_slip_card(slip, is_top_card, i)

func _render_slip_card(slip: Dictionary, is_top: bool, depth_index: int) -> void:
	var default_def_id: String = STATIONERY_REGISTRY.get_default_definition_id()
	var def_id: String = str(slip.get("stationery_profile", default_def_id)).to_upper()
	var def: Dictionary = STATIONERY_REGISTRY.get_definition(def_id)

	if def.is_empty():
		push_warning("[DesktopSlipStack] Stationery '%s' not allowed in active manifest; resolving default '%s'." % [def_id, default_def_id])
		def = STATIONERY_REGISTRY.get_definition(default_def_id)

	var palettes: Dictionary = def.get("palettes", {})
	var palette_key: String = str(slip.get("palette_key", "")).to_upper()
	var fallback_palette: Dictionary = palettes.values()[0] if not palettes.is_empty() else {"bg": "#f5f5f0", "ink": "#1a1a1a", "title": "MEMO"}
	var palette: Dictionary = palettes.get(palette_key, fallback_palette)

	var mono_font: Font = RETRO_THEME.get_monospace_font()

	var card := PanelContainer.new()
	var dims: Array = def.get("dimensions", [270.0, 240.0])
	var card_w: float = float(dims[0]) if dims.size() > 0 else 270.0
	var card_h: float = float(dims[1]) if dims.size() > 1 else 240.0
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.size = Vector2(card_w, card_h)
	card.pivot_offset = Vector2(card_w * 0.5, card_h * 0.5)

	var slot_center := card_slot.size * 0.5
	if slot_center == Vector2.ZERO:
		slot_center = Vector2(190, 160)

	var jitter: Vector2 = slip.get("jitter_offset", Vector2.ZERO)
	card.position = slot_center - card.pivot_offset + jitter
	card.rotation_degrees = float(slip.get("tilt_degrees", 0.0))

	if not is_top:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	var bg_color := Color(palette.get("bg", "#f5f5f0"))
	var ink_color := Color(palette.get("ink", "#1a1a1a"))
	if not is_top:
		bg_color = bg_color.darkened(0.05 * (depth_index + 1))
	sb.bg_color = bg_color
	sb.set_corner_radius_all(int(def.get("corner_radius", 2)))
	sb.set_content_margin_all(int(def.get("padding", 8)))

	# Optional outer border defined by stationery JSON
	if def.has("border") and def["border"] is Dictionary:
		var border_cfg: Dictionary = def["border"]
		var bw: int = int(border_cfg.get("width", 1))
		sb.set_border_width_all(bw)
		sb.border_color = Color(border_cfg.get("color", ink_color.to_html()))

	var shadow_cfg: Dictionary = def.get("shadow", {})
	var shadow_offset: Array = shadow_cfg.get("offset", [2.0, 3.0])
	var shadow_alpha: float = float(shadow_cfg.get("alpha", 0.28))
	sb.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha if not is_top else shadow_alpha + 0.1)
	sb.shadow_size = int(shadow_cfg.get("size", 6))
	sb.shadow_offset = Vector2(float(shadow_offset[0]), float(shadow_offset[1]))
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	if not is_top:
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 1. Header
	var title_text: String = tr(palette.get("title_token", palette.get("title", "MEMO NOTE")))
	var hdr := Label.new()
	hdr.text = "%s // WK %02d" % [title_text, int(slip.get("week", slip.get("tick", 1)))]
	hdr.add_theme_font_override("font", mono_font)
	hdr.add_theme_font_size_override("font_size", 9)
	hdr.add_theme_color_override("font_color", ink_color)
	vbox.add_child(hdr)

	var sep := HSeparator.new()
	sep.modulate = ink_color
	sep.modulate.a = 0.25
	vbox.add_child(sep)

	# 2. Optional Grid Boxes Layout (e.g., Argos Catalogue Order Pad)
	var layout_variant: String = str(def.get("layout_variant", "")).to_upper()
	if layout_variant == "GRID_BOXES" and def.has("grid_boxes") and def["grid_boxes"] is Dictionary:
		_append_grid_boxes_header(vbox, def["grid_boxes"], ink_color, mono_font)

	# 3. Body (wrapped in a ruled box if grid_boxes.body_box is enabled)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = str(slip.get("display_text", slip.get("text", "Shift completed.")))
	body.fit_content = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("normal_font", mono_font)
	body.add_theme_font_size_override("normal_font_size", 10)
	body.add_theme_color_override("default_color", ink_color)
	if not is_top:
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if layout_variant == "GRID_BOXES" and bool(def.get("grid_boxes", {}).get("body_box", false)):
		var grid_cfg: Dictionary = def["grid_boxes"]
		var box_color := Color(grid_cfg.get("border_color", ink_color.to_html()))
		var body_frame := PanelContainer.new()
		body_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var frame_sb := StyleBoxFlat.new()
		frame_sb.bg_color = Color(0, 0, 0, 0)
		frame_sb.set_border_width_all(1)
		frame_sb.border_color = box_color
		frame_sb.set_content_margin_all(4)
		body_frame.add_theme_stylebox_override("panel", frame_sb)
		if not is_top:
			body_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body_frame.add_child(body)
		vbox.add_child(body_frame)
	else:
		vbox.add_child(body)

	# 4. Footer
	var author: String = str(slip.get("author", tr("DEFAULT_OPERATIVE_TITLE")))
	var ftr := Label.new()
	ftr.text = "- %s" % author
	ftr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ftr.add_theme_font_override("font", mono_font)
	ftr.add_theme_font_size_override("font_size", 9)
	ftr.add_theme_color_override("font_color", ink_color.lightened(0.2))
	vbox.add_child(ftr)

	# 5. Interactive Destination Routing on Top Slip
	if is_top:
		var routing_box := HBoxContainer.new()
		routing_box.add_theme_constant_override("separation", 4)

		var dest_opt := OptionButton.new()
		dest_opt.add_theme_font_override("font", mono_font)
		dest_opt.add_theme_font_size_override("font_size", 9)
		dest_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dest_opt.add_item(tr("UI_DEST_DIARY"), 0)
		dest_opt.set_item_metadata(0, "DIARY")
		dest_opt.add_item(tr("UI_DEST_DOSSIER"), 1)
		dest_opt.set_item_metadata(1, "DOSSIER")
		dest_opt.add_item(tr("UI_DEST_ROSTER"), 2)
		dest_opt.set_item_metadata(2, "ROSTER")
		dest_opt.add_item(tr("UI_DEST_ACCOUNTS"), 3)
		dest_opt.set_item_metadata(3, "FINANCE")

		var requested_destination := str(slip.get("destination", "DIARY")).to_upper()
		for option_index in range(dest_opt.item_count):
			if str(dest_opt.get_item_metadata(option_index)).to_upper() == requested_destination:
				dest_opt.select(option_index)
				break
		routing_box.add_child(dest_opt)

		var btn_file := Button.new()
		btn_file.text = tr("UI_BTN_FILE")
		btn_file.focus_mode = Control.FOCUS_NONE
		btn_file.add_theme_font_override("font", mono_font)
		btn_file.add_theme_font_size_override("font_size", 9)
		btn_file.pressed.connect(func():
			var chosen_dest: String = dest_opt.get_selected_metadata()
			_on_file_pressed(slip, chosen_dest)
		)
		routing_box.add_child(btn_file)

		var btn_discard := Button.new()
		btn_discard.text = "X " + tr("UI_BTN_DISCARD")
		btn_discard.focus_mode = Control.FOCUS_NONE
		btn_discard.add_theme_font_override("font", mono_font)
		btn_discard.add_theme_font_size_override("font_size", 9)
		btn_discard.add_theme_color_override("font_color", Color("#8a1c14"))
		btn_discard.pressed.connect(_on_discard_pressed.bind(slip))
		routing_box.add_child(btn_discard)

		vbox.add_child(routing_box)

	card_slot.add_child(card)

func _append_grid_boxes_header(parent_vbox: VBoxContainer, grid_cfg: Dictionary, default_ink: Color, mono_font: Font) -> void:
	var columns: Array = grid_cfg.get("columns", [])
	if columns.is_empty():
		return

	var box_border_color := Color(grid_cfg.get("border_color", default_ink.to_html()))
	var accent_color := Color(grid_cfg.get("accent_color", box_border_color.to_html()))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)

	for col in columns:
		if not (col is Dictionary):
			continue
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = float(col.get("width_ratio", 0.25))

		var cell_sb := StyleBoxFlat.new()
		cell_sb.bg_color = Color(box_border_color.r, box_border_color.g, box_border_color.b, 0.08)
		cell_sb.set_border_width_all(1)
		cell_sb.border_color = box_border_color
		cell_sb.set_content_margin_all(2)
		cell.add_theme_stylebox_override("panel", cell_sb)

		var col_token: String = str(col.get("token", ""))
		var col_fallback: String = str(col.get("fallback", ""))
		var translated: String = tr(col_token) if not col_token.is_empty() else ""
		var lbl := Label.new()
		lbl.text = translated if (not translated.is_empty() and translated != col_token) else col_fallback
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", mono_font)
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", accent_color)
		cell.add_child(lbl)
		row.add_child(cell)

	parent_vbox.add_child(row)

func _on_file_pressed(slip: Dictionary, destination: String) -> void:
	_pending_slips.pop_front()
	slip["destination"] = destination
	top_card_action.emit("FILE", slip)
	_refresh_display()
	stack_count_changed.emit(_pending_slips.size())

func _on_discard_pressed(slip: Dictionary) -> void:
	_pending_slips.pop_front()
	top_card_action.emit("DISCARD", slip)
	_refresh_display()
	stack_count_changed.emit(_pending_slips.size())

func _normalize_card_payload(raw_card: Variant) -> Dictionary:
	var card: Dictionary = raw_card.duplicate(true) if raw_card is Dictionary else {}
	if not card.has("display_text"):
		card["display_text"] = card.get("text", "Shift completed.")
	if not card.has("stationery_profile"):
		card["stationery_profile"] = card.get("slip_style", STATIONERY_REGISTRY.get_default_definition_id())
	if not card.has("destination"):
		card["destination"] = "DIARY"
	return card

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