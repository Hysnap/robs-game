# res://scenes/ui/components/stationery_renderer.gd
class_name StationeryRenderer
extends RefCounted

## Resolves a named palette from a stationery definition dictionary.
static func resolve_palette(def: Dictionary, palette_key: String = "") -> Dictionary:
	var palettes: Dictionary = def.get("palettes", {})
	var upper_key: String = palette_key.to_upper().strip_edges()
	if not upper_key.is_empty() and palettes.has(upper_key) and palettes[upper_key] is Dictionary:
		return palettes[upper_key]
	if not palettes.is_empty():
		var first_val: Variant = palettes.values()[0]
		if first_val is Dictionary:
			return first_val
	return {"bg": "#f5f5f0", "ink": "#1a1a1a"}

## Builds a StyleBoxTexture (when background_texture is configured) or StyleBoxFlat
## from a stationery definition and resolved palette.
static func build_panel_stylebox(def: Dictionary, palette: Dictionary, depth_index: int = 0) -> StyleBox:
	var tex_path: String = str(def.get("background_texture", "")).strip_edges()
	if not tex_path.is_empty():
		assert(ResourceLoader.exists(tex_path), "FATAL: [StationeryRenderer] Missing background_texture asset: %s" % tex_path)
		var tex := load(tex_path) as Texture2D
		assert(tex != null, "FATAL: [StationeryRenderer] Failed to load Texture2D at: %s" % tex_path)

		var tex_sb := StyleBoxTexture.new()
		tex_sb.texture = tex

		var tex_margins: Array = def.get("texture_margins", [])
		if tex_margins.size() == 4:
			tex_sb.texture_margin_left = float(tex_margins[0])
			tex_sb.texture_margin_top = float(tex_margins[1])
			tex_sb.texture_margin_right = float(tex_margins[2])
			tex_sb.texture_margin_bottom = float(tex_margins[3])

		_apply_content_margins(tex_sb, def)

		var tint: Color = Color(str(palette.get("bg", "#ffffff"))) if bool(def.get("tint_with_palette", false)) else Color.WHITE
		if depth_index > 0:
			tint = tint.darkened(0.05 * depth_index)
		tex_sb.modulate_color = tint
		return tex_sb

	var flat_sb := StyleBoxFlat.new()
	var bg_color := Color(str(palette.get("bg", "#f5f5f0")))
	var ink_color := Color(str(palette.get("ink", "#1a1a1a")))
	if depth_index > 0:
		bg_color = bg_color.darkened(0.05 * depth_index)
	flat_sb.bg_color = bg_color
	flat_sb.set_corner_radius_all(int(def.get("corner_radius", 2)))
	_apply_content_margins(flat_sb, def)

	if def.has("border") and def["border"] is Dictionary:
		var border_cfg: Dictionary = def["border"]
		flat_sb.set_border_width_all(int(border_cfg.get("width", 1)))
		flat_sb.border_color = Color(str(border_cfg.get("color", ink_color.to_html())))

	var shadow_cfg: Dictionary = def.get("shadow", {})
	if not shadow_cfg.is_empty():
		var shadow_offset: Array = shadow_cfg.get("offset", [2.0, 3.0])
		var shadow_alpha: float = float(shadow_cfg.get("alpha", 0.28))
		flat_sb.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha + (0.1 if depth_index == 0 else 0.0))
		flat_sb.shadow_size = int(shadow_cfg.get("size", 6))
		if shadow_offset.size() >= 2:
			flat_sb.shadow_offset = Vector2(float(shadow_offset[0]), float(shadow_offset[1]))

	return flat_sb

