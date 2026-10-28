# res://scenes/ui/shells/apple2/apple2_crt_spread.gd
class_name Apple2CrtSpread
extends PanelContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

@onready var nav_slot: Control = $ScreenVBox/BodyHBox/NavSlot
@onready var content_slot: Control = $ScreenVBox/BodyHBox/ScreenFrameLeft/ContentSlot
@onready var action_slot: Control = $ScreenVBox/BodyHBox/ScreenFrameRight/ActionSlot
@onready var screen_frame_left: PanelContainer = $ScreenVBox/BodyHBox/ScreenFrameLeft
@onready var screen_frame_right: PanelContainer = $ScreenVBox/BodyHBox/ScreenFrameRight
@onready var status_line: Label = $ScreenVBox/StatusBar/SystemStatus

func _ready() -> void:
	# Automatically activate phosphor profile on load
	RETRO_THEME.load_all_catalog_profiles("apple2")
	RETRO_THEME.apply_profile("apple2_phosphor_green")
	RETRO_THEME.register_theme_listener(apply_visual_skin)
	apply_visual_skin()

func _exit_tree() -> void:
	RETRO_THEME.unregister_theme_listener(apply_visual_skin)

## Styles bezel and terminal window
func apply_visual_skin() -> void:
	# 1. Apple Monitor Beige Bezel Style
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color("#2D3027") # Dark militarized/office industrial olive-beige
	bezel.border_color = Color("#181A15")
	bezel.set_border_width_all(6)
	bezel.set_corner_radius_all(14)
	bezel.set_content_margin_all(8)
	add_theme_stylebox_override("panel", bezel)

	# 2. CRT Glass Inner Screens
	var crt_glass := StyleBoxFlat.new()
	crt_glass.bg_color = RETRO_THEME.color_page_bg # #0A0D08 Pure phosphor black
	crt_glass.border_color = RETRO_THEME.color_ruled_line
	crt_glass.set_border_width_all(2)
	crt_glass.set_corner_radius_all(6)
	crt_glass.set_content_margin_all(10)
	
	if screen_frame_left:
		screen_frame_left.add_theme_stylebox_override("panel", crt_glass)
	if screen_frame_right:
		screen_frame_right.add_theme_stylebox_override("panel", crt_glass)

	# 3. Status text typography
	if status_line:
		status_line.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
		status_line.add_theme_font_override("font", RETRO_THEME.get_monospace_font())

## Architectural Slot Contract (Identical to FilofaxSpread)
func get_slot(slot_name: String) -> Control:
	match slot_name.to_upper():
		"NAV": return nav_slot
		"CONTENT": return content_slot
		"ACTION": return action_slot
		_: return null