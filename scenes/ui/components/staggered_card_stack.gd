# res://scenes/ui/modules/staggered_card_stack.gd
class_name StaggeredCardStack
extends Control

signal top_card_action(action_id, card_payload)

@export var max_visible_cards: int = 4
@export var max_tilt_degrees: float = 45.0
@export var jitter_px: float = 12.0

var _pending_payloads: Array[Dictionary] = []
var _card_tilts: Array[float] = []
var _card_offsets: Array[Vector2] = []

var _container: Control = null

func _init() -> void:
	_container = Control.new()
	_container.name = "CardSlot"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_container)

## Configures the module dynamically from a loaded JSON schema
func configure_from_schema(schema: Dictionary) -> void:
	var rules = schema.get("stack_rules", {})
	max_visible_cards = int(rules.get("max_visible_cards", max_visible_cards))
	max_tilt_degrees = float(rules.get("max_tilt_degrees", max_tilt_degrees))
	jitter_px = float(rules.get("jitter_offset_px", jitter_px))

## Ingests an array of generic card payloads
func push_cards(cards: Array) -> void:
	for c in cards:
		_pending_payloads.append(c)
		_card_tilts.append(randf_range(-max_tilt_degrees, max_tilt_degrees))
		_card_offsets.append(Vector2(randf_range(-jitter_px, jitter_px), randf_range(-jitter_px, jitter_px)))
	_refresh_display()

func get_card_count() -> int:
	return _pending_payloads.size()

func is_empty() -> bool:
	return _pending_payloads.is_empty()

func get_top_card() -> Dictionary:
	return _pending_payloads[0] if not _pending_payloads.is_empty() else {}

## Removes the top card and notifies listeners
func pop_top_card(action_id: String) -> Dictionary:
	if _pending_payloads.is_empty():
		return {}

	var popped: Dictionary = _pending_payloads.pop_front()
	_card_tilts.pop_front()
	_card_offsets.pop_front()
	_refresh_display()

	top_card_action.emit(action_id, popped)
	return popped

func _refresh_display() -> void:
	for child in _container.get_children():
		_container.remove_child(child)
		child.queue_free()

	if _pending_payloads.is_empty():
		visible = false
		return

	visible = true
	var count_to_show = mini(_pending_payloads.size(), max_visible_cards)

	# Render from bottom-most visible up to top card
	for i in range(count_to_show - 1, -1, -1):
		var payload = _pending_payloads[i]
		var is_top = (i == 0)

		var card_panel = PanelContainer.new()
		card_panel.custom_minimum_size = Vector2(240, 140)
		card_panel.pivot_offset = Vector2(120, 70)
		card_panel.rotation_degrees = _card_tilts[i]
		card_panel.position = _card_offsets[i]

		var layout = VBoxContainer.new()
		layout.add_theme_constant_override("separation", 4)
		card_panel.add_child(layout)

		var label = Label.new()
		label.text = str(payload.get("display_text", ""))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout.add_child(label)

		if is_top:
			# Top card receives interactive triage controls
			var action_box = HBoxContainer.new()
			action_box.add_theme_constant_override("separation", 6)
			
			var btn_file = Button.new()
			btn_file.text = "📌 " + tr("UI_BTN_FILE")
			btn_file.pressed.connect(func(): pop_top_card("FILE"))
			action_box.add_child(btn_file)

			var btn_discard = Button.new()
			btn_discard.text = "🗑 " + tr("UI_BTN_DISCARD")
			btn_discard.pressed.connect(func(): pop_top_card("DISCARD"))
			action_box.add_child(btn_discard)

			layout.add_child(action_box)
		else:
			# Lower cards ignore mouse events so top card is always triaged first
			card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_container.add_child(card_panel)