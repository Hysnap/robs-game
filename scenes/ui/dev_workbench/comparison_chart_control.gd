# res://scenes/ui/dev_workbench/comparison_chart_control.gd
class_name ComparisonChartControl
extends Control

enum ChartMode {
	POPULATION_PYRAMID,
	DUAL_CURVE,
	AGE_SEX_BREAKDOWN
}

const COL_BG := Color(0.08, 0.09, 0.11, 1.0)
const COL_BORDER := Color(0.22, 0.25, 0.30, 1.0)
const COL_GRID := Color(0.16, 0.18, 0.22, 1.0)
const COL_TEXT := Color(0.90, 0.92, 0.95, 1.0)
const COL_MUTED := Color(0.62, 0.66, 0.73, 1.0)
const COL_EXPECTED := Color(0.32, 0.62, 0.92, 0.92)
const COL_EXPECTED_FILL := Color(0.32, 0.62, 0.92, 0.12)
const COL_ACTUAL := Color(0.28, 0.84, 0.56, 0.96)
const COL_ACTUAL_FILL := Color(0.28, 0.84, 0.56, 0.15)
const COL_MALE := Color(0.30, 0.64, 0.94, 0.92)
const COL_FEMALE := Color(0.90, 0.44, 0.64, 0.92)
const COL_TARGET_TICK := Color(0.98, 0.88, 0.32, 0.98)
const COL_OK := Color(0.30, 0.84, 0.54, 1.0)
const COL_WARN := Color(0.95, 0.72, 0.24, 1.0)
const COL_ALERT := Color(0.94, 0.36, 0.36, 1.0)

var _mode: ChartMode = ChartMode.DUAL_CURVE
var _title: String = ""
var _subtitle: String = ""
var _rows: Array[Dictionary] = []
var _curve_meta: Dictionary = {}

func configure_pyramid(title: String, subtitle: String, rows: Array[Dictionary]) -> void:
	_mode = ChartMode.POPULATION_PYRAMID
	_title = title
	_subtitle = subtitle
	_rows = rows
	_curve_meta = {}
	_recalculate_min_height()
	queue_redraw()

## Configures a 2-curve distribution chart (Expected Modelled Curve vs Actual SQLite Curve)
func configure_dual_curve(title: String, subtitle: String, curve_payload: Dictionary) -> void:
	_mode = ChartMode.DUAL_CURVE
	_title = title
	_subtitle = subtitle
	_rows = []
	_curve_meta = curve_payload
	_recalculate_min_height()
	queue_redraw()

## Configures an Age x Sex distribution chart (Male vs Female across age cohorts)
func configure_age_sex_breakdown(title: String, subtitle: String, rows: Array[Dictionary], y_max_scale: float = 1.0) -> void:
	_mode = ChartMode.AGE_SEX_BREAKDOWN
	_title = title
	_subtitle = subtitle
	_rows = rows
	_curve_meta = {"y_max_scale": y_max_scale}
	_recalculate_min_height()
	queue_redraw()

