# res://scenes/ui/shells/filofax_spread.gd
class_name FilofaxSpread
extends PanelContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

@onready var nav_slot: Control = $SpreadHBox/NavSlot
@onready var content_slot: Control = $SpreadHBox/LeftPageFrame/ContentSlot
@onready var action_slot: Control = $SpreadHBox/RightPageFrame/ActionSlot
@onready var left_page_frame: PanelContainer = $SpreadHBox/LeftPageFrame
@onready var right_page_frame: PanelContainer = $SpreadHBox/RightPageFrame

func _ready() -> void:
	RETRO_THEME.load_all_catalog_profiles("filofax")
	RETRO_THEME.register_theme_listener(apply_visual_skin)
	apply_visual_skin()

func _exit_tree() -> void:
	RETRO_THEME.unregister_theme_listener(apply_visual_skin)

func apply_visual_skin() -> void:
	add_theme_stylebox_override("panel", RETRO_THEME.create_cover_style())
	var page_style := RETRO_THEME.create_page_style()
	if left_page_frame:
		left_page_frame.add_theme_stylebox_override("panel", page_style)
	if right_page_frame:
		right_page_frame.add_theme_stylebox_override("panel", page_style)

func get_slot(slot_name: String) -> Control:
	match slot_name.to_upper():
		"NAV": return nav_slot
		"CONTENT": return content_slot
		"ACTION": return action_slot
		_: return null