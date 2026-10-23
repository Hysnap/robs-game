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
	
	assert(_layout_rules.has("default_city_radius"), "FATAL: default_city_radius missing from business_rules.cfg")
	assert(_layout_rules.has("default_radial_jitter"), "FATAL: default_radial_jitter missing from business_rules.cfg")
	assert(_layout_rules.has("boundary_noise_scale"), "FATAL: boundary_noise_scale missing from business_rules.cfg")

	var cfg = city_configuration
	var radius: int = int(cfg.get("city_radius")) if (cfg and "city_radius" in cfg) else int(_layout_rules.get("default_city_radius"))
	var jitter: float = float(cfg.get("radial_jitter")) if (cfg and "radial_jitter" in cfg) else float(_layout_rules.get("default_radial_jitter"))
	var noise_scale: float = float(_layout_rules.get("boundary_noise_scale"))

	# 1. Pre-claim multi-cell civic anchor footprints
	for arch_key in _archetypes_data.keys():
		if arch_key in ["_meta", "setup"]:
			continue
		var arch: Dictionary = _archetypes_data[arch_key]
		if not arch.get("is_unique_anchor", false):
			continue
			
		var sites: Array = arch.get("anchor_sites", [])
		for site in sites:
			var toggle_prop: String = str(site.get("toggle_property", ""))
			var is_enabled: bool = true
			if cfg and not toggle_prop.is_empty() and toggle_prop in cfg:
				is_enabled = bool(cfg.get(toggle_prop))
				
			if not is_enabled:
				continue
				
			var target_origin := Vector2i(
				int(float(radius) * float(site.get("scale_x", 0.0))),
				int(float(radius) * float(site.get("scale_z", 0.0)))
			)
			
			var f_size_arr: Array = site.get("footprint_size", [1, 1])
			var footprint := Vector2i(int(f_size_arr[0]), int(f_size_arr[1]))
			
			blocks_data.append({
				"position": target_origin,
				"size": footprint
			})
			
			for bx in range(footprint.x):
				for bz in range(footprint.y):
					var cell := Vector2i(target_origin.x + bx, target_origin.y + bz)
					occupied_positions[cell] = true
					_anchor_claim_map[cell] = arch_key

	# 2. Populate regular blocks around civic anchors
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			var dist: float = Vector2(x, z).length()
			var noise_val: float = noise.get_noise_2d(float(x) * noise_scale, float(z) * noise_scale)
			var max_r: float = float(radius) * (1.0 + (noise_val * jitter))
			
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
	var radius: float = float(cfg.get("city_radius")) if (cfg and "city_radius" in cfg) else float(_layout_rules.get("default_city_radius"))
	var norm_dist: float = Vector2(grid_x, grid_z).length() / max(radius, 1.0)

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
	var z_noise_scale: float = float(_layout_rules.get("zoning_noise_scale"))
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
	# 1. Return from runtime cache if already built
	if _material_cache.has(district_type):
		return _material_cache[district_type]

	var cfg = city_configuration

	# 2. Priority 1: Direct material override set in city_configuration (User Inspector override)
	var prop_name := "%s_ground_material" % district_type
	if cfg and prop_name in cfg and cfg.get(prop_name) != null:
		var mat = cfg.get(prop_name)
		_material_cache[district_type] = mat
		return mat

	# 3. Priority 2: Build dynamic StandardMaterial3D from archetypes.json
	_init_archetypes()
	var arch: Dictionary = _archetypes_data.get(district_type, {})
	var visual: Dictionary = arch.get("visual_profile", {})

	if not visual.is_empty():
		var mat := StandardMaterial3D.new()
		mat.resource_name = "Mat_%s" % district_type
		
		# Set solid albedo color if specified (supports hex like "#D97706" or standard names)
		var hex_color: String = str(visual.get("color", ""))
		if not hex_color.is_empty():
			mat.albedo_color = Color.from_string(hex_color, Color.GRAY)
			
		# Set image/albedo texture if a valid file path is provided
		var tex_path: String = str(visual.get("texture_path", ""))
		if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
			var tex = load(tex_path)
			if tex is Texture2D:
				mat.albedo_texture = tex
				
		# Optional UV scaling (for repeating tile textures)
		var uv_scale_arr: Array = visual.get("uv_scale", [1.0, 1.0])
		if uv_scale_arr.size() >= 2:
			mat.uv1_scale = Vector3(float(uv_scale_arr[0]), float(uv_scale_arr[1]), 1.0)
			
		# PBR properties
		mat.roughness = float(visual.get("roughness", 0.85))
		mat.metallic = float(visual.get("metallic", 0.0))

		_material_cache[district_type] = mat
		return mat

	# 4. Priority 3: Fall back to sector-class material on cfg, then generic ground_material
	var sector_class: String = str(arch.get("sector_class", "")).to_lower()
	if not sector_class.is_empty():
		var sector_prop := "%s_ground_material" % sector_class
		if cfg and sector_prop in cfg and cfg.get(sector_prop) != null:
			var mat = cfg.get(sector_prop)
			_material_cache[district_type] = mat
			return mat

	var fallback = cfg.ground_material if (cfg and "ground_material" in cfg) else null
	return fallback

