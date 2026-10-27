# res://scenes/ui/filofax/filofax_slip_stack.gd
class_name FilofaxSlipStack
extends VBoxContainer

signal slip_filed(slip_data: Dictionary, destination: String)
signal slip_discarded(slip_data: Dictionary)

const RETRO_THEME = preload("res://scenes/ui/filofax/retro_theme.gd")

@onready var lbl_counter: Label = $Header/SlipCounter
@onready var stack_viewport: CenterContainer = $StackViewport
@onready var empty_label: Label = $EmptyStateLabel

var _pending_slips: Array[Dictionary] = []

# Palette of messy desk slips
const SLIP_PALETTES: Dictionary = {
	"STICKY_YELLOW": {"bg": Color("#fff9a6"), "ink": Color("#1a1a1a"), "title": "MEMO NOTE"},
	"STICKY_MINT":   {"bg": Color("#d4fcd6"), "ink": Color("#102413"), "title": "FIELD NOTE"},
	"STICKY_ROSE":   {"bg": Color("#ffd1d5"), "ink": Color("#2b1114"), "title": "URGENT DISPATCH"},
	"PAPER_SCRAP":   {"bg": Color("#f0ede6"), "ink": Color("#1f2421"), "title": "TORN RECEIPT / SCRAP"},
	"OFFICIAL_SLIP": {"bg": Color("#e8ecf0"), "ink": Color("#0d1b2a"), "title": "CARBON COPY"}
}

func _ready() -> void:
	_refresh_view()

## Adds newly generated action outcome slips to the pending stack
func push_slips(new_slips: Array) -> void:
	for slip in new_slips:
		# Ensure procedural physical slip properties exist
		if not slip.has("slip_style"):
			var styles: Array = SLIP_PALETTES.keys()
			slip["slip_style"] = styles[randi() % styles.size()]
		if not slip.has("tilt_degrees"):
			slip["tilt_degrees"] = randf_range(-3.5, 3.5) # Haphazard desk rotation
			
		_pending_slips.append(slip)
		
	_refresh_view()

func _refresh_view() -> void:
	# Clear active rendered slip card
	for child in stack_viewport.get_children():
		child.queue_free()

	var count: int = _pending_slips.size()
	if lbl_counter:
		lbl_counter.text = "(%d unfiled)" % count

	if count == 0:
		stack_viewport.visible = false
		empty_label.visible = true
		return

	stack_viewport.visible = true
	empty_label.visible = false

	# Always display and triage the TOP slip (index 0)
	var top_slip: Dictionary = _pending_slips[0]
	_render_active_slip(top_slip)

func _render_active_slip(slip: Dictionary) -> void:
	var style_key: String = str(slip.get("slip_style", "STICKY_YELLOW"))
	var palette: Dictionary = SLIP_PALETTES.get(style_key, SLIP_PALETTES["STICKY_YELLOW"])
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 220)
	card.rotation_degrees = float(slip.get("tilt_degrees", 0.0))
	card.pivot_offset = Vector2(120, 110)

	# Build tactical physical paper StyleBoxFlat
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette["bg"]
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(2, 3)
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# 1. Header (Type & Week)
	var hdr := Label.new()
	var tick: int = int(slip.get("tick", 1))
	hdr.text = "[ %s • WK %02d ]" % [palette["title"], tick]
	hdr.add_theme_font_override("font", mono_font)
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", palette["ink"])
	vbox.add_child(hdr)

	# Faint tear-off divider
	var line := HSeparator.new()
	line.modulate = palette["ink"]
	line.modulate.a = 0.2
	vbox.add_child(line)

	# 2. Body / Natural Language Outcome
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = str(slip.get("text", "Shift completed."))
	body.fit_content = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("normal_font", mono_font)
	body.add_theme_font_size_override("normal_font_size", 11)
	body.add_theme_color_override("default_color", palette["ink"])
	vbox.add_child(body)

	# 3. Footer / Author metadata
	var author: String = str(slip.get("author", "Runner Dispatch"))
	var ftr := Label.new()
	ftr.text = "- %s" % author
	ftr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ftr.add_theme_font_override("font", mono_font)
	ftr.add_theme_font_size_override("font_size", 9)
	ftr.add_theme_color_override("font_color", palette["ink"].lightened(0.2))
	vbox.add_child(ftr)

	# 4. Action Triage Buttons
	var btn_box := HBoxContainer.new()
	btn_box.theme_override_constants.separation = 6

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
	btn_discard.add_theme_color_override("font_color", RETRO_THEME.color_ink_warning)
	btn_discard.pressed.connect(_on_discard_pressed.bind(slip))
	btn_box.add_child(btn_discard)

	vbox.add_child(btn_box)
	stack_viewport.add_child(card)

func _on_file_pressed(slip: Dictionary) -> void:
	_pending_slips.pop_front()
	# Modular routing: destination can be specified by the slip or default to "team_feedback"
	var dest: String = str(slip.get("destination", "team_feedback"))
	slip_filed.emit(slip, dest)
	_refresh_view()

func _on_discard_pressed(slip: Dictionary) -> void:
	_pending_slips.pop_front()
	# The event already occurred in reality; disposing simply drops the written report
	slip_discarded.emit(slip)
	_refresh_view()