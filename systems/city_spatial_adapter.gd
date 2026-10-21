# res://systems/city_spatial_adapter.gd
class_name CitySpatialAdapter
extends RefCounted

static var _archetypes: Dictionary = {}

static func load_archetypes(file_path: String = "res://data_modules/core/spatial/districts/archetypes.json") -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_archetypes = json.data
			return
	push_error("[CitySpatialAdapter] Could not load archetypes from: %s" % file_path)

static func ingest_citycrafter_generation(citycrafter_node: Node3D, out_world_state: Dictionary, seed_id: String) -> void:
	if _archetypes.is_empty():
		load_archetypes()
		
	if not out_world_state.has("districts"):
		out_world_state["districts"] = {}
	if not out_world_state.has("filofax_cache"):
		out_world_state["filofax_cache"] = {"districts": {}, "pinned_memos": []}

	# Ingest starting configuration
	var home_id: String = "block_0_0"
	var rules_file := ConfigFile.new()
	if rules_file.load("res://data_modules/core/business_rules.cfg") == OK:
		home_id = rules_file.get_value("starting_operations", "home_district_id", "block_0_0")

	var rng := RandomNumberGenerator.new()
	
	for child in citycrafter_node.get_children():
		if not child.has_meta("city_entity_type") or child.get_meta("city_entity_type") != "district":
			continue
			
		var block_id: String = child.get_meta("block_id")
		var district_type: String = child.get_meta("district")
		var pos_3d: Vector3 = child.global_position
		
		# Deterministic seed per block coordinate
		var block_seed: int = absi(("%s:%s" % [seed_id, block_id]).hash())
		rng.seed = block_seed
		
		var grid_x := int(round(pos_3d.x / 48.0))
		var grid_z := int(round(pos_3d.z / 48.0))
		var display_name := DistrictNamer.generate_district_name(district_type, seed_id, grid_x, grid_z)
		
		var archetype: Dictionary = _archetypes.get(district_type, _archetypes.get("civic_default", {}))

		# --- DYNAMIC PROPERTY INGESTION (NO HARDCODED METRICS) ---
		var district_payload := {
			"district_id": block_id,
			"display_name": display_name,
			"district_type": district_type,
			"spatial_anchor": Vector2(pos_3d.x, pos_3d.z),
			"grid_coords": Vector2i(grid_x, grid_z),
			"spatial_radius": 24.0,
			"assigned_manager_id": "",
			"last_audited_tick": 1,
			"building_ids": []
		}
		
		var perceived_payload := {
			"district_id": block_id,
			"display_name": display_name,
			"district_type": district_type,
			"survey_status": "UNSURVEYED",
			"data_age_ticks": 999,
			"last_verified_tick": -1,
			"perceived_metrics": {}
		}

		# Dynamically unpack all metrics defined in archetypes.json
		for key in archetype.keys():
			if key.begins_with("_"):
				continue
			var val = archetype[key]
			
			if val is Array and val.size() == 2 and (val[0] is float or val[0] is int):
				# Handle numeric range: [min, max]
				if val[0] is int and val[1] is int:
					district_payload[key] = rng.randi_range(val[0], val[1])
				else:
					district_payload[key] = rng.randf_range(float(val[0]), float(val[1]))
			else:
				# Static archetype value
				district_payload[key] = val

		# Handle Home Ward vs Fog
		if block_id == home_id:
			perceived_payload["survey_status"] = "SURVEYED"
			perceived_payload["data_age_ticks"] = 0
			perceived_payload["last_verified_tick"] = 1
			# Mirror initial baseline truth into perceived cache for home ward
			for key in district_payload.keys():
				if not key in ["spatial_anchor", "grid_coords", "building_ids"]:
					perceived_payload["perceived_metrics"][key] = district_payload[key]

		out_world_state["districts"][block_id] = district_payload
		out_world_state["filofax_cache"]["districts"][block_id] = perceived_payload
		child.set_meta("display_name", display_name)