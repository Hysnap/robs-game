# res://systems/operations_controller.gd
class_name OperationsController
extends RefCounted

const SimControllerScript = preload("res://systems/sim_controller.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")
const UIActionCommandScript = preload("res://scenes/ui/shell_host/ui_action_command.gd")
const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")

const UI_COMMANDS_DIR := "res://systems/ui_commands/"

const _SUB_DOCKET_FALLBACKS: Dictionary = {
	"ESTABLISHMENT_DOCKET": "DOSSIER",
	"RESIDENTIAL_DOCKET": "ROSTER",
	"OPERATIVE_DOSSIER": "ROSTER"
}

static var _command_scripts: Dictionary = {} # "open_roster" -> Script
static var _commands_initialized: bool = false
static var _domain_route_cache: Dictionary = {} # "ESTABLISHMENT_DOCKET" -> { "filter_key": 42, ... }

## Crawls res://systems/ui_commands/ for cmd_*.gd handlers and caches them in memory
static func initialize_commands(force_reload: bool = false) -> void:
	if _commands_initialized and not force_reload:
		return

	_command_scripts.clear()
	var paths: Array[String] = FileSystemCrawlerScript.find_files_recursive(UI_COMMANDS_DIR, "", ".gd")
	for path in paths:
		var file_name: String = path.get_file().get_basename().to_lower()
		if not file_name.begins_with("cmd_"):
			continue
		var action_key: String = file_name.trim_prefix("cmd_")
		assert(not action_key.is_empty(), "FATAL: [OperationsController] Invalid command script filename: %s" % path)
		var script_res = load(path)
		assert(script_res != null, "FATAL: [OperationsController] Failed to load UI command script: %s" % path)
		_command_scripts[action_key] = script_res

	_commands_initialized = true
	SystemLogger.log_info("[OperationsController] Registered %d UI command scripts from %s." % [_command_scripts.size(), UI_COMMANDS_DIR])

## Primary entry point for unified UI action commands crossing the MVC boundary
static func dispatch_ui_command(command: UIActionCommandScript, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	initialize_commands()
	assert(command != null, "FATAL: [OperationsController] Received null UIActionCommand.")
	var code: String = command.action_code.strip_edges().to_lower()
	assert(not code.is_empty(), "FATAL: [OperationsController] Received empty UIActionCommand.action_code.")
	assert(_command_scripts.has(code), "FATAL: [OperationsController] Unregistered UI command '%s' (expected %scmd_%s.gd)." % [code, UI_COMMANDS_DIR, code])

	var handler_script = _command_scripts[code]
	handler_script.execute(command.payload, view_host, context_refs)

	if view_host != null and not command.payload.is_empty():
		var active_dom: String = view_host.get_active_domain().strip_edges().to_upper()
		if not active_dom.is_empty():
			_domain_route_cache[active_dom] = command.payload.duplicate(true)

## Refreshes a named domain view by invoking its canonical open_<domain> command script
static func refresh_domain_view(domain_key: String, view_host: ViewHost, payload: Dictionary = {}) -> void:
	if view_host == null or domain_key.is_empty():
		return
	initialize_commands()

	var norm_domain: String = domain_key.strip_edges().to_upper()
	var effective_payload: Dictionary = payload.duplicate(true)
	if not effective_payload.is_empty():
		_domain_route_cache[norm_domain] = effective_payload.duplicate(true)
	elif _domain_route_cache.has(norm_domain):
		effective_payload = (_domain_route_cache[norm_domain] as Dictionary).duplicate(true)
	elif _SUB_DOCKET_FALLBACKS.has(norm_domain):
		norm_domain = _SUB_DOCKET_FALLBACKS[norm_domain]

	var open_code: String = "open_" + norm_domain.to_lower()
	if _command_scripts.has(open_code):
		_command_scripts[open_code].execute(effective_payload, view_host, {})
	else:
		view_host.switch_to_domain(norm_domain)

## Executes staged directives through SimController, updates world state, and returns UI payloads
static func execute_staged_cycle(staged_orders: Array, view_host: ViewHost = null) -> Dictionary:
	SystemLogger.log_info("[OperationsController] Executing %d staged directives." % staged_orders.size())
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		SystemLogger.log_error("[OperationsController] GameState or world_state unmounted.")
		push_error("[OperationsController] GameState or world_state unmounted.")
		return {}

	if staged_orders.is_empty():
		SystemLogger.log_info("[OperationsController] No directives staged: executing idle turn cycle.")

	# 1. Run pure simulation cycle
	var report: Dictionary = SimControllerScript.process_turn_cycle(gs.world_state, staged_orders)

	# 2. Ingest outcome slips via FeedbackTranslator
	var events: Array = report.get("executed_events", [])
	var cards: Array = FeedbackTranslatorScript.triggers_to_slip_cards(events)

	# 3. If a ViewHost is present, update the UI layers using the typed mount contract
	if view_host != null:
		var planner_view: Control = view_host.get_action_component()
		if is_instance_valid(planner_view) and planner_view.has_method("clear_staged_directives"):
			planner_view.clear_staged_directives()

		var current_date_str: String = report.get("calendar_date", "Shift Report")
		for memo in report.get("diary_memos", []):
			view_host.inscribe_entry_to_domain("DIARY", {
				"tick": report.get("week", 1),
				"text": "[%s] %s" % [current_date_str, memo]
			})

		if not cards.is_empty():
			view_host.push_feedback_slips(cards)
			if view_host.has_method("show_feedback_inbox"):
				view_host.show_feedback_inbox()

		refresh_domain_view(view_host.get_active_domain(), view_host)

	# 4. Notify world of timeline step
	if gs.has_signal("turn_advanced"):
		var current_day_tick: int = int(report.get("current_sim_day", report.get("day_offset", gs.world_state.get("metadata", {}).get("current_day_tick", 1))))
		gs.turn_advanced.emit(current_day_tick)

	SystemLogger.log_info("[OperationsController] Operational cycle produced %d feedback cards." % cards.size())
	return report