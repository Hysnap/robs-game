# res://scripts/world/custom_city_crafter.gd
@tool
class_name CustomCityCrafter
extends "res://addons/citycrafter/citycrafter.gd"

# Cached layout rules from business_rules.cfg
var _layout_rules: Dictionary = {}

func _init_layout_rules() -> void:
	if not _layout_rules.is_empty():
		return
		
	var path := "res://data_modules/core/business_rules.cfg"
	if FileAccess.file_exists(path):
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK:
			if cfg.has_section("map_layout"):
				for key in cfg.get_section_keys("map_layout"):
					_layout_rules[key] = cfg.get_value("map_layout", key)
			if cfg.has_section("system_diagnostics"):
				for key in cfg.get_section_keys("system_diagnostics"):
					_layout_rules[key] = cfg.get_value("system_diagnostics", key)

## Overrides generate_base_grid_with_sizes() -> Array to match parent signature
func generate_base_grid_with_sizes() -> Array:
	_init_layout_rules()
	var blocks_data: Array = []
	var occupied_positions: Dictionary = {}
	
	var default_r: int = int(_layout_rules.get("default_city_radius", 14))
	var default_j: float = float(_layout_rules.get("default_radial_jitter", 0.35))
	var noise_scale: float = float(_layout_rules.get("boundary_noise_scale", 15.0))
	
	var radius: int = default_r
	var jitter: float = default_j
	
	if city_configuration is CustomCityConfiguration:
		radius = (city_configuration as CustomCityConfiguration).city_radius
		jitter = (city_configuration as CustomCityConfiguration).radial_jitter
	elif "city_radius" in city_configuration:
		radius = int(city_configuration.get("city_radius"))

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
			if city_configuration.enable_multi_size_blocks:
				block_size = determine_block_size(x, z, occupied_positions)
				
			blocks_data.append({
				"position": pos,
				"size": block_size
			})
			
			for bx in range(block_size.x):
				for bz in range(block_size.y):
					occupied_positions[Vector2i(x + bx, z + bz)] = true
					
	return blocks_data

## Overrides concentric zoning lookup using parameters from business_rules.cfg
func get_district_type(grid_x: int, grid_z: int) -> String:
	_init_layout_rules()
	var cfg = city_configuration as CustomCityConfiguration
	var radius: float = float(cfg.city_radius) if cfg else float(_layout_rules.get("default_city_radius", 14))
	var norm_dist: float = Vector2(grid_x, grid_z).length() / max(radius, 1.0)
	
	var hosp_scale: float = float(_layout_rules.get("hospital_radius_scale", 0.25))
	var univ_scale: float = float(_layout_rules.get("university_radius_scale", -0.35))
	
	# 1. Civic Anchors
	if cfg and cfg.spawn_local_government and grid_x == 0 and grid_z == 0:
		return "local_government"
	if cfg and cfg.spawn_hospital and grid_x == int(radius * hosp_scale) and grid_z == int(radius * hosp_scale):
		return "hospital_site"
	if cfg and cfg.spawn_university and grid_x == int(radius * univ_scale) and grid_z == int(radius * univ_scale):
		return "university_campus"

	# 2. Concentric Bands & Noise Cutoffs
	var core_max: float = float(_layout_rules.get("core_commercial_max_dist", 0.20))
	var inner_max: float = float(_layout_rules.get("inner_low_rise_max_dist", 0.45))
	var mid_max: float = float(_layout_rules.get("mid_ring_max_dist", 0.70))
	var z_noise_scale: float = float(_layout_rules.get("zoning_noise_scale", 8.0))
	
	if norm_dist <= core_max:
		return "commercial"
		
	elif norm_dist <= inner_max:
		var inner_noise = (noise.get_noise_2d(grid_x * z_noise_scale, grid_z * z_noise_scale) + 1.0) * 0.5
		if inner_noise > float(_layout_rules.get("inner_industrial_noise_threshold", 0.75)):
			return "industrial"
		return "high_density_low_rise"
		
	elif norm_dist <= mid_max:
		var mid_noise = (noise.get_noise_2d(grid_x * z_noise_scale, grid_z * z_noise_scale) + 1.0) * 0.5
		if mid_noise < float(_layout_rules.get("mid_high_rise_noise_threshold", 0.40)):
			return "high_density_high_rise"
		elif mid_noise < float(_layout_rules.get("mid_industrial_noise_threshold", 0.70)):
			return "industrial"
		else:
			return "commercial"
			
	else:
		return "suburban_low_density"

## Overrides building generation to respect enable_building_spawning
func generate_buildings_async() -> void:
	var cfg = city_configuration as CustomCityConfiguration
	if cfg and not cfg.enable_building_spawning:
		emit_progress(90, 100, "Macro Map: Building meshes bypassed")
		return
	await super.generate_buildings_async()

## Overrides ground generation loop using batching and logging controls from business_rules.cfg
func generate_ground_planes_async() -> void:
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
			if yield_frame:
				await get_tree().process_frame

	if enable_log:
		emit_progress(30, 100, "Ground planes complete.")

## Overrides create_ground_plane with trimesh collision generation for raycasting
func create_ground_plane(center: Vector3, size: Vector2, district_type: String = "residential", block_id: String = ""):
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = size
	
	var ground := MeshInstance3D.new()
	ground.mesh = plane_mesh
	ground.position = center
	
	var mat: Material = city_configuration.ground_material
	var cfg = city_configuration as CustomCityConfiguration
	
	match district_type:
		"commercial":
			if city_configuration.commercial_ground_material: mat = city_configuration.commercial_ground_material
		"industrial":
			if city_configuration.industrial_ground_material: mat = city_configuration.industrial_ground_material
		"high_density_high_rise":
			if cfg and cfg.high_rise_ground_material: mat = cfg.high_rise_ground_material
			elif city_configuration.residential_ground_material: mat = city_configuration.residential_ground_material
		"high_density_low_rise":
			if cfg and cfg.low_rise_ground_material: mat = cfg.low_rise_ground_material
			elif city_configuration.residential_ground_material: mat = city_configuration.residential_ground_material
		"suburban_low_density":
			if city_configuration.residential_ground_material: mat = city_configuration.residential_ground_material
		"local_government", "hospital_site", "university_campus":
			if cfg and cfg.civic_ground_material: mat = cfg.civic_ground_material
			
	if mat:
		ground.material_override = mat
		
	ground.name = "Ground_%s_%s" % [district_type, block_id]
	add_child(ground)
	
	# Generate physics collision for click raycasts
	ground.create_trimesh_collision()
	
	ground.set_meta("city_entity_type", "district")
	ground.set_meta("district", district_type)
	ground.set_meta("city_entity_id", block_id)
	ground.set_meta("block_id", block_id)
	ground.add_to_group("city_district")
	
	return ground