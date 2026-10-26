# res://systems/society/parcel_civic_planner.gd
class_name ParcelCivicPlanner
extends RefCounted

const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

## Pass 0.5: Precalculates surface area, typical building sizes, initial vacancy, and population bounds
static func precalculate_district_metrics(world_state: Dictionary, archetypes: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var setup: Dictionary = archetypes.get("setup", {})
	var metrics: Dictionary = setup.get("block_metrics", {})
	var std_w: float = float(metrics.get("standard_block_width_m", 200.0))
	var std_h: float = float(metrics.get("standard_block_height_m", 200.0))
	var std_lot_sqm: float = std_w * std_h

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var dtype: String = str(d.get("district_type", ""))
		var arch: Dictionary = archetypes.get(dtype, {})

		var area_sqm: float = get_district_area_sqm(d, archetypes)
		d["area_sqm"] = area_sqm

		# Dedicated institutional anchors preserve authored capacity
		if arch.get("sector_class", "") == "CIVIC" or arch.get("is_unique_anchor", false):
			d["actual_building_count"] = 1
			d["avg_bldg_sqm"] = area_sqm
			d["building_allocations"] = []
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = int(arch.get("population_range", [0, 0])[0])
			d["expected_pop_min"] = d["estimated_population"]
			d["expected_pop_max"] = d["estimated_population"]
			d["is_initially_vacant"] = false
			continue

		# 8% to 10% Initial Vacancy Roll for Civic Demand Absorption
		var is_vacant_roll: bool = (rng.randf() < 0.09)
		if is_vacant_roll and arch.get("sector_class", "") != "CIVIC" and not arch.get("is_unique_anchor", false):
			d["is_initially_vacant"] = true
			d["initial_sector"] = str(arch.get("sector_class", "RESIDENTIAL"))
			d["actual_building_count"] = 0
			d["avg_bldg_sqm"] = 800.0
			d["building_allocations"] = []
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = 0
			d["expected_pop_min"] = 0
			d["expected_pop_max"] = 0
			continue

		d["is_initially_vacant"] = false
		d["initial_sector"] = str(arch.get("sector_class", "RESIDENTIAL"))

		var area_ratio: float = area_sqm / std_lot_sqm
		var base_pop_range: Array = arch.get("population_range", [0, 0])
		d["expected_pop_min"] = int(round(float(base_pop_range[0]) * area_ratio))
		d["expected_pop_max"] = int(round(float(base_pop_range[1]) * area_ratio))

		# Scale building footprint appropriately
		var base_footprint_sqm: float = float(arch.get("footprint_size", 1600.0))
		var b_range: Array = arch.get("buildings", [2, 4])
		var rolled_bldgs_for_base: int = rng.randi_range(int(b_range[0]), int(b_range[1]))
		var avg_bldg_sqm: float = maxf(50.0, base_footprint_sqm / float(maxi(1, rolled_bldgs_for_base)))
		d["avg_bldg_sqm"] = avg_bldg_sqm

		var total_buildings: int = maxi(1, int(round(area_sqm / avg_bldg_sqm)))
		d["actual_building_count"] = total_buildings

		# Per-building independent tenancy allocation
		var perc_arr: Array = arch.get("res_com_ind_perc", [100, 0, 0])
		var r_chance: float = float(perc_arr[0])
		var c_chance: float = float(perc_arr[1])
		var i_chance: float = float(perc_arr[2])

		var hab_range: Array = arch.get("habitable_units_per_building", [0, 0])
		var comm_range: Array = arch.get("commercial_units_per_building", [0, 0])
		var ind_range: Array = arch.get("industrial_units_per_building", [0, 0])

		var allocations: Array[Dictionary] = []
		var sum_hab := 0
		var sum_comm := 0
		var sum_ind := 0

		for b_idx in range(total_buildings):
			var b_hab := 0
			var b_comm := 0
			var b_ind := 0

			if (rng.randf() * 100.0) < r_chance and hab_range[1] > 0:
				b_hab = rng.randi_range(int(hab_range[0]), int(hab_range[1]))
			if (rng.randf() * 100.0) < c_chance and comm_range[1] > 0:
				b_comm = rng.randi_range(int(comm_range[0]), int(comm_range[1]))
			if (rng.randf() * 100.0) < i_chance and ind_range[1] > 0:
				b_ind = rng.randi_range(int(ind_range[0]), int(ind_range[1]))

			sum_hab += b_hab
			sum_comm += b_comm
			sum_ind += b_ind

			allocations.append({
				"building_index": b_idx,
				"habitable_units": b_hab,
				"commercial_units": b_comm,
				"industrial_units": b_ind
			})

		d["building_allocations"] = allocations
		d["total_habitable_units"] = sum_hab
		d["total_commercial_units"] = sum_comm
		d["total_industrial_units"] = sum_ind
		d["estimated_population"] = int(round(float(sum_hab) * 2.6))

## Pass 1: Dynamically places population-ratio civic facilities and absorbs vacant plots
static func run_civic_cadence_pass(world_state: Dictionary, archetypes: Dictionary, rng: RandomNumberGenerator) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var block_estimates: Dictionary = {}
	var total_city_est_pop: float = 0.0
	var max_r: float = 1.0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var p = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		max_r = max(max_r, p.length())
		
		if bool(d.get("is_initially_vacant", false)):
			block_estimates[dist_id] = 0.0
		else:
			var est_p: float = float(d.get("estimated_population", 0.0))
			block_estimates[dist_id] = est_p
			total_city_est_pop += est_p

	var cadence_rules: Array[Dictionary] = _harvest_cadence_rules(archetypes)
	var placed_by_type: Dictionary = {}

	for spec in cadence_rules:
		var code: String = spec["code"]
		placed_by_type[code] = []

		if total_city_est_pop < float(spec.get("min_pop", 0)):
			continue

		var pop_ratio: float = float(spec["pop_ratio"])
		var quota: int = maxi(1, int(round((total_city_est_pop / pop_ratio) * rng.randf_range(0.85, 1.15))))
		var placed := 0

		for _attempt in range(quota * 15):
			if placed >= quota:
				break

			var chosen: Dictionary = SPATIAL_RESOLVER.find_best_host_district(
				districts, block_estimates, placed_by_type[code], spec, max_r
			)
			if chosen.is_empty():
				break

			var dist_id: String = chosen["dist_id"]
			var d: Dictionary = districts[dist_id]

			if chosen["is_vacant"] or float(spec["footprint_sqm"]) >= (chosen["area_sqm"] * 0.70):
				d["district_type"] = code
				d["is_repurposed_civic"] = true
				d["is_initially_vacant"] = false
				d["actual_building_count"] = 1
				total_city_est_pop = max(0.0, total_city_est_pop - chosen["est_pop"])
				block_estimates[dist_id] = 0.0
			else:
				_apply_sub_block_carveout(d, spec, total_city_est_pop, block_estimates)

			placed_by_type[code].append(chosen["center"])
			placed += 1

		print("  ✓ Cadence: Placed %d '%s' facilities (Quota: %d)" % [placed, code, quota])

	_reclassify_surplus_vacant_parcels(districts)

static func _apply_sub_block_carveout(chosen_d: Dictionary, spec: Dictionary, total_city_est_pop: float, block_estimates: Dictionary) -> void:
	var req_sqm: float = float(spec.get("footprint_sqm", 1600.0))
	var avg_bldg_sqm: float = float(chosen_d.get("avg_bldg_sqm", 800.0))
	var cur_bldgs: int = int(chosen_d.get("actual_building_count", 1))

	var bldgs_consumed: int = maxi(1, int(round(req_sqm / avg_bldg_sqm)))
	bldgs_consumed = mini(bldgs_consumed, maxi(1, int(cur_bldgs * 0.25)))

	var allocations: Array = chosen_d.get("building_allocations", [])
	var fraction_lost: float = float(bldgs_consumed) / float(maxi(1, cur_bldgs))

	var total_hab: int = int(chosen_d.get("total_habitable_units", 0))
	var total_comm: int = int(chosen_d.get("total_commercial_units", 0))
	var total_ind: int = int(chosen_d.get("total_industrial_units", 0))

	chosen_d["total_habitable_units"] = maxi(0, total_hab - int(round(float(total_hab) * fraction_lost)))
	chosen_d["total_commercial_units"] = maxi(0, total_comm - int(round(float(total_comm) * fraction_lost)))
	chosen_d["total_industrial_units"] = maxi(0, total_ind - int(round(float(total_ind) * fraction_lost)))

	for _k in range(bldgs_consumed):
		if not allocations.is_empty():
			allocations.pop_back()

	chosen_d["actual_building_count"] = allocations.size()

	if not chosen_d.has("embedded_civics"):
		chosen_d["embedded_civics"] = []
	chosen_d["embedded_civics"].append(spec["code"])

	var pop_lost: float = float(chosen_d.get("estimated_population", 0.0)) * fraction_lost
	total_city_est_pop = max(0.0, total_city_est_pop - pop_lost)
	chosen_d["estimated_population"] = max(0.0, float(chosen_d.get("estimated_population", 0.0)) - pop_lost)
	block_estimates[chosen_d.get("district_id", "")] = chosen_d["estimated_population"]

static func _harvest_cadence_rules(archetypes: Dictionary) -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	for arch_key in archetypes.keys():
		if arch_key in ["_meta", "setup"]:
			continue
		var arch: Dictionary = archetypes[arch_key]
		var sp_rules: Dictionary = arch.get("spatial_rules", {})
		if sp_rules.get("placement_mode", "") == "CADENCE":
			rules.append({
				"code": arch_key,
				"pop_ratio": float(sp_rules.get("pop_ratio", 1500.0)),
				"travel_dist_m": float(sp_rules.get("travel_dist_m", sp_rules.get("min_sep_m", 750.0))),
				"min_sep_m": 0.0,
				"min_pop": int(sp_rules.get("min_city_population", 0)),
				"footprint_sqm": float(arch.get("footprint_size", arch.get("footprint_sqm", 40000.0))),
				"norm_dist_range": sp_rules.get("norm_distance_range", [0.0, 1.0]),
				"allowed_sectors": ["RESIDENTIAL", "COMMERCIAL"],
				"forbidden_types": ["municipal_park", "industrial"],
				"prefer_vacant": true
			})
	return rules

static func _reclassify_surplus_vacant_parcels(districts: Dictionary) -> void:
	var count := 0
	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		if bool(d.get("is_initially_vacant", false)):
			var orig_sector: String = str(d.get("initial_sector", "RESIDENTIAL")).to_upper()
			match orig_sector:
				"RESIDENTIAL":
					d["district_type"] = "municipal_allotments"
				"COMMERCIAL":
					d["district_type"] = "demolition_cleared_site"
				"INDUSTRIAL":
					d["district_type"] = "railway_sidings_and_scrap"
				_:
					d["district_type"] = "municipal_allotments"
			
			d["is_initially_vacant"] = false
			d["actual_building_count"] = 1
			d["total_habitable_units"] = 0
			d["total_commercial_units"] = 0
			d["total_industrial_units"] = 0
			d["estimated_population"] = 0
			d["building_allocations"] = []
			count += 1

	if count > 0:
		print("  ✓ Reassigned %d surplus vacant parcels to allotments/cleared sites/scrap sidings." % count)

static func get_district_area_sqm(district: Dictionary, archetypes: Dictionary) -> float:
	var setup: Dictionary = archetypes.get("setup", {})
	var metrics: Dictionary = setup.get("block_metrics", {})
	var std_w: float = float(metrics.get("standard_block_width_m", 200.0))
	var std_h: float = float(metrics.get("standard_block_height_m", 200.0))

	if district.has("boundary_polygon"):
		var poly: PackedVector2Array = district["boundary_polygon"]
		if poly.size() >= 3:
			var area := 0.0
			for i in range(poly.size()):
				var j := (i + 1) % poly.size()
				area += poly[i].x * poly[j].y
				area -= poly[j].x * poly[i].y
			return absf(area) * 0.5

	if district.has("size"):
		var sz = district["size"]
		if sz is Array and sz.size() >= 2:
			return float(sz[0]) * float(sz[1])
		elif sz is Vector2:
			return float(sz.x * sz.y)

	var g_size: Vector2i = district.get("grid_size", Vector2i(1, 1))
	return float(g_size.x) * std_w * float(g_size.y) * std_h