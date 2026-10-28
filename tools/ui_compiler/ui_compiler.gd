# res://tools/ui_compiler/ui_compiler.gd
@tool
class_name UICompiler
extends RefCounted

const SCHEMAS_DIR := "res://data_modules/core/ui_schemas/views/"
const OUTPUT_DIR := "res://generated/ui/"
const STRINGS_CSV := "res://data_modules/core/localization/ui_strings.csv"

static func compile_all() -> void:
	var dir := DirAccess.open(SCHEMAS_DIR)
	if not dir:
		push_error("[UICompiler] Schema folder missing: " + SCHEMAS_DIR)
		return

	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	var harvested_tokens: Dictionary = {}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var schema_path := SCHEMAS_DIR.path_join(file_name)
			_compile_schema(schema_path, harvested_tokens)
		file_name = dir.get_next()
	dir.list_dir_end()

	_sync_localization_csv(harvested_tokens)
	print("[UICompiler] Build complete. Artifacts written to: " + OUTPUT_DIR)

static func _compile_schema(file_path: String, out_tokens: Dictionary) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return
	var json_str := file.get_as_text()
	var schema: Dictionary = JSON.parse_string(json_str)
	file.close()

	var meta: Dictionary = schema.get("_meta", {})
	var class_name_str: String = meta.get("target_class", "GeneratedUI")
	var extends_str: String = meta.get("extends", "Control")
	var out_path := OUTPUT_DIR + "gen_" + file_path.get_file().replace(".json", ".gd")

	var code := ""
	code += "# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY\n"
	code += "# Compiled from: %s\n" % file_path
	code += "class_name %s\n" % class_name_str
	code += "extends %s\n\n" % extends_str
	
	# Explicit reference to decoupled shell_host
	code += "const RETRO_THEME = preload(\"res://scenes/ui/shell_host/retro_theme.gd\")\n\n"

	for sig in meta.get("signals", []):
		code += "signal %s\n" % sig
	code += "\n"

	code += "var _value_labels: Dictionary = {}\n"
	code += "var _inscribed_entries_container: VBoxContainer = null\n\n"

	# _init()
	code += "func _init() -> void:\n"
	code += "\tbuild_ui()\n\n"

	# build_ui()
	code += "func build_ui() -> void:\n"
	code += "\tfor child in get_children():\n"
	code += "\t\tremove_child(child)\n"
	code += "\t\tchild.queue_free()\n"
	code += "\tvar mono_font: Font = RETRO_THEME.get_monospace_font()\n\n"

	for section in schema.get("sections", []):
		var s_header: String = section.get("header_token", "")
		var s_id: String = section.get("id", "sec")
		if not s_header.is_empty():
			out_tokens[s_header] = section.get("default_text", s_header)
			code += "\t# --- Section: %s ---\n" % s_header
			code += "\tvar hdr_%s := Label.new()\n" % s_id
			code += "\thdr_%s.text = tr(\"%s\")\n" % [s_id, s_header]
			code += "\thdr_%s.add_theme_font_override(\"font\", mono_font)\n"
			code += "\thdr_%s.add_theme_color_override(\"font_color\", RETRO_THEME.color_ink_accent)\n"
			code += "\tadd_child(hdr_%s)\n\n" % s_id

		for row in section.get("rows", []):
			var r_id: String = row.get("id", "")
			var r_type: String = row.get("type", "TEXT")
			var r_token: String = row.get("token", "")
			if not r_token.is_empty():
				out_tokens[r_token] = row.get("default_text", r_token)

			match r_type:
				"BUTTON":
					code += "\tvar btn_%s := Button.new()\n" % r_id
					code += "\tbtn_%s.text = tr(\"%s\")\n" % [r_id, r_token]
					code += "\tbtn_%s.add_theme_font_override(\"font\", mono_font)\n" % r_id
					var action_signal: String = row.get("action_signal", "action_clicked")
					var emit_args: String = row.get("emit_args", "")
					if not emit_args.is_empty():
						code += "\tbtn_%s.pressed.connect(func(): %s.emit(%s))\n" % [r_id, action_signal, emit_args]
					else:
						code += "\tbtn_%s.pressed.connect(func(): %s.emit())\n" % [r_id, action_signal]
					code += "\t_value_labels[\"%s\"] = btn_%s\n" % [r_id, r_id]
					code += "\tadd_child(btn_%s)\n" % r_id

				"ITEM_LIST":
					code += "\tvar list_%s := ItemList.new()\n" % r_id
					code += "\tlist_%s.custom_minimum_size = Vector2(0, 120)\n" % r_id
					code += "\tlist_%s.add_theme_font_override(\"font\", mono_font)\n" % r_id
					code += "\t_value_labels[\"%s\"] = list_%s\n" % [r_id, r_id]
					code += "\tadd_child(list_%s)\n" % r_id

				_:
					code += "\tvar row_%s := HBoxContainer.new()\n" % r_id
					code += "\tvar lbl_%s := Label.new()\n" % r_id
					code += "\tlbl_%s.text = tr(\"%s\")\n" % [r_id, r_token]
					code += "\tlbl_%s.add_theme_font_override(\"font\", mono_font)\n" % r_id
					code += "\tlbl_%s.add_theme_color_override(\"font_color\", RETRO_THEME.color_ink_body)\n" % r_id
					code += "\trow_%s.add_child(lbl_%s)\n" % [r_id, r_id]

					code += "\tvar val_%s := Label.new()\n" % r_id
					code += "\tval_%s.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n" % r_id
					code += "\tval_%s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT\n" % r_id
					code += "\tval_%s.add_theme_font_override(\"font\", mono_font)\n" % r_id
					code += "\tval_%s.add_theme_color_override(\"font_color\", RETRO_THEME.color_ink_body)\n" % r_id
					code += "\trow_%s.add_child(val_%s)\n" % [r_id, r_id]

					code += "\t_value_labels[\"%s\"] = val_%s\n" % [r_id, r_id]
					code += "\tadd_child(row_%s)\n" % r_id

	if schema.get("has_inscribed_entries", false):
		code += "\n\t# Inscribed ruled ledger container\n"
		code += "\t_inscribed_entries_container = VBoxContainer.new()\n"
		code += "\t_inscribed_entries_container.name = \"InscribedEntries\"\n"
		code += "\tadd_child(_inscribed_entries_container)\n"

	# bind_data()
	code += "\nfunc bind_data(data: Dictionary) -> void:\n"
	for section in schema.get("sections", []):
		for row in section.get("rows", []):
			var r_id: String = row.get("id", "")
			var f_name: String = row.get("field", "")
			var fmt: String = row.get("format", "STRING")
			var suffix: String = row.get("suffix", "")
			if f_name.is_empty():
				continue

			code += "\tif _value_labels.has(\"%s\") and data.has(\"%s\"):\n" % [r_id, f_name]
			match fmt:
				"CURRENCY":
					code += "\t\t_value_labels[\"%s\"].text = \"£\" + (\"%%.2f\" %% float(data[\"%s\"])) + \"%s\"\n" % [r_id, f_name, suffix]
				"PERCENT":
					code += "\t\t_value_labels[\"%s\"].text = (\"%%.1f\" %% (float(data[\"%s\"]) * 100.0)) + \"%%\" + \"%s\"\n" % [r_id, f_name, suffix]
				"INT":
					code += "\t\t_value_labels[\"%s\"].text = str(int(data[\"%s\"])) + \"%s\"\n" % [r_id, f_name, suffix]
				"FLOAT":
					code += "\t\t_value_labels[\"%s\"].text = (\"%%.1f\" %% float(data[\"%s\"])) + \"%s\"\n" % [r_id, f_name, suffix]
				_:
					code += "\t\t_value_labels[\"%s\"].text = str(data[\"%s\"]) + \"%s\"\n" % [r_id, f_name, suffix]

	# inscribe_entry()
	if schema.get("has_inscribed_entries", false):
		code += "\nfunc inscribe_entry(entry: Dictionary) -> void:\n"
		code += "\tif _inscribed_entries_container == null:\n\t\treturn\n"
		code += "\tvar row := HBoxContainer.new()\n"
		code += "\tvar mono: Font = RETRO_THEME.get_monospace_font()\n"
		code += "\tvar tick_lbl := Label.new()\n"
		code += "\ttick_lbl.text = \"[W%%02d] \" %% int(entry.get(\"tick\", 1))\n"
		code += "\ttick_lbl.add_theme_font_override(\"font\", mono)\n"
		code += "\ttick_lbl.add_theme_color_override(\"font_color\", RETRO_THEME.color_ink_muted)\n"
		code += "\trow.add_child(tick_lbl)\n"
		code += "\tvar txt_lbl := Label.new()\n"
		code += "\ttxt_lbl.text = str(entry.get(\"text\", \"\"))\n"
		code += "\ttxt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n"
		code += "\ttxt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n"
		code += "\ttxt_lbl.add_theme_font_override(\"font\", mono)\n"
		code += "\ttxt_lbl.add_theme_color_override(\"font_color\", RETRO_THEME.color_ink_body)\n"
		code += "\trow.add_child(txt_lbl)\n"
		code += "\t_inscribed_entries_container.add_child(row)\n"

	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	if out_file:
		out_file.store_string(code)
		out_file.close()

static func _sync_localization_csv(new_tokens: Dictionary) -> void:
	var existing_lines: Array[String] = []
	var known_keys: Dictionary = {}
	if FileAccess.file_exists(STRINGS_CSV):
		var file := FileAccess.open(STRINGS_CSV, FileAccess.READ)
		while not file.eof_reached():
			var line := file.get_line()
			if line.strip_edges().is_empty():
				continue
			existing_lines.append(line)
			var key := line.split(",")[0].strip_edges()
			known_keys[key] = true
		file.close()
	else:
		existing_lines.append("keys,en_GB")

	var added := false
	for token in new_tokens.keys():
		if not known_keys.has(token):
			existing_lines.append("%s,\"%s\"" % [token, new_tokens[token]])
			added = true

	if added:
		var write_file := FileAccess.open(STRINGS_CSV, FileAccess.WRITE)
		for l in existing_lines:
			write_file.store_line(l)
		write_file.close()