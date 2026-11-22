# res://scenes/ui/hud/game_hud.gd
class_name GameHUD
extends CanvasLayer

signal toggle_filofax_requested
signal toggle_messages_inbox_requested
signal map_overlay_selected(overlay_id: String)

const MapOverlayHudBarScript = preload("res://scenes/ui/hud/map_overlay_hud_bar.gd")

@onready var top_bar: HBoxContainer = $MarginContainer/TopBar
@onready var btn_main_menu: Button = $MarginContainer/TopBar/HBoxLeft/BtnMainMenu
@onready var btn_toggle_filofax: Button = $MarginContainer/TopBar/HBoxLeft/BtnFilofax
@onready var btn_messages_alert: Button = $MarginContainer/TopBar/HBoxLeft/BtnMessagesAlert
@onready var lbl_date_tick: Label = $MarginContainer/TopBar/HBoxRight/LblDateTick
@onready var lbl_ticker_status: Label = $MarginContainer/BottomBar/LblTickerStatus

var _map_overlay_bar: HBoxContainer = null

func _ready() -> void:
	layer = 10
	
	if btn_main_menu:
		btn_main_menu.text = tr("CITY_VIEW_BTN_MAIN_MENU")
		btn_main_menu.pressed.connect(_on_return_to_main_menu_pressed)
		
	if btn_toggle_filofax:
		btn_toggle_filofax.text = tr("UI_HUD_BTN_FILOFAX")
		btn_toggle_filofax.pressed.connect(func(): toggle_filofax_requested.emit())

	if btn_messages_alert:
		btn_messages_alert.pressed.connect(func(): toggle_messages_inbox_requested.emit())

	if lbl_ticker_status:
		lbl_ticker_status.text = tr("UI_HUD_TICKER_STATUS_DEFAULT")

	_mount_map_overlay_bar()

	# Bind reactive timeline updates from GameState safely
	var gs = ScenarioManifestManager.get_game_state()
	if gs != null and gs.has_signal("turn_advanced"):
		gs.turn_advanced.connect(_on_turn_advanced)
		
	_refresh_timeline_display()

func _mount_map_overlay_bar() -> void:
	if top_bar == null or _map_overlay_bar != null:
		return
	_map_overlay_bar = MapOverlayHudBarScript.new()
	_map_overlay_bar.name = "MapOverlayHudBar"
	top_bar.add_child(_map_overlay_bar)
	# Place right after HBoxLeft (index 1), before HBoxRight
	if top_bar.get_child_count() > 2:
		top_bar.move_child(_map_overlay_bar, 1)
	_map_overlay_bar.overlay_selected.connect(func(overlay_id: String) -> void:
		map_overlay_selected.emit(overlay_id)
	)

func set_overlay_legend(legend_entries: Array) -> void:
	if _map_overlay_bar != null:
		_map_overlay_bar.update_legend(legend_entries)

func set_selected_map_overlay(overlay_id: String) -> void:
	if _map_overlay_bar != null:
		_map_overlay_bar.set_selected_overlay(overlay_id)

func _on_return_to_main_menu_pressed() -> void:
	var main_scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert(not main_scene_path.is_empty(), "FATAL: [GameHUD] 'application/run/main_scene' is not configured in ProjectSettings.")
	var error := get_tree().change_scene_to_file(main_scene_path)
	if error != OK:
		push_error("[GameHUD] Failed returning to main menu '%s'. Error: %s" % [main_scene_path, error])

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
		var tpl: String = tr("UI_HUD_BTN_INBOX")
		if tpl == "UI_HUD_BTN_INBOX" or tpl.is_empty():
			tpl = "📝 INBOX ({count})"
		btn_messages_alert.text = tpl.replace("{count}", str(count))
		# Visual alert tone
		if count > 0:
			btn_messages_alert.add_theme_color_override("font_color", Color("#fff9a6")) # Canary note yellow