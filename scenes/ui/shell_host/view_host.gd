# res://scenes/ui/shell_host/view_host.gd
class_name ViewHost
extends Node

## Signals emitted outward to notify orchestrating controllers of user intent
signal route_changed(domain_key: String)
signal action_requested(action_code: String, payload: Dictionary)
signal triage_slip_action(action_id: String, card_payload: Dictionary)
signal item_selected(target_route: String, filter_key: Variant)

@export var shell_node: OuterShell

# Generic map: domain_key (String) -> Control (Compiled View Instance)
var _views: Dictionary = {}
var _active_domain: String = ""
var _planner_view: Control = null
var _desk_inbox: Control = null
var _composer_modal: Control = null

# Staged turn directives buffer
var _staged_directives: Array[Dictionary] = []

func _ready() -> void:
	if shell_node == null:
		shell_node = get_parent() as OuterShell
	SystemLogger.log_info("[ViewHost] View host ready.")

func _exit_tree() -> void:
	cleanup()

## Mounts any compiled navigation widget into the shell's generic NAV slot
func set_navigation_component(nav_bar: Control) -> void:
	if shell_node:
		shell_node.mount_view("NAV", nav_bar)
		if nav_bar.has_signal("route_requested"):
			nav_bar.connect("route_requested", Callable(self, "_on_nav_route_requested"))

## Registers any compiled UI view to an arbitrary string key from configuration
func register_view(domain_key: String, view_control: Control) -> void:
	SystemLogger.log_debug("[ViewHost] Registering view domain '%s'." % domain_key)
	if _views.has(domain_key):
		var old_view = _views[domain_key]
		if is_instance_valid(old_view) and old_view != view_control:
			if old_view.get_parent() != null:
				old_view.get_parent().remove_child(old_view)
			old_view.queue_free()
	_views[domain_key] = view_control

	if is_instance_valid(view_control):
		if view_control.has_signal("item_selected"):
			if not view_control.is_connected("item_selected", Callable(self, "_on_view_item_selected")):
				view_control.connect("item_selected", Callable(self, "_on_view_item_selected"))
		if view_control.has_signal("route_requested"):
			if not view_control.is_connected("route_requested", Callable(self, "_on_nav_route_requested")):
				view_control.connect("route_requested", Callable(self, "_on_nav_route_requested"))

## Swaps whatever view is currently mounted in CONTENT slot
func switch_to_domain(domain_key: String) -> void:
	if not _views.has(domain_key) or shell_node == null:
		SystemLogger.log_warn("[ViewHost] Cannot switch to unavailable domain '%s'." % domain_key)
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

## Checks whether a registered domain view supports the inscribe_entry protocol
func supports_inscriptions(domain_key: String) -> bool:
	if _views.has(domain_key):
		var target_view: Control = _views[domain_key]
		return is_instance_valid(target_view) and target_view.has_method("inscribe_entry")
	return false

## Pure Inscription: Records an audit, transaction, or log entry into the target domain's ledger
func inscribe_entry_to_domain(domain_key: String, entry_data: Dictionary) -> void:
	if _views.has(domain_key):
		var target_view: Control = _views[domain_key]
		if is_instance_valid(target_view) and target_view.has_method("inscribe_entry"):
			target_view.inscribe_entry(entry_data)
	else:
		SystemLogger.log_warn("[ViewHost] Cannot inscribe entry: unknown domain '%s'." % domain_key)
		push_warning("[ViewHost] Cannot inscribe entry: unknown domain '%s'" % domain_key)

## Connects the Action Planner, Desktop Feedback Inbox, and optional Era Composer Modal
func attach_action_system(planner: Control, inbox: Control, composer_modal: Control = null) -> void:
	_planner_view = planner
	_desk_inbox = inbox
	_composer_modal = composer_modal

	if _planner_view and _planner_view.has_signal("action_clicked"):
		_planner_view.connect("action_clicked", func(action_code: String):
			match action_code:
				"MOVE_UP":
					move_staged_directive(-1)
				"MOVE_DOWN":
					move_staged_directive(1)
				"REMOVE_ORDER":
					remove_staged_directive()
				_:
					action_requested.emit(action_code, {})
		)

	if _composer_modal and _composer_modal.has_signal("directive_committed"):
		_composer_modal.connect("directive_committed", func(directive: Dictionary):
			add_staged_directive(directive)
		)

	if _desk_inbox and _desk_inbox.has_signal("top_card_action"):
		_desk_inbox.connect("top_card_action", func(action_id: String, payload: Dictionary):
			triage_slip_action.emit(action_id, payload)
		)

