# res://scenes/ui/filofax/retro_theme.gd
class_name RetroTheme
extends RefCounted

signal theme_changed

const CONFIG_PATH := "user://filofax_custom_colors.cfg"
const PROFILES_PATH := "user://filofax_profiles.cfg"

# --- Mutable Active Palette (Initial Defaults) ---
static var color_binder_cover: Color = Color("#2b1d14") # Oxblood leather
static var color_binder_trim: Color  = Color("#422b1f") # Stitching / rim
static var color_page_bg: Color      = Color("#f4eedb") # Warm aged Manila paper
static var color_ruled_line: Color   = Color("#dcd3bc") # Pale ruled divider
static var color_ink_body: Color     = Color("#1c1c1c") # Heavy typewriter black
static var color_ink_accent: Color   = Color("#1b325f") # Ledger biro blue
static var color_ink_warning: Color  = Color("#8a1c14") # Audit red / high heat
static var color_ink_muted: Color    = Color("#5a5751") # Pencil margin notes
static var _cached_mono_font: Font = null

# --- Historical 1980s Presets ---
const FACTORY_PRESETS: Dictionary = {
	"1984 Oxblood (Classic)": {
		"cover": Color("#2b1d14"), "trim": Color("#422b1f"),
		"page": Color("#f4eedb"), "line": Color("#dcd3bc"),
		"ink": Color("#1c1c1c"), "accent": Color("#1b325f"),
		"warning": Color("#8a1c14"), "muted": Color("#5a5751")
	},
	"British Racing Green": {
		"cover": Color("#112918"), "trim": Color("#224d2d"),
		"page": Color("#f2ede1"), "line": Color("#d5cfbe"),
		"ink": Color("#101b12"), "accent": Color("#205b38"),
		"warning": Color("#96241a"), "muted": Color("#5a6358")
	},
	"City Executive Navy": {
		"cover": Color("#121b2b"), "trim": Color("#212f45"),
		"page": Color("#eef3f7"), "line": Color("#cbdaf0"),
		"ink": Color("#111a24"), "accent": Color("#1e4f8a"),
		"warning": Color("#a6231b"), "muted": Color("#596677")
	},
	"Canary Legal Pad": {
		"cover": Color("#33241d"), "trim": Color("#4a372d"),
		"page": Color("#fff4a3"), "line": Color("#ead977"),
		"ink": Color("#141414"), "accent": Color("#8a2be2"),
		"warning": Color("#c41e14"), "muted": Color("#736c4b")
	},
	"Monochrome Minimalist": {
		"cover": Color("#1a1a1a"), "trim": Color("#333333"),
		"page": Color("#f8f8f8"), "line": Color("#dcdcdc"),
		"ink": Color("#0a0a0a"), "accent": Color("#4a4a4a"),
		"warning": Color("#d32f2f"), "muted": Color("#757575")
	},
	"Fleet Street Monolith": {
		"cover": Color("#1a1a1a"), "trim": Color("#333333"),
		"page": Color("#f5f5f5"), "line": Color("#d8d8d8"),
		"ink": Color("#0c0c0c"), "accent": Color("#4a4a4a"),
		"warning": Color("#b31b1b"), "muted": Color("#e9aaaa")
	}
}

static var user_profiles: Dictionary = {}
static var active_profile_name: String = "Classic 1984 Oxblood"

static func get_monospace_font() -> Font:
	if _cached_mono_font != null:
		return _cached_mono_font
		
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Courier New", 
		"Consolas", 
		"Lucida Console", 
		"Liberation Mono", 
		"DejaVu Sans Mono", 
		"Courier"
	])
	# Set fallback to default UI font to guarantee font data (fd) is never null
	sys_font.fallbacks = [ThemeDB.fallback_font]
	_cached_mono_font = sys_font
	return _cached_mono_font

