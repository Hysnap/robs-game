# res://scenes/ui/shell_host/retro_theme.gd
class_name RetroTheme
extends RefCounted

const THEMES_DIR := "res://data_modules/core/theme_profiles/"
const USER_PROFILES_PATH := "user://shell_profiles.cfg"

# Active In-Memory Palette
static var color_binder_cover: Color = Color("#2B1D14")
static var color_binder_trim: Color = Color("#422B1F")
static var color_page_bg: Color = Color("#F4EEDB")
static var color_ruled_line: Color = Color("#DCD3BC")
static var color_ink_body: Color = Color("#1C1C1C")
static var color_ink_accent: Color = Color("#1B325F")
static var color_ink_warning: Color = Color("#8A1C14")
static var color_ink_muted: Color = Color("#5A5751")

static var catalog_profiles: Dictionary = {}
static var user_profiles: Dictionary = {}
static var active_profile_id: String = ""
static var active_shell_type: String = "filofax"

static var _listeners: Array[Callable] = []

static func register_theme_listener(listener: Callable) -> void:
	if not _listeners.has(listener):
		_listeners.append(listener)

static func unregister_theme_listener(listener: Callable) -> void:
	_listeners.erase(listener)

static func notify_theme_changed() -> void:
	for listener in _listeners:
		if listener.is_valid():
			listener.call()

static func get_monospace_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Courier New", "Consolas", "Liberation Mono", "DejaVu Sans Mono", "Courier"
	])
	return font

