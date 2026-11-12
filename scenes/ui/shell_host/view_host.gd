# res://scenes/ui/shell_host/view_host.gd
class_name ViewHost
extends Node


## Unified signal emitting structured UIActionCommand objects
signal ui_command_dispatched(command: UIActionCommand)
signal slip_filed(slip_data: Dictionary, destination: String)

@export var shell_node: OuterShell

# Generic map: domain_key (String) -> Control (Compiled View Instance)
var _views: Dictionary = {}
var _active_domain: String = ""
var _desk_inbox: Control = null
var _action_component: Control = null

func _ready() -> void:
	if shell_node == null:
		shell_node = get_parent() as OuterShell
	_connect_shell_signals()
	SystemLogger.log_info("[ViewHost] View host ready.")

func _exit_tree() -> void:
	cleanup()

func _connect_shell_signals() -> void:
	if shell_node != null and shell_node.has_signal("shell_switch_requested"):
		var cb := Callable(self, "_on_shell_switch_requested")
		if not shell_node.is_connected("shell_switch_requested", cb):
			shell_node.connect("shell_switch_requested", cb)

func _on_shell_switch_requested(shell_id: String) -> void:
	var cmd := UIActionCommand.new(
		UIActionCommand.CommandType.SWITCH_SHELL,
		"",
		shell_id,
		{"shell_id": shell_id}
	)
	ui_command_dispatched.emit(cmd)

## Populates the OuterShell workspace switcher with year-unlocked shells
func sync_shell_selector(shells: Array[Dictionary], active_shell_id: String) -> void:
	_connect_shell_signals()
	if shell_node != null and shell_node.has_method("populate_shell_options"):
		shell_node.populate_shell_options(shells, active_shell_id)

func set_action_component(action_control: Control) -> void:
	_action_component = action_control

	if action_control != null \
	and action_control.has_signal("action_clicked"):
		var callback := Callable(self, "_on_view_action_clicked")
		if not action_control.is_connected("action_clicked", callback):
			action_control.connect("action_clicked", callback)

func get_action_component() -> Control:
	return _action_component

## Mounts any compiled navigation widget into the shell's generic NAV slot
func set_navigation_component(nav_bar: Control) -> void:
	if shell_node:
		shell_node.mount_view("NAV", nav_bar)

	if nav_bar.has_signal("action_clicked"):
		var callback := Callable(self, "_on_navigation_action_clicked")
		if not nav_bar.is_connected("action_clicked", callback):
			nav_bar.connect("action_clicked", callback)

func _on_navigation_action_clicked(
	action_code: String,
	payload: Dictionary
) -> void:
	if action_code != "NAV_ROUTE":
		return

	var domain_token := str(payload.get("domain", "")).strip_edges()
	if domain_token.is_empty():
		push_warning("[ViewHost] Navigation action did not provide a domain.")
		return

	var cmd := UIActionCommand.new(
		UIActionCommand.CommandType.ROUTE_REQUEST,
		domain_token
	)
	ui_command_dispatched.emit(cmd)

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
		if view_control.has_signal("action_clicked"):
			if not view_control.is_connected("action_clicked", Callable(self, "_on_view_action_clicked")):
				view_control.connect("action_clicked", Callable(self, "_on_view_action_clicked"))

## Swaps whatever view is currently mounted in CONTENT slot
func switch_to_domain(domain_key: String) -> void:
	if not _views.has(domain_key) or shell_node == null:
		SystemLogger.log_warn(
			"[ViewHost] Cannot switch to unavailable domain '%s'." % domain_key
		)
		return

	var target_view = _views[domain_key]
	if not is_instance_valid(target_view):
		push_error("[ViewHost] Registered view '%s' has already been freed." % domain_key)
		_views.erase(domain_key)
		return

	_active_domain = domain_key
	shell_node.mount_view("CONTENT", target_view, false)

func get_active_domain() -> String:
	return _active_domain

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

## Mounts the feedback desk inbox and connects its filing and triage signals
func set_desk_inbox(inbox_control: Control) -> void:
	_desk_inbox = inbox_control
	if _desk_inbox != null:
		if _desk_inbox.has_signal("slip_filed"):
			if not _desk_inbox.slip_filed.is_connected(_on_desk_slip_filed):
				_desk_inbox.slip_filed.connect(_on_desk_slip_filed)
		if _desk_inbox.has_signal("top_card_action"):
			if not _desk_inbox.top_card_action.is_connected(_on_desk_top_card_action):
				_desk_inbox.top_card_action.connect(_on_desk_top_card_action)

func _on_desk_slip_filed(slip_data: Dictionary, destination: String) -> void:
	inscribe_entry_to_domain(destination, slip_data)
	slip_filed.emit(slip_data, destination)
	
	# Emit unified command for filing
	var cmd = UIActionCommand.new(UIActionCommand.CommandType.SLIP_FILED, destination, "", slip_data)
	ui_command_dispatched.emit(cmd)

func _on_desk_top_card_action(action_id: String, payload: Dictionary) -> void:
	# Emit unified command for inbox triage actions
	var cmd = UIActionCommand.new(UIActionCommand.CommandType.ACTION_CLICKED, "INBOX", action_id, payload)
	ui_command_dispatched.emit(cmd)

## Presentation helper: Dispatches raw slip cards to the desk inbox
func push_feedback_slips(cards: Array) -> void:
	if _desk_inbox and _desk_inbox.has_method("push_cards"):
		_desk_inbox.push_cards(cards)

## Presentation helper: Ensures the feedback desk stack is visible and brought to the front
func show_feedback_inbox() -> void:
	if _desk_inbox != null:
		_desk_inbox.visible = true
		_desk_inbox.move_to_front()
		var parent_node := _desk_inbox.get_parent()
		if parent_node is CanvasLayer:
			(parent_node as CanvasLayer).visible = true
		elif shell_node != null and shell_node.get_parent() is CanvasLayer:
			(shell_node.get_parent() as CanvasLayer).visible = true

## Frees registered domain views and action planner without tearing down persistent desk inbox
func clear_registered_views() -> void:
	for domain_key in _views.keys():
		var v = _views[domain_key]
		if is_instance_valid(v):
			if v.get_parent() != null:
				v.get_parent().remove_child(v)
			v.queue_free()
	_views.clear()
	_action_component = null

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
	_action_component = null

	if is_instance_valid(_desk_inbox) and _desk_inbox.get_parent() == null:
		_desk_inbox.free()
	_desk_inbox = null

func _on_view_item_selected(target_route: String, filter_key: Variant) -> void:
	var cmd = UIActionCommand.new(UIActionCommand.CommandType.ITEM_SELECTED, target_route, "", {"filter_key": filter_key})
	ui_command_dispatched.emit(cmd)

func _on_view_action_clicked(action_code: String) -> void:
	var cmd = UIActionCommand.new(UIActionCommand.CommandType.ACTION_CLICKED, _active_domain, action_code)
	ui_command_dispatched.emit(cmd)

func _on_nav_route_requested(
	domain_token: String,
	_target_page: String
	) -> void:
	var cmd := UIActionCommand.new(
		UIActionCommand.CommandType.ROUTE_REQUEST,
		domain_token
	)
	ui_command_dispatched.emit(cmd)