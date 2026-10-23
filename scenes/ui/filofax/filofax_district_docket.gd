# res://scenes/ui/filofax/filofax_district_docket.gd
class_name FilofaxDistrictDocket
extends Control

@export var title_label: Label
@export var archetype_label: Label
@export var sections_container: VBoxContainer

@export_file("*.json") var ui_spec_path: String = "res://data_modules/core/feedback/spatial/district_ui.json"

var _ui_spec: Dictionary = {}

func _ready() -> void:
	assert(title_label != null, "FATAL: title_label must be assigned in inspector")
	assert(archetype_label != null, "FATAL: archetype_label must be assigned in inspector")
	assert(sections_container != null, "FATAL: sections_container must be assigned in inspector")
	_load_ui_specification()

func _load_ui_specification() -> void:
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

## Renders the district docket dynamically from the external JSON schema
func display_district(block_id: String) -> void:
	if _ui_spec.is_empty():
		_load_ui_specification()

	var data: Dictionary = GameState.get_district_view(block_id)
	if data.is_empty():
		push_error("[FilofaxDistrictDocket] No data returned for block_id: %s" % block_id)
		return

	# Header (Direct Reality)
	title_label.text = str(data.get("display_name", block_id))
	archetype_label.text = str(data.get("district_type", "")).capitalize()

	# Clear previous dynamically generated rows
	for child in sections_container.get_children():
		child.queue_free()

	var styling: Dictionary = _ui_spec["styling"]

	# 1. Dynamically render metrics sections
	var sections: Array = _ui_spec.get("sections", [])
	for sec in sections:
		_build_section(sec, data, styling)

	# 2. Dynamically render establishment directory
	var estab_spec: Dictionary = _ui_spec.get("establishment_section", {})
	_build_establishments(estab_spec, data.get("establishments_summary", []), styling)

func _build_section(section_spec: Dictionary, data: Dictionary, styling: Dictionary) -> void:
	assert(section_spec.has("header_label"), "FATAL: Section missing 'header_label'")
	assert(section_spec.has("fields"), "FATAL: Section missing 'fields'")

	# Header Label
	var header := Label.new()
	header.text = str(section_spec["header_label"])
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#FFFFFF")), Color.WHITE)
	sections_container.add_child(header)

	# 2-Column Grid for Field Rows
	var grid := GridContainer.new()
	grid.columns = int(styling.get("grid_columns", 2))
	grid.add_theme_constant_override("h_separation", int(styling.get("grid_h_separation", 16)))
	grid.add_theme_constant_override("v_separation", int(styling.get("grid_v_separation", 4)))
	sections_container.add_child(grid)

	for field in section_spec.get("fields", []):
		assert(field.has("key"), "FATAL: Metric field definition missing 'key'")
		assert(field.has("label"), "FATAL: Metric field definition missing 'label'")
		assert(field.has("format"), "FATAL: Metric field definition missing 'format'")
		
		var key: String = str(field["key"])
		if not data.has(key):
			continue

		var val = data[key]
		var formatted_val: String = _format_value(val, field)

		var lbl_name := Label.new()
		lbl_name.text = str(field["label"])
		lbl_name.modulate = Color.from_string(str(styling.get("label_color", "#B0B0B0")), Color.LIGHT_GRAY)

		var lbl_val := Label.new()
		lbl_val.text = formatted_val
		lbl_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_val.modulate = Color.from_string(str(styling.get("value_color", "#FFFFFF")), Color.WHITE)

		grid.add_child(lbl_name)
		grid.add_child(lbl_val)

	# Visual Ledger Separator
	var sep := HSeparator.new()
	sep.modulate.a = float(styling.get("separator_alpha", 0.2))
	sections_container.add_child(sep)

func _build_establishments(estab_spec: Dictionary, estabs: Array, styling: Dictionary) -> void:
	assert(estab_spec.has("header_label"), "FATAL: Establishment spec missing 'header_label'")
	assert(estab_spec.has("empty_text"), "FATAL: Establishment spec missing 'empty_text'")
	assert(estab_spec.has("row_template"), "FATAL: Establishment spec missing 'row_template'")

	var header := Label.new()
	header.text = str(estab_spec["header_label"])
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#FFFFFF")), Color.WHITE)
	sections_container.add_child(header)

	if estabs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = str(estab_spec["empty_text"])
		empty_lbl.modulate = Color.from_string(str(styling.get("empty_color", "#808080")), Color.GRAY)
		sections_container.add_child(empty_lbl)
		return

	var row_tpl: String = str(estab_spec["row_template"])
	for item in estabs:
		var name_str = str(item.get("venue_type", "")).capitalize()
		var count_val = int(item.get("count", 0))
		var row_lbl := Label.new()
		row_lbl.text = row_tpl.replace("{name}", name_str).replace("{count}", str(count_val))
		sections_container.add_child(row_lbl)

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
			# Converts decimal ratios (0.18 -> 18.0%) or handles already scaled values
			var pct = float(val) * 100.0 if float(val) <= 1.0 and float(val) > 0.0 else float(val)
			return "%s%.*f%%%s" % [prefix, decimals, pct, suffix]
		"CURRENCY":
			return "%s%.*f%s" % [prefix, decimals, float(val), suffix]
		_:
			return "%s%s%s" % [prefix, str(val), suffix]