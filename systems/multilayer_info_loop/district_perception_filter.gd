# res://systems/multilayer_info_loop/district_perception_filter.gd
class_name DistrictPerceptionFilter
extends RefCounted

const CONDITION_EVALUATOR = preload("res://systems/condition_evaluator.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const FOG_OF_WAR_PATH := "res://data_modules/core/spatial/districts/fog_of_war_rules.json"

static var _rules_cache: Dictionary = {}
static var _metric_profiles_cache: Array = []

## Clears cached fog-of-war rules and discovered metric profiles
static func reset_cache() -> void:
	_rules_cache.clear()
	_metric_profiles_cache.clear()

## Loads rules dynamically from manifest ("fog_of_war") or fog_of_war_rules.json
static func _get_rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache

	var parsed: Dictionary = {}
	if ScenarioManifestManagerScript.has_module("fog_of_war"):
		parsed = ScenarioManifestManagerScript.load_module("fog_of_war")
	else:
		assert(FileAccess.file_exists(FOG_OF_WAR_PATH),
			"FATAL: [DistrictPerceptionFilter] fog_of_war_rules.json not found at: %s" % FOG_OF_WAR_PATH)
		var f := FileAccess.open(FOG_OF_WAR_PATH, FileAccess.READ)
		assert(f != null, "FATAL: [DistrictPerceptionFilter] Failed to open: %s" % FOG_OF_WAR_PATH)
		var raw = JSON.parse_string(f.get_as_text())
		assert(raw is Dictionary, "FATAL: [DistrictPerceptionFilter] Root must be a Dictionary in: %s" % FOG_OF_WAR_PATH)
		parsed = raw

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

	if perception_block.has("mode"):
		specs.append(perception_block)
		return specs

	if perception_block.has("outputs") and perception_block["outputs"] is Array:
		specs.append_array(perception_block["outputs"])
		return specs

	for channel_key in perception_block.keys():
		var child = perception_block[channel_key]
		if child is Dictionary and child.has("mode"):
			specs.append(child)

	return specs

## Resolves continuous 0-100 score strictly from player_context["intel_scores"] or sparse knowledge_pools (zero fallbacks)
static func _resolve_entity_score(player_context: Dictionary, target_scope: String, target_id: String) -> float:
	assert(not target_id.is_empty(), "FATAL: [DistrictPerceptionFilter] target_id cannot be empty.")
	assert(not player_context.has("known_districts"),
		"FATAL: [DistrictPerceptionFilter] Legacy binary visibility arrays ('known_districts') are retired. Supply 'intel_scores' or ('world_state' + 'observers').")

	var explicit_scores = player_context.get("intel_scores", null)
	if explicit_scores is Dictionary:
		var compound_key := "%s:%s" % [target_scope.to_upper(), target_id]
		if explicit_scores.has(compound_key):
			return clampf(float(explicit_scores[compound_key]), 0.0, 100.0)
		if explicit_scores.has(target_id):
			return clampf(float(explicit_scores[target_id]), 0.0, 100.0)
		return 0.0

	var world_state = player_context.get("world_state", null)
	var observers = player_context.get("observers", null)
	assert(world_state is Dictionary and observers is Array,
		"FATAL: [DistrictPerceptionFilter] player_context must provide either 'intel_scores' Dictionary or ('world_state' Dictionary + 'observers' Array).")

	return IntelManagerScript.get_collective_score(world_state, observers, target_scope, target_id)

## Builds an attenuated copy of a perception channel spec scaled by the entity's 0-100 intel score
static func _attenuate_channel_spec(spec: Dictionary, score: float) -> Dictionary:
	if not spec.has("fuzz_jitter_min") and not spec.has("fuzz_jitter_max"):
		return spec
	var attenuated: Dictionary = spec.duplicate(true)
	var err_floor: float = float(attenuated.get("error_floor", 0.0))
	if attenuated.has("fuzz_jitter_min"):
		attenuated["fuzz_jitter_min"] = IntelManagerScript.attenuate_fuzz(float(attenuated["fuzz_jitter_min"]), err_floor, score)
	if attenuated.has("fuzz_jitter_max"):
		attenuated["fuzz_jitter_max"] = IntelManagerScript.attenuate_fuzz(float(attenuated["fuzz_jitter_max"]), err_floor, score)
	return attenuated

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
	var district_score: float = _resolve_entity_score(player_context, "DISTRICT", district_id)
	if is_landmark and district_score < 20.0:
		district_score = 20.0

	var is_known: bool = IntelManagerScript.is_entity_known(district_score, "DISTRICT")

	var home_district_id: String = str(player_context.get("home_district_id", ""))
	var is_home_turf: bool = (district_id == home_district_id)

	var view_data: Dictionary = raw_data.duplicate(true)
	view_data["is_known"] = is_known
	view_data["is_home_turf"] = is_home_turf
	view_data["intel_score"] = district_score

	# 1. Masked / Fog-of-War District (Below existence threshold)
	if not is_known:
		var keys_to_check := view_data.keys()
		for key in keys_to_check:
			if not key in universally_known and not key in engine_metadata:
				view_data.erase(key)

		for m_field in masked_defaults.keys():
			view_data[m_field] = masked_defaults[m_field]

		view_data["intel_status"] = general_cfg.get("unexplored_intel_token", "INTEL_STATUS_UNEXPLORED")
		view_data["intel_status_token"] = general_cfg.get("unexplored_intel_token", "INTEL_STATUS_UNEXPLORED")

		for profile in metric_profiles:
			var p_block: Dictionary = profile.get("perception", {})
			var specs := _extract_channel_specs(p_block)
			for spec in specs:
				var target_key: String = spec.get("target_field", "")
				if not target_key.is_empty():
					view_data[target_key] = spec.get("fallback_token", "UI_INTEL_MASKED_BLANK")

		return view_data

	# 2. Discovered District Intel Status
	var status_tok: String = str(general_cfg.get("verified_intel_token", "INTEL_STATUS_VERIFIED"))
	if district_score < 40.0:
		status_tok = str(general_cfg.get("stale_intel_token", "INTEL_STATUS_STALE"))

	view_data["intel_status"] = status_tok
	view_data["intel_status_token"] = status_tok
	view_data["is_surveyed"] = true

	# 3. Resolve Exposed District Fields First
	var exposed_district_fields := IntelManagerScript.get_exposed_fields(district_score, "DISTRICT")
	var allow_all_district_fields: bool = exposed_district_fields.has("*")

	# 4. Dynamic Measure Transformations with Intel-Attenuated Fuzz (only for exposed fields)
	var establishment_profiles: Array = []
	var perceived_output_fields: Array[String] = []

	for profile in metric_profiles:
		var p_block: Dictionary = profile.get("perception", {})
		var specs := _extract_channel_specs(p_block)
		if specs.is_empty():
			continue

		if profile.get("target_scope", "") == "SPATIAL_MICRO" or profile.get("telemetry_source", {}).get("scope", "") == "ESTABLISHMENT":
			establishment_profiles.append(profile)
			continue

		var telemetry: Dictionary = profile.get("telemetry_source", {})
		var t_type: String = str(telemetry.get("type", ""))

		for spec in specs:
			var t_field: String = spec.get("target_field", "")
			if t_field.is_empty():
				continue
			if not allow_all_district_fields and not exposed_district_fields.has(t_field):
				view_data.erase(t_field)
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

			var scaled_spec := _attenuate_channel_spec(spec, district_score)
			view_data[t_field] = CONDITION_EVALUATOR.transform_measure(raw_val, scaled_spec, is_home_turf)
			perceived_output_fields.append(t_field)

	# 5. Enforce Threshold Field Exposure on Remaining District Fields
	if not allow_all_district_fields:
		var current_keys := view_data.keys()
		for k in current_keys:
			var k_str := str(k)
			if k_str in universally_known or k_str in engine_metadata or k_str in perceived_output_fields:
				continue
			if k_str in ["is_known", "is_home_turf", "is_surveyed", "intel_score", "intel_status", "intel_status_token"]:
				continue
			if not exposed_district_fields.has(k_str):
				view_data.erase(k_str)

	# 6. Filter & Project Sub-Entity Establishment Records by Individual 0-100 Score
	var raw_estabs: Array = view_data.get("establishments_summary", [])
	var perceived_estabs: Array = []

	for estab in raw_estabs:
		if not (estab is Dictionary):
			continue
		var estab_id: String = str(estab.get("establishment_id", ""))
		var estab_score: float = _resolve_entity_score(player_context, "ESTABLISHMENT", estab_id)
		if bool(estab.get("is_public_landmark", false)) and estab_score < 20.0:
			estab_score = 20.0
		if not IntelManagerScript.is_entity_known(estab_score, "ESTABLISHMENT"):
			continue

		var e_copy: Dictionary = estab.duplicate(true)
		for e_prof in establishment_profiles:
			var e_specs := _extract_channel_specs(e_prof.get("perception", {}))
			for e_spec in e_specs:
				var source_prop: String = str(e_spec.get("source_field", e_prof.get("telemetry_source", {}).get("query_field", "worker_count")))
				var target_prop: String = str(e_spec.get("target_field", source_prop))
				var raw_count: float = float(e_copy.get(source_prop, 0.0))
				var scaled_e_spec := _attenuate_channel_spec(e_spec, estab_score)
				e_copy[target_prop] = CONDITION_EVALUATOR.transform_measure(raw_count, scaled_e_spec, is_home_turf)

		var projected_estab := IntelManagerScript.project_record(e_copy, estab_score, "ESTABLISHMENT")
		projected_estab["intel_score"] = estab_score
		perceived_estabs.append(projected_estab)

	if view_data.has("establishments_summary"):
		view_data["establishments_summary"] = perceived_estabs
	return view_data