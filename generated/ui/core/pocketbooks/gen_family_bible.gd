# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/pocketbooks/family_bible.json
extends VBoxContainer

signal item_selected(target_route: String, filter_key: Variant)
signal action_clicked(action_code: String, payload: Dictionary)

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

	# --- Header Block ---
	var box_bible_header := VBoxContainer.new()
	box_bible_header.name = "bible_header"
	box_bible_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_bible_header.add_theme_constant_override("separation", 0)
	var title_bible_header := Label.new()
	title_bible_header.name = "bible_header_title"
	title_bible_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bible_header.theme_type_variation = &"HeaderTitle"
	title_bible_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_bible_header.add_child(title_bible_header)
	_value_labels["bible_header_title"] = title_bible_header
	var sub_bible_header := Label.new()
	sub_bible_header.name = "bible_header_subtitle"
	sub_bible_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_bible_header.theme_type_variation = &"HeaderSubtitle"
	sub_bible_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_bible_header.add_child(sub_bible_header)
	_value_labels["bible_header_subtitle"] = sub_bible_header
	box_bible_header.add_child(HSeparator.new())
	add_child(box_bible_header)

	var row_lbl_crew_lineages := HBoxContainer.new()
	row_lbl_crew_lineages.name = "lbl_crew_lineages"
	row_lbl_crew_lineages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_lbl_crew_lineages := Label.new()
	lbl_lbl_crew_lineages.text = tr("UI_SEC_FAMILY_LINEAGES")
	lbl_lbl_crew_lineages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_lbl_crew_lineages.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_lbl_crew_lineages.add_child(lbl_lbl_crew_lineages)
	var val_lbl_crew_lineages := Label.new()
	val_lbl_crew_lineages.name = "lbl_crew_lineages_value"
	val_lbl_crew_lineages.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl_crew_lineages.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_lbl_crew_lineages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_lbl_crew_lineages.add_child(val_lbl_crew_lineages)
	_value_labels["lbl_crew_lineages"] = val_lbl_crew_lineages
	add_child(row_lbl_crew_lineages)

	var civic_box_crew_lineages := VBoxContainer.new()
	civic_box_crew_lineages.name = "crew_lineages"
	civic_box_crew_lineages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_crew_lineages.add_theme_constant_override("separation", 2)
	_value_labels["crew_lineages"] = civic_box_crew_lineages
	add_child(civic_box_crew_lineages)

	var row_lbl_vital_records := HBoxContainer.new()
	row_lbl_vital_records.name = "lbl_vital_records"
	row_lbl_vital_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_lbl_vital_records := Label.new()
	lbl_lbl_vital_records.text = tr("UI_SEC_VITAL_RECORDS")
	lbl_lbl_vital_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_lbl_vital_records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_lbl_vital_records.add_child(lbl_lbl_vital_records)
	var val_lbl_vital_records := Label.new()
	val_lbl_vital_records.name = "lbl_vital_records_value"
	val_lbl_vital_records.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl_vital_records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_lbl_vital_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_lbl_vital_records.add_child(val_lbl_vital_records)
	_value_labels["lbl_vital_records"] = val_lbl_vital_records
	add_child(row_lbl_vital_records)

	var list_vital_records_list := ItemList.new()
	list_vital_records_list.name = "vital_records_list"
	list_vital_records_list.custom_minimum_size = Vector2(0, 120)
	list_vital_records_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["vital_records_list"] = list_vital_records_list
	add_child(list_vital_records_list)

	# --- Inscriptions Container: inscriptions_section ---
	var hdr_inscriptions_section := Label.new()
	hdr_inscriptions_section.text = "[ " + tr("UI_SEC_FAMILY_NOTES").to_upper() + " ]"
	hdr_inscriptions_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_inscriptions_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_inscriptions_section.add_theme_font_override("font", mono_font)
	hdr_inscriptions_section.add_theme_color_override("font_color", clr_blue)
	add_child(hdr_inscriptions_section)
	var insc_list_inscriptions_section := VBoxContainer.new()
	insc_list_inscriptions_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["__inscriptions__"] = insc_list_inscriptions_section
	add_child(insc_list_inscriptions_section)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("crew_lineages"):
		var ctrl = _value_labels["crew_lineages"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var mono_f: Font = RETRO_THEME.get_monospace_font()
			var items: Array = data.get("crew_lineages", [])
			if items.is_empty():
				pass
			else:
				for item in items:
					assert(item is Dictionary, "[UI CONTRACT ERROR] Expected Dictionary in list payload for: crew_lineages")
					assert(item.has("establishment_id"), "[UI CONTRACT ERROR] Missing required key 'establishment_id' in item: " + str(item))
					var key_val = item["establishment_id"]
					var main_txt: String = str(item.get("name", "Unnamed"))
					var sub_txt: String = str(item.get("category_title", ""))
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
					btn.pressed.connect(func(): item_selected.emit("OPERATIVE_DETAIL", key_val))
					ctrl.add_child(btn)
	if _value_labels.has("vital_records_list"):
		var ctrl = _value_labels["vital_records_list"]
		if ctrl is ItemList:
			ctrl.clear()
			if data.has("vital_records") and data["vital_records"] is Array:
				var items: Array = data["vital_records"]
				for item in items:
					ctrl.add_item(str(item))

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
