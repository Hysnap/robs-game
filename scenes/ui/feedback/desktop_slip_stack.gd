# res://scenes/ui/feedback/desktop_slip_stack.gd
class_name DesktopSlipStack
extends PanelContainer

signal slip_filed(slip_data: Dictionary, destination: String)
signal slip_discarded(slip_data: Dictionary)
signal stack_count_changed(unread_count: int)

const RETRO_THEME = preload("res://scenes/ui/filofax/retro_theme.gd")

@onready var drag_handle: Label = $VBoxContainer/Header/DragHandle
@onready var close_btn: Button = $VBoxContainer/Header/BtnMinimize
@onready var count_lbl: Label = $VBoxContainer/Header/CountLabel
@onready var card_slot: Control = $VBoxContainer/CardSlot
@onready var empty_lbl: Label = $VBoxContainer/EmptyLabel

var _pending_slips: Array[Dictionary] = []
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

# Manifest configuration defaults
var _presentation_order: String = "ISSUED_ORDER"
var _max_visible_stack: int = 4
var _max_rotation_degrees: float = 45.0

const SLIP_PALETTES: Dictionary = {
	"STICKY_YELLOW": {"bg": Color("#fff9a6"), "ink": Color("#1a1a1a"), "title": "MEMO NOTE"},
	"STICKY_MINT":   {"bg": Color("#d4fcd6"), "ink": Color("#102413"), "title": "FIELD NOTE"},
	"STICKY_ROSE":   {"bg": Color("#ffd1d5"), "ink": Color("#2b1114"), "title": "URGENT DISPATCH"},
	"PAPER_SCRAP":   {"bg": Color("#f0ede6"), "ink": Color("#1f2421"), "title": "TORN RECEIPT / SCRAP"}
}

func _ready() -> void:
	_load_manifest_rules()
	if drag_handle:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_handle.gui_input.connect(_on_drag_input)
	if close_btn:
		close_btn.pressed.connect(func(): visible = false)
	_refresh_display()

## Loads inbox rules from the scenario manifest via ScenarioManifestManager
func _load_manifest_rules() -> void:
	# Safe check: ScenarioManifestManager is globally registered
	if ClassDB.class_exists("ScenarioManifestManager"):
		var manifest: Dictionary = ScenarioManifestManager.get_manifest()
		var rules: Dictionary = manifest.get("inbox_rules", {})
		_presentation_order = str(rules.get("presentation_order", "ISSUED_ORDER")).to_upper()
		_max_visible_stack = int(rules.get("max_visible_stack", 4))
		_max_rotation_degrees = float(rules.get("max_rotation_degrees", 45.0))

func push_slips(slips: Array) -> void:
	_load_manifest_rules()
	
	var new_batch: Array = slips.duplicate()

	# 1. Apply Manifest Presentation Order Rule
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

	# 2. Assign procedural physical traits (persistent across redraws)
	for slip in new_batch:
		if not slip.has("slip_style"):
			var keys := SLIP_PALETTES.keys()
			slip["slip_style"] = keys[randi() % keys.size()]
		if not slip.has("tilt_degrees"):
			slip["tilt_degrees"] = randf_range(-_max_rotation_degrees, _max_rotation_degrees)
		if not slip.has("jitter_offset"):
			slip["jitter_offset"] = Vector2(randf_range(-14, 14), randf_range(-10, 10))

		_pending_slips.append(slip)
		
	_refresh_display()
	stack_count_changed.emit(_pending_slips.size())

func get_unread_count() -> int:
	return _pending_slips.size()

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

	# Render up to _max_visible_stack slips
	var visible_count: int = mini(_max_visible_stack, _pending_slips.size())
	
	# Godot renders lowest child index first.
	# We render from deepest card (visible_count - 1) down to top card (0),
	# so that index 0 is rendered last and sits on top of the pile!
	for i in range(visible_count - 1, -1, -1):
		var slip: Dictionary = _pending_slips[i]
		var is_top_card: bool = (i == 0)
		_render_slip_card(slip, is_top_card, i)

