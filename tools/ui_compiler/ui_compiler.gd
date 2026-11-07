# res://tools/ui_compiler/ui_compiler.gd
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
	SystemLogger.log_info("[UICompiler] Build and verification complete. Artifacts written to: " + OUTPUT_DIR)

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

	# 1. Harvest and Deduplicate Signals from Sections (NO _meta access)
	var declared_signals: Dictionary = {}
	var signal_defs: Array[String] = []

	var sections: Array = schema.get("sections", [])
	for sec in sections:
		var s_type: String = sec.get("type", "").to_upper()
		if s_type == "SIGNALS":
			for sig in sec.get("signals", []):
				var sig_str: String = str(sig).strip_edges()
				var base_name: String = sig_str.split("(")[0].strip_edges()
				if not declared_signals.has(base_name):
					declared_signals[base_name] = true
					signal_defs.append(sig_str)

	# Auto-discover signals needed by interactive primitives
	for sec in sections:
		for row in sec.get("rows", []):
			var r_type: String = row.get("type", "").to_upper()
			if r_type == "LINKED_LIST" or r_type == "CIVIC_SUMMARY":
				var sig_name: String = str(row.get("action_signal", "item_selected")).strip_edges()
				if not declared_signals.has(sig_name):
					declared_signals[sig_name] = true
					signal_defs.append(sig_name + "(target_route, filter_key)")

	var lines: Array[String] = []
	lines.append("# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY")
	lines.append("# Compiled from: " + schema_path)
	lines.append("class_name " + class_name_str)
	lines.append("extends " + extends_str + "\n")

	for sig_def in signal_defs:
		lines.append("signal " + sig_def)
	if not signal_defs.is_empty():
		lines.append("")

	lines.append("const RETRO_THEME = preload(\"res://scenes/ui/shell_host/retro_theme.gd\")\n")
	lines.append("var _value_labels: Dictionary = {}")

	var has_action_queue: bool = bool(meta.get("has_action_queue", false))
	if has_action_queue:
		lines.append("var _queue: ActionQueuePresenter = ActionQueuePresenter.new()")
	lines.append("")

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

	var has_inscriptions_container: bool = false

	for sec in sections:
		var s_id: String = sec.get("id", "sec")
		var s_type: String = sec.get("type", "").to_upper()
		
		# Skip signal sections during visual UI construction
		if s_type == "SIGNALS":
			continue

		var s_token: String = sec.get("header_token", "")
		var s_def: String = sec.get("header_default", s_id.capitalize())

		if not s_token.is_empty():
			out_tokens[s_token] = s_def

		# First-class section: INSCRIPTIONS
		if s_type == "INSCRIPTIONS":
			has_inscriptions_container = true
			lines.append("\t# --- Inscriptions Container: " + s_id + " ---")
			if not s_token.is_empty():
				lines.append("\tvar hdr_" + s_id + " := Label.new()")
				lines.append("\thdr_" + s_id + ".text = \"[ \" + tr(\"" + s_token + "\").to_upper() + \" ]\"")
				lines.append("\thdr_" + s_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
				lines.append("\thdr_" + s_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
				lines.append("\thdr_" + s_id + ".add_theme_font_override(\"font\", mono_font)")
				lines.append("\thdr_" + s_id + ".add_theme_color_override(\"font_color\", clr_blue)")
				lines.append("\tadd_child(hdr_" + s_id + ")")
			lines.append("\tvar insc_list_" + s_id + " := VBoxContainer.new()")
			lines.append("\tinsc_list_" + s_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\t_value_labels[\"__inscriptions__\"] = insc_list_" + s_id)
			lines.append("\tadd_child(insc_list_" + s_id + ")\n")
			continue

		# Standard section with header
		if not s_token.is_empty():
			lines.append("\t# --- Section: " + s_id + " ---")
			lines.append("\tvar sec_" + s_id + " := VBoxContainer.new()")
			lines.append("\tsec_" + s_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\tsec_" + s_id + ".add_theme_constant_override(\"separation\", 2)")
			lines.append("\tvar hdr_" + s_id + " := Label.new()")
			lines.append("\thdr_" + s_id + ".text = \"[ \" + tr(\"" + s_token + "\").to_upper() + \" ]\"")
			lines.append("\thdr_" + s_id + ".size_flags_horizontal = Control.SIZE_EXPAND_FILL")
			lines.append("\thdr_" + s_id + ".autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
			lines.append("\thdr_" + s_id + ".add_theme_font_override(\"font\", mono_font)")
			lines.append("\thdr_" + s_id + ".add_theme_color_override(\"font_color\", clr_blue)")
			lines.append("\tsec_" + s_id + ".add_child(hdr_" + s_id + ")")
			lines.append("\tvar sep_" + s_id + " := HSeparator.new()")
			lines.append("\tsec_" + s_id + ".add_child(sep_" + s_id + ")")
			lines.append("\tadd_child(sec_" + s_id + ")\n")

		for row in sec.get("rows", []):
			var r_type: String = row.get("type", "").to_upper()
			if r_type == "INSCRIPTIONS_CONTAINER":
				has_inscriptions_container = true

			var r_token: String = row.get("token", "")
			var r_def: String = row.get("default_text", row.get("id", ""))
			if not r_token.is_empty():
				out_tokens[r_token] = r_def

			lines.append_array(UI_WIDGET_EMITTERS.emit_widget_build(row))

	if has_action_queue:
		lines.append("\t_queue.queue_changed.connect(_on_queue_changed)\n")

	# bind_data()
	lines.append("func bind_data(data: Dictionary) -> void:")
	var binding_lines: Array[String] = []
	for sec in sections:
		if sec.get("type", "").to_upper() == "SIGNALS":
			continue
		for row in sec.get("rows", []):
			binding_lines.append_array(UI_BINDER_EMITTERS.emit_binding_logic(row))

	if binding_lines.is_empty():
		lines.append("\tpass")
	else:
		lines.append_array(binding_lines)

	# inscribe_entry() (if supported)
	if has_inscriptions_container:
		lines.append("\nfunc inscribe_entry(entry: Dictionary) -> void:")
		lines.append("\tif not _value_labels.has(\"__inscriptions__\") and not _value_labels.has(\"observations_box\"):")
		lines.append("\t\treturn")
		lines.append("\tvar target_box = _value_labels.get(\"__inscriptions__\", _value_labels.get(\"observations_box\"))")
		lines.append("\tif not target_box is Container:")
		lines.append("\t\treturn")
		lines.append("\tvar author: String = str(entry.get(\"author\", \"\"))")
		lines.append("\tvar text_content: String = str(entry.get(\"text\", \"\"))")
		lines.append("\tvar note_lbl := Label.new()")
		lines.append("\tif not author.is_empty():")
		lines.append("\t\tnote_lbl.text = \"[\" + author + \"] \" + text_content")
		lines.append("\telse:")
		lines.append("\t\tnote_lbl.text = text_content")
		lines.append("\tnote_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL")
		lines.append("\tnote_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART")
		lines.append("\tnote_lbl.add_theme_font_override(\"font\", RETRO_THEME.get_monospace_font())")
		lines.append("\tnote_lbl.add_theme_color_override(\"font_color\", RETRO_THEME.get_ink_color(\"body\"))")
		lines.append("\ttarget_box.add_child(note_lbl)")

	# --- INJECT QUEUE API ---
	if has_action_queue:
		lines.append_array([
			"",
			"func add_directive(directive: Dictionary) -> void:",
			"\t_queue.add_directive(directive)",
			"",
			"func get_staged_directives() -> Array[Dictionary]:",
			"\treturn _queue.get_staged_directives()",
			"",
			"func consume_selected_directives() -> Array[Dictionary]:",
			"\treturn _queue.consume_selected_directives()",
			"",
			"func clear_staged_directives() -> void:",
			"\t_queue.clear()",
			"",
			"func _on_queue_changed(display_lines: Array, _selected_index: int) -> void:",
			"\tif _value_labels.has(\"queue_list\"):",
			"\t\tvar lst = _value_labels[\"queue_list\"]",
			"\t\tif lst is ItemList:",
			"\t\t\tlst.clear()",
			"\t\t\tfor line in display_lines:",
			"\t\t\t\tlst.add_item(line)"
		])

	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	assert(out_file != null, "[UICompiler FATAL] Could not write output file: " + out_path)
	out_file.store_string("\n".join(lines) + "\n")
	out_file.close()

	# 2. Enforced Post-Compilation Validation
	_validate_generated_view(out_path, declared_signals)
	SystemLogger.log_info("[UICompiler] Generated & Validated: " + out_path)

static func _validate_generated_view(out_path: String, expected_signals: Dictionary) -> void:
	var script_res = load(out_path)
	assert(script_res != null, "[UIValidator FATAL] Failed to load generated script: " + out_path)
	
	var instance = script_res.new()
	assert(instance != null, "[UIValidator FATAL] Failed to instantiate generated view: " + out_path)
	
	for sig_name in expected_signals.keys():
		assert(instance.has_signal(sig_name), "[UIValidator FATAL] Generated view missing declared signal '%s' in %s" % [sig_name, out_path])
	
	if instance is Node:
		_deep_free_node(instance)
	else:
		instance.free()

static func _deep_free_node(node: Node) -> void:
	for child in node.get_children():
		_deep_free_node(child)
	node.free()

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
			SystemLogger.log_info("[UICompiler] Appended token to ui_strings.csv: " + token_key)

	if not appended_lines.is_empty():
		var out_file := FileAccess.open(UI_STRINGS_PATH, FileAccess.WRITE)
		assert(out_file != null, "[UICompiler FATAL] Failed to write to ui_strings.csv")
		out_file.store_string(content.strip_edges() + "\n" + "\n".join(appended_lines) + "\n")
		out_file.close()