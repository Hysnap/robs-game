# res://systems/society/borough_clusterer.gd
class_name BoroughClusterer
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")

## Pass 2.5: Clusters districts into realistic British municipal boroughs/wards
static func cluster_districts_into_boroughs(
	world_state: Dictionary, 
	civic_hierarchy: Dictionary, 
	lexicon_data: Dictionary, 
	_rng: RandomNumberGenerator
) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		return

	var num_districts: int = districts.size()
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	var cfg: Dictionary = civic_hierarchy.get("borough_clustering", {})
	var borough_names: Array = lexicon_data.get("borough_names", ["Aston", "Edgbaston", "Selly Oak", "Handsworth", "Erdington"]).duplicate()
	borough_names.shuffle()

	var core_def: Dictionary = cfg.get("central_core_borough", {
		"borough_id": "BOROUGH_CORE",
		"display_name": "Central Municipal Core Council"
	})
	var target_pop_per_ward: float = float(cfg.get("target_population_per_ward", 25000.0))

	var borough_defs: Array[Dictionary] = []
	var core_id: String = str(core_def.get("borough_id", "BOROUGH_CORE"))
	var core_title: String = str(core_def.get("display_name", "Central Municipal Core"))

	borough_defs.append({
		"id": core_id,
		"display_name": core_title,
		"is_core": true
	})

	var core_radius: float = float(cfg.get("core_radius_ratio", 0.22))
	var max_r := 1.0
	for d in districts.values():
		var pos = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		max_r = max(max_r, pos.length())
	var core_threshold := max_r * core_radius

	var outer_districts: Array[Dictionary] = []
	for dist_id in districts.keys():
		var d = districts[dist_id]
		var pos = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))
		var r := pos.length()

		if r <= core_threshold or str(d.get("district_type", "")) in ["commercial", "local_government"]:
			d["borough_id"] = core_id
		else:
			outer_districts.append({"id": dist_id, "pos": pos, "data": d})

	var angle_offset_radians: float = deg_to_rad(float(cfg.get("outer_ring_angle_offset_deg", 60.0)))
	var num_sectors: int = int(cfg.get("cardinal_sectors", 4))
	var sector_span: float = TAU / float(num_sectors)

	var sector_groups: Array = []
	for i in range(num_sectors):
		sector_groups.append([])

	for item in outer_districts:
		var pos: Vector2 = item["pos"]
		var angle := wrapf(atan2(pos.y, pos.x) + angle_offset_radians, -PI, PI)
		var sector_idx := int(floor((angle + PI) / sector_span)) % num_sectors
		sector_groups[sector_idx].append(item)

	var ward_counter := 0
	var dist_updates: Dictionary = {core_id: []}
	for d_id in districts.keys():
		if districts[d_id].get("borough_id") == core_id:
			dist_updates[core_id].append(d_id)

	for sector_list in sector_groups:
		if sector_list.is_empty():
			continue

		sector_list.sort_custom(func(a, b):
			return str(a["data"].get("district_type", "")) < str(b["data"].get("district_type", ""))
		)

		var current_ward_pop := 0.0
		var current_ward_dists: Array[String] = []
		var name_idx := ward_counter % borough_names.size()
		var b_name: String = borough_names[name_idx]
		var b_id := "BOROUGH_%s_%d" % [b_name.to_upper().replace(" ", "_"), ward_counter]
		var b_display := "%s Metropolitan Ward" % b_name

		for item in sector_list:
			var d: Dictionary = item["data"]
			current_ward_dists.append(item["id"])
			current_ward_pop += float(d.get("estimated_population", 500.0))

			if current_ward_pop >= target_pop_per_ward:
				borough_defs.append({"id": b_id, "display_name": b_display, "is_core": false})
				dist_updates[b_id] = current_ward_dists
				for d_id in current_ward_dists:
					d["borough_id"] = b_id
				
				ward_counter += 1
				name_idx = ward_counter % borough_names.size()
				b_name = borough_names[name_idx]
				b_id = "BOROUGH_%s_%d" % [b_name.to_upper().replace(" ", "_"), ward_counter]
				b_display = "%s Metropolitan Ward" % b_name
				current_ward_pop = 0.0
				current_ward_dists = []

		if not current_ward_dists.is_empty():
			borough_defs.append({"id": b_id, "display_name": b_display, "is_core": false})
			dist_updates[b_id] = current_ward_dists
			for d_id in current_ward_dists:
				districts[d_id]["borough_id"] = b_id
			ward_counter += 1

	var borough_inserts: Array[String] = []
	var update_statements: Array[String] = []

	for b in borough_defs:
		var b_id: String = b["id"]
		var b_title: String = b["display_name"]
		
		borough_inserts.append("""
			INSERT OR REPLACE INTO boroughs (
				borough_id, display_name, controlling_party_id, police_division_code, 
				base_council_tax_rate, valid_from, valid_to, change_reason_id
			) VALUES (
				'%s', '%s', NULL, 'D_DIVISION', 1.10, %d, NULL, %d
			);
		""" % [b_id, b_title.replace("'", "''"), sim_start_day, reason_world_gen_id])

		var assigned_dists: Array = dist_updates.get(b_id, [])
		if not assigned_dists.is_empty():
			var in_clause := ""
			for d_id in assigned_dists:
				in_clause += "'%s'," % d_id
			in_clause = in_clause.trim_suffix(",")

			update_statements.append("""
				UPDATE districts SET borough_id = '%s' WHERE district_id IN (%s);
			""" % [b_id, in_clause])

	DB_MANAGER.execute_batch(borough_inserts)
	DB_MANAGER.execute_batch(update_statements)

	print("  ✓ UK Organic Borough Realignment: Clustered %d districts into %d municipal wards." % [
		num_districts, borough_defs.size()
	])