# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/roster_docket.json
class_name GenRosterDocket
extends VBoxContainer

signal operative_selected(operative_id)
signal route_requested(domain_token, target_page_name)

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

var _value_labels: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_ui()

func build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_value_labels.clear()
	var mono_font: Font = RETRO_THEME.get_monospace_font()
	assert(mono_font != null, "[UI FATAL] retro_theme.gd failed to supply monospace font.")
	var clr_blue: Color = RETRO_THEME.get_ink_color("accent")
	var clr_muted: Color = RETRO_THEME.get_ink_color("muted")
	var clr_black: Color = RETRO_THEME.get_ink_color("body")

	# --- Section: header_section ---
	var sec_header_section := VBoxContainer.new()
	sec_header_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_header_section.add_theme_constant_override("separation", 2)
	var hdr_header_section := Label.new()
	hdr_header_section.text = "[ " + tr("UI_HDR_CREW_DOSSIER").to_upper() + " ]"
	hdr_header_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_header_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_header_section.add_theme_font_override("font", mono_font)
	hdr_header_section.add_theme_color_override("font_color", clr_blue)
	sec_header_section.add_child(hdr_header_section)
	var sep_header_section := HSeparator.new()
	sec_header_section.add_child(sep_header_section)
	add_child(sec_header_section)

	# --- Header Block ---
	var box_crew_header := VBoxContainer.new()
	box_crew_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_crew_header.add_theme_constant_override("separation", 0)
	var title_crew_header := Label.new()
	title_crew_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_crew_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_crew_header.add_theme_font_override("font", mono_font)
	title_crew_header.add_theme_font_size_override("font_size", 18)
	title_crew_header.add_theme_color_override("font_color", clr_blue)
	box_crew_header.add_child(title_crew_header)
	_value_labels["crew_header_title"] = title_crew_header
	var sub_crew_header := Label.new()
	sub_crew_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_crew_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_crew_header.add_theme_font_override("font", mono_font)
	sub_crew_header.add_theme_font_size_override("font_size", 12)
	sub_crew_header.add_theme_color_override("font_color", clr_muted)
	box_crew_header.add_child(sub_crew_header)
	_value_labels["crew_header_subtitle"] = sub_crew_header
	box_crew_header.add_child(HSeparator.new())
	add_child(box_crew_header)

	# --- Section: operative_list_section ---
	var sec_operative_list_section := VBoxContainer.new()
	sec_operative_list_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_operative_list_section.add_theme_constant_override("separation", 2)
	var hdr_operative_list_section := Label.new()
	hdr_operative_list_section.text = "[ " + tr("UI_HDR_ACTIVE_OPERATIVES").to_upper() + " ]"
	hdr_operative_list_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_operative_list_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_operative_list_section.add_theme_font_override("font", mono_font)
	hdr_operative_list_section.add_theme_color_override("font_color", clr_blue)
	sec_operative_list_section.add_child(hdr_operative_list_section)
	var sep_operative_list_section := HSeparator.new()
	sec_operative_list_section.add_child(sep_operative_list_section)
	add_child(sec_operative_list_section)

	var civic_box_operative_cards := VBoxContainer.new()
	civic_box_operative_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_operative_cards.add_theme_constant_override("separation", 2)
	_value_labels["operative_cards"] = civic_box_operative_cards
	add_child(civic_box_operative_cards)

	# --- Section: dossier_notes_section ---
	var sec_dossier_notes_section := VBoxContainer.new()
	sec_dossier_notes_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_dossier_notes_section.add_theme_constant_override("separation", 2)
	var hdr_dossier_notes_section := Label.new()
	hdr_dossier_notes_section.text = "[ " + tr("UI_SEC_FIELD_OBSERVATIONS").to_upper() + " ]"
	hdr_dossier_notes_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_dossier_notes_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_dossier_notes_section.add_theme_font_override("font", mono_font)
	hdr_dossier_notes_section.add_theme_color_override("font_color", clr_blue)
	sec_dossier_notes_section.add_child(hdr_dossier_notes_section)
	var sep_dossier_notes_section := HSeparator.new()
	sec_dossier_notes_section.add_child(sep_dossier_notes_section)
	add_child(sec_dossier_notes_section)

	var row_observations_box := HBoxContainer.new()
	row_observations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_observations_box := Label.new()
	lbl_observations_box.text = tr("")
	lbl_observations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_observations_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_observations_box.add_theme_font_override("font", mono_font)
	lbl_observations_box.add_theme_color_override("font_color", clr_muted)
	row_observations_box.add_child(lbl_observations_box)
	var val_observations_box := Label.new()
	val_observations_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_observations_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_observations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_observations_box.add_theme_font_override("font", mono_font)
	val_observations_box.add_theme_color_override("font_color", clr_black)
	row_observations_box.add_child(val_observations_box)
	_value_labels["observations_box"] = val_observations_box
	add_child(row_observations_box)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("crew_header_title") and data.has("enterprise_title"):
		_value_labels["crew_header_title"].text = str(data.get("enterprise_title", "--- UNNAMED ---")).to_upper()
	if _value_labels.has("crew_header_subtitle") and data.has("home_district_name"):
		_value_labels["crew_header_subtitle"].text = str(data.get("home_district_name", "")).to_upper()
	if _value_labels.has("operative_cards") and data.has("crew_members"):
		var ctrl = _value_labels["operative_cards"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.queue_free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var mono_f: Font = RETRO_THEME.get_monospace_font()
			var items: Array = data.get("crew_members", [])
			if items.is_empty():
				var empty_lbl := Label.new()
				empty_lbl.text = tr("UI_INTEL_MASKED_BLANK")
				empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				empty_lbl.add_theme_font_override("font", mono_f)
				empty_lbl.add_theme_color_override("font_color", clr_m)
				ctrl.add_child(empty_lbl)
			else:
				for item in items:
					assert(item is Dictionary, "[UI CONTRACT ERROR] Expected Dictionary in list payload for: crew_members")
					assert(item.has("resident_id"), "[UI CONTRACT ERROR] Missing required key 'resident_id' in item: " + str(item))
					var key_val = item["resident_id"]
					var main_txt: String = str(item.get("name", "Unnamed"))
					var sub_txt: String = str(item.get("summary_line", ""))
					var display_txt: String = "• " + main_txt
					if not sub_txt.is_empty():
						display_txt += " (" + sub_txt + ")"
					var btn := Button.new()
					btn.text = display_txt
					btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
					btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					btn.add_theme_font_override("font", mono_f)
					btn.add_theme_font_size_override("font_size", 11)
					btn.add_theme_color_override("font_color", clr_b)
					btn.pressed.connect(func(): operative_selected.emit("OPERATIVE_DETAIL", key_val))
					ctrl.add_child(btn)

func inscribe_entry(entry: Dictionary) -> void:
	if not _value_labels.has("__inscriptions__") and not _value_labels.has("observations_box"):
		return
	var target_box = _value_labels.get("__inscriptions__", _value_labels.get("observations_box"))
	if not target_box is Container:
		return
	var author: String = str(entry.get("author", ""))
	var text_content: String = str(entry.get("text", ""))
	var note_lbl := Label.new()
	if not author.is_empty():
		note_lbl.text = "[" + author + "] " + text_content
	else:
		note_lbl.text = text_content
	note_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.add_theme_font_override("font", RETRO_THEME.get_monospace_font())
	note_lbl.add_theme_color_override("font_color", RETRO_THEME.get_ink_color("body"))
	target_box.add_child(note_lbl)