## Collects the current visual footprint of all ground planes and roads
func export_visual_layout() -> Dictionary:
	var layout := {
		"districts": {},
		"seed_id": seed_id
	}
	
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("block_id"):
			var b_id: String = child.get_meta("block_id")
			var p_mesh: PlaneMesh = child.mesh as PlaneMesh
			var b_size := Vector2.ZERO
			if p_mesh:
				b_size = p_mesh.size
				
			layout["districts"][b_id] = {
				"center": [child.position.x, child.position.y, child.position.z],
				"size": [b_size.x, b_size.y],
				"district_type": child.get_meta("district")
			}
			
	return layout

## Instantiates ground planes directly from saved layout data (No procedural math needed)
func load_visual_layout(layout_data: Dictionary) -> void:
	_init_archetypes()
	var setup: Dictionary = _archetypes_data.get("setup", {})
	assert(setup.has("default_fallback_archetype"), "FATAL: 'setup.default_fallback_archetype' is missing in archetypes.json")
	var fallback_archetype: String = str(setup.get("default_fallback_archetype"))

	for child in get_children():
		child.queue_free()
		
	var districts_data: Dictionary = layout_data.get("districts", {})
	for b_id in districts_data.keys():
		var data: Dictionary = districts_data[b_id]
		var center_arr: Array = data.get("center", [0, 0, 0])
		var size_arr: Array = data.get("size", [40, 40])
		var dtype: String = str(data.get("district_type", fallback_archetype))
		
		var center := Vector3(center_arr[0], center_arr[1], center_arr[2])
		var size := Vector2(size_arr[0], size_arr[1])
		
		create_ground_plane(center, size, dtype, b_id)

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

## Computes concentric band radial cutoffs dynamically for ANY number of bands
## driven 100% by archetypes.json band definitions and user sector sliders
func _compute_dynamic_concentric_bands(cfg) -> Array:
	var setup: Dictionary = _archetypes_data.get("setup", {})
	var bands_template: Array = setup.get("concentric_bands", [])
	assert(not bands_template.is_empty(), "FATAL: 'setup.concentric_bands' is missing or empty in archetypes.json")

	# 1. Read user ratios dynamically from configuration
	# (Collects whatever sector ratios exist on cfg, e.g. commercial_ratio, residential_ratio, etc.)
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

	# 2. Compute the relative demand of each configured band
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

	# 3. Calculate dynamic radius for each band using the Area-Integral: r = sqrt(Cumulative Area)
	var dynamic_bands: Array = []
	var cumulative_area: float = 0.0
	var num_bands: int = band_demands.size()

	for i in range(num_bands):
		var demand_share: float = band_demands[i]["demand"] / total_demand
		cumulative_area += demand_share
		
		var max_r: float = 1.0
		if i == num_bands - 1:
			max_r = 99.0 # Outermost band absorbs any edge extensions / jitter
		else:
			# Area(r) = r^2  =>  r = sqrt(Area)
			max_r = sqrt(clampf(cumulative_area, 0.05, 0.95))
			
		dynamic_bands.append({
			"weight_key": band_demands[i]["weight_key"],
			"max_norm_dist": max_r
		})

	return dynamic_bands

