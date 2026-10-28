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
static func load_all_catalog_profiles(target_shell: String = "filofax")-> void:
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
						# If profile specifies a shell, preserve it; otherwise default to "filofax"
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

## Returns only catalog presets configured for a specific shell archetype ("filofax", "apple2")
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
	cfg.load(USER_PROFILES_PATH) # preserve existing entries
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
