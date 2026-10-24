# res://scenes/3d_scenes/city_view.gd
extends Node3D

@onready var city_crafter: Node3D = $CityCrafter
@onready var rts_camera: RTSCamera3D = $RTSCamera3D
@onready var filofax_canvas: CanvasLayer = $FilofaxCanvas
var filofax_ui: FilofaxUI = null

func _ready() -> void:
	setup_navigation()

	# Resolve Filofax UI
	if filofax_canvas != null:
		filofax_ui = filofax_canvas.find_child("FilofaxBinder", true, false) as FilofaxUI

	# Connect Camera Signals
	if rts_camera != null:
		rts_camera.district_clicked.connect(_on_district_clicked)
		rts_camera.focus_on(city_crafter.global_position)
	
	# 4. Ingest Seed and Load Visual Layout
	var active_seed: String = str(GameState.world_state.get("metadata", {}).get("active_seed", "default-city"))
	if "seed_id" in city_crafter:
		city_crafter.seed_id = active_seed

	# Load Visual Layout
	var saved_layout: Dictionary = GameState.world_state.get("city_layout", {})
	if not saved_layout.is_empty() and city_crafter.has_method("load_visual_layout"):
		city_crafter.load_visual_layout(saved_layout)

func _unhandled_input(event: InputEvent) -> void:
	# Keep TAB hotkey for Filofax toggle
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_filofax_visibility()
			get_viewport().set_input_as_handled()

func _on_district_clicked(block_id: String) -> void:
	print("[CityView] District ground clicked: %s" % block_id)

	# 1. Update GameState selection pointer
	if GameState.has_method("set_selected_district"):
		GameState.set_selected_district(block_id)
	else:
		GameState.world_state["selected_district_id"] = block_id

	# 2. Force CanvasLayer and Filofax UI to be visible
	if filofax_canvas != null:
		filofax_canvas.visible = true
	
	# 3. Resolve filofax_ui if not cached, make visible, and display docket
	if filofax_ui == null and filofax_canvas != null:
		filofax_ui = filofax_canvas.find_child("FilofaxBinder", true, false) as FilofaxUI

	if filofax_ui != null:
		filofax_ui.visible = true
		filofax_ui.display_district_docket(block_id)
		print("[CityView] Successfully popped Filofax docket for: %s" % block_id)
	else:
		push_error("[CityView] Failed to find FilofaxUI under FilofaxCanvas!")

func _toggle_filofax_visibility() -> void:
	if filofax_canvas == null:
		return

	var will_be_visible: bool = not filofax_canvas.visible
	filofax_canvas.visible = will_be_visible
	
	if filofax_ui == null:
		filofax_ui = filofax_canvas.find_child("FilofaxBinder", true, false) as FilofaxUI

	if filofax_ui != null:
		filofax_ui.visible = will_be_visible
		# If opening the binder from the button and no district is open yet, show active or home district
		if will_be_visible:
			var active_id: String = str(GameState.world_state.get("selected_district_id", ""))
			if not active_id.is_empty():
				filofax_ui.display_district_docket(active_id)

func setup_navigation() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CityNavigation"
	add_child(canvas_layer)

	# 1. Main Menu Button
	var return_button := Button.new()
	return_button.name = "ReturnToMainMenu"
	return_button.text = tr("CITY_VIEW_BTN_MAIN_MENU")
	return_button.position = Vector2(20.0, 20.0)
	return_button.custom_minimum_size = Vector2(180.0, 44.0)
	return_button.pressed.connect(_on_return_to_main_menu_pressed)
	canvas_layer.add_child(return_button)

	# 2. Filofax Organizer Desk Button (Top-Left HUD)
	var filofax_button := Button.new()
	filofax_button.name = "ToggleFilofaxButton"
	filofax_button.text = "📖 FILOFAX (TAB)"
	filofax_button.position = Vector2(20.0, 72.0)
	filofax_button.custom_minimum_size = Vector2(180.0, 44.0)
	filofax_button.pressed.connect(_toggle_filofax_visibility)
	
	# Clean 1980s leather/gold styling
	filofax_button.add_theme_color_override("font_color", Color("#D4AF37"))
	filofax_button.add_theme_color_override("font_hover_color", Color("#FFF0AA"))
	canvas_layer.add_child(filofax_button)

	# 3. Status Label (Shifted down below the Filofax button)
	var status_label := Label.new()
	status_label.name = "GenerationStatus"
	status_label.position = Vector2(20.0, 126.0)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	canvas_layer.add_child(status_label)

func _on_return_to_main_menu_pressed() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/menus/main_menu/main.tscn")
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)
