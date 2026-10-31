@tool
class_name UICompiler
extends RefCounted

const UI_WIDGET_EMITTERS = preload("res://tools/ui_compiler/widget_emitters.gd")
const UI_BINDER_EMITTERS = preload("res://tools/ui_compiler/binder_emitters.gd")

const SCHEMAS_VIEW_DIR := "res://data_modules/core/ui_schemas/views/"
const OUTPUT_DIR := "res://generated/ui/"
const UI_STRINGS_PATH := "res://data_modules/core/localization/ui_strings.csv"

static func compile_all() -> void:
	var dir := DirAccess.open(SCHEMAS_VIEW_DIR)
	assert(dir != null, "[UICompiler FATAL] View schema directory missing: " + SCHEMAS_VIEW_DIR)

	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	var harvested_tokens: Dictionary = {}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			compile_schema(SCHEMAS_VIEW_DIR + file_name, harvested_tokens)
		file_name = dir.get_next()
	dir.list_dir_end()

	sync_localization_tokens(harvested_tokens)
	print("[UICompiler] Build complete. Artifacts written to: " + OUTPUT_DIR)

static func compile_schema(schema_path: String, out_tokens: Dictionary = {}) -> void:
	var file := FileAccess.open(schema_path, FileAccess.READ)
	assert(file != null, "[UICompiler FATAL] Could not open schema file: " + schema_path)
	var raw := file.get_as_text()
	file.close()

	var schema: Dictionary = JSON.parse_string(raw)
	assert(schema is Dictionary, "[UICompiler FATAL] Schema root must be a Dictionary: " + schema_path)

	var meta: Dictionary = schema.get("_meta", {})
	var class_name_str: String = meta.get("target_class", "GeneratedUI")
	var extends_str: String = meta.get("extends", "VBoxContainer")
	var target_filename := "gen_" + schema_path.get_file().replace(".json", ".gd")
	var out_path := OUTPUT_DIR + target_filename

	var lines: Array[String] = []
	lines.append("# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY")
	lines.append("# Compiled from: " + schema_path)
	lines.append("class_name " + class_name_str)
	lines.append("extends " + extends_str + "\n")

	# Schema signals
	var signals: Array = meta.get("signals", [])
	for sig in signals:
		lines.append("signal " + str(sig))
	if not signals.is_empty():
		lines.append("")

	lines.append("const RETRO_THEME = preload(\"res://scenes/ui/shell_host/retro_theme.gd\")\n")
	lines.append("var _value_labels: Dictionary = {}\n")

	# _init()
	lines.append("func _init() -> void:")
	lines.append("\tsize_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\tsize_flags_vertical = Control.SIZE_EXPAND_FILL")
	lines.append("\tbuild_ui()\n")

	# build_ui() with static palette queries
	lines.append("func build_ui() -> void:")
	lines.append("\tfor child in get_children():")
	lines.append("\t\tchild.queue_free()")
	lines.append("\t_value_labels.clear()")
	lines.append("\tvar mono_font: Font = RETRO_THEME.get_monospace_font()")
	lines.append("\tassert(mono_font != null, \"[UI FATAL] retro_theme.gd failed to supply monospace font.\")")
	lines.append("\tvar clr_blue: Color = RETRO_THEME.get_ink_color(\"accent\")")
	lines.append("\tvar clr_muted: Color = RETRO_THEME.get_ink_color(\"muted\")")
	lines.append("\tvar clr_black: Color = RETRO_THEME.get_ink_color(\"body\")\n")

	var sections: Array = schema.get("sections", [])
	for sec in sections:
		var s_id: String = sec.get("id", "sec")
		var s_token: String = sec.get("header_token", "")
		var s_def: String = sec.get("header_default", s_id.capitalize())

		if not s_token.is_empty():
			out_tokens[s_token] = s_def
			lines.append("\t# --- Section: " + s_id + " ---")
			lines.append("\tvar sec_" + s_id + " := VBoxContainer.new()")
			lines.append("\tsec_" + s_id + ".add_theme_constant_override(\"separation\", 2)")
			lines.append("\tvar hdr_" + s_id + " := Label.new()")
			lines.append("\thdr_" + s_id + ".text = \"[ \" + tr(\"" + s_token + "\").to_upper() + \" ]\"")
			lines.append("\thdr_" + s_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\thdr_" + s_id + ".add_theme_color_override(\"font_color\", clr_blue)")
			lines.append("\tsec_" + s_id + ".add_child(hdr_" + s_id + ")")
			lines.append("\tvar sep_" + s_id + " := HSeparator.new()")
			lines.append("\tsec_" + s_id + ".add_child(sep_" + s_id + ")")
			lines.append("\tadd_child(sec_" + s_id + ")\n")

		for row in sec.get("rows", []):
			var r_token: String = row.get("token", "")
			var r_def: String = row.get("default_text", row.get("id", ""))
			if not r_token.is_empty():
				out_tokens[r_token] = r_def

			lines.append_array(UI_WIDGET_EMITTERS.emit_widget_build(row))

	if meta.get("has_inscriptions", false):
		_emit_inscriptions_block(lines, meta, out_tokens)

	# bind_data()
	lines.append("func bind_data(data: Dictionary) -> void:")
	var binding_lines: Array[String] = []
	for sec in sections:
		for row in sec.get("rows", []):
			binding_lines.append_array(UI_BINDER_EMITTERS.emit_binding_logic(row))

	if binding_lines.is_empty():
		lines.append("\tpass")
	else:
		lines.append_array(binding_lines)

	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	assert(out_file != null, "[UICompiler FATAL] Could not write output file: " + out_path)
	out_file.store_string("\n".join(lines) + "\n")
	out_file.close()
	print("[UICompiler] Generated: " + out_path)

static func _emit_inscriptions_block(lines: Array[String], meta: Dictionary, out_tokens: Dictionary) -> void:
	var h_token: String = meta.get("inscriptions_header_token", "UI_SEC_INSCRIBED_NOTES")
	var h_def: String = meta.get("inscriptions_header_default", "INSCRIBED NOTES")
	out_tokens[h_token] = h_def

	lines.append("\t# --- Inscriptions Container ---")
	lines.append("\tvar hdr_insc := Label.new()")
	lines.append("\thdr_insc.text = \"[ \" + tr(\"" + h_token + "\").to_upper() + \" ]\"")
	lines.append("\thdr_insc.add_theme_font_override(\"font\", mono_font)")
	lines.append("\thdr_insc.add_theme_color_override(\"font_color\", clr_blue)")
	lines.append("\tadd_child(hdr_insc)")
	lines.append("\tvar insc_list := VBoxContainer.new()")
	lines.append("\tinsc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL")
	lines.append("\t_value_labels[\"__inscriptions__\"] = insc_list")
	lines.append("\tadd_child(insc_list)\n")

static func sync_localization_tokens(tokens_to_sync: Dictionary) -> void:
	if not FileAccess.file_exists(UI_STRINGS_PATH):
		push_warning("[UICompiler] ui_strings.csv missing at: " + UI_STRINGS_PATH)
		return

	var file := FileAccess.open(UI_STRINGS_PATH, FileAccess.READ)
	if not file:
		return
	var content := file.get_as_text()
	file.close()

	var lines := content.split("\n", false)
	if lines.is_empty():
		return

	var header_line := lines[0]
	var headers := header_line.split(",")
	var existing_keys := {}

	for i in range(1, lines.size()):
		var line := lines[i].strip_edges()
		if line.is_empty():
			continue
		var row_key := line.split(",")[0].strip_edges().replace("\"", "")
		existing_keys[row_key] = true

	var appended_lines: Array[String] = []
	for token_key in tokens_to_sync.keys():
		if not existing_keys.has(token_key):
			var def_text: String = str(tokens_to_sync[token_key]).replace("\"", "\"\"")
			var row_cols: Array[String] = ["\"" + token_key + "\"", "\"" + def_text + "\""]
			for h in range(2, headers.size()):
				row_cols.append("\"\"")
			appended_lines.append(",".join(row_cols))
			print("[UICompiler] Appended token to ui_strings.csv: " + token_key)

	if not appended_lines.is_empty():
		var out_file := FileAccess.open(UI_STRINGS_PATH, FileAccess.WRITE)
		assert(out_file != null, "[UICompiler FATAL] Failed to write to ui_strings.csv")
		out_file.store_string(content.strip_edges() + "\n" + "\n".join(appended_lines) + "\n")
		out_file.close()