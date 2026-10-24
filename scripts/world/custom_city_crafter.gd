# res://scripts/world/custom_city_crafter.gd
@tool
class_name CustomCityCrafter
extends "res://addons/citycrafter/citycrafter.gd"

# Cached layout rules from business_rules.cfg
var _layout_rules: Dictionary = {}
var _archetypes_data: Dictionary = {}
var _anchor_claim_map: Dictionary = {} # Vector2i -> archetype_id
var _material_cache: Dictionary = {}
var _civic_hierarchy: Dictionary = {}
var _placed_facilities: Array = [] # Array of { "type": String, "origin": Vector2i, "footprint": Vector2i }


## Loads business rules with a strict HARD FAIL if the file does not exist
func _init_layout_rules() -> void:
	if not _layout_rules.is_empty():
		return
		
	var path := "res://data_modules/core/business_rules.cfg"
	assert(FileAccess.file_exists(path), "FATAL: business_rules.cfg does not exist at: %s" % path)
	
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	assert(err == OK, "FATAL: Could not parse business_rules.cfg. Error code: %d" % err)
	
	if cfg.has_section("map_layout"):
		for key in cfg.get_section_keys("map_layout"):
			_layout_rules[key] = cfg.get_value("map_layout", key)
	if cfg.has_section("spatial"):
		for key in cfg.get_section_keys("spatial"):
			_layout_rules[key] = cfg.get_value("spatial", key)
	if cfg.has_section("system_diagnostics"):
		for key in cfg.get_section_keys("system_diagnostics"):
			_layout_rules[key] = cfg.get_value("system_diagnostics", key)

