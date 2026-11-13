# res://systems/city_spatial_adapter.gd
class_name CitySpatialAdapter
extends RefCounted

const INTEL_MANAGER = preload("res://systems/multilayer_info_loop/intel_manager.gd")

static var _archetypes: Dictionary = {}

static func load_archetypes() -> void:
	if not _archetypes.is_empty():
		return

	assert(ScenarioManifestManager.has_module("archetypes"), 
		"FATAL: Scenario manifest missing 'archetypes' module registration.")

	_archetypes = ScenarioManifestManager.load_module("archetypes")
	SystemLogger.log_info("[CitySpatialAdapter] Loaded %d district archetypes." % _archetypes.size())
	assert(not _archetypes.is_empty(), "HALT: Archetypes loaded as empty dictionary.")

static func ingest_citycrafter_generation(citycrafter_node: Node3D, out_world_state: Dictionary, seed_id: String) -> void:
	SystemLogger.log_info("[CitySpatialAdapter] Ingesting generated city for seed '%s'." % seed_id)
	if _archetypes.is_empty():
		load_archetypes()
		
	assert(not _archetypes.is_empty(), "HALT: _archetypes dictionary is empty during city ingestion!")

	if not out_world_state.has("districts"):
		out_world_state["districts"] = {}

	# Derive active spatial metrics from the configuration resource
	var cfg = ScenarioManifestManager.get_city_configuration()
	var block_side_m: float = float(cfg.get("block_size")) if (cfg and "block_size" in cfg) else 200.0
	var street_w_m: float = float(cfg.get("street_width")) if (cfg and "street_width" in cfg) else 25.0
	var cell_pitch: float = block_side_m + street_w_m
	var cell_area_sqm: float = block_side_m * block_side_m

	var rng := RandomNumberGenerator.new()
	
	for child in citycrafter_node.get_children():
		if not child.has_meta("city_entity_type") or child.get_meta("city_entity_type") != "district":
			continue

		var block_id: String = child.get_meta("block_id")
		var district_type: String = child.get_meta("district")
		var pos_3d: Vector3 = child.global_position

		if not _archetypes.has(district_type):
			assert(false, "HALT: Missing archetype definition for '%s'" % district_type)
			return

		var archetype: Dictionary = _archetypes[district_type]

		# 2. Extract block geometry & calculate true discrete grid cell footprint
		var raw_size_m := Vector2(block_side_m, block_side_m)
		if child is MeshInstance3D and child.mesh is PlaneMesh:
			var p_mesh: PlaneMesh = child.mesh as PlaneMesh
			raw_size_m = p_mesh.size
		elif child is MeshInstance3D and child.mesh is BoxMesh:
			var b_mesh: BoxMesh = child.mesh as BoxMesh
			raw_size_m = Vector2(b_mesh.size.x, b_mesh.size.z)
		
		# Convert raw metres into true discrete grid units using active pitch
		var discrete_w: int = int(round((raw_size_m.x + street_w_m) / cell_pitch))
		var discrete_h: int = int(round((raw_size_m.y + street_w_m) / cell_pitch))

		discrete_w = maxi(1, discrete_w)
		discrete_h = maxi(1, discrete_h)
		
		var block_size := Vector2i(discrete_w, discrete_h)
		var scale_factor: float = _calculate_district_scale_factor(archetype, block_size, cell_area_sqm)

		var pop_rng: Array = archetype["population_range"]
		var unemp_rng: Array = archetype["unemployment_rate_range"]
		var inc_rng: Array = archetype["avg_disposable_income_range"]
		var zhi_rng: Array = archetype["zone_health_index_range"]

		var block_seed: int = absi(("%s:%s" % [seed_id, block_id]).hash())
		rng.seed = block_seed

		var grid_x := int(round(pos_3d.x / cell_pitch))
		var grid_z := int(round(pos_3d.z / cell_pitch))
		var display_name := DistrictNamer.generate_district_name(district_type, seed_id, grid_x, grid_z)

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

		out_world_state["districts"][block_id] = {
			"district_id": block_id,
			"display_name": display_name,
			"district_type": district_type,
			"spatial_anchor": Vector2(pos_3d.x, pos_3d.z),
			"grid_coords": Vector2i(grid_x, grid_z),
			"grid_size": block_size,
			"spatial_radius": (block_side_m * 0.5) * float(max(block_size.x, block_size.y)),
			
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
	SystemLogger.log_info("[CitySpatialAdapter] Ingested %d districts." % out_world_state["districts"].size())

## Evaluates finalized districts to find a valid, populated residential neighborhood.
## Seeds public landmarks and the selected home district into sparse knowledge_pools via IntelManager.
static func resolve_verified_home_district(world_state: Dictionary, seed_id: String) -> String:
	load_archetypes()
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return ""

	if not world_state.has("player_knowledge"):
		world_state["player_knowledge"] = {"home_district_id": "", "known_outlets": [], "district_survey_ticks": {}}
	if not world_state.has("knowledge_pools"):
		world_state["knowledge_pools"] = {}

	var observer_ids: Array[String] = _collect_crew_observer_ids(world_state)
	var candidates: Array[String] = []

	# Check each district for residential eligibility, housing, and active population
	for d_id in districts.keys():
		var d: Dictionary = districts[d_id]
		var d_type: String = str(d.get("district_type", ""))
		var arch: Dictionary = _archetypes.get(d_type, {})
		
		# Auto-seed public landmarks into sparse knowledge pools
		if bool(arch.get("is_public_landmark", false)):
			for obs_id in observer_ids:
				INTEL_MANAGER.apply_effort_impulse(
					world_state, "RESIDENT", obs_id, "DISTRICT", str(d_id), 10.0,
					{"distance": 0.0, "access_permeability": 1.0}
				)

		# Exclude non-residential civil anchors or heavy industrial sites
		if d_type in ["place_of_worship", "primary_school", "secondary_school", "hospital_site", "civic_penal_block", "local_government", "industrial_automotive_works", "police_station", "police_headquarters"]:
			continue

		var is_eligible: bool = bool(arch.get("is_eligible_home", false))
		var is_res_sector: bool = str(arch.get("sector_class", d.get("initial_sector", ""))).to_upper() == "RESIDENTIAL"
		var units: int = int(d.get("total_habitable_units", 0))
		var pop: int = int(d.get("population", 0))

		if (is_eligible or is_res_sector) and units > 0 and pop > 0:
			candidates.append(str(d_id))

	# Fallback: any residential sector with citizens
	if candidates.is_empty():
		for d_id in districts.keys():
			var d: Dictionary = districts[d_id]
			var d_type: String = str(d.get("district_type", ""))
			var arch: Dictionary = _archetypes.get(d_type, {})
			var is_res: bool = str(arch.get("sector_class", d.get("initial_sector", ""))).to_upper() == "RESIDENTIAL"
			if is_res and int(d.get("population", 0)) > 0:
				candidates.append(str(d_id))

	# Absolute fallback: any district with active population
	if candidates.is_empty():
		for d_id in districts.keys():
			if int(districts[d_id].get("population", 0)) > 0:
				candidates.append(str(d_id))

	assert(not candidates.is_empty(), "FATAL: [CitySpatialAdapter] No populated districts found on generated map.")

	# Deterministic selection using seed hash
	candidates.sort_custom(func(a, b):
		var ha = abs(("%s:%s" % [seed_id, a]).hash())
		var hb = abs(("%s:%s" % [seed_id, b]).hash())
		return ha < hb
	)

	var selected_home_id: String = candidates[0]
	SystemLogger.log_info("[CitySpatialAdapter] Resolved home district '%s' from %d candidates." % [selected_home_id, candidates.size()])

	for obs_id in observer_ids:
		INTEL_MANAGER.apply_effort_impulse(
			world_state, "RESIDENT", obs_id, "DISTRICT", selected_home_id, 85.0,
			{"distance": 0.0, "access_permeability": 1.0}
		)

	return selected_home_id

static func _collect_crew_observer_ids(world_state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var staff_dict: Dictionary = world_state.get("staff", {})
	for staff_id in staff_dict.keys():
		var member = staff_dict[staff_id]
		if member is Dictionary:
			var obs_id: String = str(member.get("resident_id", staff_id))
			if not obs_id.is_empty() and not ids.has(obs_id):
				ids.append(obs_id)
	if ids.is_empty():
		ids.append("crew_0")
	return ids

static func _calculate_district_scale_factor(archetype: Dictionary, block_size: Vector2i, standard_lot_sqm: float) -> float:
	var allocated_cells: int = block_size.x * block_size.y
	var sqm: float = float(archetype.get("footprint_size", archetype.get("footprint_sqm", 1600.0)))
	var native_cells: int = maxi(1, int(round(sqm / standard_lot_sqm)))
	var ratio: float = float(allocated_cells) / float(native_cells)
	return clampf(ratio, 1.0, 4.0)