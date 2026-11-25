# res://systems/society/route_round_seeder.gd
class_name RouteRoundSeeder
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")

const ROLE_TO_SERVICE_MAP: Dictionary = {
	"INSURANCE_AGENT_COLLECTOR": "INSURANCE_COLLECTION_ROUND",
	"RENT_COLLECTOR_AGENT": "RENT_AND_CHECK_ROUND"
}

const DEPOT_CLASS_TO_SERVICE_MAP: Dictionary = {
	"DAIRY_DEPOT": "MILK_ROUND",
	"SOFT_DRINKS_DEPOT": "POP_DELIVERY_ROUND",
	"COAL_MERCHANT_YARD": "COAL_ROUND",
	"INSURANCE_DISTRICT_OFFICE": "INSURANCE_COLLECTION_ROUND",
	"PRIVATE_LANDLORDS_OFFICE": "RENT_AND_CHECK_ROUND",
	"CLUB_CHECK_CREDIT_OFFICE": "RENT_AND_CHECK_ROUND"
}

## Computes effective working days per worker per year after excluding bank holidays (optional) and ~30 absence days
static func compute_effective_working_days_per_year(
	coverage_cfg: Dictionary,
	sim_start_day: int,
	active_days_per_week: int = 6
) -> float:
	assert(coverage_cfg.has("absence_days_per_year"), "FATAL: [RouteRoundSeeder] Missing 'absence_days_per_year' in route_rounds.staffing_coverage!")
	var absence_days: float = maxf(0.0, float(coverage_cfg["absence_days_per_year"]))
	var exclude_holidays: bool = bool(coverage_cfg.get("exclude_bank_holidays", true))

	var bank_holiday_days: float = 0.0
	if exclude_holidays:
		var yr: int = CALENDAR_HELPER.day_to_year(sim_start_day)
		var yr_holidays: Dictionary = CALENDAR_HELPER._get_holidays_for_year(yr)
		var postal_map: Dictionary = yr_holidays.get("POSTAL", {})
		bank_holiday_days = float(postal_map.size())

	var base_active_days: float = float(clampi(active_days_per_week, 1, 7)) * 52.0
	var effective_days: float = base_active_days - absence_days - bank_holiday_days
	return maxf(52.0, effective_days)

## Computes required roundsmen/collectors for a round given district count, active days, and ~30-day absence allowance
static func compute_required_workers(
	round_cfg: Dictionary,
	coverage_cfg: Dictionary,
	eligible_district_count: int,
	sim_start_day: int
) -> int:
	if eligible_district_count <= 0:
		return 0
	var min_per_depot: int = maxi(1, int(coverage_cfg.get("min_roundsmen_per_active_depot", 1)))
	var per_worker_districts: int = maxi(1, int(round_cfg.get("districts_per_roundsman", 4)))
	var patch_mode: String = str(round_cfg.get("patch_mode", "ROTATING_DAILY"))

	var deliv_cfg: Dictionary = round_cfg.get("delivery_schedule", {})
	var deliv_days: Array = deliv_cfg.get("days_of_week", [1, 2, 3, 4, 5, 6])
	var effective_days: float = compute_effective_working_days_per_year(coverage_cfg, sim_start_day, deliv_days.size())
	var scheduled_days_per_year: float = float(deliv_days.size()) * 52.0
	var absence_factor: float = clampf(scheduled_days_per_year / effective_days, 1.0, 1.5)

	var base_needed: float = 0.0
	if patch_mode == "FIXED_TERRITORY":
		base_needed = ceil(float(eligible_district_count) / float(per_worker_districts))
	else:
		base_needed = ceil(float(eligible_district_count) / float(maxi(1, deliv_days.size())))

	return maxi(min_per_depot, int(ceil(base_needed * absence_factor)))

