# res://scenes/ui/shells/filofax/filofax_spread.gd
class_name FilofaxSpread
extends PanelContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const StickyOrderPadScene = preload("res://scenes/ui/shells/filofax/sticky_order_pad.tscn")

@onready var nav_slot: Control = $SpreadHBox/NavSlot
@onready var content_slot: Control = $SpreadHBox/LeftPageFrame/ContentSlot
@onready var action_slot: Control = $SpreadHBox/RightPageFrame/ActionSlot
@onready var left_page_frame: PanelContainer = $SpreadHBox/LeftPageFrame
@onready var right_page_frame: PanelContainer = $SpreadHBox/RightPageFrame

var _directive_modal: Control = null

func _ready() -> void:
	RETRO_THEME.load_all_catalog_profiles("filofax")
	RETRO_THEME.register_theme_listener(apply_visual_skin)
	apply_visual_skin()
	_setup_era_modal()

func _exit_tree() -> void:
	RETRO_THEME.unregister_theme_listener(apply_visual_skin)

func _setup_era_modal() -> void:
	if _directive_modal == null:
		_directive_modal = StickyOrderPadScene.instantiate() as Control
		_directive_modal.visible = false
		_directive_modal.z_index = 25
		add_child(_directive_modal)

## Contract method for ViewHost to retrieve whatever input composer this era uses
func get_directive_modal() -> Control:
	if _directive_modal == null:
		_setup_era_modal()
	return _directive_modal

func apply_visual_skin() -> void:
	add_theme_stylebox_override("panel", RETRO_THEME.create_cover_style())
	var page_style := RETRO_THEME.create_page_style()
	if left_page_frame:
		left_page_frame.add_theme_stylebox_override("panel", page_style)
	if right_page_frame:
		right_page_frame.add_theme_stylebox_override("panel", page_style)

func get_slot(slot_name: String) -> Control:
	match slot_name.to_upper():
		"MODAL", "COMPOSER", "DIRECTIVE_MODAL":
			return get_directive_modal()
		"NAV":
			if nav_slot != null:
				return nav_slot
			return get_node_or_null("SpreadHBox/NavSlot") as Control
		"CONTENT", "DOSSIER", "MAIN":
			if content_slot != null:
				return content_slot
			return get_node_or_null("SpreadHBox/LeftPageFrame/ContentSlot") as Control
		"ACTION", "PLANNER", "RIGHT":
			if action_slot != null:
				return action_slot
			return get_node_or_null("SpreadHBox/RightPageFrame/ActionSlot") as Control
		_:
			return get_node_or_null(slot_name) as Control