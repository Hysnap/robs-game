# res://scenes/ui/filofax/view_host.gd
class_name ViewHost
extends Node

## Signals emitted purely to notify outer listeners of user interaction
signal route_changed(domain_key: String)
signal item_action_requested(action_type: String, payload: Dictionary)

const SimControllerScript = preload("res://systems/sim_controller.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")
const StationeryRegistryScript = preload("res://scenes/ui/feedback/stationery_registry.gd")

@export var shell_node: OuterShell

# Generic map: domain_key (String) -> Control (Compiled View Instance)
var _views: Dictionary = {}
var _active_domain: String = ""
var _planner_view: Control = null
var _desk_inbox: Control = null
var _composer_modal: Control = null

func _ready() -> void:
	if shell_node == null:
		shell_node = get_parent() as OuterShell

## Mounts any compiled navigation widget into the shell's generic NAV slot
func set_navigation_component(nav_bar: Control) -> void:
	if shell_node:
		shell_node.mount_view("NAV", nav_bar)
		if nav_bar.has_signal("route_requested"):
			nav_bar.connect("route_requested", Callable(self, "_on_nav_route_requested"))

## Registers any compiled UI view to an arbitrary string key from configuration
func register_view(domain_key: String, view_control: Control) -> void:
	_views[domain_key] = view_control

## Swaps whatever view is currently mounted in CONTENT slot
func switch_to_domain(domain_key: String) -> void:
	if not _views.has(domain_key) or shell_node == null:
		return
	_active_domain = domain_key
	shell_node.mount_view("CONTENT", _views[domain_key])
	route_changed.emit(domain_key)

## Pure Data Ingestion: Forwards arbitrary domain telemetry to active view's bind_data()
func update_active_view_data(display_data: Dictionary) -> void:
	if _views.has(_active_domain):
		var active_view: Control = _views[_active_domain]
		if is_instance_valid(active_view) and active_view.has_method("bind_data"):
			active_view.bind_data(display_data)

## Pure Inscription: Records an audit, transaction, or log entry into the target domain's ledger
func inscribe_entry_to_domain(domain_key: String, entry_data: Dictionary) -> void:
	if _views.has(domain_key):
		var target_view: Control = _views[domain_key]
		if is_instance_valid(target_view) and target_view.has_method("inscribe_entry"):
			target_view.inscribe_entry(entry_data)
		else:
			push_warning("[ViewHost] Domain view '%s' does not implement inscribe_entry()" % domain_key)
	else:
		push_warning("[ViewHost] Cannot inscribe entry: unknown domain '%s'" % domain_key)

## Connects the Action Planner and the Desktop Card Stack Inbox
func attach_planner_and_inbox(planner: Control, inbox: Control) -> void:
	_planner_view = planner
	_desk_inbox = inbox
	
	if _planner_view and _planner_view.has_signal("action_clicked"):
		_planner_view.connect("action_clicked", _on_planner_action_clicked)
		
	if _desk_inbox and _desk_inbox.has_signal("top_card_action"):
		_desk_inbox.connect("top_card_action", _on_card_stack_triage)

## Pure Simulation Execution: Hands orders to SimController and routes outcomes
func _execute_operational_cycle() -> void:
	if _planner_view == null:
		return

	var staged: Array = []
	if _planner_view.has_method("get_staged_orders"):
		staged = _planner_view.get_staged_orders()

	if staged.is_empty():
		print("[ViewHost] No directives staged for operational cycle.")
		return

	# 1. SimController runs the pure simulation cycle
	var report: Dictionary = SimControllerScript.process_turn_cycle(GameState.world_state, staged)

	# 2. Clear planner queue
	if _planner_view.has_method("clear_staged_orders"):
		_planner_view.clear_staged_orders()

	# 3. Inscribe memo entries to the DIARY domain
	var current_date_str: String = report.get("calendar_date", "Shift Report")
	for memo in report.get("diary_memos", []):
		inscribe_entry_to_domain("DIARY", {
			"tick": report.get("week", 1),
			"text": "[%s] %s" % [current_date_str, memo]
		})

	# 4. Ingest outcome slips and push to the active inbox
	if _desk_inbox != null and _desk_inbox.has_method("push_cards"):
		StationeryRegistryScript.initialize()
		var events: Array = report.get("executed_events", [])
		var cards: Array = []

		for ev in events:
			var verb: String = ev.get("verb", "")
			var binding: Dictionary = StationeryRegistryScript.get_verb_binding(verb)
			
			var card_payload := {
				"stationery_profile": binding.get("default_definition", "STICKY_NOTE"),
				"destination": binding.get("default_filing_domain", "DIARY"),
				"display_text": ev.get("message", "Task settled."),
				"tick": ev.get("tick", 1),
				"week": ev.get("week", 1),
				"success": ev.get("success", false),
				"author": ev.get("author", "Runner Dispatch")
			}
			cards.append(card_payload)

		if not cards.is_empty():
			_desk_inbox.push_cards(cards)

	# 5. Refresh active view if district docket is open
	var active_id: String = str(GameState.world_state.get("selected_district_id", ""))
	if not active_id.is_empty():
		var district_data: Dictionary = GameState.get_district_view(active_id)
		update_active_view_data(district_data)

