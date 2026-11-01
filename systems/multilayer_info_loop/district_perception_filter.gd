# res://systems/multilayer_info_loop/district_perception_filter.gd
class_name DistrictPerceptionFilter
extends RefCounted

const CONDITION_EVALUATOR = preload("res://systems/condition_evaluator.gd")
const FOG_OF_WAR_PATH := "res://data_modules/core/spatial/districts/fog_of_war_rules.json"

static var _rules_cache: Dictionary = {}
static var _metric_profiles_cache: Array = []

## Loads rules dynamically from fog_of_war_rules.json with strict assertion enforcement
static func _get_rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache

	assert(FileAccess.file_exists(FOG_OF_WAR_PATH),
		"FATAL: [DistrictPerceptionFilter] fog_of_war_rules.json not found at: %s" % FOG_OF_WAR_PATH)

	var f := FileAccess.open(FOG_OF_WAR_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [DistrictPerceptionFilter] Failed to open: %s" % FOG_OF_WAR_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [DistrictPerceptionFilter] Root must be a Dictionary in: %s" % FOG_OF_WAR_PATH)

	assert(parsed.has("general"), "FATAL: [DistrictPerceptionFilter] Missing 'general' section in fog_of_war rules.")
	assert(parsed.has("field_access"), "FATAL: [DistrictPerceptionFilter] Missing 'field_access' section in fog_of_war rules.")

	var field_access: Dictionary = parsed["field_access"]
	assert(field_access.has("universally_known_fields"), "FATAL: [DistrictPerceptionFilter] Missing 'universally_known_fields' in field_access.")
	assert(field_access.has("engine_metadata_fields"), "FATAL: [DistrictPerceptionFilter] Missing 'engine_metadata_fields' in field_access.")
	assert(field_access.has("unexplored_masked_defaults"), "FATAL: [DistrictPerceptionFilter] Missing 'unexplored_masked_defaults' in field_access.")

	_rules_cache = parsed
	return _rules_cache

## Recursively scans res://data_modules/ to discover all profile.json files defining perception rules
static func _discover_metric_profiles(dir_path: String) -> Array:
	var profiles: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return profiles

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			profiles.append_array(_discover_metric_profiles(full_path))
		elif file_name == "profile.json":
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary and parsed.has("perception"):
					profiles.append(parsed)
		file_name = dir.get_next()
	dir.list_dir_end()
	return profiles

## Returns cached array of all discovered metric profiles defining perception rules
static func _get_perceived_metric_profiles() -> Array:
	if not _metric_profiles_cache.is_empty():
		return _metric_profiles_cache

	_metric_profiles_cache = _discover_metric_profiles("res://data_modules/")
	return _metric_profiles_cache

## Normalizes perception blocks into an Array of channel spec dictionaries
static func _extract_channel_specs(perception_block: Dictionary) -> Array:
	var specs: Array = []
	if perception_block.is_empty():
		return specs

	# Case 1: Flat single-spec block
	if perception_block.has("mode"):
		specs.append(perception_block)
		return specs

	# Case 2: Named channel dictionaries (Option 1) or outputs array
	if perception_block.has("outputs") and perception_block["outputs"] is Array:
		specs.append_array(perception_block["outputs"])
		return specs

	for channel_key in perception_block.keys():
		var child = perception_block[channel_key]
		if child is Dictionary and child.has("mode"):
			specs.append(child)

	return specs

