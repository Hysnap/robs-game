# res://scenes/3d_scenes/city_view.gd
extends Node3D

@onready var city_crafter: Node3D = $CityCrafter
@onready var rts_camera: RTSCamera3D = $RTSCamera3D
@onready var game_hud: GameHUD = $GameHUD
@onready var filofax_canvas: CanvasLayer = $FilofaxCanvas
@onready var desktop_inbox: DesktopSlipStack = find_child("DesktopSlipStack", true, false)

var filofax_ui: FilofaxUI = null

func _ready() -> void:
	# 1. Resolve Filofax reference
	if filofax_canvas:
		filofax_ui = filofax_canvas.find_child("FilofaxBinder", true, false) as FilofaxUI

	# 2. Wire Camera Raycast to District Docket
	if rts_camera != null:
		rts_camera.district_clicked.connect(_on_district_clicked)
		rts_camera.focus_on(city_crafter.global_position)

	# 3. Connect HUD toggle button
	if game_hud != null:
		game_hud.toggle_filofax_requested.connect(_toggle_filofax_visibility)

	# 3.5 Inbox Button and Notification
	if game_hud != null and desktop_inbox != null:
		game_hud.toggle_messages_inbox_requested.connect(func():
			desktop_inbox.visible = not desktop_inbox.visible
			if desktop_inbox.visible:
				desktop_inbox.move_to_front()
		)
		desktop_inbox.stack_count_changed.connect(game_hud.update_unread_message_count)
		desktop_inbox.slip_filed.connect(_on_slip_filed_to_filofax)

	# 4. Synchronize seed and render saved visual layout
	var active_seed: String = str(GameState.world_state.get("metadata", {}).get("active_seed", "default-city"))
	if "seed_id" in city_crafter:
		city_crafter.seed_id = active_seed

	var saved_layout: Dictionary = GameState.world_state.get("city_layout", {})
	if not saved_layout.is_empty() and city_crafter.has_method("load_visual_layout"):
		city_crafter.load_visual_layout(saved_layout)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_filofax_visibility()
			get_viewport().set_input_as_handled()

func _on_district_clicked(block_id: String) -> void:
	GameState.set_selected_district(block_id)
	
	_ensure_filofax_hierarchy_visible()
	if filofax_ui != null:
		filofax_ui.display_district_docket(block_id)

func _toggle_filofax_visibility() -> void:
	if filofax_canvas == null or filofax_ui == null:
		return

	var target_visibility: bool = not filofax_canvas.visible
	if target_visibility:
		_ensure_filofax_hierarchy_visible()
		var active_id: String = str(GameState.selected_district_id)
		if not active_id.is_empty():
			filofax_ui.display_district_docket(active_id)
	else:
		filofax_canvas.visible = false
		filofax_ui.visible = false

## Walks up the hierarchy ensuring parent nodes and modulations aren't masked
func _ensure_filofax_hierarchy_visible() -> void:
	if filofax_canvas:
		filofax_canvas.visible = true
	if filofax_ui:
		var node: Node = filofax_ui
		while node != null and node != filofax_canvas:
			if node is CanvasItem:
				node.visible = true
				node.modulate.a = 1.0
			node = node.get_parent()
		filofax_ui.visible = true

func _on_slip_filed_to_filofax(slip: Dictionary, destination: String) -> void:
	# Records permanently to the Filofax cache
	if not GameState.world_state.has("filed_records"):
		GameState.world_state["filed_records"] = {}
	if not GameState.world_state["filed_records"].has(destination):
		GameState.world_state["filed_records"][destination] = []
		
	GameState.world_state["filed_records"][destination].append(slip)
	print("[Desk] Filed slip permanently to '%s': %s" % [destination, slip.get("text", "")])