func _render_slip_card(slip: Dictionary, is_top: bool, depth_index: int) -> void:
	var style_key: String = str(slip.get("slip_style", "STICKY_YELLOW"))
	var palette: Dictionary = SLIP_PALETTES.get(style_key, SLIP_PALETTES["STICKY_YELLOW"])
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	var card := PanelContainer.new()
	var card_w: float = 260.0
	var card_h: float = 230.0
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.size = Vector2(card_w, card_h)
	
	# Explicit pivot center for clean angular tilt
	card.pivot_offset = Vector2(card_w * 0.5, card_h * 0.5)
	
	# Center inside CardSlot + apply random tilt and spatial jitter
	var slot_center := card_slot.size * 0.5
	if slot_center == Vector2.ZERO:
		slot_center = Vector2(190, 160) # Fallback to halfway across 380x320 area
		
	var jitter: Vector2 = slip.get("jitter_offset", Vector2.ZERO)
	card.position = slot_center - card.pivot_offset + jitter
	card.rotation_degrees = float(slip.get("tilt_degrees", 0.0))

	# Non-top cards ignore mouse clicks so only top card is triaged
	if not is_top:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	var bg_color: Color = palette["bg"]
	if not is_top:
		bg_color = bg_color.darkened(0.05 * (depth_index + 1))
	sb.bg_color = bg_color
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.20 if not is_top else 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(2, 3)
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	if not is_top:
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 1. Header
	var hdr := Label.new()
	hdr.text = "%s • WK %02d" % [palette["title"], int(slip.get("tick", 1))]
	hdr.add_theme_font_override("font", mono_font)
	hdr.add_theme_font_size_override("font_size", 9)
	hdr.add_theme_color_override("font_color", palette["ink"])
	vbox.add_child(hdr)

	var sep := HSeparator.new()
	sep.modulate = palette["ink"]
	sep.modulate.a = 0.25
	vbox.add_child(sep)

	# 2. Body
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = str(slip.get("text", "Shift completed."))
	body.fit_content = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("normal_font", mono_font)
	body.add_theme_font_size_override("normal_font_size", 10)
	body.add_theme_color_override("default_color", palette["ink"])
	if not is_top:
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body)

	# 3. Footer
	var author: String = str(slip.get("author", "Runner Dispatch"))
	var ftr := Label.new()
	ftr.text = "- %s" % author
	ftr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ftr.add_theme_font_override("font", mono_font)
	ftr.add_theme_font_size_override("font_size", 9)
	ftr.add_theme_color_override("font_color", palette["ink"].lightened(0.2))
	vbox.add_child(ftr)

	# 4. Triage Buttons on Top Card
	if is_top:
		var btn_box := HBoxContainer.new()
		btn_box.add_theme_constant_override("separation", 8)

		var btn_file := Button.new()
		btn_file.text = "📌 File in Filofax"
		btn_file.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_file.focus_mode = Control.FOCUS_NONE
		btn_file.add_theme_font_override("font", mono_font)
		btn_file.add_theme_font_size_override("font_size", 10)
		btn_file.pressed.connect(_on_file_pressed.bind(slip))
		btn_box.add_child(btn_file)

		var btn_discard := Button.new()
		btn_discard.text = "🗑 Tear Off"
		btn_discard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_discard.focus_mode = Control.FOCUS_NONE
		btn_discard.add_theme_font_override("font", mono_font)
		btn_discard.add_theme_font_size_override("font_size", 10)
		btn_discard.add_theme_color_override("font_color", Color("#8a1c14"))
		btn_discard.pressed.connect(_on_discard_pressed.bind(slip))
		btn_box.add_child(btn_discard)

		vbox.add_child(btn_box)

	card_slot.add_child(card)

func _on_file_pressed(slip: Dictionary) -> void:
	_pending_slips.pop_front()
	var dest: String = str(slip.get("destination", "team_feedback"))
	slip_filed.emit(slip, dest)
	_refresh_display()
	stack_count_changed.emit(_pending_slips.size())

func _on_discard_pressed(slip: Dictionary) -> void:
	_pending_slips.pop_front()
	slip_discarded.emit(slip)
	_refresh_display()
	stack_count_changed.emit(_pending_slips.size())

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
