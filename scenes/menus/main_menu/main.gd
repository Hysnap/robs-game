# res://scenes/menus/main_menu/main.gd
extends Control

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const SHELL_REGISTRY = preload("res://scenes/ui/shell_host/shell_registry.gd")

@onready var title_label: Label = $Backdrop/CenterMargin/CardPanel/VBoxContainer/TitleLabel
@onready var new_city_button: Button = $Backdrop/CenterMargin/CardPanel/VBoxContainer/OpenMapMenu
@onready var continue_button: Button = $Backdrop/CenterMargin/CardPanel/VBoxContainer/OpenGeneratedCity
@onready var exit_button: Button = $Backdrop/CenterMargin/CardPanel/VBoxContainer/Exit

func _ready() -> void:
	if RETRO_THEME.active_profile_id.is_empty():
		var active_shell: String = SHELL_REGISTRY.get_configured_shell_id()
		RETRO_THEME.load_all_catalog_profiles(active_shell)
	theme = RETRO_THEME.create_godot_theme()

	var backdrop := get_node_or_null("Backdrop") as PanelContainer
	if backdrop:
		backdrop.add_theme_stylebox_override("panel", RETRO_THEME.create_cover_style())
	var card_panel := get_node_or_null("Backdrop/CenterMargin/CardPanel") as PanelContainer
	if card_panel:
		card_panel.add_theme_stylebox_override("panel", RETRO_THEME.create_page_style())

	_apply_localized_labels()
	new_city_button.pressed.connect(_on_open_map_menu_pressed)
	continue_button.pressed.connect(_on_continue_game_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	SystemLogger.log_info("[MainMenu] Main menu ready.")
	_update_continue_button_state()

func _apply_localized_labels() -> void:
	title_label.text = tr("MENU_GAME_TITLE")
	new_city_button.text = tr("MENU_NEW_CITY")
	continue_button.text = tr("MENU_CONTINUE_GAME")
	exit_button.text = tr("MENU_EXIT")

## Updates the Continue button state depending on whether at least one valid save slot exists
func _update_continue_button_state() -> void:
	if continue_button == null:
		return

	var has_saves: bool = not SaveManager.list_save_slots().is_empty()
	continue_button.disabled = not has_saves
	continue_button.modulate = Color.WHITE if has_saves else Color(0.5, 0.5, 0.5, 0.6)

func _on_open_map_menu_pressed() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/menus/map_menu/map_menu.tscn")
	if error != OK:
		SystemLogger.log_error("[MainMenu] Could not open map_menu.tscn: %s" % error)
		push_error("[MainMenu] Could not open map_menu.tscn: %s" % error)

func _on_continue_game_pressed() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/menus/load_game_menu/load_game_menu.tscn")
	if error != OK:
		SystemLogger.log_error("[MainMenu] Could not open load_game_menu.tscn: %s" % error)
		push_error("[MainMenu] Could not open load_game_menu.tscn: %s" % error)

func _on_exit_pressed() -> void:
	if OS.has_feature("editor"):
		SystemLogger.log_info("Returning to the Godot editor...")
	get_tree().quit()