static func create_paper_page_style(
	bg_color: Color = color_page_bg, 
	pad_x: int = 14, 
	pad_y: int = 14, 
	border_color: Color = color_ruled_line
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(pad_x)
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	sb.set_border_width_all(1)
	sb.border_color = border_color
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(2, 3)
	return sb

static func apply_stationery_styling(root: Node, default_ink: Color = color_ink_body) -> void:
	var mono_font: Font = get_monospace_font()
	_apply_styling_step(root, default_ink, mono_font)

static func _apply_styling_step(node: Node, ink_color: Color, mono_font: Font) -> void:
	if mono_font == null:
		mono_font = ThemeDB.fallback_font

	if node is Label:
		node.add_theme_color_override("font_color", ink_color)
		if mono_font:
			node.add_theme_font_override("font", mono_font)
		node.add_theme_font_size_override("font_size", 12)
		
	elif node is Button:
		node.add_theme_color_override("font_color", ink_color)
		node.add_theme_color_override("font_pressed_color", ink_color)
		node.add_theme_color_override("font_hover_color", color_ink_accent)
		node.add_theme_color_override("font_focus_color", ink_color)
		if mono_font:
			node.add_theme_font_override("font", mono_font)
		node.add_theme_font_size_override("font_size", 11)
		if node is OptionButton:
			var popup: PopupMenu = node.get_popup()
			popup.add_theme_color_override("font_color", ink_color)
			popup.add_theme_color_override("font_hover_color", color_ink_accent)
			if mono_font:
				popup.add_theme_font_override("font", mono_font)
			
	elif node is ItemList:
		node.add_theme_color_override("font_color", ink_color)
		node.add_theme_color_override("font_selected_color", color_page_bg)
		if mono_font:
			node.add_theme_font_override("font", mono_font)
		node.add_theme_font_size_override("font_size", 11)
		
	elif node is RichTextLabel:
		node.add_theme_color_override("default_color", ink_color)
		if mono_font:
			node.add_theme_font_override("normal_font", mono_font)
		node.add_theme_font_size_override("normal_font_size", 11)

	for child in node.get_children():
		_apply_styling_step(child, ink_color, mono_font)

## Loads a dictionary palette into the active color state
static func load_palette_dict(p: Dictionary, name: String = "") -> void:
	color_binder_cover = p.get("cover", color_binder_cover)
	color_binder_trim  = p.get("trim", color_binder_trim)
	color_page_bg      = p.get("page", color_page_bg)
	color_ruled_line   = p.get("line", color_ruled_line)
	color_ink_body     = p.get("ink", color_ink_body)
	color_ink_accent   = p.get("accent", color_ink_accent)
	color_ink_warning  = p.get("warning", color_ink_warning)
	color_ink_muted    = p.get("muted", color_ink_muted)
	if not name.is_empty():
		active_profile_name = name

## Exports current in-memory colors as a dictionary
static func get_current_palette_dict() -> Dictionary:
	return {
		"cover": color_binder_cover,
		"trim": color_binder_trim,
		"page": color_page_bg,
		"line": color_ruled_line,
		"ink": color_ink_body,
		"accent": color_ink_accent,
		"warning": color_ink_warning,
		"muted": color_ink_muted
	}

static func apply_preset(preset_name: String) -> void:
	if not FACTORY_PRESETS.has(preset_name):
		return
	var p: Dictionary = FACTORY_PRESETS[preset_name]
	color_binder_cover = p["cover"]
	color_binder_trim  = p["trim"]
	color_page_bg      = p["page"]
	color_ruled_line   = p["line"]
	color_ink_body     = p["ink"]
	color_ink_accent   = p["accent"]
	color_ink_warning  = p["warning"]
	color_ink_muted    = p["muted"]
	save_custom_colors()

static func save_custom_colors() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("colors", "binder_cover", color_binder_cover.to_html())
	cfg.set_value("colors", "binder_trim", color_binder_trim.to_html())
	cfg.set_value("colors", "page_bg", color_page_bg.to_html())
	cfg.set_value("colors", "ruled_line", color_ruled_line.to_html())
	cfg.set_value("colors", "ink_body", color_ink_body.to_html())
	cfg.set_value("colors", "ink_accent", color_ink_accent.to_html())
	cfg.set_value("colors", "ink_warning", color_ink_warning.to_html())
	cfg.set_value("colors", "ink_muted", color_ink_muted.to_html())
	cfg.save(CONFIG_PATH)

static func load_custom_colors() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	color_binder_cover = Color.from_string(cfg.get_value("colors", "binder_cover", color_binder_cover.to_html()), color_binder_cover)
	color_binder_trim  = Color.from_string(cfg.get_value("colors", "binder_trim", color_binder_trim.to_html()), color_binder_trim)
	color_page_bg      = Color.from_string(cfg.get_value("colors", "page_bg", color_page_bg.to_html()), color_page_bg)
	color_ruled_line   = Color.from_string(cfg.get_value("colors", "ruled_line", color_ruled_line.to_html()), color_ruled_line)
	color_ink_body     = Color.from_string(cfg.get_value("colors", "ink_body", color_ink_body.to_html()), color_ink_body)
	color_ink_accent   = Color.from_string(cfg.get_value("colors", "ink_accent", color_ink_accent.to_html()), color_ink_accent)
	color_ink_warning  = Color.from_string(cfg.get_value("colors", "ink_warning", color_ink_warning.to_html()), color_ink_warning)
	color_ink_muted    = Color.from_string(cfg.get_value("colors", "ink_muted", color_ink_muted.to_html()), color_ink_muted)

## Saves a named profile to persistent config file
static func save_custom_profile(profile_name: String) -> void:
	if profile_name.is_empty():
		return
	user_profiles[profile_name] = get_current_palette_dict()
	active_profile_name = profile_name

	var cfg := ConfigFile.new()
	cfg.load(PROFILES_PATH) # preserve existing keys
	for prof in user_profiles.keys():
		var data: Dictionary = user_profiles[prof]
		for key in data.keys():
			cfg.set_value(prof, key, (data[key] as Color).to_html())
	cfg.set_value("_meta", "last_active_profile", active_profile_name)
	cfg.save(PROFILES_PATH)

## Loads all custom user profiles from disk
static func load_all_profiles() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILES_PATH) != OK:
		return
		
	for section in cfg.get_sections():
		if section == "_meta":
			continue
		var loaded_p := {
			"cover": Color.from_string(cfg.get_value(section, "cover", color_binder_cover.to_html()), color_binder_cover),
			"trim": Color.from_string(cfg.get_value(section, "trim", color_binder_trim.to_html()), color_binder_trim),
			"page": Color.from_string(cfg.get_value(section, "page", color_page_bg.to_html()), color_page_bg),
			"line": Color.from_string(cfg.get_value(section, "line", color_ruled_line.to_html()), color_ruled_line),
			"ink": Color.from_string(cfg.get_value(section, "ink", color_ink_body.to_html()), color_ink_body),
			"accent": Color.from_string(cfg.get_value(section, "accent", color_ink_accent.to_html()), color_ink_accent),
			"warning": Color.from_string(cfg.get_value(section, "warning", color_ink_warning.to_html()), color_ink_warning),
			"muted": Color.from_string(cfg.get_value(section, "muted", color_ink_muted.to_html()), color_ink_muted)
		}
		user_profiles[section] = loaded_p
		
	var last_active: String = cfg.get_value("_meta", "last_active_profile", "Classic 1984 Oxblood")
	if user_profiles.has(last_active):
		load_palette_dict(user_profiles[last_active], last_active)
	elif FACTORY_PRESETS.has(last_active):
		load_palette_dict(FACTORY_PRESETS[last_active], last_active)

