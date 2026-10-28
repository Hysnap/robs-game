# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/action_planner.json
class_name GenActionPlanner
extends VBoxContainer

signal order_pad_requested
signal turn_commit_requested

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

var _value_labels: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_ui()

func build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_value_labels.clear()
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	# --- Section: planner_body ---
	var sec_planner_body := VBoxContainer.new()
	sec_planner_body.add_theme_constant_override("separation", 4)
	var hdr_planner_body := Label.new()
	hdr_planner_body.text = "[ " + tr("UI_SEC_DIRECTIVES").to_upper() + " ]"
	hdr_planner_body.add_theme_font_override("font", mono_font)
	hdr_planner_body.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	sec_planner_body.add_child(hdr_planner_body)
	var sep_planner_body := HSeparator.new()
	sec_planner_body.add_child(sep_planner_body)
	add_child(sec_planner_body)

	var list_queue_list := ItemList.new()
	list_queue_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_queue_list.select_mode = ItemList.SELECT_SINGLE
	sec_planner_body.add_child(list_queue_list)
	_value_labels["queue_list"] = list_queue_list

	var btn_btn_add := Button.new()
	btn_btn_add.text = tr("UI_BTN_NEW_ORDER")
	btn_btn_add.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_add.custom_minimum_size = Vector2(0, 36)
	btn_btn_add.focus_mode = Control.FOCUS_NONE
	btn_btn_add.add_theme_font_override("font", mono_font)
	btn_btn_add.add_theme_font_size_override("font_size", 11)
	btn_btn_add.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	btn_btn_add.pressed.connect(func(): order_pad_requested.emit())
	sec_planner_body.add_child(btn_btn_add)
	_value_labels["btn_add"] = btn_btn_add

	var btn_btn_commit := Button.new()
	btn_btn_commit.text = tr("UI_BTN_EXECUTE_TURN")
	btn_btn_commit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_commit.custom_minimum_size = Vector2(0, 36)
	btn_btn_commit.focus_mode = Control.FOCUS_NONE
	btn_btn_commit.add_theme_font_override("font", mono_font)
	btn_btn_commit.add_theme_font_size_override("font_size", 11)
	btn_btn_commit.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	btn_btn_commit.pressed.connect(func(): turn_commit_requested.emit())
	sec_planner_body.add_child(btn_btn_commit)
	_value_labels["btn_commit"] = btn_btn_commit

func bind_data(data: Dictionary) -> void:
	pass

