# res://scenes/ui/shell_host/shell_customizer.gd
class_name ShellCustomizer
extends PanelContainer

signal colors_updated
@export var target_shell: String = "filofax"

@onready var title_handle: Label = $VBoxContainer/Title
@onready var profile_option: OptionButton = $VBoxContainer/ProfileRow/ProfileOption
@onready var profile_name_input: LineEdit = $VBoxContainer/SaveRow/ProfileNameInput
@onready var btn_save_profile: Button = $VBoxContainer/SaveRow/BtnSaveProfile

@onready var cp_binder: ColorPickerButton = $VBoxContainer/Grid/CP_Binder
@onready var cp_trim: ColorPickerButton = $VBoxContainer/Grid/CP_Trim
@onready var cp_page: ColorPickerButton = $VBoxContainer/Grid/CP_Page
@onready var cp_line: ColorPickerButton = $VBoxContainer/Grid/CP_Line
@onready var cp_ink: ColorPickerButton = $VBoxContainer/Grid/CP_Ink
@onready var cp_accent: ColorPickerButton = $VBoxContainer/Grid/CP_Accent
@onready var cp_warn: ColorPickerButton = $VBoxContainer/Grid/CP_Warn
@onready var cp_muted: ColorPickerButton = $VBoxContainer/Grid/CP_Muted
@onready var btn_close: Button = $VBoxContainer/BottomButtons/CloseButton

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	RETRO_THEME.load_all_catalog_profiles()
	_refresh_profile_dropdown()
	_sync_pickers_from_theme()

	# Connect Title Dragging
	if title_handle:
		title_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		title_handle.gui_input.connect(_on_title_gui_input)

	if profile_option:
		profile_option.item_selected.connect(_on_profile_selected)
	if btn_save_profile:
		btn_save_profile.pressed.connect(_on_save_profile_pressed)
	if btn_close:
		btn_close.pressed.connect(func(): visible = false)

	for picker in [cp_binder, cp_trim, cp_page, cp_line, cp_ink, cp_accent, cp_warn, cp_muted]:
		if picker:
			picker.color_changed.connect(_on_picker_color_changed)

func set_target_shell(shell_id: String) -> void:
	target_shell = shell_id
	if title_handle:
		title_handle.text = "[ %s THEME CONFIGURATION ]" % target_shell.to_upper()
	_refresh_profile_dropdown()

func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			_is_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_is_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _is_dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()

func _refresh_profile_dropdown() -> void:
	if not profile_option:
		return
	profile_option.clear()
	profile_option.add_item("-- Select Theme Preset --")
	profile_option.set_item_disabled(0, true)

	# 1. Catalog profiles filtered for this shell
	var catalog_matches := RETRO_THEME.get_profiles_for_shell(target_shell)
	for prof in catalog_matches:
		var p_id: String = prof.get("id", "")
		var d_name: String = prof.get("display_name", p_id)
		profile_option.add_item("📁 " + d_name)
		profile_option.set_item_metadata(profile_option.item_count - 1, {"type": "catalog", "id": p_id})

	# 2. User-saved profiles filtered for this shell
	var user_matches := RETRO_THEME.get_user_profiles_for_shell(target_shell)
	for u_name in user_matches.keys():
		profile_option.add_item("⭐ " + u_name)
		profile_option.set_item_metadata(profile_option.item_count - 1, {"type": "user", "id": u_name})

	_select_active_in_dropdown()

func _select_active_in_dropdown() -> void:
	for i in range(profile_option.item_count):
		var meta = profile_option.get_item_metadata(i)
		if meta is Dictionary and meta.get("id") == RETRO_THEME.active_profile_id:
			profile_option.select(i)
			return

func _sync_pickers_from_theme() -> void:
	if cp_binder: cp_binder.color = RETRO_THEME.color_binder_cover
	if cp_trim:   cp_trim.color   = RETRO_THEME.color_binder_trim
	if cp_page:   cp_page.color   = RETRO_THEME.color_page_bg
	if cp_line:   cp_line.color   = RETRO_THEME.color_ruled_line
	if cp_ink:    cp_ink.color    = RETRO_THEME.color_ink_body
	if cp_accent: cp_accent.color = RETRO_THEME.color_ink_accent
	if cp_warn:   cp_warn.color   = RETRO_THEME.color_ink_warning
	if cp_muted:  cp_muted.color  = RETRO_THEME.color_ink_muted

func _on_profile_selected(index: int) -> void:
	var meta = profile_option.get_item_metadata(index)
	if not (meta is Dictionary):
		return

	var p_id: String = meta.get("id", "")
	RETRO_THEME.apply_profile(p_id)
	profile_name_input.text = p_id
	_sync_pickers_from_theme()
	colors_updated.emit()

func _on_picker_color_changed(_color: Color) -> void:
	RETRO_THEME.color_binder_cover = cp_binder.color
	RETRO_THEME.color_binder_trim  = cp_trim.color
	RETRO_THEME.color_page_bg      = cp_page.color
	RETRO_THEME.color_ruled_line   = cp_line.color
	RETRO_THEME.color_ink_body     = cp_ink.color
	RETRO_THEME.color_ink_accent   = cp_accent.color
	RETRO_THEME.color_ink_warning  = cp_warn.color
	RETRO_THEME.color_ink_muted    = cp_muted.color
	colors_updated.emit()

func _on_save_profile_pressed() -> void:
	var new_name: String = profile_name_input.text.strip_edges()
	if new_name.is_empty():
		new_name = "My %s Custom Scheme" % target_shell.capitalize()
	RETRO_THEME.save_user_profile(new_name, target_shell)
	_refresh_profile_dropdown()
	colors_updated.emit()