## Adds a newly committed directive to the staged queue buffer
func add_staged_directive(directive: Dictionary) -> void:
	_staged_directives.append(directive)
	_refresh_planner_queue_display(_staged_directives.size() - 1)

## Moves the currently selected directive up (-1) or down (+1) in the staging queue
func move_staged_directive(direction: int) -> void:
	var selected_idx := _get_selected_queue_index()
	if selected_idx == -1:
		return

	var target_idx := selected_idx + direction
	if target_idx < 0 or target_idx >= _staged_directives.size():
		return

	var temp := _staged_directives[selected_idx]
	_staged_directives[selected_idx] = _staged_directives[target_idx]
	_staged_directives[target_idx] = temp

	_refresh_planner_queue_display(target_idx)

## Discards the currently selected directive from the staging queue
func remove_staged_directive() -> void:
	var selected_idx := _get_selected_queue_index()
	if selected_idx == -1 or selected_idx >= _staged_directives.size():
		return

	_staged_directives.remove_at(selected_idx)
	var new_select := clampi(selected_idx, 0, _staged_directives.size() - 1)
	if _staged_directives.is_empty():
		new_select = -1
	_refresh_planner_queue_display(new_select)

func _get_selected_queue_index() -> int:
	if _planner_view == null:
		return -1
	var list_ctrl := _planner_view.find_child("queue_list", true, false) as ItemList
	if list_ctrl == null:
		# Fallback checking dictionary map if compiled
		if "_value_labels" in _planner_view and _planner_view._value_labels.has("queue_list"):
			list_ctrl = _planner_view._value_labels["queue_list"] as ItemList
	if list_ctrl and list_ctrl.is_anything_selected():
		var sel = list_ctrl.get_selected_items()
		if not sel.is_empty():
			return sel[0]
	return -1

func _refresh_planner_queue_display(select_index: int = -1) -> void:
	if _planner_view == null:
		return

	var display_queue: Array = []
	for i in range(_staged_directives.size()):
		var d: Dictionary = _staged_directives[i]
		var verb: String = str(d.get("verb", "ORDER"))
		var item: String = str(d.get("target_item", ""))
		var qty: float = float(d.get("amount", 0.0))
		var assignee: String = str(d.get("assigned_to", d.get("initiator_id", "Player")))
		var target_node: String = str(d.get("target_node_id", ""))
		var contact: String = str(d.get("counterparty_id", ""))

		var line := "%d. [%s] %s x%.0f @ %s (Assigned: %s)" % [
			i + 1, verb, item, qty, target_node, assignee
		]
		if not contact.is_empty():
			line += " [Contact: %s]" % contact
		display_queue.append(line)

	if _planner_view.has_method("bind_data"):
		_planner_view.bind_data({"staged_queue": display_queue})

	# Restore selection pointer so the user can keep pressing Up/Down
	if select_index >= 0:
		var list_ctrl := _planner_view.find_child("queue_list", true, false) as ItemList
		if list_ctrl == null and "_value_labels" in _planner_view and _planner_view._value_labels.has("queue_list"):
			list_ctrl = _planner_view._value_labels["queue_list"] as ItemList
		if list_ctrl and select_index < list_ctrl.item_count:
			list_ctrl.select(select_index)

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
	return _staged_directives.duplicate(true)

## Presentation helper: Clears staged directives in planner
func clear_staged_directives() -> void:
	_staged_directives.clear()
	_refresh_planner_queue_display()

## Cleanly frees all registered view instances and clears cached references
func cleanup() -> void:
	for domain_key in _views.keys():
		var v = _views[domain_key]
		if is_instance_valid(v):
			if v.get_parent() != null:
				v.get_parent().remove_child(v)
			v.free()
	_views.clear()
	_active_domain = ""
	_staged_directives.clear()

	if is_instance_valid(_planner_view) and _planner_view.get_parent() == null:
		_planner_view.free()
	_planner_view = null

	if is_instance_valid(_desk_inbox) and _desk_inbox.get_parent() == null:
		_desk_inbox.free()
	_desk_inbox = null

	if is_instance_valid(_composer_modal) and _composer_modal.get_parent() == null:
		_composer_modal.free()
	_composer_modal = null

func _on_view_item_selected(target_route: String, filter_key: Variant) -> void:
	item_selected.emit(target_route, filter_key)

func _on_nav_route_requested(domain_token: String, _target_page: String) -> void:
	switch_to_domain(domain_token)