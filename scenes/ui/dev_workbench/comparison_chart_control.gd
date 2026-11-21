# res://scenes/ui/dev_workbench/comparison_chart_control.gd
class_name ComparisonChartControl
extends Control

enum ChartMode {
	PAIRED_BAR,
	POPULATION_PYRAMID
}

const COL_BG := Color(0.08, 0.09, 0.11, 1.0)
const COL_BORDER := Color(0.22, 0.25, 0.30, 1.0)
const COL_GRID := Color(0.16, 0.18, 0.22, 1.0)
const COL_TEXT := Color(0.90, 0.92, 0.95, 1.0)
const COL_MUTED := Color(0.62, 0.66, 0.73, 1.0)
const COL_EXPECTED := Color(0.32, 0.62, 0.92, 0.85)
const COL_ACTUAL := Color(0.28, 0.82, 0.56, 0.92)
const COL_MALE := Color(0.30, 0.64, 0.94, 0.88)
const COL_FEMALE := Color(0.90, 0.44, 0.64, 0.88)
const COL_TARGET_TICK := Color(0.98, 0.88, 0.32, 0.98)
const COL_OK := Color(0.30, 0.84, 0.54, 1.0)
const COL_WARN := Color(0.95, 0.72, 0.24, 1.0)
const COL_ALERT := Color(0.94, 0.36, 0.36, 1.0)

var _mode: ChartMode = ChartMode.PAIRED_BAR
var _title: String = ""
var _subtitle: String = ""
var _rows: Array[Dictionary] = []
var _is_normalized: bool = false

func configure_paired_bars(title: String, subtitle: String, rows: Array[Dictionary], is_normalized: bool = false) -> void:
	_mode = ChartMode.PAIRED_BAR
	_title = title
	_subtitle = subtitle
	_rows = rows
	_is_normalized = is_normalized
	_recalculate_min_height()
	queue_redraw()

func configure_pyramid(title: String, subtitle: String, rows: Array[Dictionary]) -> void:
	_mode = ChartMode.POPULATION_PYRAMID
	_title = title
	_subtitle = subtitle
	_rows = rows
	_recalculate_min_height()
	queue_redraw()