## Loads archetypes with a strict HARD FAIL if the file does not exist
func _init_archetypes() -> void:
	if not _archetypes_data.is_empty():
		return
		
	_init_layout_rules()
	assert(_layout_rules.has("archetypes_path"), "FATAL: [spatial] archetypes_path is missing from business_rules.cfg")
	var path: String = str(_layout_rules.get("archetypes_path"))
	
	assert(FileAccess.file_exists(path), "FATAL: Archetypes configuration file not found at: %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "FATAL: Failed to read archetypes file at: %s" % path)
	
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	assert(parsed is Dictionary, "FATAL: Archetypes JSON root must be a Dictionary: %s" % path)
	_archetypes_data = parsed

## Overrides generate_base_grid_with_sizes() -> Array
## Claims multi-cell anchor footprints first, then populates surrounding blocks
func generate_base_grid_with_sizes() -> Array:
	_init_layout_rules()
	_init_archetypes()
	
	var blocks_data: Array = []
	var occupied_positions: Dictionary = {}
	_anchor_claim_map.clear()
	_placed_facilities.clear()

	var cfg = city_configuration
	var radius_val: int = int(cfg.get("city_radius")) if (cfg and "city_radius" in cfg and int(cfg.get("city_radius")) > 0) else int(_layout_rules.get("default_city_radius", 14))
	var jitter: float = float(cfg.get("radial_jitter")) if (cfg and "radial_jitter" in cfg) else float(_layout_rules.get("default_radial_jitter", 0.35))
	var noise_scale: float = float(_layout_rules.get("boundary_noise_scale", 15.0))

	# 1. Pre-claim multi-cell & dedicated spatial archetypes
	_preclaim_spatial_archetypes(radius_val, occupied_positions, blocks_data)

	# 2. Populate regular blocks around pre-claimed footprints
	for x in range(-radius_val, radius_val + 1):
		for z in range(-radius_val, radius_val + 1):
			var dist: float = Vector2(x, z).length()
			var noise_val: float = noise.get_noise_2d(float(x) * noise_scale, float(z) * noise_scale)
			var max_r: float = float(radius_val) * (1.0 + (noise_val * jitter))
			
			if dist > max_r:
				continue
				
			var pos := Vector2i(x, z)
			if occupied_positions.has(pos):
				continue
				
			var block_size := Vector2i(1, 1)
			if cfg and cfg.get("enable_multi_size_blocks"):
				block_size = determine_block_size(x, z, occupied_positions)
				
			blocks_data.append({
				"position": pos,
				"size": block_size
			})
			
			for bx in range(block_size.x):
				for bz in range(block_size.y):
					occupied_positions[Vector2i(x + bx, z + bz)] = true
					
	return blocks_data

## 100% Data-Driven Zoning Selection
## Priority: Anchor Pre-claims -> archetypes.json Bands & Placement -> Fallback
func get_district_type(grid_x: int, grid_z: int) -> String:
	_init_archetypes()
	var pos := Vector2i(grid_x, grid_z)
	
	# 1. Check if claimed by a multi-cell civic anchor
	if _anchor_claim_map.has(pos):
		return str(_anchor_claim_map[pos])

	var cfg = city_configuration
	var radius_val: float = float(cfg.get("city_radius")) if (cfg and "city_radius" in cfg and float(cfg.get("city_radius")) > 0.0) else float(_layout_rules.get("default_city_radius", 14.0))
	var norm_dist: float = Vector2(grid_x, grid_z).length() / max(radius_val, 1.0)

	var setup: Dictionary = _archetypes_data.get("setup", {})
	assert(setup.has("default_fallback_archetype"), "FATAL: 'setup.default_fallback_archetype' is missing in archetypes.json")
	var fallback_archetype: String = str(setup.get("default_fallback_archetype"))

	# 2. Determine normalized ring band key dynamically from user ratios via area integral
	var bands: Array = _compute_dynamic_concentric_bands(cfg)
	var band_key: String = str(bands[-1].get("weight_key"))
	for band in bands:
		if norm_dist <= float(band.get("max_norm_dist")):
			band_key = str(band.get("weight_key"))
			break
			
	if band_key.is_empty():
		band_key = str(bands[-1].get("weight_key"))

	# 3. Filter candidate archetypes and modulate weights purely by user-entered sector ratios
	var candidate_weights: Dictionary = {}
	for arch_key in _archetypes_data.keys():
		if arch_key in ["_meta", "setup"]: 
			continue
		var arch: Dictionary = _archetypes_data[arch_key]
		if arch.get("is_unique_anchor", false): 
			continue
		
		var placement: Dictionary = arch.get("spatial_placement", {})
		var dist_min: float = float(placement.get("normalized_distance_min", 0.0))
		var dist_max: float = float(placement.get("normalized_distance_max", 1.0))
		
		if norm_dist >= dist_min and norm_dist <= dist_max:
			var base_w: float = float(placement.get(band_key, 0))
			if base_w > 0:
				var sector_name: String = str(arch.get("sector_class", "")).to_lower()
				var ratio_prop: String = "%s_ratio" % sector_name
				
				var user_weight: float = 1.0
				if cfg and ratio_prop in cfg:
					user_weight = float(cfg.get(ratio_prop))
					
				var effective_w: int = int(round(base_w * user_weight * 100.0))
				if effective_w > 0:
					candidate_weights[arch_key] = effective_w

	if candidate_weights.is_empty():
		return fallback_archetype

	# 4. Deterministic sample via 2D spatial noise
	assert(_layout_rules.has("zoning_noise_scale"), "FATAL: zoning_noise_scale missing in business_rules.cfg")
	var z_noise_scale: float = float(_layout_rules.get("zoning_noise_scale", 8.0))
	var sample_val: float = (noise.get_noise_2d(float(grid_x) * z_noise_scale, float(grid_z) * z_noise_scale) + 1.0) * 0.5
	
	return _sample_weighted_archetype(candidate_weights, sample_val)

## Overrides building generation to respect enable_building_spawning
func generate_buildings_async() -> void:
	var cfg = city_configuration
	if cfg and "enable_building_spawning" in cfg and not bool(cfg.get("enable_building_spawning")):
		emit_progress(90, 100, "Macro Map: Building meshes bypassed")
		return
	await super.generate_buildings_async()

## Overrides ground generation loop using batching and logging controls from business_rules.cfg
func generate_ground_planes_async() -> void:
	print(">>> RUNNING CUSTOM CITY CRAFTER GROUND GENERATION <<<")
	if not city_configuration.generate_ground:
		return
		
	var total_blocks: int = active_blocks.size()
	if total_blocks == 0:
		return
		
	_init_layout_rules()
	var batch_interval: int = int(_layout_rules.get("ground_batch_log_interval", 50))
	var enable_log: bool = bool(_layout_rules.get("enable_generation_progress_log", true))
	var yield_frame: bool = bool(_layout_rules.get("yield_per_batch", true))

	var cell_size: float = city_configuration.block_size + city_configuration.street_width
	var half_street: float = city_configuration.street_width * 0.5
	
	if enable_log:
		emit_progress(10, 100, "Generating ground layout (%d districts)..." % total_blocks)
	
	for i in range(total_blocks):
		var pos: Vector2i = active_blocks[i]
		var block_size: Vector2i = block_sizes.get(pos, Vector2i(1, 1))
		
		var world_w: float = float(block_size.x) * city_configuration.block_size + float(block_size.x - 1) * city_configuration.street_width
		var world_h: float = float(block_size.y) * city_configuration.block_size + float(block_size.y - 1) * city_configuration.street_width
		
		var center := Vector3(
			float(pos.x) * cell_size + world_w * 0.5 + half_street,
			city_configuration.ground_height_offset,
			float(pos.y) * cell_size + world_h * 0.5 + half_street
		)
		
		var district_type: String = get_district_type(pos.x, pos.y)
		var block_id: String = get_block_id(pos.x, pos.y)
		create_ground_plane(center, Vector2(world_w, world_h), district_type, block_id)
		
		if (i % batch_interval == 0) or (i == total_blocks - 1):
			if enable_log:
				var pct: int = 10 + int((float(i) / float(total_blocks)) * 20.0)
				emit_progress(pct, 100, "Ground layout: %d/%d" % [i + 1, total_blocks])
			if yield_frame and is_inside_tree() and get_tree():
				await get_tree().process_frame

	if enable_log:
		emit_progress(30, 100, "Ground planes complete.")

## Overrides create_ground_plane matching exact parent signature with default arguments
func create_ground_plane(center: Vector3, size: Vector2, district_type: String = "residential", block_id: String = ""):
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = size
	
	var ground := MeshInstance3D.new()
	ground.mesh = plane_mesh
	ground.position = center
	
	var mat: Material = _resolve_district_material(district_type)
	if mat:
		ground.material_override = mat
		
	ground.name = "Ground_%s_%s" % [district_type, block_id]
	add_child(ground)
	
	# Generate physics collision for click raycasts safely
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.5, size.y)
	collision_shape.shape = box
	collision_shape.position = Vector3(0.0, -0.25, 0.0)
	
	static_body.add_child(collision_shape)
	ground.add_child(static_body)
	
	for target in [ground, static_body]:
		target.set_meta("city_entity_type", "district")
		target.set_meta("district", district_type)
		target.set_meta("city_entity_id", block_id)
		target.set_meta("block_id", block_id)
		target.add_to_group("city_district")
	
	return ground

