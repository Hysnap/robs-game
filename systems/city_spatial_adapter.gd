# res://systems/city_spatial_adapter.gd
class_name CitySpatialAdapter
extends RefCounted

static var _archetypes: Dictionary = {}

## Loads archetypes dynamically via ScenarioManifestManager
static func load_archetypes() -> void:
	if not _archetypes.is_empty():
		return

	if ScenarioManifestManager.has_module("archetypes"):
		_archetypes = ScenarioManifestManager.load_module("archetypes")
	elif ScenarioManifestManager.has_module("spatial_archetypes"):
		_archetypes = ScenarioManifestManager.load_module("spatial_archetypes")
	else:
		assert(false, "FATAL: Scenario manifest missing 'archetypes' module registration.")

	assert(not _archetypes.is_empty(), "HALT: Archetypes loaded as empty dictionary.")
	print("[CitySpatialAdapter] Successfully loaded %d district archetypes via ScenarioManifestManager." % _archetypes.size())

## Ingests CityCrafter's 3D mesh children into the canonical GameState world_state
static func ingest_citycrafter_generation(citycrafter_node: Node3D, out_world_state: Dictionary, seed_id: String) -> void:
	if _archetypes.is_empty():
		load_archetypes()
		
	assert(not _archetypes.is_empty(), "HALT: _archetypes dictionary is empty during city ingestion!")

	if not out_world_state.has("districts"):
		out_world_state["districts"] = {}

	var rng := RandomNumberGenerator.new()
	
	for child in citycrafter_node.get_children():
		if not child.has_meta("city_entity_type") or child.get_meta("city_entity_type") != "district":
			continue

		var block_id: String = child.get_meta("block_id")
		var district_type: String = child.get_meta("district")
		var pos_3d: Vector3 = child.global_position

		# 1. Resolve archetype
		if not _archetypes.has(district_type):
			push_error("[CRITICAL FATAL] District '%s' has type '%s' not in archetypes.json!" % [block_id, district_type])
			assert(false, "HALT: Missing archetype definition for '%s'" % district_type)
			return

		var archetype: Dictionary = _archetypes[district_type]

		# 2. Extract block geometry & calculate true discrete grid cell footprint
		var raw_size_m := Vector2i(200, 200)
		if child is MeshInstance3D and child.mesh is PlaneMesh:
			var p_mesh: PlaneMesh = child.mesh as PlaneMesh
			raw_size_m = p_mesh.size
		elif child is MeshInstance3D and child.mesh is BoxMesh:
			var b_mesh: BoxMesh = child.mesh as BoxMesh
			raw_size_m = Vector2i(roundi(b_mesh.size.x), roundi(b_mesh.size.z))
		
		# Convert raw metres into true discrete grid units (225m pitch = 200m block + 25m street)
		var discrete_w: int = int(round((raw_size_m.x + 25.0) / 225.0))
		var discrete_h: int = int(round((raw_size_m.y + 25.0) / 225.0))

		# Ensure minimum 1x1
		discrete_w = maxi(1, discrete_w)
		discrete_h = maxi(1, discrete_h)
		
		var block_size := Vector2i(maxi(1, discrete_w), maxi(1, discrete_h))
		var scale_factor: float = _calculate_district_scale_factor(archetype, block_size)

		# 3. Demographic metric evaluation
		assert(archetype.has("population_range"), "Archetype '%s' missing 'population_range'" % district_type)
		assert(archetype.has("unemployment_rate_range"), "Archetype '%s' missing 'unemployment_rate_range'" % district_type)
		assert(archetype.has("avg_disposable_income_range"), "Archetype '%s' missing 'avg_disposable_income_range'" % district_type)
		assert(archetype.has("zone_health_index_range"), "Archetype '%s' missing 'zone_health_index_range'" % district_type)

		var pop_rng: Array = archetype["population_range"]
		var unemp_rng: Array = archetype["unemployment_rate_range"]
		var inc_rng: Array = archetype["avg_disposable_income_range"]
		var zhi_rng: Array = archetype["zone_health_index_range"]

		# Seed deterministically per block
		var block_seed: int = absi(("%s:%s" % [seed_id, block_id]).hash())
		rng.seed = block_seed

		var grid_x := int(round(pos_3d.x / 48.0))
		var grid_z := int(round(pos_3d.z / 48.0))
		var display_name := DistrictNamer.generate_district_name(district_type, seed_id, grid_x, grid_z)

		# Scaled standard zones vs. authored multi-cell complexes
		var base_pop: int = rng.randi_range(int(pop_rng[0]), int(pop_rng[1]))
		var pop_val: int = int(round(float(base_pop) * scale_factor))

		var bldg_range: Array = archetype.get("buildings", [1, 2])
		var min_bldgs: int = int(round(float(bldg_range[0]) * scale_factor))
		var max_bldgs: int = int(round(float(bldg_range[1]) * scale_factor))
		var target_buildings: int = rng.randi_range(min_bldgs, max_bldgs)

		var unemp_val: float = rng.randf_range(float(unemp_rng[0]), float(unemp_rng[1]))
		var inc_val: float = rng.randf_range(float(inc_rng[0]), float(inc_rng[1]))
		var zhi_val: float = rng.randf_range(float(zhi_rng[0]), float(zhi_rng[1]))
		
		var heat_val: float = float(archetype.get("actual_police_heat", 0.0))
		var desp_val: float = float(archetype.get("consumer_desperation_index", 0.0))
		var corrupt_val: float = float(archetype.get("corruption_tolerance", 0.0))

		# 4. Pure Objective Truth (World State Reality)
		out_world_state["districts"][block_id] = {
			"district_id": block_id,
			"display_name": display_name,
			"district_type": district_type,
			"spatial_anchor": Vector2(pos_3d.x, pos_3d.z),
			"grid_coords": Vector2i(grid_x, grid_z),
			"grid_size": block_size,
			"spatial_radius": 24.0 * float(max(block_size.x, block_size.y)),
			
			"population": pop_val,
			"building_capacity": target_buildings,
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

		child.set_meta("display_name", display_name)

## Multi-cell scaling: compares actual discrete cells against authored archetype footprint
static func _calculate_district_scale_factor(archetype: Dictionary, block_size: Vector2i) -> float:
	var allocated_cells: int = block_size.x * block_size.y
	var native_footprint_arr: Array = archetype.get("footprint_size", [1, 1])
	var native_cells: int = max(1, int(native_footprint_arr[0]) * int(native_footprint_arr[1]))

	# Only scale if an archetype was placed on an area larger than its authored footprint
	var ratio: float = float(allocated_cells) / float(native_cells)
	return clampf(ratio, 1.0, 4.0)