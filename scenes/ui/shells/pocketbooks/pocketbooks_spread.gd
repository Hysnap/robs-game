# res://scenes/ui/shells/pocketbooks/pocketbooks_spread.gd
class_name PocketbooksSpread
extends PanelContainer

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const StickyOrderPadScene = preload("res://scenes/ui/components/sticky_order_pad.tscn")

# Vintage cloth-bound pocketbook cover palette (Oxblood, Forest, Navy, Manilla Tan, Slate, Ochre)
const BOOK_SPINE_PALETTE: Array[Color] = [
	Color(0.46, 0.14, 0.14, 1.0),
	Color(0.15, 0.34, 0.22, 1.0),
	Color(0.14, 0.22, 0.38, 1.0),
	Color(0.68, 0.55, 0.34, 1.0),
	Color(0.26, 0.28, 0.34, 1.0),
	Color(0.56, 0.36, 0.14, 1.0)
]

const BOOK_STAGGER_LEFT: Array[int] = [0, 8, 3, 10, 2, 6]
const BOOK_STAGGER_RIGHT: Array[int] = [8, 0, 6, 0, 9, 3]

@onready var book_stack_frame: PanelContainer = $DeskMargin/DeskHBox/BookStackFrame
@onready var nav_slot: Control = $DeskMargin/DeskHBox/BookStackFrame/NavSlot
@onready var left_page_frame: PanelContainer = $DeskMargin/DeskHBox/NotebookSpread/LeftPageFrame
@onready var content_slot: Control = $DeskMargin/DeskHBox/NotebookSpread/LeftPageFrame/ContentSlot
@onready var center_seam: PanelContainer = $DeskMargin/DeskHBox/NotebookSpread/CenterFoldSeam
@onready var right_page_frame: PanelContainer = $DeskMargin/DeskHBox/NotebookSpread/RightPageFrame
@onready var action_slot: Control = $DeskMargin/DeskHBox/NotebookSpread/RightPageFrame/ActionSlot

var _directive_modal: Control = null
var _active_book_id: String = "diary"

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
	var page_style: StyleBoxFlat = RETRO_THEME.create_page_style()

	# Warm oak/manilla desk work surface on which the open pocketbook and book stack rest
	var desk_sb := StyleBoxFlat.new()
	desk_sb.bg_color = Color(0.55, 0.41, 0.27, 1.0)
	desk_sb.border_color = Color(0.34, 0.24, 0.14, 1.0)
	desk_sb.set_border_width_all(3)
	desk_sb.set_corner_radius_all(4)
	desk_sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	desk_sb.shadow_size = 6
	add_theme_stylebox_override("panel", desk_sb)

	if left_page_frame:
		var left_sb := page_style.duplicate() as StyleBoxFlat
		left_sb.border_color = cover_style.bg_color
		left_sb.border_width_left = 6
		left_sb.border_width_top = 4
		left_sb.border_width_bottom = 4
		left_sb.border_width_right = 1
		left_sb.shadow_color = Color(0.15, 0.10, 0.05, 0.40)
		left_sb.shadow_size = 5
		left_sb.shadow_offset = Vector2(2, 3)
		left_page_frame.add_theme_stylebox_override("panel", left_sb)

	if right_page_frame:
		var right_sb := page_style.duplicate() as StyleBoxFlat
		right_sb.border_color = cover_style.bg_color
		right_sb.border_width_right = 6
		right_sb.border_width_top = 4
		right_sb.border_width_bottom = 4
		right_sb.border_width_left = 1
		right_sb.shadow_color = Color(0.15, 0.10, 0.05, 0.40)
		right_sb.shadow_size = 5
		right_sb.shadow_offset = Vector2(3, 3)
		right_page_frame.add_theme_stylebox_override("panel", right_sb)

	# Transparent desk surface under the pile of separate pocketbooks (no digital frame box)
	if book_stack_frame:
		var tray_sb := StyleBoxFlat.new()
		tray_sb.bg_color = Color(0.49, 0.36, 0.23, 0.55)
		tray_sb.border_color = Color(0.38, 0.27, 0.16, 0.65)
		tray_sb.set_border_width_all(1)
		tray_sb.set_corner_radius_all(4)
		tray_sb.set_content_margin_all(6)
		book_stack_frame.add_theme_stylebox_override("panel", tray_sb)

	# Stitched pocketbook spine gutter derived from active page style
	if center_seam:
		var seam_sb := page_style.duplicate() as StyleBoxFlat
		seam_sb.bg_color = cover_style.bg_color.darkened(0.15)
		seam_sb.set_border_width_all(0)
		seam_sb.set_content_margin_all(0)
		center_seam.add_theme_stylebox_override("panel", seam_sb)

	_style_nav_as_book_pile()

