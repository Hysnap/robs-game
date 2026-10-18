# res://systems/action_base.gd
class_name ActionBase extends RefCounted

## Scans the calling verb's relative impacts/ subfolder
static func load_subfolder_impacts(subfolder_path: String) -> Array:
	var loaded: Array = []
	if not DirAccess.dir_exists_absolute(subfolder_path):
		return loaded

	var dir = DirAccess.open(subfolder_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".gd") and file_name.begins_with("impact_"):
				var script_res = load(subfolder_path.path_join(file_name))
				if script_res:
					loaded.append(script_res)
			file_name = dir.get_next()
		dir.list_dir_end()
	return loaded

## Compiles deltas from all active subfolder impact scripts
static func compile_impact_deltas(impact_scripts: Array, action_params: Dictionary, summary: Dictionary, commodity_profile: Dictionary) -> Dictionary:
	var deltas = {}
	for impact_script in impact_scripts:
		var metric_key: String = impact_script.get_target_metric()
		var delta_val: float = impact_script.calculate_action_delta(action_params, summary, commodity_profile)
		if metric_key != "" and delta_val != 0.0:
			deltas[metric_key] = deltas.get(metric_key, 0.0) + delta_val
	return deltas