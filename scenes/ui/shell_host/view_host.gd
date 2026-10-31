# res://scenes/ui/shell_host/view_host.gd
class_name ViewHost
extends Node

## Signals emitted outward to notify orchestrating controllers of user intent
signal route_changed(domain_key: String)
signal action_requested(action_code: String, payload: Dictionary)
signal triage_slip_action(action_id: String, card_payload: Dictionary)

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

## Connects the Action Planner, Desktop Feedback Inbox, and optional Era Composer Modal
func attach_action_system(planner: Control, inbox: Control, composer_modal: Control = null) -> void:
	_planner_view = planner
	_desk_inbox = inbox
	_composer_modal = composer_modal
	
	if _planner_view and _planner_view.has_signal("action_clicked"):
		_planner_view.connect("action_clicked", func(action_code: String):
			action_requested.emit(action_code, {})
		)
		
	if _composer_modal and _composer_modal.has_signal("directive_committed"):
		_composer_modal.connect("directive_committed", func(directive: Dictionary):
			if _planner_view and _planner_view.has_method("add_directive_to_queue"):
				_planner_view.add_directive_to_queue(directive)
		)
		
	if _desk_inbox and _desk_inbox.has_signal("top_card_action"):
		_desk_inbox.connect("top_card_action", func(action_id: String, payload: Dictionary):
			triage_slip_action.emit(action_id, payload)
		)

## Presentation helper: Opens the mounted composer modal with caller context
func open_composer(context_payload: Dictionary = {}) -> void:
	if _composer_modal and _composer_modal.has_method("open_for_context"):
		_composer_modal.open_for_context(context_payload)

## Presentation helper: Dispatches raw slip cards to the desk inbox
func push_feedback_slips(cards: Array) -> void:
	if _desk_inbox and _desk_inbox.has_method("push_cards"):
		_desk_inbox.push_cards(cards)

## Presentation helper: Gets staged directives from planner
func get_staged_directives() -> Array:
	if _planner_view and _planner_view.has_method("get_staged_orders"):
		return _planner_view.get_staged_orders()
	return []

## Presentation helper: Clears staged directives in planner
func clear_staged_directives() -> void:
	if _planner_view and _planner_view.has_method("clear_staged_orders"):
		_planner_view.clear_staged_orders()

func _on_nav_route_requested(domain_token: String, _target_page: String) -> void:
	switch_to_domain(domain_token)