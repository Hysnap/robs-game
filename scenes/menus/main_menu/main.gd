extends Control
# Called when the node enters the scene tree for the first time.

func _on_open_map_menu_pressed() -> void:
    var error := get_tree().change_scene_to_file("res://scenes/menus/map_menu/map_menu.tscn")
	
    if error != OK:
        push_error("Could not open map menu. Error Code: %s" % error)

func _on_open_generated_city_pressed() -> void:
    var error := get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")
	
    if error != OK:
        push_error("Could not open 3d cityview. Error Code: %s" % error)

func _on_exit_pressed():
    if OS.has_feature("editor"):
        print("Returning to the Godot editor...")
    else:
		# Save game logic for actual players goes here
        pass

    get_tree().quit()