func _recalculate_min_height() -> void:
	var row_h: float = 24.0 if _mode == ChartMode.POPULATION_PYRAMID else 34.0
	var header_h: float = 64.0
	var footer_h: float = 20.0
	custom_minimum_size = Vector2(680.0, header_h + (float(maxi(1, _rows.size())) * row_h) + footer_h)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, COL_BG, true)
	draw_rect(rect, COL_BORDER, false, 1.0)

	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	# Header Title & Subtitle
	draw_string(font, Vector2(14.0, 22.0), _title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 14, COL_TEXT)
	draw_string(font, Vector2(14.0, 39.0), _subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 11, COL_MUTED)

	if _rows.is_empty():
		draw_string(font, Vector2(14.0, 74.0), "No data rows available.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 12, COL_MUTED)
		return

	if _mode == ChartMode.POPULATION_PYRAMID:
		_draw_population_pyramid(font)
	else:
		_draw_paired_bars(font)

func _draw_population_pyramid(font: Font) -> void:
	# Legend
	var lx: float = 14.0
	var ly: float = 54.0
	draw_rect(Rect2(lx, ly - 9.0, 12.0, 10.0), COL_MALE, true)
	draw_string(font, Vector2(lx + 16.0, ly), "Male Actual %", HORIZONTAL_ALIGNMENT_LEFT, 120.0, 11, COL_TEXT)
	draw_rect(Rect2(lx + 125.0, ly - 9.0, 12.0, 10.0), COL_FEMALE, true)
	draw_string(font, Vector2(lx + 141.0, ly), "Female Actual %", HORIZONTAL_ALIGNMENT_LEFT, 130.0, 11, COL_TEXT)
	draw_line(Vector2(lx + 275.0, ly - 10.0), Vector2(lx + 275.0, ly + 2.0), COL_TARGET_TICK, 2.5)
	draw_string(font, Vector2(lx + 283.0, ly), "JSON Target Marker", HORIZONTAL_ALIGNMENT_LEFT, 160.0, 11, COL_TARGET_TICK)

	var max_pct: float = 5.0
	for r in _rows:
		max_pct = maxf(max_pct, maxf(float(r.get("expected_male_pct", 0.0)), float(r.get("actual_male_pct", 0.0))))
		max_pct = maxf(max_pct, maxf(float(r.get("expected_female_pct", 0.0)), float(r.get("actual_female_pct", 0.0))))
	max_pct = ceilf(max_pct)

	var center_x: float = size.x * 0.5
	var label_half_w: float = 34.0
	var half_bar_max: float = maxf(80.0, (size.x * 0.5) - label_half_w - 86.0)
	var top_y: float = 68.0
	var row_h: float = 24.0

	# Vertical grid lines
	for step_i in range(1, int(max_pct) + 1):
		var frac: float = float(step_i) / max_pct
		var dx: float = frac * half_bar_max
		draw_line(Vector2(center_x - label_half_w - dx, top_y), Vector2(center_x - label_half_w - dx, top_y + (_rows.size() * row_h)), COL_GRID, 1.0)
		draw_line(Vector2(center_x + label_half_w + dx, top_y), Vector2(center_x + label_half_w + dx, top_y + (_rows.size() * row_h)), COL_GRID, 1.0)

	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var y: float = top_y + (float(i) * row_h)
		var bar_y: float = y + 4.0
		var bar_h: float = 14.0

		# Center Age Band Label
		draw_string(font, Vector2(center_x - label_half_w, y + 15.0), str(r.get("label", "")), HORIZONTAL_ALIGNMENT_CENTER, label_half_w * 2.0, 11, COL_TEXT)

		# Male (Left)
		var act_m: float = float(r.get("actual_male_pct", 0.0))
		var exp_m: float = float(r.get("expected_male_pct", 0.0))
		var m_w: float = (act_m / max_pct) * half_bar_max
		var exp_m_x: float = center_x - label_half_w - ((exp_m / max_pct) * half_bar_max)
		draw_rect(Rect2(center_x - label_half_w - m_w, bar_y, m_w, bar_h), COL_MALE, true)
		draw_line(Vector2(exp_m_x, bar_y - 2.0), Vector2(exp_m_x, bar_y + bar_h + 2.0), COL_TARGET_TICK, 2.0)
		draw_string(font, Vector2(12.0, y + 15.0), "%.1f%% (%.1f%%)" % [act_m, exp_m], HORIZONTAL_ALIGNMENT_LEFT, 74.0, 10, COL_MUTED)

		# Female (Right)
		var act_f: float = float(r.get("actual_female_pct", 0.0))
		var exp_f: float = float(r.get("expected_female_pct", 0.0))
		var f_w: float = (act_f / max_pct) * half_bar_max
		var exp_f_x: float = center_x + label_half_w + ((exp_f / max_pct) * half_bar_max)
		draw_rect(Rect2(center_x + label_half_w, bar_y, f_w, bar_h), COL_FEMALE, true)
		draw_line(Vector2(exp_f_x, bar_y - 2.0), Vector2(exp_f_x, bar_y + bar_h + 2.0), COL_TARGET_TICK, 2.0)
		draw_string(font, Vector2(size.x - 84.0, y + 15.0), "%.1f%% (%.1f%%)" % [act_f, exp_f], HORIZONTAL_ALIGNMENT_RIGHT, 74.0, 10, COL_MUTED)

func _draw_paired_bars(font: Font) -> void:
	# Legend
	var lx: float = 14.0
	var ly: float = 54.0
	draw_rect(Rect2(lx, ly - 9.0, 12.0, 10.0), COL_EXPECTED, true)
	draw_string(font, Vector2(lx + 16.0, ly), "Expected (JSON Rule)", HORIZONTAL_ALIGNMENT_LEFT, 150.0, 11, COL_TEXT)
	draw_rect(Rect2(lx + 165.0, ly - 9.0, 12.0, 10.0), COL_ACTUAL, true)
	draw_string(font, Vector2(lx + 181.0, ly), "Actual (City SQLite DB)", HORIZONTAL_ALIGNMENT_LEFT, 160.0, 11, COL_TEXT)

	var max_val: float = 1.0 if _is_normalized else 5.0
	if not _is_normalized:
		for r in _rows:
			max_val = maxf(max_val, maxf(float(r.get("expected_pct", 0.0)), float(r.get("actual_pct", 0.0))))
		max_val = maxf(1.0, ceilf(max_val * 1.15))

	var label_w: float = 215.0
	var stats_w: float = 230.0
	var bar_x: float = 14.0 + label_w
	var bar_max_w: float = maxf(120.0, size.x - label_w - stats_w - 28.0)
	var top_y: float = 68.0
	var row_h: float = 34.0

	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var y: float = top_y + (float(i) * row_h)

		# Subtle row divider
		if i > 0:
			draw_line(Vector2(14.0, y), Vector2(size.x - 14.0, y), COL_GRID, 1.0)

		draw_string(font, Vector2(14.0, y + 20.0), str(r.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, label_w - 8.0, 11, COL_TEXT)

		var exp_frac: float = 0.0
		var act_frac: float = 0.0
		var detail_txt: String = ""
		var delta_val: float = float(r.get("delta_pct", 0.0))

		if _is_normalized:
			exp_frac = clampf(float(r.get("expected_norm", 0.0)), 0.0, 1.0)
			act_frac = clampf(float(r.get("actual_norm", 0.0)), 0.0, 1.0)
			detail_txt = "Exp:%s | Act:%s %s (%+.1f%%)" % [
				str(r.get("expected_display", "")),
				str(r.get("actual_display", "")),
				str(r.get("range_display", "")),
				delta_val
			]
		else:
			var exp_p: float = float(r.get("expected_pct", 0.0))
			var act_p: float = float(r.get("actual_pct", 0.0))
			exp_frac = clampf(exp_p / max_val, 0.0, 1.0)
			act_frac = clampf(act_p / max_val, 0.0, 1.0)
			var sev_suffix: String = ""
			if r.has("avg_severity") and float(r["avg_severity"]) > 0.0:
				sev_suffix = " [sev %.2f]" % float(r["avg_severity"])
			detail_txt = "Exp:%.2f%% | Act:%.2f%% (%+.2f%%)%s" % [exp_p, act_p, delta_val, sev_suffix]

		# Expected Bar (Top) & Actual Bar (Bottom)
		draw_rect(Rect2(bar_x, y + 6.0, exp_frac * bar_max_w, 9.0), COL_EXPECTED, true)
		draw_rect(Rect2(bar_x, y + 17.0, act_frac * bar_max_w, 10.0), COL_ACTUAL, true)

		var badge_col: Color = COL_OK
		if absf(delta_val) > 5.0:
			badge_col = COL_ALERT
		elif absf(delta_val) > 2.0:
			badge_col = COL_WARN

		draw_string(font, Vector2(bar_x + bar_max_w + 10.0, y + 20.0), detail_txt, HORIZONTAL_ALIGNMENT_LEFT, stats_w, 10, badge_col)