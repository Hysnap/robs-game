# res://scenes/ui/filofax/filofax_district_docket.gd
class_name FilofaxDistrictDocket
extends VBoxContainer

const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")
const RETRO_THEME = preload("res://scenes/ui/filofax/retro_theme.gd")

@export_file("*.json") var ui_spec_path: String = "res://data_modules/core/feedback/spatial/district_ui.json"

var _ui_spec: Dictionary = {}
var _current_block_id: String = ""

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_load_ui_specification()

func _load_ui_specification() -> void:
	if not _ui_spec.is_empty():
		return
	if not FileAccess.file_exists(ui_spec_path):
		return
	var file := FileAccess.open(ui_spec_path, FileAccess.READ)
	if file == null:
		return
	
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_ui_spec = parsed

## Renders the district docket dynamically using the single block_id key
func display_district(block_id: String) -> void:
	assert(not block_id.is_empty(), "FATAL: FilofaxDistrictDocket received empty block_id")
	_current_block_id = block_id

	# 1. Clear previous rows to guarantee no duplicate/stacked content
	_clear_docket()

	if _ui_spec.is_empty():
		_load_ui_specification()

	# 2. Fetch ground truth from GameState
	var data: Dictionary = GameState.get_district_view(block_id)
	if data.is_empty():
		_render_empty_state("No municipal records found for: %s" % block_id)
		return

	var styling: Dictionary = _ui_spec.get("styling", {})

	# 3. Render Header
	_build_header(data)

	# 4. Render Metrics Sections
	var sections: Array = _ui_spec.get("sections", [])
	for sec in sections:
		_build_section(sec, data, styling)

	# 5. Render Live Clickable Establishments from SQLite
	_build_establishments_section(block_id, styling)

func _clear_docket() -> void:
	for child in get_children():
		child.queue_free()

func _create_ruled_separator() -> HSeparator:
	var sep := HSeparator.new()
	var line_style := StyleBoxLine.new()
	line_style.color = RETRO_THEME.color_ruled_line
	line_style.thickness = 1
	sep.add_theme_stylebox_override("separator", line_style)
	return sep

func _build_header(data: Dictionary) -> void:
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	var title_lbl := Label.new()
	title_lbl.text = str(data.get("display_name", _current_block_id)).to_upper()
	title_lbl.add_theme_font_override("font", mono_font)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(title_lbl)

	var archetype_lbl := Label.new()
	archetype_lbl.text = "Classification: %s" % str(data.get("district_type", "")).capitalize().replace("_", " ")
	archetype_lbl.add_theme_font_override("font", mono_font)
	archetype_lbl.add_theme_font_size_override("font_size", 11)
	archetype_lbl.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	archetype_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	archetype_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(archetype_lbl)

	add_child(_create_ruled_separator())

func _build_section(section_spec: Dictionary, data: Dictionary, styling: Dictionary) -> void:
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	var header := Label.new()
	header.text = "\n[ %s ]" % str(section_spec.get("header_label", "SECTION")).to_upper()
	header.add_theme_font_override("font", mono_font)
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 12)))
	header.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)

	var grid := GridContainer.new()
	grid.columns = int(styling.get("grid_columns", 2))
	grid.add_theme_constant_override("h_separation", int(styling.get("grid_h_separation", 16)))
	grid.add_theme_constant_override("v_separation", int(styling.get("grid_v_separation", 4)))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)

	for field in section_spec.get("fields", []):
		var key: String = str(field["key"])
		if not data.has(key):
			continue

		var val = data[key]
		var formatted_val: String = _format_value(val, field)

		var lbl_name := Label.new()
		lbl_name.text = "• " + str(field.get("label", key)) + ":"
		lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_name.add_theme_font_override("font", mono_font)
		lbl_name.add_theme_font_size_override("font_size", 11)
		lbl_name.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)

		var lbl_val := Label.new()
		lbl_val.text = formatted_val
		lbl_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_val.add_theme_font_override("font", mono_font)
		lbl_val.add_theme_font_size_override("font_size", 11)
		
		# Police heat warning indicator check
		if key == "actual_police_heat" and float(val) >= 0.5:
			lbl_val.add_theme_color_override("font_color", RETRO_THEME.color_ink_warning)
		else:
			lbl_val.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)

		grid.add_child(lbl_name)
		grid.add_child(lbl_val)

	add_child(_create_ruled_separator())

