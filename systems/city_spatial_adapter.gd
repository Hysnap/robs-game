# res://systems/city_spatial_adapter.gd
class_name CitySpatialAdapter
extends RefCounted

const SOCIAL_NETWORK = preload("res://systems/social_network_generator.gd")

static var _archetypes: Dictionary = {}

static func load_archetypes(file_path: String = "res://data_modules/core/spatial/districts/archetypes.json") -> void:
	if not FileAccess.file_exists(file_path):
		push_error("[CRITICAL FATAL] Missing required district archetypes file: %s" % file_path)
		assert(false, "HALT: Cannot generate city without valid archetypes.json at %s" % file_path)
		return

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		var err := FileAccess.get_open_error()
		push_error("[CRITICAL FATAL] Failed opening %s. Error code: %d" % [file_path, err])
		assert(false, "HALT: Unreadable archetypes file: %s" % file_path)
		return

	var json := JSON.new()
	var parse_err := json.parse(file.get_as_text())
	if parse_err != OK or not json.data is Dictionary:
		push_error("[CRITICAL FATAL] JSON Syntax Error in %s on line %d: %s" % [file_path, json.get_error_line(), json.get_error_message()])
		assert(false, "HALT: Corrupt or invalid JSON in %s" % file_path)
		return

	_archetypes = json.data
	print("[CitySpatialAdapter] Successfully loaded %d district archetypes from: %s" % [_archetypes.size(), file_path])

static func ingest_citycrafter_generation(citycrafter_node: Node3D, out_world_state: Dictionary, seed_id: String) -> void:
	if _archetypes.is_empty():
		load_archetypes()
		
	# Strict assertion: Ensure archetypes actually populated
	assert(not _archetypes.is_empty(), "HALT: _archetypes dictionary is empty during city ingestion!")

	if not out_world_state.has("districts"):
		out_world_state["districts"] = {}
	if not out_world_state.has("filofax_cache"):
		out_world_state["filofax_cache"] = {"districts": {}, "pinned_memos": []}

	# Identify configured home district from rules
	var home_id: String = "block_0_0"
	var rules_path := "res://data_modules/core/business_rules.cfg"
	var rules_file := ConfigFile.new()
	if rules_file.load(rules_path) == OK:
		home_id = rules_file.get_value("starting_operations", "home_district_id", "block_0_0")
	else:
		push_warning("[CitySpatialAdapter] business_rules.cfg missing at %s; defaulting home_id to block_0_0" % rules_path)

	var rng := RandomNumberGenerator.new()
	
	for child in citycrafter_node.get_children():
		if not child.has_meta("city_entity_type") or child.get_meta("city_entity_type") != "district":
			continue

		var block_id: String = child.get_meta("block_id")
		var district_type: String = child.get_meta("district")
		var pos_3d: Vector3 = child.global_position

		# 1. Strict Archetype Validation: Must exist in JSON!
		if not _archetypes.has(district_type):
			# If civic site, check if civic_default exists
			if district_type in ["local_government", "hospital_site", "university_campus"] and _archetypes.has("civic_default"):
				district_type = "civic_default"
			else:
				push_error("[CRITICAL FATAL] District '%s' has type '%s' which is not defined in archetypes.json!" % [block_id, district_type])
				assert(false, "HALT: Missing archetype definition for '%s'" % district_type)
				return

		var archetype: Dictionary = _archetypes[district_type]

		# 2. Strict Schema Verification: Assert required arrays exist in the archetype
		assert(archetype.has("population_range"), "Archetype '%s' missing required 'population_range'" % district_type)
		assert(archetype.has("unemployment_rate_range"), "Archetype '%s' missing required 'unemployment_rate_range'" % district_type)
		assert(archetype.has("avg_disposable_income_range"), "Archetype '%s' missing required 'avg_disposable_income_range'" % district_type)
		assert(archetype.has("zone_health_index_range"), "Archetype '%s' missing required 'zone_health_index_range'" % district_type)

		var pop_rng: Array = archetype["population_range"]
		var unemp_rng: Array = archetype["unemployment_rate_range"]
		var inc_rng: Array = archetype["avg_disposable_income_range"]
		var zhi_rng: Array = archetype["zone_health_index_range"]

		# Deterministic seed per block coordinate
		var block_seed: int = absi(("%s:%s" % [seed_id, block_id]).hash())
		rng.seed = block_seed

		var grid_x := int(round(pos_3d.x / 48.0))
		var grid_z := int(round(pos_3d.z / 48.0))
		var display_name := DistrictNamer.generate_district_name(district_type, seed_id, grid_x, grid_z)

		# Explicit demographic metric generation from confirmed valid ranges
		var pop_val: int = rng.randi_range(int(pop_rng[0]), int(pop_rng[1]))
		var unemp_val: float = rng.randf_range(float(unemp_rng[0]), float(unemp_rng[1]))
		var inc_val: float = rng.randf_range(float(inc_rng[0]), float(inc_rng[1]))
		var zhi_val: float = rng.randf_range(float(zhi_rng[0]), float(zhi_rng[1]))
		
		var heat_val: float = float(archetype.get("actual_police_heat", 0.0))
		var desp_val: float = float(archetype.get("consumer_desperation_index", 0.0))
		var corrupt_val: float = float(archetype.get("corruption_tolerance", 0.0))

		# 3. REGISTER THE OBJECTIVE TRUTH
		var district_payload := {
			"district_id": block_id,
			"display_name": display_name,
			"district_type": district_type,
			"spatial_anchor": Vector2(pos_3d.x, pos_3d.z),
			"grid_coords": Vector2i(grid_x, grid_z),
			"spatial_radius": 24.0,
			
			# Strictly evaluated demographics
			"population": pop_val,
			"unemployment_rate": unemp_val,
			"avg_disposable_income": inc_val,
			"zone_health_index": zhi_val,
			"actual_police_heat": heat_val,
			"consumer_desperation_index": desp_val,
			"corruption_tolerance": corrupt_val,
			
			"assigned_manager_id": "",
			"last_audited_tick": 1,
			"building_ids": [],
			"venues": {}
		}

		# 4. SEED DIEGETIC FILOFAX CACHE
		var is_home_turf: bool = (block_id == home_id)
		var perceived_payload := {
			"district_id": block_id,
			"display_name": display_name + (" (Home Turf)" if is_home_turf else ""),
			"district_type": district_type if is_home_turf else "Unknown Ward",
			"survey_status": "SURVEYED" if is_home_turf else "UNSURVEYED",
			"data_age_ticks": 0 if is_home_turf else 999,
			"last_verified_tick": 1 if is_home_turf else -1,
			"inked_police_heat": heat_val if is_home_turf else 0.0,
			"inked_zone_health": zhi_val if is_home_turf else 0.0,
			"notes": "Home estate. Known faces and familiar alleys." if is_home_turf else "No physical reconnaissance on file."
		}

		out_world_state["districts"][block_id] = district_payload
		out_world_state["filofax_cache"]["districts"][block_id] = perceived_payload
		child.set_meta("display_name", display_name)

	# Build the living society in SQLite!
	## SOCIAL_NETWORK.generate_city_society(out_world_state, seed_id)