## Dynamically resolves or generates district materials from archetypes.json visual_profile
func _resolve_district_material(district_type: String) -> Material:
	if _material_cache.has(district_type):
		return _material_cache[district_type]

	var cfg = city_configuration

	var prop_name := "%s_ground_material" % district_type
	if cfg and prop_name in cfg and cfg.get(prop_name) != null:
		var mat = cfg.get(prop_name)
		_material_cache[district_type] = mat
		return mat

	_init_archetypes()
	var arch: Dictionary = _archetypes_data.get(district_type, {})
	var visual: Dictionary = arch.get("visual_profile", {})

	if not visual.is_empty():
		var mat := StandardMaterial3D.new()
		mat.resource_name = "Mat_%s" % district_type
		
		var hex_color: String = str(visual.get("color", ""))
		if not hex_color.is_empty():
			mat.albedo_color = Color.from_string(hex_color, Color.GRAY)
			
		var tex_path: String = str(visual.get("texture_path", ""))
		if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
			var tex = load(tex_path)
			if tex is Texture2D:
				mat.albedo_texture = tex
				
		var uv_scale_arr: Array = visual.get("uv_scale", [1.0, 1.0])
		if uv_scale_arr.size() >= 2:
			mat.uv1_scale = Vector3(float(uv_scale_arr[0]), float(uv_scale_arr[1]), 1.0)
			
		mat.roughness = float(visual.get("roughness", 0.85))
		mat.metallic = float(visual.get("metallic", 0.0))

		_material_cache[district_type] = mat
		return mat

	var sector_class: String = str(arch.get("sector_class", "")).to_lower()
	if not sector_class.is_empty():
		var sector_prop := "%s_ground_material" % sector_class
		if cfg and sector_prop in cfg and cfg.get(sector_prop) != null:
			var mat = cfg.get(sector_prop)
			_material_cache[district_type] = mat
			return mat

	var fallback = cfg.ground_material if (cfg and "ground_material" in cfg) else null
	return fallback