## Scans res://data_modules/core/theme_profiles/*.json on startup
static func load_all_catalog_profiles(target_shell: String = "filofax") -> void:
	active_shell_type = target_shell
	catalog_profiles.clear()

	var dir := DirAccess.open(THEMES_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var path := THEMES_DIR.path_join(file_name)
				var file := FileAccess.open(path, FileAccess.READ)
				if file:
					var data = JSON.parse_string(file.get_as_text())
					if data is Dictionary and data.has("id"):
						var profile_shell: String = str(data.get("shell", "filofax")).to_lower()
						data["shell"] = profile_shell
						catalog_profiles[data["id"]] = data
			file_name = dir.get_next()
		dir.list_dir_end()

	load_user_profiles_from_disk()

	# Apply initial default relevant to the targeted shell
	var relevant_defaults := get_profiles_for_shell(target_shell)
	if not relevant_defaults.is_empty():
		apply_profile(relevant_defaults[0].get("id", ""))
	elif not catalog_profiles.is_empty():
		apply_profile(catalog_profiles.keys()[0])

## Returns only catalog presets configured for a specific shell archetype ("filofax", "pocketbooks", "apple2")
static func get_profiles_for_shell(shell_type: String) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for p_id in catalog_profiles.keys():
		var prof: Dictionary = catalog_profiles[p_id]
		var target: String = str(prof.get("shell", "")).to_lower()
		if target.is_empty() or target == shell_type.to_lower():
			matching.append(prof)
	return matching

## Returns only user-saved presets matching a specific shell archetype
static func get_user_profiles_for_shell(shell_type: String) -> Dictionary:
	var matching: Dictionary = {}
	for u_name in user_profiles.keys():
		var u_data: Dictionary = user_profiles[u_name]
		var target: String = str(u_data.get("shell", "filofax")).to_lower()
		if target == shell_type.to_lower():
			matching[u_name] = u_data
	return matching

## Applies a profile by ID from catalog or user saves
static func apply_profile(profile_id: String) -> void:
	var data: Dictionary = {}
	if catalog_profiles.has(profile_id):
		data = catalog_profiles[profile_id].get("colors", {})
	elif user_profiles.has(profile_id):
		data = user_profiles[profile_id]

	if not data.is_empty():
		color_binder_cover = Color.from_string(data.get("binder_cover", color_binder_cover.to_html()), color_binder_cover)
		color_binder_trim = Color.from_string(data.get("binder_trim", color_binder_trim.to_html()), color_binder_trim)
		color_page_bg = Color.from_string(data.get("page_bg", color_page_bg.to_html()), color_page_bg)
		color_ruled_line = Color.from_string(data.get("ruled_line", color_ruled_line.to_html()), color_ruled_line)
		color_ink_body = Color.from_string(data.get("ink_body", color_ink_body.to_html()), color_ink_body)
		color_ink_accent = Color.from_string(data.get("ink_accent", color_ink_accent.to_html()), color_ink_accent)
		color_ink_warning = Color.from_string(data.get("ink_warning", color_ink_warning.to_html()), color_ink_warning)
		color_ink_muted = Color.from_string(data.get("ink_muted", color_ink_muted.to_html()), color_ink_muted)
		active_profile_id = profile_id
		notify_theme_changed()

## Loads custom user-saved profiles from user://
static func load_user_profiles_from_disk() -> void:
	user_profiles.clear()
	var cfg := ConfigFile.new()
	if cfg.load(USER_PROFILES_PATH) != OK:
		return
	for section in cfg.get_sections():
		if section == "_meta":
			continue
		user_profiles[section] = {
			"shell": cfg.get_value(section, "shell", "filofax"),
			"binder_cover": cfg.get_value(section, "binder_cover", color_binder_cover.to_html()),
			"binder_trim": cfg.get_value(section, "binder_trim", color_binder_trim.to_html()),
			"page_bg": cfg.get_value(section, "page_bg", color_page_bg.to_html()),
			"ruled_line": cfg.get_value(section, "ruled_line", color_ruled_line.to_html()),
			"ink_body": cfg.get_value(section, "ink_body", color_ink_body.to_html()),
			"ink_accent": cfg.get_value(section, "ink_accent", color_ink_accent.to_html()),
			"ink_warning": cfg.get_value(section, "ink_warning", color_ink_warning.to_html()),
			"ink_muted": cfg.get_value(section, "ink_muted", color_ink_muted.to_html())
		}

## Saves a custom user-defined preset tagged by shell archetype
static func save_user_profile(profile_name: String, target_shell: String = "filofax") -> void:
	if profile_name.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(USER_PROFILES_PATH)
	cfg.set_value(profile_name, "shell", target_shell)
	cfg.set_value(profile_name, "binder_cover", color_binder_cover.to_html())
	cfg.set_value(profile_name, "binder_trim", color_binder_trim.to_html())
	cfg.set_value(profile_name, "page_bg", color_page_bg.to_html())
	cfg.set_value(profile_name, "ruled_line", color_ruled_line.to_html())
	cfg.set_value(profile_name, "ink_body", color_ink_body.to_html())
	cfg.set_value(profile_name, "ink_accent", color_ink_accent.to_html())
	cfg.set_value(profile_name, "ink_warning", color_ink_warning.to_html())
	cfg.set_value(profile_name, "ink_muted", color_ink_muted.to_html())
	cfg.save(USER_PROFILES_PATH)
	load_user_profiles_from_disk()
	active_profile_id = profile_name
	notify_theme_changed()

## Shared StyleBox helpers for presentation wrappers
static func create_cover_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color_binder_cover
	sb.border_color = color_binder_trim
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	return sb

static func create_page_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color_page_bg
	sb.border_color = color_ruled_line
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(12)
	return sb

## Queries an ink color token by semantic key, asserting on missing or invalid configurations
static func get_ink_color(token: String) -> Color:
	var c = null
	match token.to_lower():
		"accent", "blue", "color_ink_accent", "color_ink_blue":
			c = color_ink_accent
		"muted", "gray", "color_ink_muted":
			c = color_ink_muted
		"body", "black", "color_ink_body", "color_ink_black", "text":
			c = color_ink_body
		"warning", "red", "color_ink_warning":
			c = color_ink_warning
		_:
			assert(false, "[RetroTheme FATAL] Unknown ink color token requested: " + token)
			return Color.MAGENTA

	assert(c is Color, "[RetroTheme FATAL] Color token '%s' is not configured as a valid Color." % token)
	return c

## Builds a complete Godot Theme resource from the active palette across all UI widgets
static func create_godot_theme() -> Theme:
	var t := Theme.new()
	var mono := get_monospace_font()
	t.default_font = mono
	t.default_font_size = 14

	# PanelContainer (OuterShell frame & unstyled sub-panels)
	var shell_panel := create_cover_style()
	t.set_stylebox("panel", "PanelContainer", shell_panel)

	# Label
	t.set_color("font_color", "Label", color_ink_body)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	# Button
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = color_page_bg.darkened(0.06)
	btn_normal.border_color = color_binder_trim
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(3)
	btn_normal.set_content_margin_all(8)

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = color_ink_accent
	btn_hover.border_color = color_binder_cover

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = color_binder_cover

	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = color_page_bg.darkened(0.12)
	btn_disabled.border_color = color_ruled_line

	for btn_type in ["Button", "OptionButton", "CheckBox"]:
		t.set_stylebox("normal", btn_type, btn_normal)
		t.set_stylebox("hover", btn_type, btn_hover)
		t.set_stylebox("pressed", btn_type, btn_pressed)
		t.set_stylebox("disabled", btn_type, btn_disabled)
		t.set_stylebox("focus", btn_type, btn_hover)
		t.set_color("font_color", btn_type, color_ink_body)
		t.set_color("font_hover_color", btn_type, color_page_bg)
		t.set_color("font_pressed_color", btn_type, color_page_bg)
		t.set_color("font_focus_color", btn_type, color_page_bg)
		t.set_color("font_disabled_color", btn_type, color_ink_muted)

	# PopupMenu (OptionButton dropdowns)
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = color_page_bg
	popup_panel.border_color = color_binder_trim
	popup_panel.set_border_width_all(2)
	popup_panel.set_corner_radius_all(3)
	popup_panel.set_content_margin_all(6)

	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = color_ink_accent
	popup_hover.set_corner_radius_all(2)
	popup_hover.set_content_margin_all(4)

	t.set_stylebox("panel", "PopupMenu", popup_panel)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_color", "PopupMenu", color_ink_body)
	t.set_color("font_hover_color", "PopupMenu", color_page_bg)
	t.set_color("font_separator_color", "PopupMenu", color_ruled_line)

	# LineEdit & TextEdit
	var input_sb := StyleBoxFlat.new()
	input_sb.bg_color = color_page_bg.lightened(0.03)
	input_sb.border_color = color_binder_trim
	input_sb.set_border_width_all(1)
	input_sb.set_corner_radius_all(2)
	input_sb.set_content_margin_all(6)

	var input_focus := input_sb.duplicate() as StyleBoxFlat
	input_focus.border_color = color_ink_accent
	input_focus.set_border_width_all(2)

	for edit_type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", edit_type, input_sb)
		t.set_stylebox("focus", edit_type, input_focus)
		t.set_color("font_color", edit_type, color_ink_body)
		t.set_color("font_placeholder_color", edit_type, color_ink_muted)
		t.set_color("caret_color", edit_type, color_ink_accent)
		t.set_color("selection_color", edit_type, color_ink_accent)

	# ItemList
	var list_sb := StyleBoxFlat.new()
	list_sb.bg_color = color_page_bg.darkened(0.03)
	list_sb.border_color = color_ruled_line
	list_sb.set_border_width_all(1)
	list_sb.set_content_margin_all(6)

	var list_sel_sb := StyleBoxFlat.new()
	list_sel_sb.bg_color = color_ink_accent
	list_sel_sb.border_color = color_binder_cover
	list_sel_sb.set_border_width_all(1)
	list_sel_sb.set_corner_radius_all(2)
	list_sel_sb.set_content_margin_all(4)

	t.set_stylebox("panel", "ItemList", list_sb)
	t.set_stylebox("selected", "ItemList", list_sel_sb)
	t.set_stylebox("selected_focus", "ItemList", list_sel_sb)
	t.set_color("font_color", "ItemList", color_ink_body)
	t.set_color("font_hovered_color", "ItemList", color_ink_accent)
	t.set_color("font_selected_color", "ItemList", color_page_bg)
	t.set_color("guide_color", "ItemList", color_ruled_line)

	# ScrollBars (ledger & pocketbook page scroll gutters)
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = color_page_bg.darkened(0.08)
	scroll_bg.set_content_margin_all(3)

	var grabber_sb := StyleBoxFlat.new()
	grabber_sb.bg_color = color_binder_trim
	grabber_sb.set_corner_radius_all(3)

	var grabber_hi := StyleBoxFlat.new()
	grabber_hi.bg_color = color_ink_accent
	grabber_hi.set_corner_radius_all(3)

	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, scroll_bg)
		t.set_stylebox("grabber", sb_type, grabber_sb)
		t.set_stylebox("grabber_highlight", sb_type, grabber_hi)
		t.set_stylebox("grabber_pressed", sb_type, grabber_hi)

	return t