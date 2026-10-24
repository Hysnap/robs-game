# res://systems/logger.gd
class_name SystemLogger
extends Node

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, CRITICAL = 4 }

const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")
const DEFAULT_LOG_PATH: String = "user://session_output.log"

static var _instance: AppLogger = null

var active_log_level: Level = Level.DEBUG
var log_file: FileAccess = null
var _is_file_enabled: bool = true
var _log_path: String = DEFAULT_LOG_PATH

func _enter_tree() -> void:
	_instance = self

func _ready() -> void:
	_init_configuration()
	if _is_file_enabled:
		_open_log_stream()

## Reads diagnostic rules dynamically from the canonical business_rules.cfg
func _init_configuration() -> void:
	var cfg_path := MANIFEST_MGR.BUSINESS_RULES_PATH
	if not FileAccess.file_exists(cfg_path):
		return

	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) == OK:
		var lvl_str: String = str(cfg.get_value("system_diagnostics", "log_level", "DEBUG")).to_upper()
		match lvl_str:
			"DEBUG": active_log_level = Level.DEBUG
			"INFO":  active_log_level = Level.INFO
			"WARN":  active_log_level = Level.WARN
			"ERROR": active_log_level = Level.ERROR
			"CRITICAL": active_log_level = Level.CRITICAL
			_: active_log_level = Level.DEBUG

		_is_file_enabled = bool(cfg.get_value("system_diagnostics", "enable_file_logging", true))
		_log_path = str(cfg.get_value("system_diagnostics", "session_log_path", DEFAULT_LOG_PATH))

func _open_log_stream() -> void:
	log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if log_file:
		info("Session log stream opened at: %s" % ProjectSettings.globalize_path(_log_path))
	else:
		push_error("[AppLogger CRITICAL] Failed opening log file at: %s (Error: %d)" % [_log_path, FileAccess.get_open_error()])

func _log_message(level: Level, tag: String, message: String) -> void:
	if level < active_log_level:
		return

	var time_str := Time.get_time_string_from_system()
	var formatted := "[%s] [%s] %s" % [time_str, tag, message]

	if level >= Level.ERROR:
		push_error(formatted)
	else:
		print(formatted)

	if _is_file_enabled and log_file:
		log_file.store_line(formatted)
		log_file.flush()

# --- Autoload Instance API (AppLog.info(...)) ---
func debug(msg: String) -> void: _log_message(Level.DEBUG, "DEBUG", msg)
func info(msg: String) -> void:  _log_message(Level.INFO,  "INFO ", msg)
func warn(msg: String) -> void:  _log_message(Level.WARN,  "WARN ", msg)
func error(msg: String) -> void: _log_message(Level.ERROR, "ERROR", msg)
func critical(msg: String) -> void: _log_message(Level.CRITICAL, "CRIT ", msg)

# --- Static Fallback API (AppLogger.log_info(...)) ---
static func log_info(msg: String) -> void:
	if _instance:
		_instance.info(msg)
	else:
		print("[%s] [INFO ] %s" % [Time.get_time_string_from_system(), msg])

static func log_error(msg: String) -> void:
	if _instance:
		_instance.error(msg)
	else:
		push_error("[%s] [ERROR] %s" % [Time.get_time_string_from_system(), msg])

static func log_debug(msg: String) -> void:
	if _instance:
		_instance.debug(msg)
	else:
		print("[%s] [DEBUG] %s" % [Time.get_time_string_from_system(), msg])

static func log_warn(msg: String) -> void:
	if _instance:
		_instance.warn(msg)
	else:
		print("[%s] [WARN ] %s" % [Time.get_time_string_from_system(), msg])