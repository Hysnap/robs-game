# res://scenes/ui/filofax/filofax_district_docket.gd
class_name FilofaxDistrictDocket
extends VBoxContainer

@export var title_label: Label
@export var archetype_label: Label
@export var sections_container: VBoxContainer

@export_file("*.json") var ui_spec_path: String = "res://data_modules/core/feedback/spatial/district_ui.json"

var _ui_spec: Dictionary = {}

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
	if _ui_spec.is_empty():
		_load_ui_specification()

	var data: Dictionary = GameState.get_district_view(block_id)
	if data.is_empty():
		push_error("[FilofaxDistrictDocket] No data returned for block_id: %s" % block_id)
		return

	# 1. Header (Direct Reality)
	if title_label:
		title_label.text = str(data.get("display_name", block_id)).to_upper()
	if archetype_label:
		archetype_label.text = str(data.get("district_type", "")).capitalize().replace("_", " ")

	# 2. Clear previous dynamically generated rows
	if sections_container:
		for child in sections_container.get_children():
			child.queue_free()

	var styling: Dictionary = _ui_spec.get("styling", {})
	var target_container: VBoxContainer = sections_container if sections_container != null else self

	# 3. Dynamically render metrics sections
	var sections: Array = _ui_spec.get("sections", [])
	for sec in sections:
		_build_section(sec, data, styling, target_container)

	# 4. Dynamically render establishment directory
	var estab_spec: Dictionary = _ui_spec.get("establishment_section", {})
	_build_establishments(estab_spec, data.get("establishments_summary", []), styling, target_container)

func _build_section(section_spec: Dictionary, data: Dictionary, styling: Dictionary, parent_node: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "\n[ %s ]" % str(section_spec.get("header_label", "SECTION")).to_upper()
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#D4AF37")), Color.GOLD)
	parent_node.add_child(header)

	var grid := GridContainer.new()
	grid.columns = int(styling.get("grid_columns", 2))
	grid.add_theme_constant_override("h_separation", int(styling.get("grid_h_separation", 16)))
	grid.add_theme_constant_override("v_separation", int(styling.get("grid_v_separation", 4)))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_node.add_child(grid)

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
	parent_node.add_child(sep)

func _build_establishments(estab_spec: Dictionary, estabs: Array, styling: Dictionary, parent_node: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "\n[ %s ]" % str(estab_spec.get("header_label", "LOCAL TRADE & CIVIC ESTABLISHMENTS")).to_upper()
	header.add_theme_font_size_override("font_size", int(styling.get("header_font_size", 13)))
	header.modulate = Color.from_string(str(styling.get("header_color", "#D4AF37")), Color.GOLD)
	parent_node.add_child(header)

	if estabs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = str(estab_spec.get("empty_text", "• Purely Residential / Undeveloped"))
		empty_lbl.modulate = Color.from_string(str(styling.get("empty_color", "#808080")), Color.GRAY)
		parent_node.add_child(empty_lbl)
		return

	var row_tpl: String = str(estab_spec.get("row_template", "• {name} [{category}]: Capacity {capacity}"))
	for item in estabs:
		var name_str = str(item.get("name", "Establishment"))
		var cat_str = str(item.get("category_title", item.get("venue_type", "Commercial"))).capitalize()
		var cap_val = int(item.get("capacity", item.get("count", 0)))

		var row_lbl := Label.new()
		row_lbl.text = row_tpl.replace("{name}", name_str).replace("{category}", cat_str).replace("{capacity}", str(cap_val))
		parent_node.add_child(row_lbl)

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