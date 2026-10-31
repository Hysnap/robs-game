# res://scenes/ui/hud/game_hud.gd
class_name GameHUD
extends CanvasLayer

signal toggle_filofax_requested
signal toggle_messages_inbox_requested

@onready var btn_main_menu: Button = $MarginContainer/TopBar/HBoxLeft/BtnMainMenu
@onready var btn_toggle_filofax: Button = $MarginContainer/TopBar/HBoxLeft/BtnFilofax
@onready var lbl_date_tick: Label = $MarginContainer/TopBar/HBoxRight/LblDateTick
@onready var lbl_ticker_status: Label = $MarginContainer/BottomBar/LblTickerStatus
@onready var btn_messages_alert: Button = $MarginContainer/TopBar/HBoxLeft/BtnMessagesAlert

func _ready() -> void:
	layer = 10
	
	if btn_main_menu:
		btn_main_menu.text = tr("CITY_VIEW_BTN_MAIN_MENU")
		btn_main_menu.pressed.connect(_on_return_to_main_menu_pressed)
		
	if btn_toggle_filofax:
		btn_toggle_filofax.pressed.connect(func(): toggle_filofax_requested.emit())

	if btn_messages_alert:
		btn_messages_alert.pressed.connect(func(): toggle_messages_inbox_requested.emit())

	# Bind reactive timeline updates from GameState safely
	var gs = ScenarioManifestManager.get_game_state()
	if gs != null and gs.has_signal("turn_advanced"):
		gs.turn_advanced.connect(_on_turn_advanced)
		
	_refresh_timeline_display()

func _on_return_to_main_menu_pressed() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/menus/main_menu/main.tscn")
	if error != OK:
		push_error("[GameHUD] Failed returning to main menu. Error: %s" % error)

func _on_turn_advanced(_current_tick: int) -> void:
	_refresh_timeline_display()

func _refresh_timeline_display() -> void:
	if lbl_date_tick == null:
		return

	var gs = ScenarioManifestManager.get_game_state()
	var meta: Dictionary = gs.world_state.get("metadata", {}) if (gs != null and "world_state" in gs) else {}
	var year_val: int = int(meta.get("calendar_year", 1984))
	var week_val: int = int(meta.get("current_week_tick", 1))
	var day_val: int = int(meta.get("current_day_tick", 1))
	
	# Format week as zero-padded 2 digits
	var wk_str: String = "%02d" % week_val

	# Resolve localized timeline pattern template via TranslationServer
	var pattern: String = TranslationServer.translate("UI_HUD_TIMELINE_TICK")
	if pattern == "UI_HUD_TIMELINE_TICK" or pattern.is_empty():
		pattern = "YR {year} | WK {week} | DAY {day}"

	lbl_date_tick.text = pattern.replace("{year}", str(year_val)).replace("{week}", wk_str).replace("{day}", str(day_val))

## Updates the bottom dispatch and interdiction ticker
func set_status_message(message: String) -> void:
	if lbl_ticker_status:
		lbl_ticker_status.text = message

func update_unread_message_count(count: int) -> void:
	if btn_messages_alert:
		btn_messages_alert.visible = (count > 0)
		btn_messages_alert.text = "📝 INBOX (%d)" % count
		# Visual alert tone
		if count > 0:
			btn_messages_alert.add_theme_color_override("font_color", Color("#fff9a6")) # Canary note yellow