## Resolves the road material from city_configuration or creates a default dark asphalt material
func _resolve_road_material() -> Material:
	var cfg = city_configuration
	if cfg and "road_material" in cfg and cfg.road_material != null:
		return cfg.road_material

	var mat := StandardMaterial3D.new()
	mat.resource_name = "Mat_Road_Default"
	mat.albedo_color = Color("#1F2937") # Dark charcoal asphalt
	mat.roughness = 0.9
	return mat

## Resolves intersection material, falling back to the road material
func _resolve_intersection_material() -> Material:
	var cfg = city_configuration
	if cfg and "intersection_material" in cfg and cfg.intersection_material != null:
		return cfg.intersection_material
	return _resolve_road_material()

## Collects the current visual footprint of all ground planes and roads
func export_visual_layout() -> Dictionary:
	var layout := {
		"districts": {},
		"roads": [],
		"seed_id": seed_id
	}
	
	var default_block_sz: float = city_configuration.block_size if city_configuration else 200.0
	var default_street_w: float = city_configuration.street_width if city_configuration else 25.0

	# 1. Capture Ground District Blocks (Direct procedural children)
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("block_id"):
			var b_id: String = child.get_meta("block_id")
			var b_size := Vector2(default_block_sz, default_block_sz)
			if child.mesh is PlaneMesh:
				b_size = (child.mesh as PlaneMesh).size
			elif child.mesh is BoxMesh:
				var b_sz = (child.mesh as BoxMesh).size
				b_size = Vector2(b_sz.x, b_sz.z)
				
			layout["districts"][b_id] = {
				"center": [child.position.x, child.position.y, child.position.z],
				"size": [b_size.x, b_size.y],
				"district_type": child.get_meta("district")
			}

	# 2. Capture Road and Intersection Meshes (Recursively finds nodes regardless of parent container)
	var all_meshes = find_children("*", "MeshInstance3D", true, false)
	for mesh_node in all_meshes:
		var n_name: String = mesh_node.name.to_lower()
		if n_name.begins_with("road") or n_name.begins_with("intersection") or n_name.begins_with("subdivisionroad"):
			var sz := [default_street_w, default_street_w]
			if mesh_node.mesh is PlaneMesh:
				var pm = mesh_node.mesh as PlaneMesh
				sz = [pm.size.x, pm.size.y]
			elif mesh_node.mesh is BoxMesh:
				var bm = mesh_node.mesh as BoxMesh
				sz = [bm.size.x, bm.size.z]

			layout["roads"].append({
				"name": mesh_node.name,
				"position": [mesh_node.position.x, mesh_node.position.y, mesh_node.position.z],
				"rotation": [mesh_node.rotation.x, mesh_node.rotation.y, mesh_node.rotation.z],
				"size": sz
			})
			
	return layout

