extends Control
# Called when the node enters the scene tree for the first time.

@onready var continue_button: Button = get_node_or_null("WelcomeScreen/ColorRect/VBoxContainer/ContinueGame")

func _ready() -> void:
    _update_continue_button_state()

## Updates the button appearance/state depending on whether a valid save exists
func _update_continue_button_state() -> void:
    if continue_button == null:
        return

    var has_memory_city: bool = not GameState.world_state.get("districts", {}).is_empty()
    var latest_slot: String = SaveManager.get_latest_save_slot()

    if has_memory_city or not latest_slot.is_empty():
        continue_button.disabled = false
        continue_button.modulate = Color.WHITE
    else:
        continue_button.disabled = true
        continue_button.modulate = Color(0.5, 0.5, 0.5, 0.6) # Dimmed if no game exists

func _on_open_generated_city_pressed() -> void:
    # 1. If GameState already has districts in memory, jump straight in
    if not GameState.world_state.get("districts", {}).is_empty():
        _launch_city_view()
        return

	# 2. Otherwise check if saved slot_01 exists on disk and load it
    if FileAccess.file_exists("user://saves/slot_01/game_state.json"):
        print("[MainMenu] Existing save found in slot_01. Loading game...")
        if SaveManager.load_game("slot_01"):
            _launch_city_view()
            return

	# 3. If neither exists, route to loader to generate a fresh city
    print("[MainMenu] No existing city or save found. Launching initial generator...")
    var error := get_tree().change_scene_to_file("res://scenes/menus/city_generator_loader.tscn")
    if error != OK:
        push_error("Could not open city generator loader. Error Code: %s" % error)

func _on_open_map_menu_pressed() -> void:
    # "CREATE CITY": Configuration setup for a fresh procedural world
    var error := get_tree().change_scene_to_file("res://scenes/menus/map_menu/map_menu.tscn")
    if error != OK:
        push_error("[MainMenu] Could not open map_menu.tscn: %s" % error)

func _on_continue_game_pressed() -> void:
	# 1. Fast Path: Current session already has the city in memory
    if not GameState.world_state.get("districts", {}).is_empty():
        print("[MainMenu] Resuming active in-memory city session...")
        _launch_city_view()
        return

	# 2. Disk Path: Find and mount the most recently modified save slot
    var latest_slot: String = SaveManager.get_latest_save_slot()
    if not latest_slot.is_empty():
        print("[MainMenu] Loading latest save slot: '%s'..." % latest_slot)
        if SaveManager.load_game(latest_slot):
            _launch_city_view()
            return
        else:
            push_error("[MainMenu] Failed to load save slot: %s" % latest_slot)

	# 3. Fallback: No save found
    push_warning("[MainMenu] No existing game save found to continue.")

func _launch_city_view() -> void:
    var error := get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")
    if error != OK:
        push_error("Could not open 3d cityview. Error Code: %s" % error)

func _on_exit_pressed() -> void:
    if OS.has_feature("editor"):
        print("Returning to the Godot editor...")
    get_tree().quit()