# res://tools/ui_compiler/widget_emitters.gd
@tool
class_name UIWidgetEmitters
extends RefCounted

const WIDGETS_DIR := "res://tools/ui_compiler/widgets/"
static var _cached_emitters: Dictionary = {}
static var _initialized: bool = false

static func _initialize_registry() -> void:
	if _initialized:
		return
	_cached_emitters.clear()
	
	var dir := DirAccess.open(WIDGETS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".gd") and file_name.begins_with("emit_"):
				var widget_type := file_name.trim_prefix("emit_").trim_suffix(".gd").to_upper()
				var script_path := WIDGETS_DIR.path_join(file_name)
				var script_res = load(script_path)
				if script_res:
					_cached_emitters[widget_type] = script_res
			file_name = dir.get_next()
		dir.list_dir_end()
	
	_initialized = true

## Emits GDScript lines for instantiating and mounting UI widgets inside build_ui() via modular disk-scanned handlers
static func emit_widget_build(row: Dictionary) -> Array[String]:
	_initialize_registry()
	
	var r_type: String = row.get("type", "TEXT_METRIC").to_upper()
	
	# Map legacy aliases
	if r_type == "CIVIC_SUMMARY":
		r_type = "LINKED_LIST"
	elif r_type == "LIST":
		r_type = "ITEM_LIST"
	elif r_type == "DROPDOWN":
		r_type = "OPTION_DROPDOWN"

	if _cached_emitters.has(r_type):
		var emitter_script = _cached_emitters[r_type]
		if emitter_script and emitter_script.has_method("emit_build"):
			return emitter_script.emit_build(row)

	if _cached_emitters.has("TEXT_METRIC"):
		push_warning("[UIWidgetEmitters] Unknown widget type '%s', falling back to TEXT_METRIC." % r_type)
		return _cached_emitters["TEXT_METRIC"].emit_build(row)

	push_error("[UIWidgetEmitters FATAL] Missing default TEXT_METRIC emitter script.")
	return []