## Instantiates ground planes and roads directly from saved layout data
func load_visual_layout(layout_data: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	# 1. Rebuild Ground Planes
	var districts_data: Dictionary = layout_data.get("districts", {})
	for b_id in districts_data.keys():
		var d = districts_data[b_id]
		var center_arr = d["center"]
		var size_arr = d["size"]
		create_ground_plane(
			Vector3(center_arr[0], center_arr[1], center_arr[2]),
			Vector2(size_arr[0], size_arr[1]),
			str(d["district_type"]),
			b_id
		)

	# 2. Rebuild Roads & Intersections
	var roads_data: Array = layout_data.get("roads", [])
	var road_mat = _resolve_road_material()
	var inter_mat = _resolve_intersection_material()

	for r in roads_data:
		var r_name: String = str(r.get("name", "Road"))
		var pos_arr = r["position"]
		var sz_arr = r["size"]
		
		var road_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(sz_arr[0], sz_arr[1])
		road_mesh.mesh = plane
		road_mesh.position = Vector3(pos_arr[0], pos_arr[1] + 0.02, pos_arr[2])
		
		if r.has("rotation"):
			var rot_arr = r["rotation"]
			road_mesh.rotation = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])
			
		if r_name.to_lower().begins_with("Intersection"):
			road_mesh.material_override = inter_mat
		else:
			road_mesh.material_override = road_mat
			
		road_mesh.name = r_name
		add_child(road_mesh)

func _sample_weighted_archetype(weights: Dictionary, sample: float) -> String:
	var total_weight: int = 0
	for w in weights.values():
		total_weight += int(w)
		
	assert(total_weight > 0, "FATAL: Attempted to sample from an empty weight table.")
		
	var target_point: float = clampf(sample, 0.0, 0.9999) * float(total_weight)
	var accumulated: float = 0.0
	
	for arch in weights.keys():
		accumulated += float(weights[arch])
		if target_point < accumulated:
			return str(arch)
			
	return str(weights.keys()[-1])

func _compute_dynamic_concentric_bands(cfg) -> Array:
	var setup: Dictionary = _archetypes_data.get("setup", {})
	var bands_template: Array = setup.get("concentric_bands", [])
	assert(not bands_template.is_empty(), "FATAL: 'setup.concentric_bands' is missing or empty in archetypes.json")

	var user_sector_ratios: Dictionary = {}
	for arch_key in _archetypes_data.keys():
		if arch_key in ["_meta", "setup"]: 
			continue
		var arch: Dictionary = _archetypes_data[arch_key]
		var sector: String = str(arch.get("sector_class", "residential")).to_lower()
		var prop_name := "%s_ratio" % sector
		
		if not user_sector_ratios.has(sector):
			var ratio_val: float = float(cfg.get(prop_name)) if (cfg and prop_name in cfg) else 1.0
			user_sector_ratios[sector] = max(0.01, ratio_val)

	var band_demands: Array = []
	var total_demand: float = 0.0

	for band_entry in bands_template:
		var weight_key: String = str(band_entry.get("weight_key"))
		var band_score: float = 0.0
		
		for arch_key in _archetypes_data.keys():
			if arch_key in ["_meta", "setup"]: 
				continue
			var arch: Dictionary = _archetypes_data[arch_key]
			if arch.get("is_unique_anchor", false):
				continue
				
			var placement: Dictionary = arch.get("spatial_placement", {})
			var base_w: float = float(placement.get(weight_key, 0))
			var sector: String = str(arch.get("sector_class", "residential")).to_lower()
			var user_ratio: float = user_sector_ratios.get(sector, 1.0)
			
			band_score += base_w * user_ratio
			
		band_score = max(0.001, band_score)
		band_demands.append({
			"weight_key": weight_key,
			"demand": band_score
		})
		total_demand += band_score

	var dynamic_bands: Array = []
	var cumulative_area: float = 0.0
	var num_bands: int = band_demands.size()

	for i in range(num_bands):
		var demand_share: float = band_demands[i]["demand"] / total_demand
		cumulative_area += demand_share
		
		var max_r: float = 1.0
		if i == num_bands - 1:
			max_r = 99.0
		else:
			max_r = sqrt(clampf(cumulative_area, 0.05, 0.95))
			
		dynamic_bands.append({
			"weight_key": band_demands[i]["weight_key"],
			"max_norm_dist": max_r
		})

	return dynamic_bands

