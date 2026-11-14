class_name CalendarHelper
extends RefCounted

const DB_MGR = preload("res://systems/db_manager.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

static var _epoch_date: String = ""
static var _sim_start_date: String = ""
static var _days_per_tick: int = 7
static var _start_day_offset: int = 0
static var _initialized: bool = false

static var _epoch_jdn: int = 0
static var _jurisdiction_id: String = ""
static var _jurisdiction_cfg: Dictionary = {}
static var _holiday_cache: Dictionary = {} # year: int -> { "POSTAL": Dictionary[int, String], "BANKING": Dictionary[int, String] }

## Initializes temporal constants dynamically from the loaded demographic config and active scenario manifest
static func initialize(temporal_config: Dictionary) -> void:
	assert(temporal_config.has("epoch_date"), "FATAL: temporal_anchor missing 'epoch_date'")
	assert(temporal_config.has("simulation_start_date"), "FATAL: temporal_anchor missing 'simulation_start_date'")
	
	_epoch_date = str(temporal_config["epoch_date"])
	_sim_start_date = str(temporal_config["simulation_start_date"])
	_days_per_tick = int(temporal_config.get("days_per_tick", 7))
	
	var epoch_parts := _parse_iso_ymd(_epoch_date)
	_epoch_jdn = _gregorian_to_jdn(epoch_parts[0], epoch_parts[1], epoch_parts[2])
	
	var start_parts := _parse_iso_ymd(_sim_start_date)
	var start_jdn := _gregorian_to_jdn(start_parts[0], start_parts[1], start_parts[2])
	_start_day_offset = start_jdn - _epoch_jdn
	
	_load_jurisdiction_calendar_rules()
	_initialized = true
	SystemLogger.log_info("[CalendarHelper] Initialized: Epoch '%s', Start Date '%s' (Day Offset: %d), Days/Tick: %d, Jurisdiction: '%s'" % [
		_epoch_date, _sim_start_date, _start_day_offset, _days_per_tick, _jurisdiction_id
	])

static func _load_jurisdiction_calendar_rules() -> void:
	_holiday_cache.clear()
	assert(MANIFEST_MGR.has_module("civic_hierarchy"), "FATAL: [CalendarHelper] Active scenario manifest missing mandatory 'civic_hierarchy' module.")
	var manifest: Dictionary = MANIFEST_MGR.get_manifest()
	_jurisdiction_id = str(manifest.get("jurisdiction", "")).strip_edges()
	assert(not _jurisdiction_id.is_empty(), "FATAL: [CalendarHelper] Scenario manifest missing mandatory top-level 'jurisdiction'.")
	
	var civic_data: Dictionary = MANIFEST_MGR.load_module("civic_hierarchy")
	assert(civic_data.has("holiday_calendar") and civic_data["holiday_calendar"] is Dictionary, "FATAL: [CalendarHelper] 'civic_hierarchy' module missing mandatory 'holiday_calendar' dictionary.")
	_jurisdiction_cfg = civic_data["holiday_calendar"]

static func get_epoch_date() -> String:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _epoch_date

static func get_simulation_start_day() -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _start_day_offset

static func get_days_per_tick() -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _days_per_tick

static func get_jurisdiction_id() -> String:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _jurisdiction_id

## Converts simulation tick into integer day offset
static func tick_to_day(tick: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _start_day_offset + (tick * _days_per_tick)

## Returns the current elapsed simulation week (1-indexed) based on day offset
static func day_to_week(day_offset: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var elapsed_days := day_offset - _start_day_offset
	return floori(float(elapsed_days) / float(_days_per_tick)) + 1

## Returns the ISO day of the week (1 = Monday ... 7 = Sunday) for any epoch day offset
static func day_of_week(day_offset: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var jdn := _epoch_jdn + day_offset
	return posmod(jdn, 7) + 1

## Determines if advancing by days crosses a week boundary
static func crosses_week_boundary(current_day: int, advance_days: int) -> bool:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var old_week := day_to_week(current_day)
	var new_week := day_to_week(current_day + advance_days)
	return new_week > old_week

## Returns true if day_offset is a working day under the requested mode ("POSTAL" or "BANKING")
static func is_working_day(day_offset: int, mode: String = "POSTAL") -> bool:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var mode_key := mode.to_upper()
	var dow := day_of_week(day_offset)
	var non_working_key := "banking_non_working_days_of_week" if mode_key == "BANKING" else "non_working_days_of_week"
	var non_working_dows: Array = _jurisdiction_cfg.get(non_working_key, [7])
	if non_working_dows.has(dow):
		return false
	
	var ymd := _day_offset_to_ymd(day_offset)
	var year_holidays := _get_holidays_for_year(ymd[0])
	var mode_map: Dictionary = year_holidays.get(mode_key, year_holidays.get("POSTAL", {}))
	return not mode_map.has(day_offset)

## Returns the holiday ID string if day_offset is a holiday in the given mode, or "" otherwise
static func get_holiday_id(day_offset: int, mode: String = "POSTAL") -> String:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var ymd := _day_offset_to_ymd(day_offset)
	var year_holidays := _get_holidays_for_year(ymd[0])
	var mode_map: Dictionary = year_holidays.get(mode.to_upper(), {})
	return str(mode_map.get(day_offset, ""))

## Advances forward by exact working_days (0 returns start_day unchanged)
static func add_working_days(start_day: int, working_days: int, mode: String = "BANKING") -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	assert(working_days >= 0, "FATAL: [CalendarHelper] working_days cannot be negative.")
	var cursor := start_day
	var remaining := working_days
	while remaining > 0:
		cursor += 1
		if is_working_day(cursor, mode):
			remaining -= 1
	return cursor

## Advances arrival_day forward until it lands on a valid postal delivery day
static func next_valid_delivery_day(arrival_day: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var cursor := arrival_day
	while not is_working_day(cursor, "POSTAL"):
		cursor += 1
	return cursor

## Returns the calendar year for a given epoch day offset
static func day_to_year(day_offset: int) -> int:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	return _day_offset_to_ymd(day_offset)[0]

## Formats any day offset into a human-readable date (e.g., "14 Apr 1984")
static func day_to_calendar_date(day_offset: int) -> String:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var ymd := _day_offset_to_ymd(day_offset)
	var months := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_str: String = months[ymd[1]] if ymd[1] < months.size() else "%02d" % ymd[1]
	return "%02d %s %04d" % [ymd[2], month_str, ymd[0]]

## Formats an epoch day integer using the localized date pattern from ui_strings.csv
static func format_day_localized(day_offset: int) -> String:
	assert(_initialized, "FATAL: CalendarHelper used before initialization")
	var ymd := _day_offset_to_ymd(day_offset)
	var months_short := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_name: String = months_short[ymd[1]] if ymd[1] < months_short.size() else "%02d" % ymd[1]
	
	var pattern := TranslationServer.translate("FMT_DATE_SHORT")
	if pattern == "FMT_DATE_SHORT":
		pattern = "{day} {month} {year}"
		
	return pattern.replace("{day}", "%02d" % ymd[2]).replace("{month}", month_name).replace("{year}", "%04d" % ymd[0])

# ==============================================================================
# LOCALE- & ERA-INDEPENDENT HOLIDAY RESOLUTION ENGINE
# ==============================================================================

static func _get_holidays_for_year(year: int) -> Dictionary:
	if _holiday_cache.has(year):
		return _holiday_cache[year]
	
	var public_map: Dictionary = {} # day_offset: int -> holiday_id: String
	var easter_offset := _compute_easter_sunday_offset(year)
	
	for rule in _jurisdiction_cfg.get("rules", []):
		if not (rule is Dictionary):
			continue
		var from_yr := int(rule.get("valid_from_year", -9999))
		var to_yr := int(rule.get("valid_to_year", 9999))
		if year < from_yr or year > to_yr:
			continue
		
		var h_id := str(rule.get("id", "HOLIDAY"))
		var r_type := str(rule.get("type", "")).to_upper()
		var raw_day := -999999999
		
		match r_type:
			"FIXED":
				var m := int(rule.get("month", 1))
				var d := int(rule.get("day", 1))
				raw_day = _ymd_to_day_offset(year, m, d)
			"EASTER_OFFSET":
				raw_day = easter_offset + int(rule.get("offset_days", 0))
			"NTH_WEEKDAY":
				raw_day = _compute_nth_weekday_offset(year, int(rule.get("month", 1)), int(rule.get("weekday", 1)), int(rule.get("nth", 1)))
			"LAST_WEEKDAY":
				raw_day = _compute_last_weekday_offset(year, int(rule.get("month", 1)), int(rule.get("weekday", 1)))
			"EQUINOX":
				var eq_type := str(rule.get("equinox_type", "VERNAL")).to_upper()
				var eq_day := _compute_equinox_day_of_month(year, eq_type)
				var eq_month := 3 if eq_type == "VERNAL" else 9
				raw_day = _ymd_to_day_offset(year, eq_month, eq_day)
			_:
				assert(false, "FATAL: [CalendarHelper] Unsupported holiday rule type '%s' in jurisdiction '%s'." % [r_type, _jurisdiction_id])
		
		var obs_rule := str(rule.get("observed", "NONE")).to_upper()
		var obs_from := int(rule.get("observed_from_year", -9999))
		if year < obs_from:
			obs_rule = "NONE"
		
		var final_day := _apply_observed_rule(raw_day, obs_rule, public_map)
		public_map[final_day] = h_id
	
	# One-off historical dates (jubilees, coronations, royal weddings)
	for one_off in _jurisdiction_cfg.get("one_off_dates", []):
		if one_off is Dictionary and int(one_off.get("year", -9999)) == year:
			var o_day := _ymd_to_day_offset(year, int(one_off.get("month", 1)), int(one_off.get("day", 1)))
			public_map[o_day] = str(one_off.get("id", "SPECIAL_HOLIDAY"))
	
	# Sandwich holiday rule (e.g. Japan Citizens' Holiday / Silver Week when a weekday sits between two holidays)
	if bool(_jurisdiction_cfg.get("enable_sandwich_holidays", false)) and year >= int(_jurisdiction_cfg.get("sandwich_valid_from_year", 1985)):
		var keys := public_map.keys()
		keys.sort()
		var sandwich_days: Array[int] = []
		for h_day in keys:
			var candidate := int(h_day) + 1
			if not public_map.has(candidate) and public_map.has(candidate + 1):
				var dow := day_of_week(candidate)
				if dow != 7:
					sandwich_days.append(candidate)
		for s_day in sandwich_days:
			public_map[s_day] = "CITIZENS_SANDWICH_HOLIDAY"
	
	# Banking-only closures (e.g., Dec 31 / Jan 2-3 bank closures in Japan)
	var banking_map := public_map.duplicate()
	for b_rule in _jurisdiction_cfg.get("banking_fixed_closures", []):
		if b_rule is Dictionary:
			var b_from := int(b_rule.get("valid_from_year", -9999))
			var b_to := int(b_rule.get("valid_to_year", 9999))
			if year >= b_from and year <= b_to:
				var b_day := _ymd_to_day_offset(year, int(b_rule.get("month", 1)), int(b_rule.get("day", 1)))
				banking_map[b_day] = str(b_rule.get("id", "BANK_CLOSURE"))
	
	var result := {
		"POSTAL": public_map,
		"BANKING": banking_map
	}
	_holiday_cache[year] = result
	return result

static func _apply_observed_rule(raw_day: int, obs_rule: String, existing_holidays: Dictionary) -> int:
	var dow := day_of_week(raw_day) # 1=Mon ... 6=Sat, 7=Sun
	match obs_rule:
		"NONE", "":
			return raw_day
		"NEXT_MONDAY":
			if dow == 6:
				return raw_day + 2
			elif dow == 7:
				return raw_day + 1
			return raw_day
		"NEXT_WEEKDAY":
			var cursor := raw_day
			while day_of_week(cursor) in [6, 7] or existing_holidays.has(cursor):
				cursor += 1
			return cursor
		"NEAREST_WEEKDAY":
			if dow == 6:
				return raw_day - 1
			elif dow == 7:
				return raw_day + 1
			return raw_day
		"NEXT_MONDAY_IF_SUNDAY":
			return raw_day + 1 if dow == 7 else raw_day
		"NEXT_WEEKDAY_IF_SUNDAY":
			if dow != 7:
				return raw_day
			var cursor := raw_day + 1
			while day_of_week(cursor) == 7 or existing_holidays.has(cursor):
				cursor += 1
			return cursor
		_:
			assert(false, "FATAL: [CalendarHelper] Unknown observed rule '%s'." % obs_rule)
			return raw_day

## Meeus/Jones/Butcher Gregorian Computus algorithm (valid for any Gregorian year 1583..4099)
static func _compute_easter_sunday_offset(year: int) -> int:
	var a := year % 19
	var b := int(year / 100.0)
	var c := year % 100
	var d := int(b / 4.0)
	var e := b % 4
	var f := int((b + 8) / 25.0)
	var g := int((b - f + 1) / 3.0)
	var h := (19 * a + b - d - g + 15) % 30
	var i := int(c / 4.0)
	var k := c % 4
	var l := (32 + 2 * e + 2 * i - h - k) % 7
	var m := int((a + 11 * h + 22 * l) / 451.0)
	var month := int((h + l - 7 * m + 114) / 31.0)
	var day := ((h + l - 7 * m + 114) % 31) + 1
	return _ymd_to_day_offset(year, month, day)

static func _compute_nth_weekday_offset(year: int, month: int, target_dow: int, nth: int) -> int:
	var first_offset := _ymd_to_day_offset(year, month, 1)
	var first_dow := day_of_week(first_offset)
	var delta := posmod(target_dow - first_dow, 7)
	return first_offset + delta + ((nth - 1) * 7)

static func _compute_last_weekday_offset(year: int, month: int, target_dow: int) -> int:
	var days_in_month := _days_in_gregorian_month(year, month)
	var last_offset := _ymd_to_day_offset(year, month, days_in_month)
	var last_dow := day_of_week(last_offset)
	var delta := posmod(last_dow - target_dow, 7)
	return last_offset - delta

## Astronomical polynomial approximation for Vernal (March) and Autumnal (September) Equinoxes (1800..2099)
static func _compute_equinox_day_of_month(year: int, eq_type: String) -> int:
	if eq_type == "VERNAL":
		if year < 1900:
			return int(floor(20.8357 + 0.242194 * float(year - 1900) - floor(float(year - 1900) / 4.0)))
		elif year < 2000:
			return int(floor(20.8357 + 0.242194 * float(year - 1980) - floor(float(year - 1980) / 4.0)))
		else:
			return int(floor(20.69115 + 0.2421904 * float(year - 2000) - floor(float(year - 2000) / 4.0)))
	else:
		if year < 1900:
			return int(floor(23.2588 + 0.242194 * float(year - 1900) - floor(float(year - 1900) / 4.0)))
		elif year < 2000:
			return int(floor(23.2588 + 0.242194 * float(year - 1980) - floor(float(year - 1980) / 4.0)))
		else:
			return int(floor(23.09 + 0.2421904 * float(year - 2000) - floor(float(year - 2000) / 4.0)))

# ==============================================================================
# PURE GREGORIAN JULIAN DAY NUMBER (JDN) CONVERSIONS (ZERO SQL ROUND-TRIPS)
# ==============================================================================

static func _parse_iso_ymd(iso: String) -> Array[int]:
	var parts := iso.strip_edges().split("-")
	assert(parts.size() >= 3, "FATAL: [CalendarHelper] Invalid ISO date string '%s'" % iso)
	return [int(parts[0]), int(parts[1]), int(parts[2])]

static func _ymd_to_day_offset(year: int, month: int, day: int) -> int:
	return _gregorian_to_jdn(year, month, day) - _epoch_jdn

static func _day_offset_to_ymd(day_offset: int) -> Array[int]:
	return _jdn_to_gregorian(_epoch_jdn + day_offset)

static func _gregorian_to_jdn(year: int, month: int, day: int) -> int:
	var a := int((14 - month) / 12.0)
	var y := year + 4800 - a
	var m := month + 12 * a - 3
	return day + int((153 * m + 2) / 5.0) + 365 * y + int(y / 4.0) - int(y / 100.0) + int(y / 400.0) - 32045

static func _jdn_to_gregorian(jdn: int) -> Array[int]:
	var f := jdn + 1401 + int((int((4 * jdn + 274277) / 146097.0) * 3) / 4.0) - 38
	var e := 4 * f + 3
	var g := int(posmod(e, 1461) / 4.0)
	var h := 5 * g + 2
	var day := int(posmod(h, 153) / 5.0) + 1
	var month := posmod(int(h / 153.0) + 2, 12) + 1
	var year := int(e / 1461.0) - 4716 + int((12 + 2 - month) / 12.0)
	return [year, month, day]

static func _days_in_gregorian_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			var is_leap := (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)
			return 29 if is_leap else 28
		_:
			return 30