# res://scenes/ui/hud/map_overlay_hud_bar.gd
class_name MapOverlayHudBar
extends HBoxContainer

signal overlay_selected(overlay_id: String)

const MapOverlayProjectorScript = preload("res://systems/multilayer_info_loop/map_overlay_projector.gd")
const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")

var _label_overlay: Label
var _overlay_option: OptionButton
var _legend_box: HBoxContainer
var _is_populating: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 10)
	_build_controls()
	populate_overlays()

func _build_controls() -> void:
	_label_overlay = Label.new()
	_label_overlay.name = "LblMapOverlay"
	_label_overlay.text = tr("UI_HUD_LBL_OVERLAY")
	_label_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label_overlay)

	_overlay_option = OptionButton.new()
	_overlay_option.name = "OptMapOverlay"
	_overlay_option.custom_minimum_size = Vector2(200, 38)
	_overlay_option.focus_mode = Control.FOCUS_NONE
	_overlay_option.item_selected.connect(_on_overlay_item_selected)
	add_child(_overlay_option)

	_legend_box = HBoxContainer.new()
	_legend_box.name = "LegendBox"
	_legend_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_box.add_theme_constant_override("separation", 8)
	_legend_box.visible = false
	add_child(_legend_box)

## Populates overlay options from MapOverlayProjector (map_overlay_profiles.json)
func populate_overlays(selected_id: String = "NONE") -> void:
	if _overlay_option == null:
		return

	_is_populating = true
	_overlay_option.clear()

	var overlays: Array[Dictionary] = MapOverlayProjectorScript.get_available_overlays()
	var target_id: String = selected_id.strip_edges().to_upper()
	var selected_idx: int = 0

	for i in range(overlays.size()):
		var entry: Dictionary = overlays[i]
		var ov_id: String = str(entry.get("id", "NONE")).to_upper()
		var tok: String = str(entry.get("label_token", "UI_OVERLAY_NONE"))
		_overlay_option.add_item(tr(tok), i)
		_overlay_option.set_item_metadata(i, ov_id)
		if ov_id == target_id:
			selected_idx = i

	if _overlay_option.item_count > 0:
		_overlay_option.select(selected_idx)

	_is_populating = false

## Programmatically updates selected overlay without re-emitting overlay_selected
func set_selected_overlay(overlay_id: String) -> void:
	if _overlay_option == null:
		return
	var target: String = overlay_id.strip_edges().to_upper()
	_is_populating = true
	for i in range(_overlay_option.item_count):
		if str(_overlay_option.get_item_metadata(i)).to_upper() == target:
			_overlay_option.select(i)
			break
	_is_populating = false

## Rebuilds the compact color/pattern legend chips from MapOverlayProjector output
func update_legend(legend_entries: Array) -> void:
	if _legend_box == null:
		return

	for child in _legend_box.get_children():
		_legend_box.remove_child(child)
		child.queue_free()

	if legend_entries.is_empty():
		_legend_box.visible = false
		return

	for item in legend_entries:
		if not (item is Dictionary):
			continue
		var swatch_color: Color = item.get("color", Color.GRAY)
		var pattern_mode: String = str(item.get("pattern_mode", "NONE")).to_upper()
		var label_tok: String = str(item.get("label_token", ""))

		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chip_hbox := HBoxContainer.new()
		chip_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_hbox.add_theme_constant_override("separation", 5)
		chip.add_child(chip_hbox)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.color = swatch_color
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_hbox.add_child(swatch)

		var lbl := Label.new()
		var text_str: String = tr(label_tok)
		if pattern_mode == "STALE_STRIPE" or pattern_mode == "CONFLICT_STRIPE" or pattern_mode == "FOG_HATCH":
			text_str = "[//] " + text_str
		lbl.text = text_str
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_hbox.add_child(lbl)

		_legend_box.add_child(chip)

	_legend_box.visible = true

func _on_overlay_item_selected(index: int) -> void:
	if _is_populating or _overlay_option == null:
		return
	var chosen_id: String = str(_overlay_option.get_item_metadata(index)).strip_edges().to_upper()
	if not chosen_id.is_empty():
		overlay_selected.emit(chosen_id)