## Pure in-memory transformation: maps raw input data against player context and config rules
static func filter_district_view(raw_data: Dictionary, player_context: Dictionary) -> Dictionary:
	var district_id: String = str(raw_data.get("district_id", ""))
	assert(not district_id.is_empty(), "FATAL: [DistrictPerceptionFilter] raw_data must contain a non-empty 'district_id'.")

	var rules: Dictionary = _get_rules()
	var general_cfg: Dictionary = rules["general"]
	var field_access: Dictionary = rules["field_access"]

	var universally_known: Array = field_access["universally_known_fields"]
	var engine_metadata: Array = field_access["engine_metadata_fields"]
	var masked_defaults: Dictionary = field_access["unexplored_masked_defaults"]
	var metric_profiles: Array = _get_perceived_metric_profiles()

	var is_landmark: bool = bool(raw_data.get("is_public_landmark", false))
	var known_districts: Array = player_context.get("known_districts", [])
	var is_known: bool = is_landmark or known_districts.has(district_id)

	var home_district_id: String = str(player_context.get("home_district_id", ""))
	var is_home_turf: bool = (district_id == home_district_id)

	var view_data: Dictionary = raw_data.duplicate(true)
	view_data["is_known"] = is_known
	view_data["is_home_turf"] = is_home_turf

	# 1. Masked / Fog-of-War District (Unsurveyed)
	if not is_known:
		var keys_to_check := view_data.keys()
		for key in keys_to_check:
			if not key in universally_known and not key in engine_metadata:
				view_data.erase(key)

		# Apply declarative masked defaults from config
		for m_field in masked_defaults.keys():
			view_data[m_field] = masked_defaults[m_field]

		view_data["intel_status"] = general_cfg.get("unexplored_intel_token", "INTEL_STATUS_UNEXPLORED")
		view_data["intel_status_token"] = general_cfg.get("unexplored_intel_token", "INTEL_STATUS_UNEXPLORED")

		# Agnostically mask all discovered perception channels
		for profile in metric_profiles:
			var p_block: Dictionary = profile.get("perception", {})
			var specs := _extract_channel_specs(p_block)
			for spec in specs:
				var target_key: String = spec.get("target_field", "")
				if not target_key.is_empty():
					view_data[target_key] = spec.get("fallback_token", "UI_INTEL_MASKED_BLANK")

		return view_data

	# 2. Surveyed District Ground Truth & Temporal Decay
	var current_sim_day: int = int(player_context.get("current_sim_day", 1))
	var survey_ticks: Dictionary = player_context.get("district_survey_ticks", {})
	var last_survey_day: int = int(survey_ticks.get(district_id, current_sim_day))
	var elapsed_days: int = current_sim_day - last_survey_day

	var status_tok: String = str(general_cfg.get("verified_intel_token", "INTEL_STATUS_VERIFIED"))
	if bool(general_cfg.get("enable_temporal_decay", true)):
		if elapsed_days > int(general_cfg.get("stale_decay_threshold_days", 28)):
			status_tok = str(general_cfg.get("stale_intel_token", "INTEL_STATUS_STALE"))

	view_data["intel_status"] = status_tok
	view_data["intel_status_token"] = status_tok
	view_data["is_surveyed"] = true

	# 3. Dynamic Measure Transformations via ConditionEvaluator
	var establishment_profiles: Array = []

	for profile in metric_profiles:
		var p_block: Dictionary = profile.get("perception", {})
		var specs := _extract_channel_specs(p_block)
		if specs.is_empty():
			continue

		# Group micro-level profiles applied to individual establishments
		if profile.get("target_scope", "") == "SPATIAL_MICRO" or profile.get("telemetry_source", {}).get("scope", "") == "ESTABLISHMENT":
			establishment_profiles.append(profile)
			continue

		var telemetry: Dictionary = profile.get("telemetry_source", {})
		var t_type: String = str(telemetry.get("type", ""))

		for spec in specs:
			var t_field: String = spec.get("target_field", "")
			if t_field.is_empty():
				continue

			var raw_val: float = 0.0
			var s_field: String = str(spec.get("source_field", ""))

			if not s_field.is_empty() and view_data.has(s_field):
				raw_val = float(view_data[s_field])
			elif t_type == "WORLD_STATE":
				var state_path: String = str(telemetry.get("state_path", ""))
				if state_path.begins_with("districts."):
					var key: String = state_path.get_slice(".", 2)
					raw_val = float(view_data.get(key, 0.0))
				else:
					raw_val = float(view_data.get(state_path, 0.0))
			elif t_type == "SQLITE_DYNAMIC" or t_type == "SQLITE_LIVE":
				var q_field: String = str(telemetry.get("query_field", t_field))
				raw_val = float(view_data.get(q_field, 0.0))
			else:
				raw_val = float(view_data.get(t_field, 0.0))

			view_data[t_field] = CONDITION_EVALUATOR.transform_measure(raw_val, spec, is_home_turf)

	# 4. Transform Sub-Entity Records Agnostically
	var raw_estabs: Array = view_data.get("establishments_summary", [])
	var perceived_estabs: Array = []

	for estab in raw_estabs:
		var e_copy: Dictionary = estab.duplicate(true)
		for e_prof in establishment_profiles:
			var e_specs := _extract_channel_specs(e_prof.get("perception", {}))
			for e_spec in e_specs:
				var source_prop: String = str(e_spec.get("source_field", e_prof.get("telemetry_source", {}).get("query_field", "worker_count")))
				var target_prop: String = str(e_spec.get("target_field", source_prop))
				var raw_count: float = float(e_copy.get(source_prop, 0.0))
				e_copy[target_prop] = CONDITION_EVALUATOR.transform_measure(raw_count, e_spec, is_home_turf)
		perceived_estabs.append(e_copy)

	view_data["establishments_summary"] = perceived_estabs
	return view_data