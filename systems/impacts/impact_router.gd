# res://systems/impacts/impact_router.gd
class_name ImpactRouter extends RefCounted

static var _registered_sinks: Dictionary = {} # Key: String (e.g., "POLICE_HEAT"), Value: ImpactSinkBase

## Register a sink handler for a specific metric key
static func register_sink(sink_class: Variant) -> void:
	var key: String = sink_class.get_metric_key()
	if key != "":
		_registered_sinks[key] = sink_class

## Routes calculated deltas to the appropriate sink
static func dispatch_delta(world_state: Dictionary, target_id: String, metric_key: String, delta: float) -> void:
	if _registered_sinks.has(metric_key):
		_registered_sinks[metric_key].apply_delta(world_state, target_id, delta)
	else:
		push_warning("[IMPACT ROUTER] No sink registered for metric: '%s'" % metric_key)

## Ticks ambient background updates across all mounted sinks
static func dispatch_ambient_tick(world_state: Dictionary) -> void:
	for metric_key in _registered_sinks.keys():
		_registered_sinks[metric_key].process_ambient(world_state)

## Autoloads all sink scripts found in a given data module directory
static func autoload_sinks(impacts_root_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(impacts_root_dir):
		return
	
	var dir = DirAccess.open(impacts_root_dir)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			var full_path = impacts_root_dir.path_join(entry)
			if dir.current_is_dir() and not entry.begins_with("."):
				autoload_sinks(full_path) # Recurse into subfolders
			elif entry.ends_with(".gd") and entry.begins_with("sink_"):
				var script = load(full_path)
				if script and script.has_method("get_metric_key"):
					register_sink(script)
			entry = dir.get_next()
		dir.list_dir_end()

static func get_metric_scope(metric_key: String) -> String:
	if _registered_sinks.has(metric_key):
		var sink = _registered_sinks[metric_key]
		if sink.has_method("get_target_scope"):
			return sink.get_target_scope()
	return "SPATIAL"