# res://tools/ui_compiler/binder_emitters.gd
@tool
class_name UIBinderEmitters
extends RefCounted

const BINDERS_DIR := "res://tools/ui_compiler/binders/"
static var _cached_binders: Dictionary = {}
static var _initialized: bool = false

static func _initialize_registry() -> void:
	if _initialized:
		return
	_cached_binders.clear()
	
	var dir := DirAccess.open(BINDERS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".gd") and file_name.begins_with("bind_"):
				var binder_type := file_name.trim_prefix("bind_").trim_suffix(".gd").to_upper()
				var script_path := BINDERS_DIR.path_join(file_name)
				var script_res = load(script_path)
				if script_res:
					_cached_binders[binder_type] = script_res
			file_name = dir.get_next()
		dir.list_dir_end()
	
	_initialized = true

## Emits GDScript lines for value extraction and presentation inside bind_data(data: Dictionary) via modular disk-scanned handlers
static func emit_binding_logic(row: Dictionary) -> Array[String]:
	_initialize_registry()
	
	var r_type: String = row.get("type", "TEXT_METRIC").to_upper()
	
	# Map legacy aliases
	if r_type == "CIVIC_SUMMARY":
		r_type = "LINKED_LIST"
	elif r_type == "LIST":
		r_type = "ITEM_LIST"
	elif r_type == "DROPDOWN":
		r_type = "OPTION_DROPDOWN"

	if _cached_binders.has(r_type):
		var binder_script = _cached_binders[r_type]
		if binder_script and binder_script.has_method("emit_binding"):
			return binder_script.emit_binding(row)

	if _cached_binders.has("TEXT_METRIC"):
		return _cached_binders["TEXT_METRIC"].emit_binding(row)

	return []