## Triage routing: File to domain or discard
func _on_card_stack_triage(action_id: String, card_payload: Dictionary) -> void:
	if action_id == "FILE":
		var dest: String = card_payload.get("destination", "DIARY")
		inscribe_entry_to_domain(dest, {
			"tick": card_payload.get("tick", 1),
			"text": card_payload.get("display_text", "")
		})
		print("[ViewHost] Filed slip to %s: %s" % [dest, card_payload.get("display_text")])
	else:
		print("[ViewHost] Discarded slip into waste: %s" % card_payload.get("display_text"))

func _on_nav_route_requested(domain_token: String, _target_page: String) -> void:
	switch_to_domain(domain_token)

## Connects the Action Queue, Desktop Feedback Inbox, and optional Era Composer Modal
func attach_action_system(planner: Control, inbox: Control, composer_modal: Control = null) -> void:
	_planner_view = planner
	_desk_inbox = inbox
	_composer_modal = composer_modal
	
	if _planner_view and _planner_view.has_signal("action_clicked"):
		_planner_view.connect("action_clicked", _on_planner_action_clicked)
		
	if _composer_modal:
		# Generic signal emitted by ANY era composer when parameters are confirmed
		if _composer_modal.has_signal("directive_committed"):
			_composer_modal.connect("directive_committed", _on_directive_committed_from_composer)
		
	if _desk_inbox and _desk_inbox.has_signal("top_card_action"):
		_desk_inbox.connect("top_card_action", _on_card_stack_triage)

## Unified router for abstract action commands emitted by the planner interface
func _on_planner_action_clicked(action_code: String) -> void:
	var active_district: String = str(GameState.world_state.get("selected_district_id", "DIST_ASTON_01"))

	match action_code:
		# Requests opening whatever parameter modal the active era shell provides
		"OPEN_PAD", "NEW_ORDER", "OPEN_COMPOSER":
			if _composer_modal and _composer_modal.has_method("open_for_context"):
				_composer_modal.open_for_context({"target_district_id": active_district})
			elif _planner_view and _planner_view.has_method("stage_current_selection"):
				_planner_view.stage_current_selection(active_district)

		# Direct staging without a modal (e.g. flat dropdown forms)
		"STAGE":
			if _planner_view and _planner_view.has_method("stage_current_selection"):
				_planner_view.stage_current_selection(active_district)

		# Commits the queue to backend simulation execution
		"COMMIT_SHIFT", "EXECUTE_TURN", "END_DAY":
			_execute_operational_cycle()

## Ingests directives committed from the era composer modal into the planner queue
func _on_directive_committed_from_composer(directive: Dictionary) -> void:
	if _planner_view:
		if _planner_view.has_method("add_directive_to_queue"):
			_planner_view.add_directive_to_queue(directive)
		elif _planner_view.has_method("stage_current_selection"):
			# Fallback if queue exposes internal array
			var queue = _planner_view.get_node_or_null("queue_list") as ItemList
			if queue:
				var verb: String = directive.get("verb", "TASK")
				var item: String = directive.get("target_item", "")
				var qty: float = float(directive.get("amount", 1.0))
				queue.add_item("[%s] %s x%.0f" % [verb, item, qty])
			if "_staged_orders" in _planner_view:
				_planner_view._staged_orders.append(directive)