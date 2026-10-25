# res://scenes/ui/filofax/filofax_district_docket.gd
class_name FilofaxDistrictDocket
extends VBoxContainer

const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")

@export_file("*.json") var ui_spec_path: String = "res://data_modules/core/feedback/spatial/district_ui.json"

var _ui_spec: Dictionary = {}
var _current_block_id: String = ""

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_load_ui_specification()

func _load_ui_specification() -> void:
	assert(FileAccess.file_exists(ui_spec_path), "FATAL: district_ui.json missing at: %s" % ui_spec_path)
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
		assert(parsed is Dictionary, "FATAL: district_ui.json root must be a Dictionary")
		assert(parsed.has("sections"), "FATAL: district_ui.json must declare 'sections'")
		assert(parsed.has("establishment_section"), "FATAL: district_ui.json must declare 'establishment_section'")
		assert(parsed.has("styling"), "FATAL: district_ui.json must declare 'styling'")
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

	# 5. Render Local Establishments
	# var estab_spec: Dictionary = _ui_spec.get("establishment_section", {})
	# _build_establishments(estab_spec, data.get("establishments_summary", []), styling)

	# 6. Render Live Clickable Establishments from SQLite
	_build_establishments_section(block_id, styling)

func _clear_docket() -> void:
	for child in get_children():
		child.queue_free()

func _build_header(data: Dictionary) -> void:
	var title_lbl := Label.new()
	title_lbl.text = str(data.get("display_name", _current_block_id)).to_upper()
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.modulate = Color.from_string("#D4AF37", Color.GOLD)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(title_lbl)

	var archetype_lbl := Label.new()
	archetype_lbl.text = "Classification: %s" % str(data.get("district_type", "")).capitalize().replace("_", " ")
	archetype_lbl.add_theme_font_size_override("font_size", 10)
	archetype_lbl.modulate = Color.from_string("#A0A0A0", Color.GRAY)
	archetype_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	archetype_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(archetype_lbl)

	var sep := HSeparator.new()
	sep.modulate.a = 0.5
	add_child(sep)

## Builds the live establishment list header and clickable items
func _build_section(section_spec: Dictionary, data: Dictionary, styling: Dictionary) -> void:
	var header := Label.new()
	header.text = "\n[ %s ]" % str(section_spec.get("header_label", "SECTION")).to_upper()
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#D4AF37")), Color.GOLD)
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
		lbl_name.modulate = Color.from_string(str(styling.get("label_color", "#B0B0B0")), Color.LIGHT_GRAY)

		var lbl_val := Label.new()
		lbl_val.text = formatted_val
		lbl_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_val.modulate = Color.from_string(str(styling.get("value_color", "#FFFFFF")), Color.WHITE)

		grid.add_child(lbl_name)
		grid.add_child(lbl_val)

	var sep := HSeparator.new()
	sep.modulate.a = float(styling.get("separator_alpha", 0.25))
	add_child(sep)

## Builds the live establishment list header and clickable items
func _build_establishments_section(district_id: String, styling: Dictionary) -> void:
	var header := Label.new()
	header.text = "\n[ LOCAL TRADE & CIVIC ESTABLISHMENTS ]"
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#D4AF37")), Color.GOLD)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)

	# Query live database via SocietyQueries
	var est_rows: Array = SOCIETY_QUERIES.get_district_establishments(district_id)

	if est_rows.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "• Purely Residential / No registered businesses."
		empty_lbl.modulate = Color.GRAY
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

## Displays the sub-docket for the clicked establishment
func open_establishment_sub_docket(estab_id: int) -> void:
	var docket: Dictionary = SOCIETY_QUERIES.get_establishment_docket(estab_id)
	if docket.is_empty():
		push_error("Failed to load docket for establishment #%d" % estab_id)
		return

	# Clear district view to display the establishment dossier
	_clear_docket()

	# 1. Back Button
	var back_btn := Button.new()
	back_btn.text = "⬅ Back to District Dossier"
	back_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(func(): display_district(_current_block_id))
	add_child(back_btn)

	var sep := HSeparator.new()
	sep.modulate.a = 0.5
	add_child(sep)

	# 2. Add RichTextLabel for wrapped, formatted docket text
	var detail_text := RichTextLabel.new()
	detail_text.bbcode_enabled = true
	detail_text.fit_content = true
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(detail_text)

	var cat_code: String = docket.get("category_code", "")

	# Case A: Residential Unit
	if cat_code == "RESIDENTIAL_UNIT":
		var hh_list: Array = docket.get("household", [])
		var res_list: Array = docket.get("residents", [])

		var bbcode := "[b][color=#D4AF37]=== RESIDENTIAL TENANCY ===[/color][/b]\n"
		bbcode += "[b]Property:[/b] %s\n" % docket.get("name", "")
		bbcode += "[b]Door Number:[/b] %s | [b]Ward:[/b] %s\n" % [
			docket.get("unit_door_number", "1"), docket.get("district_name", "")
		]

		if hh_list.is_empty() or int(docket.get("is_vacant", 0)) == 1:
			bbcode += "\n[color=#EF4444]STATUS: VACANT TENANCY[/color]\n"
		else:
			var hh: Dictionary = hh_list[0]
			bbcode += "[b]Tenure Type:[/b] %s\n" % hh.get("residence_type", "Standard")
			bbcode += "[b]Local Taproom:[/b] %s\n" % hh.get("local_pub_name", "None")
			bbcode += "[b]Demographic:[/b] %s | %s\n\n" % [hh.get("ethnicity", "Local"), hh.get("religion", "Secular")]
			bbcode += "[b][color=#D4AF37]--- RESIDENTS IN HOUSEHOLD (%d) ---[/color][/b]\n" % res_list.size()

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

		var bbcode := "[b][color=#D4AF37]=== %s ===[/color][/b]\n" % docket.get("name", "Establishment")
		bbcode += "[b]Class:[/b] %s (%s)\n" % [docket.get("category_title", "Commercial"), docket.get("owning_entity", "Local Enterprise")]
		bbcode += "[b]Ward:[/b] %s (Grid: %d, %d)\n" % [docket.get("district_name", ""), int(docket.get("grid_x", 0)), int(docket.get("grid_z", 0))]
		bbcode += "[b]Operational Capacity:[/b] %d\n\n" % int(docket.get("capacity", 0))

		bbcode += "[b][color=#38BDF8]--- MARKET CATCHMENT (SURROUNDING 9 BLOCKS) ---[/color][/b]\n"
		bbcode += "• Potential Customers: [b]%d residents[/b] across [b]%d households[/b]\n" % [
			int(market.get("total_catchment_population", 0)),
			int(market.get("total_catchment_households", 0))
		]
		bbcode += "• Avg. Neighborhood Disposable Income: [b]£%.2f / week[/b]\n\n" % float(market.get("avg_neighbor_disposable_income", 0.0))

		bbcode += "[b][color=#38BDF8]--- ACTIVE PAYROLL (%d on staff) ---[/color][/b]\n" % employees.size()
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
	lbl.modulate = Color.GRAY
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(lbl)
