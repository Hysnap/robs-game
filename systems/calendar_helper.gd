class_name CalendarHelper
extends RefCounted

const DB_MGR = preload("res://systems/db_manager.gd")

static var _epoch_date: String = ""
static var _sim_start_date: String = ""
static var _days_per_tick: int = 7
static var _start_day_offset: int = 0
static var _initialized: bool = false

## Initializes temporal constants dynamically from the loaded demographic config
static func initialize(temporal_config: Dictionary) -> void:
	assert(temporal_config.has("epoch_date"), "FATAL: temporal_anchor missing 'epoch_date'")
	assert(temporal_config.has("simulation_start_date"), "FATAL: temporal_anchor missing 'simulation_start_date'")
	
	_epoch_date = str(temporal_config["epoch_date"])
	_sim_start_date = str(temporal_config["simulation_start_date"])
	_days_per_tick = int(temporal_config.get("days_per_tick", 7))
	
	# Let SQLite compute the exact integer day difference between epoch and start date
	var sql := "SELECT CAST(julianday('%s') - julianday('%s') AS INTEGER) AS day_diff;" % [_sim_start_date, _epoch_date]
	var res = DB_MGR.query_rows(sql)
	assert(not res.is_empty(), "FATAL: Failed to calculate simulation start day offset in SQLite")
	
	_start_day_offset = int(res[0]["day_diff"])
	_initialized = true
	print("[CalendarHelper] Initialized: Epoch '%s', Start Date '%s' (Day Offset: %d), Days/Tick: %d" % [
		_epoch_date, _sim_start_date, _start_day_offset, _days_per_tick
	])

static func get_epoch_date() -> String:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _epoch_date

static func get_simulation_start_day() -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _start_day_offset

static func get_days_per_tick() -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _days_per_tick

## Converts simulation tick into integer day offset
static func tick_to_day(tick: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _start_day_offset + (tick * _days_per_tick)

## Returns the current elapsed simulation week (1-indexed) based on day offset
static func day_to_week(day_offset: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var elapsed_days := day_offset - _start_day_offset
	return (elapsed_days / _days_per_tick) + 1

## Returns the current day of the week (1 to 7) based on day offset
static func day_of_week(day_offset: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var elapsed_days := day_offset - _start_day_offset
	return (elapsed_days % _days_per_tick) + 1

## Determines if advancing by days crosses a week boundary
static func crosses_week_boundary(current_day: int, advance_days: int) -> bool:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var old_week := day_to_week(current_day)
	var new_week := day_to_week(current_day + advance_days)
	return new_week > old_week

## Formats any day offset into a localized UK date (e.g., "14 Apr 1984")
static func day_to_calendar_date(day_offset: int) -> String:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var sql := "SELECT date('%s', '+%d days') as d;" % [_epoch_date, day_offset]
	var res = DB_MGR.query_rows(sql)
	if res.is_empty():
		return "Unknown Date"
	
	var raw_iso: String = res[0]["d"]
	var parts: PackedStringArray = raw_iso.split("-")
	if parts.size() < 3:
		return raw_iso
		
	var year := parts[0]
	var month_idx := int(parts[1])
	var day := parts[2]
	var months := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_str = months[month_idx] if month_idx < months.size() else parts[1]
	
	return "%s %s %s" % [day, month_str, year]