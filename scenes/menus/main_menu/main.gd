extends Control
# Called when the node enters the scene tree for the first time.

func _on_open_map_menu_pressed() -> void:
    var error := get_tree().change_scene_to_file("res://scenes/menus/map_menu/map_menu.tscn")

    if error != OK:
        push_error("Could not open map menu. Error Code: %s" % error)

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

func _launch_city_view() -> void:
    var error := get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")
    if error != OK:
        push_error("Could not open 3d cityview. Error Code: %s" % error)

func _on_exit_pressed() -> void:
    if OS.has_feature("editor"):
        print("Returning to the Godot editor...")
    get_tree().quit()