## Constructs a data-driven stationery card PanelContainer from a stationery definition and payload.
## Returns { "card": PanelContainer, "vbox": VBoxContainer, "ink_color": Color } so callers
## (such as DesktopSlipStack) can append interactive controls if needed.
static func build_slip_card(
	def: Dictionary,
	payload: Dictionary,
	mono_font: Font = null,
	is_interactive: bool = true,
	depth_index: int = 0
) -> Dictionary:
	var palette_key: String = str(payload.get("palette_key", ""))
	var palette: Dictionary = resolve_palette(def, palette_key)
	var ink_color := Color(str(palette.get("ink", "#1a1a1a")))

	var card := PanelContainer.new()
	var dims: Array = def.get("dimensions", [270.0, 240.0])
	var card_w: float = float(dims[0]) if dims.size() > 0 else 270.0
	var card_h: float = float(dims[1]) if dims.size() > 1 else 240.0
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.size = Vector2(card_w, card_h)
	card.pivot_offset = Vector2(card_w * 0.5, card_h * 0.5)

	if not is_interactive:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	card.add_theme_stylebox_override("panel", build_panel_stylebox(def, palette, depth_index))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	if not is_interactive:
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 1. Optional Header (can be disabled via "show_header": false for pre-printed image backgrounds)
	if bool(def.get("show_header", true)):
		var title_token: String = str(palette.get("title_token", ""))
		var title_text: String = str(TranslationServer.translate(title_token)) if not title_token.is_empty() else str(palette.get("title", ""))
		var week_val: int = int(payload.get("week", payload.get("tick", 1)))
		var hdr_tpl: String = str(def.get("header_template", "{title} // WK {week}"))
		var hdr := Label.new()
		hdr.text = hdr_tpl.replace("{title}", title_text).replace("{week}", "%02d" % week_val)
		_apply_label_style(hdr, mono_font, 9, ink_color)
		vbox.add_child(hdr)

	if bool(def.get("show_separator", true)):
		var sep := HSeparator.new()
		sep.modulate = ink_color
		sep.modulate.a = 0.25
		vbox.add_child(sep)

	# 2. Optional Centered Banner (data-driven via "banner": { "token": "UI_...", "color": "#..." })
	if def.has("banner") and def["banner"] is Dictionary:
		var banner_cfg: Dictionary = def["banner"]
		var banner_token: String = str(banner_cfg.get("token", ""))
		if not banner_token.is_empty():
			var banner_lbl := Label.new()
			banner_lbl.text = str(TranslationServer.translate(banner_token))
			banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var banner_color := Color(str(banner_cfg.get("color", ink_color.to_html())))
			_apply_label_style(banner_lbl, mono_font, 8, banner_color)
			vbox.add_child(banner_lbl)

	# 3. Optional Generic Grid Boxes Row (supports static tokens and live payload bind_field cells)
	var layout_variant: String = str(def.get("layout_variant", "")).to_upper()
	var grid_cfg: Dictionary = def.get("grid_boxes", {}) if def.get("grid_boxes") is Dictionary else {}
	var has_grid: bool = layout_variant == "GRID_BOXES" and not grid_cfg.is_empty()
	var action_bound_in_grid: bool = false

	if has_grid:
		action_bound_in_grid = _append_grid_boxes_row(vbox, grid_cfg, payload, ink_color, mono_font)

	# 4. Generic Action Sub-Header (when payload carries action_label and grid_boxes did not bind it)
	var action_label: String = str(payload.get("action_label", payload.get("verb", ""))).strip_edges()
	if not action_label.is_empty() and not action_bound_in_grid:
		var act_lbl := Label.new()
		act_lbl.text = "%s: %s" % [str(TranslationServer.translate("UI_SLIP_COL_ACTION")), action_label]
		_apply_label_style(act_lbl, mono_font, 8, ink_color.lightened(0.15))
		vbox.add_child(act_lbl)

	# 5. Body (wrapped in a ruled frame if grid_boxes.body_box is enabled)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = str(payload.get("display_text", payload.get("text", "")))
	body.fit_content = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if mono_font:
		body.add_theme_font_override("normal_font", mono_font)
	body.add_theme_font_size_override("normal_font_size", 10)
	body.add_theme_color_override("default_color", ink_color)
	if not is_interactive:
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if has_grid and bool(grid_cfg.get("body_box", false)):
		var box_color := Color(str(grid_cfg.get("border_color", ink_color.to_html())))
		var body_frame := PanelContainer.new()
		body_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var frame_sb := StyleBoxFlat.new()
		frame_sb.bg_color = Color(0, 0, 0, 0)
		frame_sb.set_border_width_all(1)
		frame_sb.border_color = box_color
		frame_sb.set_content_margin_all(4)
		body_frame.add_theme_stylebox_override("panel", frame_sb)
		if not is_interactive:
			body_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body_frame.add_child(body)
		vbox.add_child(body_frame)
	else:
		vbox.add_child(body)

	# 6. Author Footer
	var author: String = str(payload.get("author", str(TranslationServer.translate("DEFAULT_OPERATIVE_TITLE"))))
	var ftr := Label.new()
	ftr.text = "- %s" % author
	ftr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_label_style(ftr, mono_font, 9, ink_color.lightened(0.2))
	vbox.add_child(ftr)

	return {
		"card": card,
		"vbox": vbox,
		"ink_color": ink_color
	}

