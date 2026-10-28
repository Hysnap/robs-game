# res://scenes/ui/filofax/view_host.gd
class_name ViewHost
extends Node

## Signals emitted purely to notify outer listeners of user interaction
signal route_changed(domain_key: String)
signal item_action_requested(action_type: String, payload: Dictionary)

@export var shell_node: OuterShell

# Generic map: domain_key (String) -> Control (Compiled View Instance)
var _views: Dictionary = {}
var _active_domain: String = ""

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

## Pure Data Ingestion: Forwards arbitrary dictionary to active view's bind_data()
func update_active_view_data(display_data: Dictionary) -> void:
	if _views.has(_active_domain):
		var active_view: Control = _views[_active_domain]
		if active_view.has_method("bind_data"):
			active_view.bind_data(display_data)

## Pure Inscription: Appends a note entry to the target view's ruled paper lines
func inscribe_entry_to_domain(domain_key: String, entry_data: Dictionary) -> void:
	if _views.has(domain_key):
		var target_view: Control = _views[domain_key]
		if target_view.has_method("inscribe_entry"):
			target_view.inscribe_entry(entry_data)

func _on_nav_route_requested(domain_token: String, _target_page: String) -> void:
	switch_to_domain(domain_token)