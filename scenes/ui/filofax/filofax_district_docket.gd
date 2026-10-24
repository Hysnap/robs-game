# res://scenes/ui/filofax/filofax_district_docket.gd
class_name FilofaxDistrictDocket
extends VBoxContainer

@export_file("*.json") var ui_spec_path: String = "res://data_modules/core/feedback/spatial/district_ui.json"

var _ui_spec: Dictionary = {}
var _current_block_id: String = ""

func _ready() -> void:
	_load_ui_specification()

func _load_ui_specification() -> void:
	if not _ui_spec.is_empty():
		return
	assert(FileAccess.file_exists(ui_spec_path), "FATAL: district_ui.json missing at: %s" % ui_spec_path)
	var file := FileAccess.open(ui_spec_path, FileAccess.READ)
	assert(file != null, "FATAL: Unable to open UI spec file at: %s" % ui_spec_path)
	
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	
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
	var estab_spec: Dictionary = _ui_spec.get("establishment_section", {})
	_build_establishments(estab_spec, data.get("establishments_summary", []), styling)

func _clear_docket() -> void:
	for child in get_children():
		child.queue_free()

func _build_header(data: Dictionary) -> void:
	var title_lbl := Label.new()
	title_lbl.text = str(data.get("display_name", _current_block_id)).to_upper()
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.modulate = Color.from_string("#D4AF37", Color.GOLD)
	add_child(title_lbl)

	var archetype_lbl := Label.new()
	archetype_lbl.text = "Classification: %s" % str(data.get("district_type", "")).capitalize().replace("_", " ")
	archetype_lbl.add_theme_font_size_override("font_size", 11)
	archetype_lbl.modulate = Color.from_string("#A0A0A0", Color.GRAY)
	add_child(archetype_lbl)

	var sep := HSeparator.new()
	sep.modulate.a = 0.5
	add_child(sep)

func _build_section(section_spec: Dictionary, data: Dictionary, styling: Dictionary) -> void:
	var header := Label.new()
	header.text = "\n[ %s ]" % str(section_spec.get("header_label", "SECTION")).to_upper()
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#D4AF37")), Color.GOLD)
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

func _build_establishments(estab_spec: Dictionary, estabs: Array, styling: Dictionary) -> void:
	var header := Label.new()
	header.text = "\n[ %s ]" % str(estab_spec.get("header_label", "LOCAL TRADE & CIVIC ESTABLISHMENTS")).to_upper()
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#D4AF37")), Color.GOLD)
	add_child(header)

	if estabs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = str(estab_spec.get("empty_text", "• Purely Residential / Undeveloped"))
		empty_lbl.modulate = Color.from_string(str(styling.get("empty_color", "#808080")), Color.GRAY)
		add_child(empty_lbl)
		return

	var row_tpl: String = str(estab_spec.get("row_template", "• {name} [{category}]: Capacity {capacity}"))
	for item in estabs:
		var name_str = str(item.get("name", "Establishment"))
		var cat_str = str(item.get("category_title", item.get("venue_type", "Commercial"))).capitalize()
		var cap_val = int(item.get("capacity", item.get("count", 0)))

		var row_lbl := Label.new()
		row_lbl.text = row_tpl.replace("{name}", name_str).replace("{category}", cat_str).replace("{capacity}", str(cap_val))
		add_child(row_lbl)

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
	add_child(lbl)