## Seeds persisted service_routes rows for contracted field/route workers using anti-collision district/day allocation
static func seed_service_routes(physical_state: Dictionary, sim_start_day: int) -> int:
	assert(MANIFEST_MANAGER.has_module("route_rounds"), "FATAL: [RouteRoundSeeder] Scenario manifest missing 'route_rounds' module!")
	var route_cfg: Dictionary = MANIFEST_MANAGER.load_module("route_rounds")
	assert(route_cfg.has("rounds") and route_cfg["rounds"] is Dictionary, "FATAL: [RouteRoundSeeder] Missing 'rounds' dictionary in route_rounds module!")
	assert(route_cfg.has("staffing_coverage") and route_cfg["staffing_coverage"] is Dictionary, "FATAL: [RouteRoundSeeder] Missing 'staffing_coverage' dictionary in route_rounds module!")

	var rounds_def: Dictionary = route_cfg["rounds"]
	var coverage_cfg: Dictionary = route_cfg["staffing_coverage"]
	var collision_cfg: Dictionary = route_cfg.get("anti_collision_rules", {})
	var same_day_service_penalty: float = float(collision_cfg.get("same_day_same_district_service_penalty", 100.0))
	var same_service_day_penalty: float = float(collision_cfg.get("same_service_same_day_district_penalty", 50.0))
	var worker_overlap_penalty: float = float(collision_cfg.get("depot_worker_overlap_penalty", 25.0))
	var pt_hours_threshold: float = 24.0

	var reason_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	var districts_map: Dictionary = physical_state.get("districts", {})
	var residential_district_ids: Array[String] = []
	var district_positions: Dictionary = {}
	for d_id_raw in districts_map.keys():
		var d_id := str(d_id_raw)
		var d_rec = districts_map[d_id_raw]
		if not (d_rec is Dictionary):
			continue
		var d_type := str(d_rec.get("district_type", ""))
		if d_type.begins_with("residential") or d_type.begins_with("high_density") or d_type.begins_with("suburban"):
			residential_district_ids.append(d_id)
		district_positions[d_id] = _resolve_pos(d_rec.get("spatial_anchor", Vector2.ZERO))

	if residential_district_ids.is_empty():
		for d_id_raw in districts_map.keys():
			residential_district_ids.append(str(d_id_raw))

	if residential_district_ids.is_empty():
		return 0

	var worker_rows: Array = DB_MANAGER.query_rows("""
		SELECT
			c.resident_id,
			c.employer_establishment_id,
			c.weekly_hours,
			l_role.code AS role_code,
			e.district_id AS depot_district_id,
			l_cat.code AS depot_category_code
		FROM livelihood_contracts c
		JOIN residents r ON c.resident_id = r.resident_id
		JOIN system_labels l_role ON c.role_title_id = l_role.label_id
		LEFT JOIN establishments e ON c.employer_establishment_id = e.establishment_id
		LEFT JOIN system_labels l_cat ON e.category_id = l_cat.label_id
		WHERE c.valid_to IS NULL
		  AND r.dod IS NULL
		  AND l_role.code IN ('ROUNDSMAN_DELIVERY', 'INSURANCE_AGENT_COLLECTOR', 'RENT_COLLECTOR_AGENT')
		ORDER BY c.employer_establishment_id ASC, c.resident_id ASC;
	""")

	if worker_rows.is_empty():
		return 0

	# Track global load per "district_id:day_of_week" and "service_code:district_id:day_of_week"
	var district_day_load: Dictionary = {}
	var service_district_day_load: Dictionary = {}
	var worker_day_assigned: Dictionary = {}
	var depot_service_workers: Dictionary = {}

	for row in worker_rows:
		var est_id: int = int(row.get("employer_establishment_id", 0))
		var role_code: String = str(row.get("role_code", ""))
		var depot_cat: String = str(row.get("depot_category_code", ""))
		var service_code: String = ""
		if DEPOT_CLASS_TO_SERVICE_MAP.has(depot_cat):
			service_code = str(DEPOT_CLASS_TO_SERVICE_MAP[depot_cat])
		elif ROLE_TO_SERVICE_MAP.has(role_code):
			service_code = str(ROLE_TO_SERVICE_MAP[role_code])
		else:
			service_code = "COAL_ROUND"

		if not rounds_def.has(service_code):
			continue

		var key := "%d:%s" % [est_id, service_code]
		if not depot_service_workers.has(key):
			depot_service_workers[key] = []
		depot_service_workers[key].append(row)

	var route_inserts: Array[String] = []
	var inserted_count: int = 0

	for key in depot_service_workers.keys():
		var parts: PackedStringArray = str(key).split(":")
		var est_id: int = int(parts[0])
		var service_code: String = str(parts[1])
		var r_cfg: Dictionary = rounds_def[service_code]
		var patch_mode: String = str(r_cfg.get("patch_mode", "ROTATING_DAILY"))
		var districts_per_worker: int = maxi(1, int(r_cfg.get("districts_per_roundsman", 4)))

		var deliv_cfg: Dictionary = r_cfg.get("delivery_schedule", {})
		var deliv_days: Array = deliv_cfg.get("days_of_week", [1, 2, 3, 4, 5])
		var deliv_window: String = str(deliv_cfg.get("time_window", "DAYTIME"))
		var deliv_action: String = str(deliv_cfg.get("action_mode", "DELIVER_AND_STOCK"))

		var coll_cfg: Dictionary = r_cfg.get("collection_schedule", {})
		var coll_enabled: bool = bool(coll_cfg.get("enabled", false))
		var coll_days: Array = coll_cfg.get("days_of_week", [5])
		var coll_window: String = str(coll_cfg.get("time_window", "AFTERNOON"))
		var coll_action: String = str(coll_cfg.get("action_mode", "COLLECT_CASH"))

		var group_workers: Array = depot_service_workers[key]
		var depot_dist_id: String = str(group_workers[0].get("depot_district_id", ""))
		var depot_pos: Vector2 = district_positions.get(depot_dist_id, Vector2.ZERO)

		var sorted_districts: Array[String] = residential_district_ids.duplicate()
		sorted_districts.sort_custom(func(a: String, b: String) -> bool:
			var pa: Vector2 = district_positions.get(a, Vector2.ZERO)
			var pb: Vector2 = district_positions.get(b, Vector2.ZERO)
			return depot_pos.distance_squared_to(pa) < depot_pos.distance_squared_to(pb)
		)

		var used_district_days: Dictionary = {}

		for w_idx in range(group_workers.size()):
			var w_row: Dictionary = group_workers[w_idx]
			var res_id: int = int(w_row.get("resident_id", 0))
			var weekly_hrs: float = float(w_row.get("weekly_hours", 40.0))
			var is_pt: int = 1 if weekly_hrs < pt_hours_threshold else 0

			# Partition candidate districts across workers in the same depot/service where possible
			var worker_patch: Array[String] = []
			var start_slice: int = (w_idx * districts_per_worker) % maxi(1, sorted_districts.size())
			for s_i in range(mini(districts_per_worker, sorted_districts.size())):
				worker_patch.append(sorted_districts[(start_slice + s_i) % sorted_districts.size()])

			if patch_mode == "FIXED_TERRITORY":
				# Milkman stays on their fixed patch across scheduled days and collects cash Friday afternoon
				var anchor_dist: String = worker_patch[0]
				for d_raw in deliv_days:
					var dow: int = int(d_raw)
					route_inserts.append("""
						INSERT INTO service_routes (
							establishment_id, worker_resident_id, service_code, day_of_week,
							time_window, target_district_id, action_mode, is_part_time,
							valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, '%s', %d, '%s', '%s', '%s', %d, %d, NULL, %d);
					""" % [
						est_id, res_id, service_code, dow, deliv_window,
						anchor_dist.replace("'", "''"), deliv_action, is_pt, sim_start_day, reason_id
					])
					inserted_count += 1
					_bump_load(district_day_load, service_district_day_load, worker_day_assigned, anchor_dist, service_code, dow, res_id, 1.0)

				if coll_enabled:
					for c_raw in coll_days:
						var cdow: int = int(c_raw)
						route_inserts.append("""
							INSERT INTO service_routes (
								establishment_id, worker_resident_id, service_code, day_of_week,
								time_window, target_district_id, action_mode, is_part_time,
								valid_from, valid_to, change_reason_id
							) VALUES (%d, %d, '%s', %d, '%s', '%s', '%s', %d, %d, NULL, %d);
						""" % [
							est_id, res_id, service_code, cdow, coll_window,
							anchor_dist.replace("'", "''"), coll_action, is_pt, sim_start_day, reason_id
						])
						inserted_count += 1
						_bump_load(district_day_load, service_district_day_load, worker_day_assigned, anchor_dist, service_code, cdow, res_id, 1.0)
			else:
				# Rotating routes (Corona, Coal, Insurance/Pru, Rent/Check) pick least-colliding (district, day) pairs
				var pool_candidates: Array[String] = worker_patch if not worker_patch.is_empty() else sorted_districts
				for d_raw in deliv_days:
					var dow: int = int(d_raw)
					var chosen_dist: String = pool_candidates[0]
					var best_cost: float = INF

					for cand_dist in pool_candidates:
						var pair_key := "%s:%d" % [cand_dist, dow]
						if used_district_days.has(pair_key):
							continue
						var d_cost: float = float(district_day_load.get(pair_key, 0.0)) * same_day_service_penalty
						var s_key := "%s:%s:%d" % [service_code, cand_dist, dow]
						var s_cost: float = float(service_district_day_load.get(s_key, 0.0)) * same_service_day_penalty
						var w_key := "%d:%d" % [res_id, dow]
						var w_cost: float = float(worker_day_assigned.get(w_key, 0.0)) * worker_overlap_penalty
						var total_cost: float = d_cost + s_cost + w_cost
						if total_cost < best_cost:
							best_cost = total_cost
							chosen_dist = cand_dist

					used_district_days["%s:%d" % [chosen_dist, dow]] = true
					route_inserts.append("""
						INSERT INTO service_routes (
							establishment_id, worker_resident_id, service_code, day_of_week,
							time_window, target_district_id, action_mode, is_part_time,
							valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, '%s', %d, '%s', '%s', '%s', %d, %d, NULL, %d);
					""" % [
						est_id, res_id, service_code, dow, deliv_window,
						chosen_dist.replace("'", "''"), deliv_action, is_pt, sim_start_day, reason_id
					])
					inserted_count += 1
					_bump_load(district_day_load, service_district_day_load, worker_day_assigned, chosen_dist, service_code, dow, res_id, 1.0)

	if not route_inserts.is_empty():
		DB_MANAGER.execute_batch(route_inserts)
		SystemLogger.log_info("  ✓ Seeded %d anti-collision service_routes entries across %d route workers." % [inserted_count, worker_rows.size()])

	return inserted_count

static func _bump_load(
	district_day_load: Dictionary,
	service_district_day_load: Dictionary,
	worker_day_assigned: Dictionary,
	dist_id: String,
	service_code: String,
	dow: int,
	res_id: int,
	delta: float
) -> void:
	var dd_key := "%s:%d" % [dist_id, dow]
	district_day_load[dd_key] = float(district_day_load.get(dd_key, 0.0)) + delta
	var sdd_key := "%s:%s:%d" % [service_code, dist_id, dow]
	service_district_day_load[sdd_key] = float(service_district_day_load.get(sdd_key, 0.0)) + delta
	var wd_key := "%d:%d" % [res_id, dow]
	worker_day_assigned[wd_key] = float(worker_day_assigned.get(wd_key, 0.0)) + delta

static func _resolve_pos(raw_anchor: Variant) -> Vector2:
	if raw_anchor is Vector2:
		return raw_anchor
	if raw_anchor is Array and raw_anchor.size() >= 2:
		return Vector2(float(raw_anchor[0]), float(raw_anchor[1]))
	if raw_anchor is Dictionary and raw_anchor.has("x") and raw_anchor.has("y"):
		return Vector2(float(raw_anchor["x"]), float(raw_anchor["y"]))
	return Vector2.ZERO