func _init_civic_hierarchy() -> void:
	if not _civic_hierarchy.is_empty():
		return
	
	assert(ScenarioManifestManager.has_module("civic_hierarchy"), 
		"FATAL: Scenario manifest is missing 'civic_hierarchy' module registration.")
		
	_civic_hierarchy = ScenarioManifestManager.load_module("civic_hierarchy")
	assert(_civic_hierarchy.has("civic_institutions"), 
		"FATAL: civic_hierarchy module is missing 'civic_institutions' root table.")

func _preclaim_spatial_archetypes(radius_val: int, occupied: Dictionary, blocks_data: Array) -> void:
	for arch_key in _archetypes_data.keys():
		if arch_key in ["_meta", "setup"]:
			continue
		var arch: Dictionary = _archetypes_data[arch_key]
		if not arch.has("spatial_rules"):
			continue

		var footprint_arr: Array = arch.get("footprint_size", [1, 1])
		var footprint := Vector2i(int(footprint_arr[0]), int(footprint_arr[1]))
		var rules: Dictionary = arch["spatial_rules"]
		var dist_range: Array = rules.get("norm_distance_range", [0.0, 1.0])
		var min_sep: int = int(rules.get("min_separation_blocks", 4))

		var origin: Vector2i = _find_valid_anchor_site(radius_val, footprint, dist_range, min_sep, occupied)
		if origin == Vector2i(9999, 9999):
			continue

		blocks_data.append({
			"position": origin,
			"size": footprint
		})

		for bx in range(footprint.x):
			for bz in range(footprint.y):
				var cell := Vector2i(origin.x + bx, origin.y + bz)
				occupied[cell] = true
				_anchor_claim_map[cell] = arch_key

		_placed_facilities.append({
			"type": arch_key,
			"origin": origin,
			"footprint": footprint
		})
		print("[CustomCityCrafter] Preclaimed '%s' [%d x %d] at %s" % [arch_key, footprint.x, footprint.y, origin])

func _find_valid_anchor_site(
	radius_val: int, 
	footprint: Vector2i, 
	dist_range: Array, 
	min_sep: int, 
	occupied: Dictionary
) -> Vector2i:
	var r_min: float = float(dist_range[0])
	var r_max: float = float(dist_range[1])

	if r_max <= 0.05:
		var core_fits := true
		for bx in range(footprint.x):
			for bz in range(footprint.y):
				if occupied.has(Vector2i(bx, bz)):
					core_fits = false
					break
			if not core_fits:
				break
		if core_fits:
			return Vector2i.ZERO
		return Vector2i(9999, 9999)

	var candidates: Array[Vector2i] = []

	for x in range(-radius_val, radius_val - footprint.x + 1):
		for z in range(-radius_val, radius_val - footprint.y + 1):
			var norm_d: float = Vector2(x, z).length() / max(float(radius_val), 1.0)
			if norm_d < r_min or norm_d > r_max:
				continue

			var can_fit := true
			for bx in range(footprint.x):
				for bz in range(footprint.y):
					var cell := Vector2i(x + bx, z + bz)
					if occupied.has(cell) or cell.length() > radius_val:
						can_fit = false
						break
				if not can_fit:
					break

			if not can_fit:
				continue

			var separated := true
			for placed in _placed_facilities:
				var p_origin: Vector2i = placed["origin"]
				var dist: float = (Vector2(x, z) - Vector2(p_origin.x, p_origin.y)).length()
				if dist < float(min_sep):
					separated = false
					break
					
			if not separated:
				continue

			candidates.append(Vector2i(x, z))

	if candidates.is_empty():
		return Vector2i(9999, 9999)

	candidates.sort_custom(func(a, b):
		var ha = abs(("%s:%d:%d" % [seed_id, a.x, a.y]).hash())
		var hb = abs(("%s:%d:%d" % [seed_id, b.x, b.y]).hash())
		return ha < hb
	)
	
	return candidates[0]