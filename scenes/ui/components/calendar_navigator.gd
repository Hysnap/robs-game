# res://scenes/ui/components/calendar_navigator.gd
class_name CalendarNavigator
extends VBoxContainer

signal action_clicked(action_code: String, payload: Dictionary)

const RETRO_THEME = preload("res://scenes/ui/shell_host/retro_theme.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

const WEEKDAY_TOKENS: Array[String] = [
	"UI_CAL_WD_MON",
	"UI_CAL_WD_TUE",
	"UI_CAL_WD_WED",
	"UI_CAL_WD_THU",
	"UI_CAL_WD_FRI",
	"UI_CAL_WD_SAT",
	"UI_CAL_WD_SUN"
]

var _month_label: Label
var _grid: GridContainer
var _selected_header: Label
var _events_box: VBoxContainer
var _month_offset: int = 0

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_build_chrome()

func _build_chrome() -> void:
	for child in get_children():
		child.queue_free()

	var mono_font: Font = RETRO_THEME.get_monospace_font()
	var clr_accent: Color = RETRO_THEME.get_ink_color("accent")
	var clr_muted: Color = RETRO_THEME.get_ink_color("muted")

	# 1. Month Navigation Bar (<  APRIL 1984  >)
	var nav_bar := HBoxContainer.new()
	nav_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_theme_constant_override("separation", 6)

	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.add_theme_font_override("font", mono_font)
	prev_btn.pressed.connect(func():
		_month_offset -= 1
		action_clicked.emit("diary_select_date", {"month_offset": _month_offset})
	)
	nav_bar.add_child(prev_btn)

	_month_label = Label.new()
	_month_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_month_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_month_label.add_theme_font_override("font", mono_font)
	_month_label.add_theme_color_override("font_color", clr_accent)
	nav_bar.add_child(_month_label)

	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.add_theme_font_override("font", mono_font)
	next_btn.pressed.connect(func():
		_month_offset += 1
		action_clicked.emit("diary_select_date", {"month_offset": _month_offset})
	)
	nav_bar.add_child(next_btn)
	add_child(nav_bar)

	# 2. 7-Column Calendar Grid (Weekday Headers + Day Cells)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	add_child(_grid)

	# 3. Selected Day Detail List
	add_child(HSeparator.new())
	_selected_header = Label.new()
	_selected_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_header.add_theme_font_override("font", mono_font)
	_selected_header.add_theme_color_override("font_color", clr_muted)
	add_child(_selected_header)

	_events_box = VBoxContainer.new()
	_events_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_events_box.add_theme_constant_override("separation", 3)
	add_child(_events_box)

## Binds a pre-computed calendar payload prepared by the Diary controller
func bind_calendar(payload: Dictionary) -> void:
	if _grid == null:
		_build_chrome()

	var mono_font: Font = RETRO_THEME.get_monospace_font()
	var clr_accent: Color = RETRO_THEME.get_ink_color("accent")
	var clr_body: Color = RETRO_THEME.get_ink_color("body")
	var clr_muted: Color = RETRO_THEME.get_ink_color("muted")

	_month_offset = int(payload.get("month_offset", _month_offset))
	var current_sim_day: int = int(payload["current_sim_day"]) if (payload.has("current_sim_day") and payload["current_sim_day"] != null) else CALENDAR_HELPER.get_current_sim_day()
	var selected_sim_day: int = int(payload.get("selected_sim_day", current_sim_day))
	_month_label.text = str(payload.get("month_title", "")).to_upper()

	for child in _grid.get_children():
		child.queue_free()

	for wd_tok in WEEKDAY_TOKENS:
		var wd_lbl := Label.new()
		wd_lbl.text = tr(wd_tok)
		wd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wd_lbl.add_theme_font_override("font", mono_font)
		wd_lbl.add_theme_color_override("font_color", clr_muted)
		_grid.add_child(wd_lbl)

	var leading_blanks: int = maxi(0, int(payload.get("leading_blank_days", 0)))
	for _b in range(leading_blanks):
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(spacer)

	var days: Array = payload.get("days", [])
	for day_entry in days:
		if not (day_entry is Dictionary):
			continue
		var sim_day: int = int(day_entry.get("sim_day", 0))
		var day_num: int = int(day_entry.get("day_of_month", 1))
		var has_items: bool = bool(day_entry.get("has_items", false))

		var cell_btn := Button.new()
		cell_btn.name = "day_btn_%d" % sim_day
		cell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell_btn.add_theme_font_override("font", mono_font)
		var label_str := "%02d*" % day_num if has_items else "%02d " % day_num
		if sim_day == selected_sim_day:
			label_str = "[%s]" % label_str.strip_edges()
			cell_btn.add_theme_color_override("font_color", clr_accent)
		elif sim_day == current_sim_day:
			cell_btn.add_theme_color_override("font_color", clr_body)
		elif has_items:
			cell_btn.add_theme_color_override("font_color", clr_accent)
		else:
			cell_btn.add_theme_color_override("font_color", clr_muted)

		cell_btn.text = label_str
		cell_btn.pressed.connect(func():
			action_clicked.emit("diary_select_date", {
				"sim_day": sim_day,
				"month_offset": _month_offset
			})
		)
		_grid.add_child(cell_btn)

	# Populate Selected Day Entries
	var selected_date_str := str(payload.get("selected_date_label", ""))
	_selected_header.text = "%s: %s" % [tr("UI_LBL_SELECTED_DATE"), selected_date_str]

	for child in _events_box.get_children():
		child.queue_free()

	var items: Array = payload.get("selected_day_items", [])
	if items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = tr("UI_DIARY_NO_SCHEDULED_ITEMS")
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_override("font", mono_font)
		empty_lbl.add_theme_color_override("font_color", clr_muted)
		_events_box.add_child(empty_lbl)
		return

	for item in items:
		if not (item is Dictionary):
			continue
		var row_box := HBoxContainer.new()
		row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_box.add_theme_constant_override("separation", 6)

		var title_tok := str(item.get("title_token", "UI_EVENT_DEFAULT"))
		var loc_label := str(item.get("location_label", ""))
		var desc_lbl := Label.new()
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_override("font", mono_font)
		desc_lbl.add_theme_color_override("font_color", clr_body)
		desc_lbl.text = "• %s (%s)" % [tr(title_tok), loc_label] if not loc_label.is_empty() else "• %s" % tr(title_tok)
		row_box.add_child(desc_lbl)

		var event_id := int(item.get("event_id", 0))
		if event_id > 0 and bool(item.get("can_attend", false)):
			var attend_btn := Button.new()
			attend_btn.name = "attend_btn_%d" % event_id
			attend_btn.text = tr("UI_BTN_ATTEND_EVENT")
			attend_btn.add_theme_font_override("font", mono_font)
			var target_node := str(item.get("location_id", ""))
			attend_btn.pressed.connect(func():
				action_clicked.emit("open_order_composer", {
					"verb": "ATTEND_EVENT",
					"event_id": event_id,
					"target_node_id": target_node
				})
			)
			row_box.add_child(attend_btn)

		_events_box.add_child(row_box)