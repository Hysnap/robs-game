# res://scenes/ui/shells/pocketbooks/pocketbooks_spread.gd
# res://scenes/ui/shells/pocketbooks/pocketbooks_spread.gd
class_name PocketbooksSpread
extends PanelContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const StickyOrderPadScene = preload("res://scenes/ui/components/sticky_order_pad.tscn")

@onready var book_stack_frame: PanelContainer = $DeskMargin/DeskHBox/BookStackFrame
@onready var nav_slot: Control = $DeskMargin/DeskHBox/BookStackFrame/NavSlot
@onready var left_page_frame: PanelContainer = $DeskMargin/DeskHBox/NotebookSpread/LeftPageFrame
@onready var content_slot: Control = $DeskMargin/DeskHBox/NotebookSpread/LeftPageFrame/ContentSlot
@onready var center_seam: PanelContainer = $DeskMargin/DeskHBox/NotebookSpread/CenterFoldSeam
@onready var right_page_frame: PanelContainer = $DeskMargin/DeskHBox/NotebookSpread/RightPageFrame
@onready var action_slot: Control = $DeskMargin/DeskHBox/NotebookSpread/RightPageFrame/ActionSlot

var _directive_modal: Control = null

func _ready() -> void:
	RETRO_THEME.load_all_catalog_profiles("pocketbooks")
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

## Contract method for ViewHost to retrieve the active era input composer (Spiral-Bound Order Pad)
func get_directive_modal() -> Control:
	if _directive_modal == null:
		_setup_era_modal()
	return _directive_modal

func apply_visual_skin() -> void:
	var cover_style: StyleBoxFlat = RETRO_THEME.create_cover_style()
	add_theme_stylebox_override("panel", cover_style)

	var page_style: StyleBoxFlat = RETRO_THEME.create_page_style()
	if left_page_frame:
		left_page_frame.add_theme_stylebox_override("panel", page_style)
	if right_page_frame:
		right_page_frame.add_theme_stylebox_override("panel", page_style)

	# Staggered PocketBooks spine stack frame derived from active cover style
	if book_stack_frame:
		var stack_sb := cover_style.duplicate() as StyleBoxFlat
		stack_sb.bg_color = cover_style.bg_color.darkened(0.18)
		stack_sb.border_width_right = 3
		stack_sb.set_corner_radius_all(3)
		stack_sb.set_content_margin_all(6)
		book_stack_frame.add_theme_stylebox_override("panel", stack_sb)

	# Stitched pocketbook spine gutter derived from active page style
	if center_seam:
		var seam_sb := page_style.duplicate() as StyleBoxFlat
		seam_sb.bg_color = page_style.bg_color.darkened(0.22)
		seam_sb.set_border_width_all(0)
		seam_sb.set_content_margin_all(0)
		center_seam.add_theme_stylebox_override("panel", seam_sb)

func get_slot(slot_name: String) -> Control:
	match slot_name.to_upper():
		"MODAL", "COMPOSER", "DIRECTIVE_MODAL":
			return get_directive_modal()
		"NAV":
			if nav_slot != null:
				return nav_slot
			return get_node_or_null("DeskMargin/DeskHBox/BookStackFrame/NavSlot") as Control
		"CONTENT", "DOSSIER", "MAIN":
			if content_slot != null:
				return content_slot
			return get_node_or_null("DeskMargin/DeskHBox/NotebookSpread/LeftPageFrame/ContentSlot") as Control
		"ACTION", "PLANNER", "RIGHT":
			if action_slot != null:
				return action_slot
			return get_node_or_null("DeskMargin/DeskHBox/NotebookSpread/RightPageFrame/ActionSlot") as Control
		_:
			return get_node_or_null(slot_name) as Control