func _init_civic_hierarchy() -> void:
	if not _civic_hierarchy.is_empty():
		return
	var path := "res://data_modules/core/spatial/society/civic_hierarchy_1980s_uk.json"
	assert(FileAccess.file_exists(path), "FATAL: civic_hierarchy JSON missing at: %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "FATAL: Unable to open: %s" % path)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	assert(parsed is Dictionary, "FATAL: civic_hierarchy root must be a Dictionary")
	_civic_hierarchy = parsed

## Seeds major civic anchors, sports grounds, and multi-cell facilities dynamically
func _preclaim_civic_facilities(radius: int, city_pop: int, occupied_positions: Dictionary, blocks_data: Array) -> void:
	_init_civic_hierarchy()
	var facilities: Dictionary = _civic_hierarchy.get("spatial_civic_facilities", {})
	_placed_facilities.clear()

	for fac_key in facilities.keys():
		var spec: Dictionary = facilities[fac_key]
		var min_pop: int = int(spec.get("min_city_population", 0))
		if city_pop < min_pop:
			continue

		var ratio: int = int(spec.get("per_capita_ratio", 0))
		var max_count: int = int(spec.get("max_per_city", 1))
		var target_count: int = 1
		if ratio > 0:
			target_count = clamp(int(floor(float(city_pop) / float(ratio))), 1, max_count)
		else:
			target_count = max_count

		var footprint_arr: Array = spec.get("footprint_size", [1, 1])
		var footprint := Vector2i(int(footprint_arr[0]), int(footprint_arr[1]))
		var rules: Dictionary = spec.get("spatial_rules", {})
		var dist_range: Array = rules.get("norm_distance_range", [0.0, 1.0])
		var min_sep: int = int(rules.get("min_separation_blocks", 0))
		var district_type: String = str(spec.get("district_type", "civic_default"))

		var placed_count: int = 0
		var candidates: Array = _find_valid_anchor_sites(radius, footprint, dist_range, min_sep, fac_key, occupied_positions)

		for origin in candidates:
			if placed_count >= target_count:
				break

			# Claim multi-cell footprint
			blocks_data.append({
				"position": origin,
				"size": footprint
			})
			for bx in range(footprint.x):
				for bz in range(footprint.y):
					var cell := Vector2i(origin.x + bx, origin.y + bz)
					occupied_positions[cell] = true
					_anchor_claim_map[cell] = district_type

			_placed_facilities.append({
				"type": fac_key,
				"district_type": district_type,
				"origin": origin,
				"footprint": footprint
			})
			placed_count += 1

func _find_valid_anchor_sites(
	radius: int, 
	footprint: Vector2i, 
	dist_range: Array, 
	min_sep: int, 
	facility_key: String, 
	occupied: Dictionary
) -> Array:
	var valid_sites: Array = []
	var r_min: float = float(dist_range[0])
	var r_max: float = float(dist_range[1])

	# Exact Core Rule (Town Hall)
	if r_max == 0.05:
		if not occupied.has(Vector2i.ZERO):
			return [Vector2i.ZERO]
		return []

	for x in range(-radius, radius - footprint.x + 1):
		for z in range(-radius, radius - footprint.y + 1):
			var norm_d: float = Vector2(x, z).length() / max(float(radius), 1.0)
			if norm_d < r_min or norm_d > r_max:
				continue

			# Verify entire footprint is unoccupied and inside radius
			var can_fit := true
			for bx in range(footprint.x):
				for bz in range(footprint.y):
					var cell := Vector2i(x + bx, z + bz)
					if occupied.has(cell) or cell.length() > radius:
						can_fit = false
						break
				if not can_fit:
					break

			if not can_fit:
				continue

			# Minimum separation from instances of the same facility
			var separated := true
			for placed in _placed_facilities:
				if placed["type"] == facility_key:
					var d = (Vector2(x, z) - Vector2(placed["origin"].x, placed["origin"].y)).length()
					if d < min_sep:
						separated = false
						break
			if not separated:
				continue

			valid_sites.append(Vector2i(x, z))

	# Deterministic shuffle using seed so sites disperse organically
	valid_sites.sort_custom(func(a, b):
		var ha = abs(("%s:%d:%d" % [seed_id, a.x, a.y]).hash())
		var hb = abs(("%s:%d:%d" % [seed_id, b.x, b.y]).hash())
		return ha < hb
	)
	return valid_sites