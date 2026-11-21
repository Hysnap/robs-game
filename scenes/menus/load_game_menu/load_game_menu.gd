# res://scenes/menus/load_game_menu/load_game_menu.gd
extends Control

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const SHELL_REGISTRY = preload("res://scenes/ui/shell_host/shell_registry.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

@onready var lbl_title: Label = $Backdrop/CenterMargin/CardPanel/CardVBox/LblTitle
@onready var lbl_nominated_hdr: Label = $Backdrop/CenterMargin/CardPanel/CardVBox/NominatedBox/LblNominatedHdr
@onready var lbl_nominated_summary: Label = $Backdrop/CenterMargin/CardPanel/CardVBox/NominatedBox/LblNominatedSummary
@onready var btn_resume_nominated: Button = $Backdrop/CenterMargin/CardPanel/CardVBox/NominatedBox/BtnResumeNominated
@onready var lbl_all_saves_hdr: Label = $Backdrop/CenterMargin/CardPanel/CardVBox/LblAllSavesHdr
@onready var save_list: ItemList = $Backdrop/CenterMargin/CardPanel/CardVBox/SaveList
@onready var btn_load_selected: Button = $Backdrop/CenterMargin/CardPanel/CardVBox/ActionRow/BtnLoadSelected
@onready var btn_delete_save: Button = $Backdrop/CenterMargin/CardPanel/CardVBox/ActionRow/BtnDeleteSave
@onready var btn_back: Button = $Backdrop/CenterMargin/CardPanel/CardVBox/ActionRow/BtnBack

var _slots: Array[Dictionary] = []
var _nominated_slot_id: String = ""

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
	btn_resume_nominated.pressed.connect(_on_resume_nominated_pressed)
	btn_load_selected.pressed.connect(_on_load_selected_pressed)
	btn_delete_save.pressed.connect(_on_delete_save_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	save_list.item_selected.connect(_on_save_item_selected)
	save_list.item_activated.connect(_on_save_item_activated)
	_refresh_slots()

func _apply_localized_labels() -> void:
	lbl_title.text = tr("UI_HDR_LOAD_CAMPAIGN")
	lbl_nominated_hdr.text = tr("UI_HDR_NOMINATED_SAVE")
	btn_resume_nominated.text = tr("UI_BTN_RESUME_NOMINATED")
	lbl_all_saves_hdr.text = tr("UI_HDR_ALL_SAVES")
	btn_load_selected.text = tr("UI_BTN_LOAD_SELECTED")
	btn_delete_save.text = tr("UI_BTN_DELETE_SAVE")
	btn_back.text = tr("MENU_BACK")

func _refresh_slots() -> void:
	_slots = SaveManager.list_save_slots()
	save_list.clear()
	_nominated_slot_id = ""

	if _slots.is_empty():
		lbl_nominated_summary.text = tr("UI_LBL_NO_SAVES_FOUND")
		btn_resume_nominated.disabled = true
		btn_load_selected.disabled = true
		btn_delete_save.disabled = true
		return

	var nominated: Dictionary = _slots[0]
	_nominated_slot_id = str(nominated.get("slot_id", ""))
	lbl_nominated_summary.text = _format_summary(nominated)
	btn_resume_nominated.disabled = _nominated_slot_id.is_empty()

	for i in range(_slots.size()):
		var entry: Dictionary = _slots[i]
		save_list.add_item(_format_row(entry))
		save_list.set_item_metadata(i, str(entry.get("slot_id", "")))

	save_list.select(0)
	_update_selection_buttons()

static func _resolve_entry_sim_day(entry: Dictionary) -> int:
	if entry.has("current_sim_day") and entry["current_sim_day"] != null:
		return CALENDAR_HELPER.get_current_sim_day({"metadata": {"current_sim_day": entry["current_sim_day"]}})
	return CALENDAR_HELPER.get_current_sim_day()

func _format_summary(entry: Dictionary) -> String:
	return tr("FMT_SAVE_SUMMARY") \
		.replace("{city}", str(entry.get("city_name", entry.get("slot_id", "")))) \
		.replace("{seed}", str(entry.get("seed_id", ""))) \
		.replace("{pop}", str(int(entry.get("population", 0)))) \
		.replace("{day}", str(_resolve_entry_sim_day(entry))) \
		.replace("{date}", str(entry.get("timestamp", "")))

func _format_row(entry: Dictionary) -> String:
	return tr("FMT_SAVE_ROW") \
		.replace("{slot}", str(entry.get("slot_id", ""))) \
		.replace("{city}", str(entry.get("city_name", entry.get("slot_id", "")))) \
		.replace("{seed}", str(entry.get("seed_id", ""))) \
		.replace("{pop}", str(int(entry.get("population", 0)))) \
		.replace("{day}", str(_resolve_entry_sim_day(entry))) \
		.replace("{date}", str(entry.get("timestamp", "")))

func _get_selected_slot_id() -> String:
	var selected := save_list.get_selected_items()
	if selected.is_empty():
		return ""
	var meta = save_list.get_item_metadata(selected[0])
	return str(meta) if meta != null else ""

func _update_selection_buttons() -> void:
	var has_sel := not _get_selected_slot_id().is_empty()
	btn_load_selected.disabled = not has_sel
	btn_delete_save.disabled = not has_sel

func _on_save_item_selected(_index: int) -> void:
	_update_selection_buttons()

func _on_save_item_activated(index: int) -> void:
	var meta = save_list.get_item_metadata(index)
	if meta != null and not str(meta).is_empty():
		_load_slot_and_launch(str(meta))

func _on_resume_nominated_pressed() -> void:
	if not _nominated_slot_id.is_empty():
		_load_slot_and_launch(_nominated_slot_id)

func _on_load_selected_pressed() -> void:
	var slot_id := _get_selected_slot_id()
	if not slot_id.is_empty():
		_load_slot_and_launch(slot_id)

func _on_delete_save_pressed() -> void:
	var slot_id := _get_selected_slot_id()
	if slot_id.is_empty():
		return
	if SaveManager.delete_save_slot(slot_id):
		_refresh_slots()

func _load_slot_and_launch(slot_id: String) -> void:
	if get_tree().has_meta("pending_city_settings"):
		get_tree().remove_meta("pending_city_settings")

	if not SaveManager.load_game(slot_id):
		SystemLogger.log_error("[LoadGameMenu] Failed to load save slot: %s" % slot_id)
		push_error("[LoadGameMenu] Failed to load save slot: %s" % slot_id)
		return

	var err := get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")
	if err != OK:
		SystemLogger.log_error("[LoadGameMenu] Could not open 3d cityview. Error Code: %s" % err)
		push_error("[LoadGameMenu] Could not open 3d cityview. Error Code: %s" % err)

func _on_back_pressed() -> void:
	var main_scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert(not main_scene_path.is_empty(), "FATAL: [LoadGameMenu] 'application/run/main_scene' is not configured in ProjectSettings.")
	var err := get_tree().change_scene_to_file(main_scene_path)
	if err != OK:
		SystemLogger.log_error("[LoadGameMenu] Could not open main scene '%s': %s" % [main_scene_path, err])
		push_error("[LoadGameMenu] Could not open main scene '%s': %s" % [main_scene_path, err])