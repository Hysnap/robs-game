# AUTO-GENERATED CODE - DO NOT EDIT MANUALLY
# Compiled from: res://data_modules/core/ui_schemas/views/org_management_docket.json
extends VBoxContainer

signal action_clicked(action_code: String, payload: Dictionary)
signal item_selected(target_route: String, filter_key: Variant)

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
	hdr_header_section.text = "[ " + tr("UI_ORG_CHART_TITLE").to_upper() + " ]"
	hdr_header_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_header_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_header_section.add_theme_font_override("font", mono_font)
	hdr_header_section.add_theme_color_override("font_color", clr_blue)
	sec_header_section.add_child(hdr_header_section)
	var sep_header_section := HSeparator.new()
	sec_header_section.add_child(sep_header_section)
	add_child(sec_header_section)

	# --- Header Block ---
	var box_org_header := VBoxContainer.new()
	box_org_header.name = "org_header"
	box_org_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_org_header.add_theme_constant_override("separation", 0)
	var title_org_header := Label.new()
	title_org_header.name = "org_header_title"
	title_org_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_org_header.theme_type_variation = &"HeaderTitle"
	title_org_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_org_header.add_child(title_org_header)
	_value_labels["org_header_title"] = title_org_header
	var sub_org_header := Label.new()
	sub_org_header.name = "org_header_subtitle"
	sub_org_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_org_header.theme_type_variation = &"HeaderSubtitle"
	sub_org_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_org_header.add_child(sub_org_header)
	_value_labels["org_header_subtitle"] = sub_org_header
	box_org_header.add_child(HSeparator.new())
	add_child(box_org_header)

	var row_active_mandate_count := HBoxContainer.new()
	row_active_mandate_count.name = "active_mandate_count"
	row_active_mandate_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_active_mandate_count := Label.new()
	lbl_active_mandate_count.text = tr("UI_LBL_ACTIVE_MANDATES")
	lbl_active_mandate_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_active_mandate_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_active_mandate_count.add_child(lbl_active_mandate_count)
	var val_active_mandate_count := Label.new()
	val_active_mandate_count.name = "active_mandate_count_value"
	val_active_mandate_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_active_mandate_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_active_mandate_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_active_mandate_count.add_child(val_active_mandate_count)
	_value_labels["active_mandate_count"] = val_active_mandate_count
	add_child(row_active_mandate_count)

	var row_arms_length_count := HBoxContainer.new()
	row_arms_length_count.name = "arms_length_count"
	row_arms_length_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_arms_length_count := Label.new()
	lbl_arms_length_count.text = tr("UI_LBL_ARMS_LENGTH_ORGS")
	lbl_arms_length_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_arms_length_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row_arms_length_count.add_child(lbl_arms_length_count)
	var val_arms_length_count := Label.new()
	val_arms_length_count.name = "arms_length_count_value"
	val_arms_length_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_arms_length_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_arms_length_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_arms_length_count.add_child(val_arms_length_count)
	_value_labels["arms_length_count"] = val_arms_length_count
	add_child(row_arms_length_count)

	# --- Section: org_hierarchy_section ---
	var sec_org_hierarchy_section := VBoxContainer.new()
	sec_org_hierarchy_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_org_hierarchy_section.add_theme_constant_override("separation", 2)
	var hdr_org_hierarchy_section := Label.new()
	hdr_org_hierarchy_section.text = "[ " + tr("UI_ORG_HIERARCHY_HDR").to_upper() + " ]"
	hdr_org_hierarchy_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_org_hierarchy_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_org_hierarchy_section.add_theme_font_override("font", mono_font)
	hdr_org_hierarchy_section.add_theme_color_override("font_color", clr_blue)
	sec_org_hierarchy_section.add_child(hdr_org_hierarchy_section)
	var sep_org_hierarchy_section := HSeparator.new()
	sec_org_hierarchy_section.add_child(sep_org_hierarchy_section)
	add_child(sec_org_hierarchy_section)

	var civic_box_org_hierarchy_list := VBoxContainer.new()
	civic_box_org_hierarchy_list.name = "org_hierarchy_list"
	civic_box_org_hierarchy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_org_hierarchy_list.add_theme_constant_override("separation", 2)
	_value_labels["org_hierarchy_list"] = civic_box_org_hierarchy_list
	add_child(civic_box_org_hierarchy_list)

	# --- Section: active_mandates_section ---
	var sec_active_mandates_section := VBoxContainer.new()
	sec_active_mandates_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_active_mandates_section.add_theme_constant_override("separation", 2)
	var hdr_active_mandates_section := Label.new()
	hdr_active_mandates_section.text = "[ " + tr("UI_ORG_MANDATES_HDR").to_upper() + " ]"
	hdr_active_mandates_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_active_mandates_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_active_mandates_section.add_theme_font_override("font", mono_font)
	hdr_active_mandates_section.add_theme_color_override("font_color", clr_blue)
	sec_active_mandates_section.add_child(hdr_active_mandates_section)
	var sep_active_mandates_section := HSeparator.new()
	sec_active_mandates_section.add_child(sep_active_mandates_section)
	add_child(sec_active_mandates_section)

	var civic_box_mandate_cards := VBoxContainer.new()
	civic_box_mandate_cards.name = "mandate_cards"
	civic_box_mandate_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_mandate_cards.add_theme_constant_override("separation", 2)
	_value_labels["mandate_cards"] = civic_box_mandate_cards
	add_child(civic_box_mandate_cards)

	var btn_btn_create_mandate := Button.new()
	btn_btn_create_mandate.name = "btn_create_mandate"
	btn_btn_create_mandate.text = tr("UI_BTN_CREATE_MANDATE")
	btn_btn_create_mandate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_create_mandate.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_create_mandate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_create_mandate.pressed.connect(func(): self.action_clicked.emit("create_org_mandate", {}))
	_value_labels["btn_create_mandate"] = btn_btn_create_mandate
	add_child(btn_btn_create_mandate)

	var btn_btn_grant_assistance := Button.new()
	btn_btn_grant_assistance.name = "btn_grant_assistance"
	btn_btn_grant_assistance.text = tr("UI_BTN_GRANT_ASSISTANCE")
	btn_btn_grant_assistance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_grant_assistance.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_grant_assistance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_grant_assistance.pressed.connect(func(): self.action_clicked.emit("grant_mandate_assistance", {}))
	_value_labels["btn_grant_assistance"] = btn_btn_grant_assistance
	add_child(btn_btn_grant_assistance)

	var btn_btn_revoke_mandate := Button.new()
	btn_btn_revoke_mandate.name = "btn_revoke_mandate"
	btn_btn_revoke_mandate.text = tr("UI_BTN_REVOKE_MANDATE")
	btn_btn_revoke_mandate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_btn_revoke_mandate.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_btn_revoke_mandate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_btn_revoke_mandate.pressed.connect(func(): self.action_clicked.emit("revoke_org_mandate", {}))
	_value_labels["btn_revoke_mandate"] = btn_btn_revoke_mandate
	add_child(btn_btn_revoke_mandate)

	# --- Section: collisions_and_reports_section ---
	var sec_collisions_and_reports_section := VBoxContainer.new()
	sec_collisions_and_reports_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_collisions_and_reports_section.add_theme_constant_override("separation", 2)
	var hdr_collisions_and_reports_section := Label.new()
	hdr_collisions_and_reports_section.text = "[ " + tr("UI_ORG_COLLISIONS_HDR").to_upper() + " ]"
	hdr_collisions_and_reports_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_collisions_and_reports_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_collisions_and_reports_section.add_theme_font_override("font", mono_font)
	hdr_collisions_and_reports_section.add_theme_color_override("font_color", clr_blue)
	sec_collisions_and_reports_section.add_child(hdr_collisions_and_reports_section)
	var sep_collisions_and_reports_section := HSeparator.new()
	sec_collisions_and_reports_section.add_child(sep_collisions_and_reports_section)
	add_child(sec_collisions_and_reports_section)

	var civic_box_collision_cards := VBoxContainer.new()
	civic_box_collision_cards.name = "collision_cards"
	civic_box_collision_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	civic_box_collision_cards.add_theme_constant_override("separation", 2)
	_value_labels["collision_cards"] = civic_box_collision_cards
	add_child(civic_box_collision_cards)

	# --- Inscriptions Container: manager_memos_section ---
	var hdr_manager_memos_section := Label.new()
	hdr_manager_memos_section.text = "[ " + tr("UI_SEC_MANAGER_MEMOS").to_upper() + " ]"
	hdr_manager_memos_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_manager_memos_section.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_manager_memos_section.add_theme_font_override("font", mono_font)
	hdr_manager_memos_section.add_theme_color_override("font_color", clr_blue)
	add_child(hdr_manager_memos_section)
	var insc_list_manager_memos_section := VBoxContainer.new()
	insc_list_manager_memos_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_labels["__inscriptions__"] = insc_list_manager_memos_section
	add_child(insc_list_manager_memos_section)