func _build_establishments_section(district_id: String, styling: Dictionary) -> void:
	var mono_font: Font = RETRO_THEME.get_monospace_font()

	var header := Label.new()
	header.text = "\n[ LOCAL TRADE & CIVIC ESTABLISHMENTS ]"
	header.add_theme_font_override("font", mono_font)
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 12)))
	header.add_theme_color_override("font_color", RETRO_THEME.color_ink_accent)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)

	var est_rows: Array = SOCIETY_QUERIES.get_district_establishments(district_id)

	if est_rows.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "• Purely Residential / No registered businesses."
		empty_lbl.add_theme_font_override("font", mono_font)
		empty_lbl.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(empty_lbl)
		return

	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	add_child(list_box)

	for row in est_rows:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_override("font", mono_font)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
		btn.add_theme_color_override("font_hover_color", RETRO_THEME.color_ink_accent)

		var cat: String = str(row.get("category_code", ""))
		var e_id: int = int(row["establishment_id"])
		var e_name: String = str(row.get("name", "Unnamed"))

		if cat == "RESIDENTIAL_UNIT":
			btn.text = "🏠 %s" % e_name
		elif cat == "COMMERCIAL":
			btn.text = "🏬 %s (%d staff)" % [e_name, int(row.get("worker_count", 0))]
		elif cat == "INDUSTRIAL":
			btn.text = "🏭 %s (%d workers)" % [e_name, int(row.get("worker_count", 0))]
		else:
			btn.text = "🏛️ %s (%s)" % [e_name, str(row.get("category_title", "Civic"))]

		btn.pressed.connect(open_establishment_sub_docket.bind(e_id))
		list_box.add_child(btn)

