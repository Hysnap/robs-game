# res://systems/progress_monitor.gd
class_name ProgressMonitor
extends RefCounted

signal progress_updated(percent: float, stage_title: String, detail_text: String)
signal pipeline_completed(elapsed_ms: int)

var _stages: Array[Dictionary] = []
var _current_stage_idx: int = 0
var _total_weight: float = 0.0
var _accumulated_weight: float = 0.0
var _start_time_ms: int = 0
var _last_emit_time_ms: int = 0
var _throttle_ms: int = 50 # Throttle UI updates to max 20Hz

## Define stages with proportional weights (e.g. weights [30, 20, 40, 10])
func configure_stages(stage_definitions: Array[Dictionary]) -> void:
	_stages.clear()
	_total_weight = 0.0
	_accumulated_weight = 0.0
	_current_stage_idx = 0
	
	for s in stage_definitions:
		var weight: float = float(s.get("weight", 1.0))
		_stages.append({
			"id": str(s.get("id", "")),
			"title": str(s.get("title", "")),
			"weight": weight
		})
		_total_weight += weight

	_start_time_ms = Time.get_ticks_msec()
	_last_emit_time_ms = 0

## Advance to a specific stage by ID or index
func begin_stage(stage_id: String, initial_detail: String = "") -> void:
	# Calculate accumulated weight of completed stages
	_accumulated_weight = 0.0
	for i in range(_stages.size()):
		if _stages[i]["id"] == stage_id or i == _current_stage_idx:
			_current_stage_idx = i
			break
		_accumulated_weight += _stages[i]["weight"]

	var stage_title: String = _stages[_current_stage_idx]["title"]
	_emit_progress(0.0, stage_title, initial_detail, true)

## Update sub-progress within the active stage (0.0 to 1.0 or current/total)
func update_sub_progress(current: float, total: float, detail_text: String = "", force: bool = false) -> void:
	if _stages.is_empty() or _total_weight <= 0.0:
		return

	var now: int = Time.get_ticks_msec()
	if not force and (now - _last_emit_time_ms < _throttle_ms):
		return
	_last_emit_time_ms = now

	var sub_ratio: float = clampf(current / maxf(total, 1.0), 0.0, 1.0)
	var stage_weight: float = _stages[_current_stage_idx]["weight"]
	var overall_weight_done: float = _accumulated_weight + (stage_weight * sub_ratio)
	var overall_percent: float = clampf((overall_weight_done / _total_weight) * 100.0, 0.0, 100.0)

	var stage_title: String = _stages[_current_stage_idx]["title"]
	_emit_progress(overall_percent, stage_title, detail_text, false)

## Mark pipeline finished
func complete(final_message: String = "Complete") -> void:
	var elapsed: int = Time.get_ticks_msec() - _start_time_ms
	progress_updated.emit(100.0, final_message, "Took %d ms" % elapsed)
	pipeline_completed.emit(elapsed)

func _emit_progress(pct: float, stage_title: String, detail: String, force: bool) -> void:
	progress_updated.emit(pct, stage_title, detail)