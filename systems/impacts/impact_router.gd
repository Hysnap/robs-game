# res://systems/impacts/impact_router.gd
class_name ImpactRouter
extends RefCounted

const UNIVERSAL_SINK = preload("res://systems/impacts/universal_metric_sink.gd")

## Registry maps: metric_id -> UniversalMetricSink instance
static var _sinks: Dictionary = {}
static var _metric_scopes: Dictionary = {}

## Clears all mounted sinks
static func reset() -> void:
	_sinks.clear()
	_metric_scopes.clear()

## Registers a sink instance manually under a metric key
static func register_sink(metric_key: String, sink: Variant) -> void:
	_sinks[metric_key] = sink
	if sink.has_method("get_target_scope"):
		_metric_scopes[metric_key] = sink.get_target_scope()
	else:
		_metric_scopes[metric_key] = "SPATIAL"

## Returns whether a metric has a registered sink
static func has_sink(metric_key: String) -> bool:
	return _sinks.has(metric_key)

## Returns the declared target scope ("SPATIAL", "ACTOR", "GLOBAL")
static func get_metric_scope(metric_key: String) -> String:
	return str(_metric_scopes.get(metric_key, "SPATIAL"))

## Dispatches an immediate action impulse delta to the registered sink
static func dispatch_delta(world_state: Dictionary, target_id: String, metric_key: String, delta: float) -> void:
	if not _sinks.has(metric_key):
		return
	var sink = _sinks[metric_key]
	if sink.has_method("apply_delta"):
		sink.apply_delta(world_state, target_id, delta)

## Ambient turn-boundary heartbeat: ticks all registered sinks
static func dispatch_ambient_tick(world_state: Dictionary) -> void:
	for metric_key in _sinks.keys():
		var sink = _sinks[metric_key]
		if sink.has_method("process_ambient"):
			sink.process_ambient(world_state)

## Scans the directory tree recursively, mounting UniversalMetricSink instances from profile.json
static func autoload_sinks(root_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(root_dir):
		return
	_scan_and_mount_profiles(root_dir)

static func _scan_and_mount_profiles(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while not file_name.is_empty():
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			_scan_and_mount_profiles(full_path)
		elif file_name == "profile.json":
			_mount_profile_file(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()

static func _mount_profile_file(profile_path: String) -> void:
	var f := FileAccess.open(profile_path, FileAccess.READ)
	if f == null:
		return

	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return

	var metric_id: String = str(parsed.get("metric_id", ""))
	if metric_id.is_empty():
		# Fallback to folder name in uppercase if metric_id is not explicitly provided
		metric_id = profile_path.get_base_dir().get_file().to_upper()
		parsed["metric_id"] = metric_id

	var sink_instance = UNIVERSAL_SINK.new(parsed)
	register_sink(metric_id, sink_instance)