func _recalculate_min_height() -> void:
	match _mode:
		ChartMode.POPULATION_PYRAMID:
			var row_h: float = 24.0
			custom_minimum_size = Vector2(680.0, 64.0 + (float(maxi(1, _rows.size())) * row_h) + 20.0)
		ChartMode.DUAL_CURVE:
			custom_minimum_size = Vector2(460.0, 235.0)
		ChartMode.AGE_SEX_BREAKDOWN:
			custom_minimum_size = Vector2(460.0, 235.0)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, COL_BG, true)
	draw_rect(rect, COL_BORDER, false, 1.0)

	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	draw_string(font, Vector2(14.0, 22.0), _title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 13, COL_TEXT)
	draw_string(font, Vector2(14.0, 38.0), _subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 10, COL_MUTED)

	match _mode:
		ChartMode.POPULATION_PYRAMID:
			if _rows.is_empty():
				draw_string(font, Vector2(14.0, 74.0), "No data rows available.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 12, COL_MUTED)
				return
			_draw_population_pyramid(font)
		ChartMode.DUAL_CURVE:
			_draw_dual_curve(font)
		ChartMode.AGE_SEX_BREAKDOWN:
			if _rows.is_empty():
				draw_string(font, Vector2(14.0, 74.0), "No age/sex cohort data available.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 12, COL_MUTED)
				return
			_draw_age_sex_breakdown(font)

func _draw_population_pyramid(font: Font) -> void:
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

		draw_string(font, Vector2(center_x - label_half_w, y + 15.0), str(r.get("label", "")), HORIZONTAL_ALIGNMENT_CENTER, label_half_w * 2.0, 11, COL_TEXT)

		var act_m: float = float(r.get("actual_male_pct", 0.0))
		var exp_m: float = float(r.get("expected_male_pct", 0.0))
		var m_w: float = (act_m / max_pct) * half_bar_max
		var exp_m_x: float = center_x - label_half_w - ((exp_m / max_pct) * half_bar_max)
		draw_rect(Rect2(center_x - label_half_w - m_w, bar_y, m_w, bar_h), COL_MALE, true)
		draw_line(Vector2(exp_m_x, bar_y - 2.0), Vector2(exp_m_x, bar_y + bar_h + 2.0), COL_TARGET_TICK, 2.0)
		draw_string(font, Vector2(12.0, y + 15.0), "%.1f%% (%.1f%%)" % [act_m, exp_m], HORIZONTAL_ALIGNMENT_LEFT, 74.0, 10, COL_MUTED)

		var act_f: float = float(r.get("actual_female_pct", 0.0))
		var exp_f: float = float(r.get("expected_female_pct", 0.0))
		var f_w: float = (act_f / max_pct) * half_bar_max
		var exp_f_x: float = center_x + label_half_w + ((exp_f / max_pct) * half_bar_max)
		draw_rect(Rect2(center_x + label_half_w, bar_y, f_w, bar_h), COL_FEMALE, true)
		draw_line(Vector2(exp_f_x, bar_y - 2.0), Vector2(exp_f_x, bar_y + bar_h + 2.0), COL_TARGET_TICK, 2.0)
		draw_string(font, Vector2(size.x - 84.0, y + 15.0), "%.1f%% (%.1f%%)" % [act_f, exp_f], HORIZONTAL_ALIGNMENT_RIGHT, 74.0, 10, COL_MUTED)

func _draw_dual_curve(font: Font) -> void:
	var exp_curve: Array = _curve_meta.get("expected_curve", [])
	var act_curve: Array = _curve_meta.get("actual_curve", [])
	var x_labels: Array = _curve_meta.get("x_labels", [])
	if exp_curve.is_empty() or act_curve.is_empty():
		draw_string(font, Vector2(14.0, 74.0), "No distribution curve points available.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 12, COL_MUTED)
		return

	# Legend + Delta Badge
	var lx: float = 14.0
	var ly: float = 54.0
	draw_line(Vector2(lx, ly - 4.0), Vector2(lx + 16.0, ly - 4.0), COL_EXPECTED, 2.5)
	draw_string(font, Vector2(lx + 20.0, ly), "Expected Modelled", HORIZONTAL_ALIGNMENT_LEFT, 120.0, 10, COL_TEXT)
	draw_line(Vector2(lx + 135.0, ly - 4.0), Vector2(lx + 151.0, ly - 4.0), COL_ACTUAL, 2.5)
	draw_string(font, Vector2(lx + 155.0, ly), "Actual SQLite", HORIZONTAL_ALIGNMENT_LEFT, 110.0, 10, COL_TEXT)

	var delta_val: float = float(_curve_meta.get("delta_pct", 0.0))
	var badge_txt: String = str(_curve_meta.get("badge_text", ""))
	if not badge_txt.is_empty():
		var badge_col: Color = COL_OK
		if absf(delta_val) > 5.0:
			badge_col = COL_ALERT
		elif absf(delta_val) > 2.0:
			badge_col = COL_WARN
		draw_string(font, Vector2(size.x - 240.0, ly), badge_txt, HORIZONTAL_ALIGNMENT_RIGHT, 226.0, 10, badge_col)

	var plot_left: float = 44.0
	var plot_right: float = size.x - 18.0
	var plot_top: float = 68.0
	var plot_bottom: float = size.y - 28.0
	var plot_w: float = maxf(80.0, plot_right - plot_left)
	var plot_h: float = maxf(60.0, plot_bottom - plot_top)

	var max_y: float = 5.0
	for v in exp_curve:
		max_y = maxf(max_y, float(v))
	for v in act_curve:
		max_y = maxf(max_y, float(v))
	max_y = maxf(1.0, ceilf(max_y * 1.15))

	# Horizontal gridlines & Y-axis percentage ticks
	for g_i in range(5):
		var frac: float = float(g_i) / 4.0
		var gy: float = plot_bottom - (frac * plot_h)
		draw_line(Vector2(plot_left, gy), Vector2(plot_right, gy), COL_GRID, 1.0)
		var tick_v: float = frac * max_y
		draw_string(font, Vector2(4.0, gy + 4.0), "%.0f%%" % tick_v, HORIZONTAL_ALIGNMENT_LEFT, 36.0, 9, COL_MUTED)

	var n_pts: int = mini(exp_curve.size(), act_curve.size())
	var exp_pts: PackedVector2Array = PackedVector2Array()
	var act_pts: PackedVector2Array = PackedVector2Array()
	var act_poly: PackedVector2Array = PackedVector2Array()
	act_poly.append(Vector2(plot_left, plot_bottom))

	for i in range(n_pts):
		var t: float = float(i) / float(maxi(1, n_pts - 1)) if n_pts > 1 else 0.5
		var px: float = plot_left + (t * plot_w)
		var ey: float = plot_bottom - (clampf(float(exp_curve[i]) / max_y, 0.0, 1.0) * plot_h)
		var ay: float = plot_bottom - (clampf(float(act_curve[i]) / max_y, 0.0, 1.0) * plot_h)
		exp_pts.append(Vector2(px, ey))
		act_pts.append(Vector2(px, ay))
		act_poly.append(Vector2(px, ay))

	act_poly.append(Vector2(plot_right, plot_bottom))
	if act_poly.size() >= 4:
		draw_colored_polygon(act_poly, COL_ACTUAL_FILL)

	# Optional vertical mean / upper-tail threshold markers
	if _curve_meta.has("expected_mean_norm"):
		var em_x: float = plot_left + (clampf(float(_curve_meta["expected_mean_norm"]), 0.0, 1.0) * plot_w)
		draw_line(Vector2(em_x, plot_top), Vector2(em_x, plot_bottom), COL_EXPECTED, 1.5)
	if _curve_meta.has("actual_mean_norm"):
		var am_x: float = plot_left + (clampf(float(_curve_meta["actual_mean_norm"]), 0.0, 1.0) * plot_w)
		draw_line(Vector2(am_x, plot_top), Vector2(am_x, plot_bottom), COL_ACTUAL, 1.5)
	if _curve_meta.has("cutoff_norm"):
		var cut_x: float = plot_left + (clampf(float(_curve_meta["cutoff_norm"]), 0.0, 1.0) * plot_w)
		draw_line(Vector2(cut_x, plot_top), Vector2(cut_x, plot_bottom), COL_TARGET_TICK, 2.0)
		draw_string(font, Vector2(minf(cut_x + 4.0, plot_right - 56.0), plot_top + 11.0), "Cutoff τ", HORIZONTAL_ALIGNMENT_LEFT, 56.0, 9, COL_TARGET_TICK)

	# Draw Expected (dashed segments) and Actual (solid polyline + vertex dots)
	for i in range(n_pts - 1):
		if i % 2 == 0 or n_pts <= 10:
			draw_line(exp_pts[i], exp_pts[i + 1], COL_EXPECTED, 2.2, true)
		else:
			var mid_p: Vector2 = exp_pts[i].lerp(exp_pts[i + 1], 0.5)
			draw_line(exp_pts[i], mid_p, COL_EXPECTED, 2.2, true)

	if act_pts.size() >= 2:
		draw_polyline(act_pts, COL_ACTUAL, 2.4, true)
	for i in range(n_pts):
		draw_circle(exp_pts[i], 2.5, COL_EXPECTED)
		draw_circle(act_pts[i], 3.0, COL_ACTUAL)

	# X-axis labels
	if not x_labels.is_empty():
		var lbl_count: int = mini(n_pts, x_labels.size())
		var slot_w: float = plot_w / float(maxi(1, lbl_count))
		for i in range(lbl_count):
			var t: float = float(i) / float(maxi(1, lbl_count - 1)) if lbl_count > 1 else 0.5
			var lx_pos: float = plot_left + (t * plot_w) - (slot_w * 0.45)
			var short_lbl: String = str(x_labels[i]).substr(0, 11)
			draw_string(font, Vector2(lx_pos, size.y - 10.0), short_lbl, HORIZONTAL_ALIGNMENT_CENTER, slot_w * 0.9, 9, COL_MUTED)
	else:
		var x_min_lbl: String = str(_curve_meta.get("x_min_label", "0.00"))
		var x_max_lbl: String = str(_curve_meta.get("x_max_label", "1.00"))
		draw_string(font, Vector2(plot_left, size.y - 10.0), x_min_lbl, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 9, COL_MUTED)
		draw_string(font, Vector2(plot_right - 60.0, size.y - 10.0), x_max_lbl, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 9, COL_MUTED)

func _draw_age_sex_breakdown(font: Font) -> void:
	var lx: float = 14.0
	var ly: float = 54.0
	draw_line(Vector2(lx, ly - 4.0), Vector2(lx + 16.0, ly - 4.0), COL_MALE, 2.5)
	draw_string(font, Vector2(lx + 20.0, ly), "Male (SQLite)", HORIZONTAL_ALIGNMENT_LEFT, 100.0, 10, COL_TEXT)
	draw_line(Vector2(lx + 115.0, ly - 4.0), Vector2(lx + 131.0, ly - 4.0), COL_FEMALE, 2.5)
	draw_string(font, Vector2(lx + 135.0, ly), "Female (SQLite)", HORIZONTAL_ALIGNMENT_LEFT, 110.0, 10, COL_TEXT)

	var plot_left: float = 44.0
	var plot_right: float = size.x - 18.0
	var plot_top: float = 68.0
	var plot_bottom: float = size.y - 28.0
	var plot_w: float = maxf(80.0, plot_right - plot_left)
	var plot_h: float = maxf(60.0, plot_bottom - plot_top)

	var max_y: float = float(_curve_meta.get("y_max_scale", 1.0))
	for r in _rows:
		max_y = maxf(max_y, maxf(float(r.get("male_val", 0.0)), float(r.get("female_val", 0.0))))
	max_y = maxf(0.01, max_y)

	for g_i in range(5):
		var frac: float = float(g_i) / 4.0
		var gy: float = plot_bottom - (frac * plot_h)
		draw_line(Vector2(plot_left, gy), Vector2(plot_right, gy), COL_GRID, 1.0)
		var tick_v: float = frac * max_y
		var tick_str: String = "%.0f" % tick_v if max_y >= 10.0 else "%.2f" % tick_v
		draw_string(font, Vector2(4.0, gy + 4.0), tick_str, HORIZONTAL_ALIGNMENT_LEFT, 36.0, 9, COL_MUTED)

	var n_pts: int = _rows.size()
	var m_pts: PackedVector2Array = PackedVector2Array()
	var f_pts: PackedVector2Array = PackedVector2Array()
	var slot_w: float = plot_w / float(maxi(1, n_pts))

	for i in range(n_pts):
		var r: Dictionary = _rows[i]
		var t: float = float(i) / float(maxi(1, n_pts - 1)) if n_pts > 1 else 0.5
		var px: float = plot_left + (t * plot_w)
		var my: float = plot_bottom - (clampf(float(r.get("male_val", 0.0)) / max_y, 0.0, 1.0) * plot_h)
		var fy: float = plot_bottom - (clampf(float(r.get("female_val", 0.0)) / max_y, 0.0, 1.0) * plot_h)
		m_pts.append(Vector2(px, my))
		f_pts.append(Vector2(px, fy))

		draw_string(font, Vector2(px - (slot_w * 0.45), size.y - 10.0), str(r.get("label", "")), HORIZONTAL_ALIGNMENT_CENTER, slot_w * 0.9, 9, COL_MUTED)

	if m_pts.size() >= 2:
		draw_polyline(m_pts, COL_MALE, 2.3, true)
		draw_polyline(f_pts, COL_FEMALE, 2.3, true)

	for i in range(n_pts):
		draw_circle(m_pts[i], 3.2, COL_MALE)
		draw_circle(f_pts[i], 3.2, COL_FEMALE)