## Applies stationery ink colors recursively to child controls without mutating font resources.
static func apply_ink_color_recursive(node: Node, ink_color: Color) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", ink_color)
	elif node is OptionButton or node is Button:
		node.add_theme_color_override("font_color", ink_color)
		node.add_theme_color_override("font_pressed_color", ink_color)
		node.add_theme_color_override("font_hover_color", ink_color)
		node.add_theme_color_override("font_focus_color", ink_color)
		if node is OptionButton:
			var popup: PopupMenu = node.get_popup()
			if popup:
				popup.add_theme_color_override("font_color", ink_color)
				popup.add_theme_color_override("font_hover_color", ink_color)
	elif node is SpinBox:
		var line_edit: LineEdit = node.get_line_edit()
		if line_edit:
			line_edit.add_theme_color_override("font_color", ink_color)
			line_edit.add_theme_color_override("font_selected_color", ink_color)

	for child in node.get_children():
		apply_ink_color_recursive(child, ink_color)

static func _apply_content_margins(sb: StyleBox, def: Dictionary) -> void:
	var margins: Array = def.get("content_margins", [])
	if margins.size() == 4:
		sb.content_margin_left = float(margins[0])
		sb.content_margin_top = float(margins[1])
		sb.content_margin_right = float(margins[2])
		sb.content_margin_bottom = float(margins[3])
	else:
		sb.set_content_margin_all(float(def.get("padding", 8)))

static func _apply_label_style(lbl: Label, mono_font: Font, font_size: int, color: Color) -> void:
	if mono_font:
		lbl.add_theme_font_override("font", mono_font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)

## Renders a generic boxed column row. Returns true if any column bound "action_label" or "verb".
static func _append_grid_boxes_row(
	parent_vbox: VBoxContainer,
	grid_cfg: Dictionary,
	payload: Dictionary,
	default_ink: Color,
	mono_font: Font
) -> bool:
	var columns: Array = grid_cfg.get("columns", [])
	if columns.is_empty():
		return false

	var box_border_color := Color(str(grid_cfg.get("border_color", default_ink.to_html())))
	var accent_color := Color(str(grid_cfg.get("accent_color", box_border_color.to_html())))
	var bound_action: bool = false

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)

	for col in columns:
		if not (col is Dictionary):
			continue
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = float(col.get("width_ratio", 0.25))

		var cell_sb := StyleBoxFlat.new()
		cell_sb.bg_color = Color(box_border_color.r, box_border_color.g, box_border_color.b, 0.08)
		cell_sb.set_border_width_all(1)
		cell_sb.border_color = box_border_color
		cell_sb.set_content_margin_all(2)
		cell.add_theme_stylebox_override("panel", cell_sb)

		var col_token: String = str(col.get("token", ""))
		var col_fallback: String = str(col.get("fallback", ""))
		var translated: String = str(TranslationServer.translate(col_token)) if not col_token.is_empty() else ""
		var label_part: String = translated if (not translated.is_empty() and translated != col_token) else col_fallback

		var bind_field: String = str(col.get("bind_field", "")).strip_edges()
		var cell_text: String = label_part
		if not bind_field.is_empty():
			if bind_field == "action_label" or bind_field == "verb":
				bound_action = true
			var raw_val: Variant = payload.get(bind_field, "")
			if col.has("int_offset") and (raw_val is int or raw_val is float):
				raw_val = int(raw_val) + int(col["int_offset"])
			var fmt: String = str(col.get("format", ""))
			var val_str: String = (fmt % raw_val) if not fmt.is_empty() else str(raw_val)
			if val_str.strip_edges().is_empty():
				val_str = "-"
			cell_text = ("%s: %s" % [label_part, val_str]) if not label_part.is_empty() else val_str

		var lbl := Label.new()
		lbl.text = cell_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_label_style(lbl, mono_font, 8, accent_color)
		cell.add_child(lbl)
		row.add_child(cell)

	parent_vbox.add_child(row)
	return bound_action