## Transforms mounted GenNavBar buttons into a staggered physical pile of separate cloth-bound pocketbooks
func _style_nav_as_book_pile() -> void:
	var target_nav: Control = nav_slot if nav_slot != null else get_node_or_null("DeskMargin/DeskHBox/BookStackFrame/NavSlot") as Control
	if target_nav == null or target_nav.get_child_count() == 0:
		return

	var nav_root: Node = target_nav.get_child(0)
	var tabs_box: VBoxContainer = nav_root.get_node_or_null("macro_tabs") as VBoxContainer
	if tabs_box == null and nav_root is VBoxContainer:
		tabs_box = nav_root as VBoxContainer
	if tabs_box == null:
		return

	tabs_box.add_theme_constant_override("separation", 8)

	var book_idx: int = 0
	for child in tabs_box.get_children():
		if not (child is Control):
			continue
		var ctrl := child as Control
		var btn: Button = ctrl as Button
		if btn == null:
			for sub in ctrl.get_children():
				if sub is Button:
					btn = sub as Button
					break
		if btn == null:
			continue

		var book_key: String = ctrl.name.to_lower()
		var base_col: Color = BOOK_SPINE_PALETTE[book_idx % BOOK_SPINE_PALETTE.size()]
		var is_selected: bool = (book_key == _active_book_id)

		var left_pad: int = BOOK_STAGGER_LEFT[book_idx % BOOK_STAGGER_LEFT.size()]
		var right_pad: int = BOOK_STAGGER_RIGHT[book_idx % BOOK_STAGGER_RIGHT.size()]
		if is_selected:
			left_pad += 8
			right_pad = maxi(0, right_pad - 6)

		btn.custom_minimum_size = Vector2(118.0, 42.0)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		var normal_sb := _create_pocketbook_cover_stylebox(base_col, is_selected, false)
		var hover_sb := _create_pocketbook_cover_stylebox(base_col.lightened(0.10), is_selected, true)
		var pressed_sb := _create_pocketbook_cover_stylebox(base_col.darkened(0.08), true, true)

		btn.add_theme_stylebox_override("normal", normal_sb)
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.add_theme_stylebox_override("pressed", pressed_sb)
		btn.add_theme_stylebox_override("focus", hover_sb)

		var foil_ink := Color(0.97, 0.93, 0.80, 1.0) if base_col.get_luminance() < 0.42 else Color(0.16, 0.12, 0.08, 1.0)
		btn.add_theme_color_override("font_color", foil_ink)
		btn.add_theme_color_override("font_hover_color", foil_ink.lightened(0.08))
		btn.add_theme_color_override("font_pressed_color", foil_ink)

		# Apply staggered book-pile offsets via container margins if wrapped, or stylebox margins
		normal_sb.content_margin_left = float(14 + left_pad)
		normal_sb.content_margin_right = float(10 + right_pad)
		hover_sb.content_margin_left = float(18 + left_pad)
		hover_sb.content_margin_right = float(6 + right_pad)
		pressed_sb.content_margin_left = float(20 + left_pad)
		pressed_sb.content_margin_right = float(4 + right_pad)

		if not btn.has_meta("_pb_book_hooked"):
			btn.set_meta("_pb_book_hooked", true)
			var captured_key := book_key
			btn.pressed.connect(func():
				_active_book_id = captured_key
				_style_nav_as_book_pile()
			)

		book_idx += 1

func _create_pocketbook_cover_stylebox(cover_color: Color, is_active: bool, is_hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cover_color.lightened(0.08) if is_active else cover_color
	# Thick dark cloth spine on the left, cream paper block edge on top/right/bottom
	sb.border_color = cover_color.darkened(0.45)
	sb.border_width_left = 10
	sb.border_width_top = 2
	sb.border_width_bottom = 3
	sb.border_width_right = 3
	sb.corner_radius_top_left = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = Color(0.12, 0.08, 0.04, 0.55 if (is_active or is_hovered) else 0.38)
	sb.shadow_size = 5 if (is_active or is_hovered) else 3
	sb.shadow_offset = Vector2(3, 3)
	return sb

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