func open_establishment_sub_docket(estab_id: int) -> void:
	var docket: Dictionary = SOCIETY_QUERIES.get_establishment_docket(estab_id)
	
	if docket.is_empty():
		push_error("Failed to load docket for establishment #%d" % estab_id)
		return

	_clear_docket()

	var mono_font: Font = RETRO_THEME.get_monospace_font()

	# 1. Back Button
	var back_btn := Button.new()
	back_btn.text = "⬅ Back to District Dossier"
	back_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.add_theme_font_override("font", mono_font)
	back_btn.add_theme_font_size_override("font_size", 11)
	back_btn.add_theme_color_override("font_color", RETRO_THEME.color_ink_body)
	back_btn.add_theme_color_override("font_hover_color", RETRO_THEME.color_ink_accent)
	back_btn.pressed.connect(func(): display_district(_current_block_id))
	add_child(back_btn)

	add_child(_create_ruled_separator())

	# 2. Add RichTextLabel for wrapped, formatted docket text
	var detail_text := RichTextLabel.new()
	detail_text.bbcode_enabled = true
	detail_text.fit_content = true
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_text.add_theme_font_override("normal_font", mono_font)
	detail_text.add_theme_font_size_override("normal_font_size", 11)
	detail_text.add_theme_color_override("default_color", RETRO_THEME.color_ink_body)
	add_child(detail_text)

	var cat_code: String = docket.get("category_code", "")

	# Case A: Residential Unit
	if cat_code == "RESIDENTIAL_UNIT":
		var hh_list: Array = docket.get("household", [])
		var res_list: Array = docket.get("residents", [])

		var bbcode := "[b][color=%s]=== RESIDENTIAL TENANCY ===[/color][/b]\n" % RETRO_THEME.color_ink_accent.to_html()
		bbcode += "[b]Property:[/b] %s\n" % docket.get("name", "")
		bbcode += "[b]Door Number:[/b] %s | [b]Ward:[/b] %s\n" % [
			docket.get("unit_door_number", "1"), docket.get("district_name", "")
		]

		if hh_list.is_empty() or int(docket.get("is_vacant", 0)) == 1:
			bbcode += "\n[color=%s]STATUS: VACANT TENANCY[/color]\n" % RETRO_THEME.color_ink_warning.to_html()
		else:
			var hh: Dictionary = hh_list[0]
			bbcode += "[b]Tenure Type:[/b] %s\n" % hh.get("residence_type", "Standard")
			bbcode += "[b]Local Taproom:[/b] %s\n" % hh.get("local_pub_name", "None")
			bbcode += "[b]Demographic:[/b] %s | %s\n\n" % [hh.get("ethnicity", "Local"), hh.get("religion", "Secular")]
			bbcode += "[b][color=%s]--- RESIDENTS IN HOUSEHOLD (%d) ---[/color][/b]\n" %[RETRO_THEME.color_ink_accent.to_html(), res_list.size()]

			for r in res_list:
				var wage_str: String = "£%.2f/wk" % float(r["weekly_wage"]) if r.get("weekly_wage") != null else "Unwaged"
				var occ_str: String = str(r.get("occupation", "None")) if r.get("occupation") != null else "Unemployed"
				bbcode += "• [b]%s[/b] (%s, %d yrs)\n  Role: %s | Edu: %s | %s\n" % [
					r["full_name"], r["gender"], int(r["age"]), occ_str, r["education"], wage_str
				]

		detail_text.text = bbcode

	# Case B: Commercial / Industrial / Civic Anchor
	else:
		var market: Dictionary = docket.get("market_catchment", {})
		var employees: Array = docket.get("employees", [])
		var raw_income = market.get("avg_neighbor_disposable_income")
		var income: float = float(str(raw_income)) if raw_income != null else 0.0

		var bbcode := "[b][color=%s]=== %s ===[/color][/b]\n" %[ RETRO_THEME.color_ink_accent.to_html(), docket.get("name", "Establishment")]
		bbcode += "[b]Class:[/b] %s (%s)\n" % [docket.get("category_title", "Commercial"), docket.get("owning_entity", "Local Enterprise")]
		bbcode += "[b]Ward:[/b] %s (Grid: %d, %d)\n" % [docket.get("district_name", ""), int(docket.get("grid_x", 0)), int(docket.get("grid_z", 0))]
		bbcode += "[b]Operational Capacity:[/b] %d\n\n" % int(docket.get("capacity", 0))

		bbcode += "[b][color=%s]--- MARKET CATCHMENT (SURROUNDING 9 BLOCKS) ---[/color][/b]\n" % RETRO_THEME.color_ink_accent.to_html()
		bbcode += "• Potential Customers: [b]%d residents[/b] across [b]%d households[/b]\n" % [
			int(market.get("total_catchment_population", 0)),
			int(market.get("total_catchment_households", 0))
		]
		bbcode += "• Avg. Neighborhood Disposable Income: [b]£%.2f / week[/b]\n\n" % income

		bbcode += "[b][color=%s]--- ACTIVE PAYROLL (%d on staff) ---[/color][/b]\n" %[RETRO_THEME.color_ink_accent.to_html(), employees.size()]
		if employees.is_empty():
			bbcode += "• No formal livelihood contracts recorded.\n"
		else:
			for emp in employees:
				bbcode += "• %s - [i]%s[/i]\n  Contract: %s | %s | £%.2f/wk\n" % [
					emp["full_name"], emp["role_title"], emp["contract_class"], emp["schedule_window"], float(emp["weekly_pay"])
				]

		detail_text.text = bbcode

func _format_value(val, spec: Dictionary) -> String:
	var format_type: String = str(spec.get("format", "STRING")).to_upper()
	var prefix: String = str(spec.get("prefix", ""))
	var suffix: String = str(spec.get("suffix", ""))
	var decimals: int = int(spec.get("decimals", 2))

	match format_type:
		"INTEGER":
			return "%s%d%s" % [prefix, int(val), suffix]
		"FLOAT":
			return "%s%.*f%s" % [prefix, decimals, float(val), suffix]
		"PERCENT":
			var pct = float(val) * 100.0 if float(val) <= 1.0 and float(val) > 0.0 else float(val)
			return "%s%.*f%%%s" % [prefix, decimals, pct, suffix]
		"CURRENCY":
			return "%s%.*f%s" % [prefix, decimals, float(val), suffix]
		_:
			return "%s%s%s" % [prefix, str(val), suffix]

func _render_empty_state(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_override("font", RETRO_THEME.get_monospace_font())
	lbl.add_theme_color_override("font_color", RETRO_THEME.color_ink_muted)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(lbl)