func bind_data(data: Dictionary) -> void:
	if _value_labels.has("org_header_title"):
		if data.has("enterprise_title") and data["enterprise_title"] != null:
			_value_labels["org_header_title"].text = str(data["enterprise_title"]).to_upper()
		else:
			_value_labels["org_header_title"].text = "--- UNNAMED ---"
	if _value_labels.has("org_header_subtitle"):
		if data.has("cycle_summary") and data["cycle_summary"] != null:
			_value_labels["org_header_subtitle"].text = str(data["cycle_summary"]).to_upper()
		else:
			_value_labels["org_header_subtitle"].text = ""
	if _value_labels.has("active_mandate_count"):
		var ctrl = _value_labels["active_mandate_count"]
		if not data.has("active_mandate_count") or data["active_mandate_count"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["active_mandate_count"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + ""
	if _value_labels.has("arms_length_count"):
		var ctrl = _value_labels["arms_length_count"]
		if not data.has("arms_length_count") or data["arms_length_count"] == null:
			ctrl.text = tr("UI_INTEL_MASKED_BLANK")
		else:
			var val_str := str(int(data["arms_length_count"]))
			ctrl.text = tr("FMT_INT").replace("{val}", val_str) + ""
	if _value_labels.has("org_hierarchy_list"):
		var ctrl = _value_labels["org_hierarchy_list"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var mono_f: Font = RETRO_THEME.get_monospace_font()
			var items: Array = data.get("organization_nodes", [])
			if items.is_empty():
				pass
			else:
				for item in items:
					assert(item is Dictionary, "[UI CONTRACT ERROR] Expected Dictionary in list payload for: organization_nodes")
					assert(item.has("org_id"), "[UI CONTRACT ERROR] Missing required key 'org_id' in item: " + str(item))
					var key_val = item["org_id"]
					var main_txt: String = str(item.get("display_name", "Unnamed"))
					var sub_txt: String = str(item.get("status_summary", ""))
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
					btn.pressed.connect(func(): item_selected.emit("ORG_NODE_SELECTED", key_val))
					ctrl.add_child(btn)
	if _value_labels.has("mandate_cards"):
		var ctrl = _value_labels["mandate_cards"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var mono_f: Font = RETRO_THEME.get_monospace_font()
			var items: Array = data.get("active_mandates", [])
			if items.is_empty():
				pass
			else:
				for item in items:
					assert(item is Dictionary, "[UI CONTRACT ERROR] Expected Dictionary in list payload for: active_mandates")
					assert(item.has("mandate_id"), "[UI CONTRACT ERROR] Missing required key 'mandate_id' in item: " + str(item))
					var key_val = item["mandate_id"]
					var main_txt: String = str(item.get("title", "Unnamed"))
					var sub_txt: String = str(item.get("scope_summary", ""))
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
					btn.pressed.connect(func(): item_selected.emit("MANDATE_SELECTED", key_val))
					ctrl.add_child(btn)
	if _value_labels.has("collision_cards"):
		var ctrl = _value_labels["collision_cards"]
		if ctrl is Container:
			for c in ctrl.get_children():
				c.free()
			var clr_m: Color = RETRO_THEME.get_ink_color("muted")
			var clr_b: Color = RETRO_THEME.get_ink_color("body")
			var mono_f: Font = RETRO_THEME.get_monospace_font()
			var items: Array = data.get("dyadic_collisions", [])
			if items.is_empty():
				pass
			else:
				for item in items:
					assert(item is Dictionary, "[UI CONTRACT ERROR] Expected Dictionary in list payload for: dyadic_collisions")
					assert(item.has("collision_key"), "[UI CONTRACT ERROR] Missing required key 'collision_key' in item: " + str(item))
					var key_val = item["collision_key"]
					var main_txt: String = str(item.get("outcome_label", "Unnamed"))
					var sub_txt: String = str(item.get("overlap_summary", ""))
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
					btn.pressed.connect(func(): item_selected.emit("COLLISION_SELECTED", key_val))
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
