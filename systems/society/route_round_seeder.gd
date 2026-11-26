# res://systems/society/route_round_seeder.gd
class_name RouteRoundSeeder
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")

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

## Seeds persisted service_routes rows for all registered rounds (legal cooperative + flavour contested/shared routes)
static func seed_service_routes(physical_state: Dictionary, sim_start_day: int) -> int:
	assert(MANIFEST_MANAGER.has_module("route_rounds"), "FATAL: [RouteRoundSeeder] Scenario manifest missing 'route_rounds' module!")
	var route_cfg: Dictionary = MANIFEST_MANAGER.load_module("route_rounds")
	assert(route_cfg.has("rounds") and route_cfg["rounds"] is Dictionary, "FATAL: [RouteRoundSeeder] Missing 'rounds' dictionary in route_rounds module!")
	assert(route_cfg.has("staffing_coverage") and route_cfg["staffing_coverage"] is Dictionary, "FATAL: [RouteRoundSeeder] Missing 'staffing_coverage' dictionary in route_rounds module!")

	var rounds_def: Dictionary = route_cfg["rounds"]
	var coverage_cfg: Dictionary = route_cfg["staffing_coverage"]
	var collision_cfg: Dictionary = route_cfg.get("anti_collision_rules", {})
	var base_same_day_service_penalty: float = float(collision_cfg.get("same_day_same_district_service_penalty", 100.0))
	var base_same_service_day_penalty: float = float(collision_cfg.get("same_service_same_day_district_penalty", 50.0))
	var base_worker_overlap_penalty: float = float(collision_cfg.get("depot_worker_overlap_penalty", 25.0))
	var pt_hours_threshold: float = 24.0

	var reason_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	var districts_map: Dictionary = physical_state.get("districts", {})
	var residential_district_ids: Array[String] = []
	var all_active_district_ids: Array[String] = []
	var district_positions: Dictionary = {}
	var district_populations: Dictionary = {}

	for d_id_raw in districts_map.keys():
		var d_id := str(d_id_raw)
		var d_rec = districts_map[d_id_raw]
		if not (d_rec is Dictionary):
			continue
		if bool(d_rec.get("is_vacant_plot", false)):
			continue
		all_active_district_ids.append(d_id)
		var d_type := str(d_rec.get("district_type", ""))
		if d_type.begins_with("residential") or d_type.begins_with("high_density") or d_type.begins_with("suburban"):
			residential_district_ids.append(d_id)
		district_positions[d_id] = _resolve_pos(d_rec.get("spatial_anchor", Vector2.ZERO))
		district_populations[d_id] = maxi(50, int(d_rec.get("estimated_population", d_rec.get("population", 250))))

	if residential_district_ids.is_empty():
		residential_district_ids = all_active_district_ids.duplicate()

	if residential_district_ids.is_empty():
		return 0

	var district_households: Dictionary = {}
	var district_addresses: Dictionary = {}
	var hh_rows: Array = DB_MANAGER.query_rows("""
		SELECT e.district_id, COUNT(h.household_id) AS hh_cnt
		FROM households h
		JOIN establishments e ON h.establishment_id = e.establishment_id
		WHERE h.valid_to IS NULL
		GROUP BY e.district_id;
	""")
	for hr in hh_rows:
		var d_id_h: String = str(hr.get("district_id", ""))
		var cnt_h: int = int(hr.get("hh_cnt", 0))
		district_households[d_id_h] = cnt_h
		district_addresses[d_id_h] = int(district_addresses.get(d_id_h, 0)) + cnt_h

	var est_rows: Array = DB_MANAGER.query_rows("""
		SELECT district_id, COUNT(establishment_id) AS est_cnt
		FROM establishments
		WHERE valid_to IS NULL
		GROUP BY district_id;
	""")
	for er in est_rows:
		var d_id_e: String = str(er.get("district_id", ""))
		district_addresses[d_id_e] = int(district_addresses.get(d_id_e, 0)) + int(er.get("est_cnt", 0))

	var worker_window_busy: Dictionary = {}

	# Discover all staff_role_ids and depot_building_classes dynamically from route_rounds
	var role_to_services: Dictionary = {}
	var depot_to_services: Dictionary = {}
	var all_role_codes: Array[String] = []

	for svc_key in rounds_def.keys():
		var r_entry = rounds_def[svc_key]
		if not (r_entry is Dictionary):
			continue
		var svc_code: String = str(r_entry.get("service_code", svc_key)).strip_edges()
		for role_raw in r_entry.get("staff_role_ids", []):
			var r_code: String = str(role_raw).strip_edges()
			if r_code.is_empty():
				continue
			if not all_role_codes.has(r_code):
				all_role_codes.append(r_code)
			if not role_to_services.has(r_code):
				role_to_services[r_code] = []
			role_to_services[r_code].append(svc_code)
		for depot_raw in r_entry.get("depot_building_classes", []):
			var d_code: String = str(depot_raw).strip_edges()
			if d_code.is_empty():
				continue
			if not depot_to_services.has(d_code):
				depot_to_services[d_code] = []
			depot_to_services[d_code].append(svc_code)

	if all_role_codes.is_empty():
		return 0

	var quoted_roles: Array[String] = []
	for rc in all_role_codes:
		quoted_roles.append("'%s'" % rc.replace("'", "''"))

	var worker_rows: Array = DB_MANAGER.query_rows("""
		SELECT
			c.resident_id,
			c.employer_establishment_id,
			c.weekly_hours,
			l_role.code AS role_code,
			COALESCE(e.district_id, h_e.district_id) AS depot_district_id,
			l_cat.code AS depot_category_code
		FROM livelihood_contracts c
		JOIN residents r ON c.resident_id = r.resident_id
		JOIN system_labels l_role ON c.role_title_id = l_role.label_id
		LEFT JOIN establishments e ON c.employer_establishment_id = e.establishment_id
		LEFT JOIN households h ON r.household_id = h.household_id
		LEFT JOIN establishments h_e ON h.establishment_id = h_e.establishment_id
		LEFT JOIN system_labels l_cat ON e.category_id = l_cat.label_id
		WHERE c.valid_to IS NULL
		  AND r.dod IS NULL
		  AND l_role.code IN (%s)
		ORDER BY c.employer_establishment_id ASC, c.resident_id ASC;
	""" % ", ".join(quoted_roles))

	var district_day_load: Dictionary = {}
	var service_district_day_load: Dictionary = {}
	var worker_day_assigned: Dictionary = {}
	var depot_service_workers: Dictionary = {}

	for row in worker_rows:
		var est_id: int = int(row.get("employer_establishment_id", 0))
		var role_code: String = str(row.get("role_code", "")).strip_edges()
		var depot_cat: String = str(row.get("depot_category_code", "")).strip_edges()
		var matched_service: String = ""

		if not depot_cat.is_empty() and depot_to_services.has(depot_cat):
			var depot_svcs: Array = depot_to_services[depot_cat]
			for cand_svc in depot_svcs:
				var r_roles: Array = rounds_def.get(cand_svc, {}).get("staff_role_ids", [])
				if not r_roles.is_empty() and r_roles.has(role_code):
					matched_service = str(cand_svc)
					break

		if matched_service.is_empty() and role_to_services.has(role_code):
			var role_svcs: Array = role_to_services[role_code]
			if not role_svcs.is_empty():
				matched_service = str(role_svcs[0])

		if matched_service.is_empty() or not rounds_def.has(matched_service):
			continue

		var key := "%d:%s" % [est_id, matched_service]
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
		var territory_mode: String = str(r_cfg.get("territory_mode", "COOPERATIVE")).to_upper()
		var districts_per_worker: int = maxi(1, int(r_cfg.get("districts_per_roundsman", 4)))

		var same_day_service_penalty: float = base_same_day_service_penalty
		var same_service_day_penalty: float = base_same_service_day_penalty
		var worker_overlap_penalty: float = base_worker_overlap_penalty

		if territory_mode == "CONTESTED":
			same_day_service_penalty *= 0.15
			same_service_day_penalty *= 0.15
		elif territory_mode == "SHARED_MARKETPLACE":
			same_day_service_penalty = 0.0
			same_service_day_penalty = 0.0

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
		var use_all_districts: bool = (not r_cfg.get("fulfillment_config", {}).is_empty()) or r_cfg.has("address_capacity_per_worker") or (not r_cfg.get("collects_from_building_classes", []).is_empty())
		var candidate_pool: Array[String] = all_active_district_ids if use_all_districts else residential_district_ids
		if candidate_pool.is_empty():
			candidate_pool = residential_district_ids

		var addr_cap: int = int(r_cfg.get("address_capacity_per_worker", 0))
		var addr_cursor: int = 0

		for w_idx in range(group_workers.size()):
			var w_row: Dictionary = group_workers[w_idx]
			var res_id: int = int(w_row.get("resident_id", 0))
			var weekly_hrs: float = float(w_row.get("weekly_hours", 40.0))
			var is_pt: int = 1 if weekly_hrs < pt_hours_threshold else 0
			var worker_base_dist: String = str(w_row.get("depot_district_id", ""))
			var depot_pos: Vector2 = district_positions.get(worker_base_dist, Vector2.ZERO)

			var sorted_districts: Array[String] = candidate_pool.duplicate()
			sorted_districts.sort_custom(func(a: String, b: String) -> bool:
				var pa: Vector2 = district_positions.get(a, Vector2.ZERO)
				var pb: Vector2 = district_positions.get(b, Vector2.ZERO)
				return depot_pos.distance_squared_to(pa) < depot_pos.distance_squared_to(pb)
			)

			var worker_patch: Array[String] = []
			if territory_mode == "SHARED_MARKETPLACE" and not worker_base_dist.is_empty() and sorted_districts.has(worker_base_dist):
				worker_patch.append(worker_base_dist)
			elif addr_cap > 0 and not sorted_districts.is_empty():
				var acc_addr: int = 0
				var safety: int = 0
				while safety < sorted_districts.size():
					var cand_d: String = sorted_districts[addr_cursor % sorted_districts.size()]
					addr_cursor += 1
					safety += 1
					worker_patch.append(cand_d)
					acc_addr += maxi(50, int(district_addresses.get(cand_d, 200)))
					if acc_addr >= addr_cap:
						break
			else:
				var start_slice: int = (w_idx * districts_per_worker) % maxi(1, sorted_districts.size())
				for s_i in range(mini(districts_per_worker, sorted_districts.size())):
					worker_patch.append(sorted_districts[(start_slice + s_i) % sorted_districts.size()])

			var est_sql: String = str(est_id) if est_id > 0 else "NULL"

			if patch_mode == "FIXED_TERRITORY":
				var anchor_dist: String = worker_patch[0]
				for p_dist in worker_patch:
					for d_raw in deliv_days:
						var dow: int = int(d_raw)
						route_inserts.append("""
							INSERT INTO service_routes (
								establishment_id, worker_resident_id, service_code, day_of_week,
								time_window, target_district_id, action_mode, is_part_time,
								valid_from, valid_to, change_reason_id
							) VALUES (%s, %d, '%s', %d, '%s', '%s', '%s', %d, %d, NULL, %d);
						""" % [
							est_sql, res_id, service_code, dow, deliv_window,
							p_dist.replace("'", "''"), deliv_action, is_pt, sim_start_day, reason_id
						])
						inserted_count += 1
						worker_window_busy["%d:%d:%s" % [res_id, dow, deliv_window]] = true
						_bump_load(district_day_load, service_district_day_load, worker_day_assigned, p_dist, service_code, dow, res_id, 1.0)

				if coll_enabled:
					for c_raw in coll_days:
						var cdow: int = int(c_raw)
						route_inserts.append("""
							INSERT INTO service_routes (
								establishment_id, worker_resident_id, service_code, day_of_week,
								time_window, target_district_id, action_mode, is_part_time,
								valid_from, valid_to, change_reason_id
							) VALUES (%s, %d, '%s', %d, '%s', '%s', '%s', %d, %d, NULL, %d);
						""" % [
							est_sql, res_id, service_code, cdow, coll_window,
							anchor_dist.replace("'", "''"), coll_action, is_pt, sim_start_day, reason_id
						])
						inserted_count += 1
						_bump_load(district_day_load, service_district_day_load, worker_day_assigned, anchor_dist, service_code, cdow, res_id, 1.0)
			else:
				var used_district_days: Dictionary = {}
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
						) VALUES (%s, %d, '%s', %d, '%s', '%s', '%s', %d, %d, NULL, %d);
					""" % [
						est_sql, res_id, service_code, dow, deliv_window,
						chosen_dist.replace("'", "''"), deliv_action, is_pt, sim_start_day, reason_id
					])
					inserted_count += 1
					_bump_load(district_day_load, service_district_day_load, worker_day_assigned, chosen_dist, service_code, dow, res_id, 1.0)

	# Seed depot-backed secondary/catchment rounds (e.g. PAPER_ROUND anchored to CORNER_SHOP & SUB_POST_OFFICE)
	inserted_count += _seed_depot_catchment_secondary_routes(
		route_inserts,
		rounds_def,
		residential_district_ids,
		district_positions,
		district_households,
		worker_window_busy,
		district_day_load,
		service_district_day_load,
		worker_day_assigned,
		sim_start_day,
		reason_id
	)

	# Seed un-premised sole-proprietor & secondary rounds (Avon, Catalogue, Pools + Concessionaires, Street Vice)
	inserted_count += _seed_unpremised_sole_routes(
		route_inserts,
		rounds_def,
		all_active_district_ids,
		district_populations,
		district_households,
		worker_window_busy,
		district_day_load,
		service_district_day_load,
		worker_day_assigned,
		sim_start_day,
		reason_id
	)

	if not route_inserts.is_empty():
		DB_MANAGER.execute_batch(route_inserts)
		SystemLogger.log_info("  ✓ Seeded %d service_routes entries across cooperative, contested, and shared marketplace rounds." % inserted_count)

	return inserted_count

## Helper: queries eligible resident_ids grouped by district using cascading operator_eligibility rules
static func _query_eligible_residents_by_district(elig: Dictionary, sim_start_day: int) -> Dictionary:
	var age_min: int = int(elig.get("age_min", 18))
	var age_max: int = int(elig.get("age_max", 55))
	var raw_roles: Array = elig.get("eligible_role_codes", [])
	var max_weekly_hrs: float = float(elig.get("max_primary_weekly_hours", -1.0))

	var role_clause: String = ""
	if not raw_roles.is_empty():
		var quoted_roles: Array[String] = []
		for rc in raw_roles:
			var clean_rc: String = str(rc).strip_edges().to_upper()
			if not clean_rc.is_empty():
				quoted_roles.append("'%s'" % clean_rc.replace("'", "''"))
		if not quoted_roles.is_empty():
			if max_weekly_hrs > 0.0:
				role_clause = "AND (l_role.code IN (%s) OR c.weekly_hours <= %.1f)" % [", ".join(quoted_roles), max_weekly_hrs]
			else:
				role_clause = "AND l_role.code IN (%s)" % ", ".join(quoted_roles)
	elif max_weekly_hrs > 0.0:
		role_clause = "AND c.weekly_hours <= %.1f" % max_weekly_hrs

	var gender_clause: String = ""
	var raw_genders: Array = elig.get("gender_codes", [])
	if not raw_genders.is_empty():
		var quoted_genders: Array[String] = []
		for gc in raw_genders:
			var clean_gc: String = str(gc).strip_edges().to_upper()
			if not clean_gc.is_empty():
				quoted_genders.append("'%s'" % clean_gc.replace("'", "''"))
		if not quoted_genders.is_empty():
			gender_clause = "AND l_gen.code IN (%s)" % ", ".join(quoted_genders)

	var min_dob: int = sim_start_day - int(round(float(age_max) * 365.25))
	var max_dob: int = sim_start_day - int(round(float(age_min) * 365.25))

	var rows: Array = DB_MANAGER.query_rows("""
		SELECT DISTINCT r.resident_id, e.district_id
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		JOIN system_labels l_gen ON r.gender_id = l_gen.label_id
		JOIN livelihood_contracts c ON c.resident_id = r.resident_id AND c.valid_to IS NULL
		JOIN system_labels l_role ON c.role_title_id = l_role.label_id
		WHERE r.dod IS NULL
		  AND r.dob BETWEEN %d AND %d
		  %s
		  %s
		ORDER BY r.resident_id ASC;
	""" % [min_dob, max_dob, role_clause, gender_clause])

	var by_dist: Dictionary = {}
	for row in rows:
		var res_id: int = int(row.get("resident_id", 0))
		if res_id <= 0:
			continue
		var d_id: String = str(row.get("district_id", ""))
		if not by_dist.has(d_id):
			by_dist[d_id] = []
		by_dist[d_id].append(res_id)
	return by_dist

static func _is_worker_free_for_schedule(worker_window_busy: Dictionary, res_id: int, days: Array, time_window: String) -> bool:
	for d_raw in days:
		if worker_window_busy.has("%d:%d:%s" % [res_id, int(d_raw), time_window]):
			return false
	return true

static func _mark_worker_busy_for_schedule(worker_window_busy: Dictionary, res_id: int, days: Array, time_window: String) -> void:
	for d_raw in days:
		worker_window_busy["%d:%d:%s" % [res_id, int(d_raw), time_window]] = true

## Seeds depot-backed secondary catchment rounds (e.g. PAPER_ROUND anchored to CORNER_SHOP & SUB_POST_OFFICE)
static func _seed_depot_catchment_secondary_routes(
	route_inserts: Array[String],
	rounds_def: Dictionary,
	residential_district_ids: Array[String],
	district_positions: Dictionary,
	district_households: Dictionary,
	worker_window_busy: Dictionary,
	district_day_load: Dictionary,
	service_district_day_load: Dictionary,
	worker_day_assigned: Dictionary,
	sim_start_day: int,
	reason_id: int
) -> int:
	var added: int = 0
	for svc_key in rounds_def.keys():
		var r_cfg = rounds_def[svc_key]
		if not (r_cfg is Dictionary):
			continue
		var depots: Array = r_cfg.get("depot_building_classes", [])
		var staff_roles: Array = r_cfg.get("staff_role_ids", [])
		var elig: Dictionary = r_cfg.get("operator_eligibility", {})
		if depots.is_empty() or not staff_roles.is_empty() or elig.is_empty():
			continue

		var svc_code: String = str(r_cfg.get("service_code", svc_key)).strip_edges()
		var quoted_cats: Array[String] = []
		for dc in depots:
			quoted_cats.append("'%s'" % str(dc).strip_edges().replace("'", "''"))

		var depot_rows: Array = DB_MANAGER.query_rows("""
			SELECT e.establishment_id, e.district_id
			FROM establishments e
			JOIN system_labels l_cat ON e.category_id = l_cat.label_id
			WHERE e.valid_to IS NULL
			  AND l_cat.code IN (%s)
			ORDER BY e.establishment_id ASC;
		""" % ", ".join(quoted_cats))
		if depot_rows.is_empty():
			continue

		var residents_by_dist: Dictionary = _query_eligible_residents_by_district(elig, sim_start_day)
		var deliv_cfg: Dictionary = r_cfg.get("delivery_schedule", {})
		var deliv_days: Array = deliv_cfg.get("days_of_week", [1, 2, 3, 4, 5, 6, 7])
		var deliv_window: String = str(deliv_cfg.get("time_window", "EARLY_MORNING"))
		var deliv_action: String = str(deliv_cfg.get("action_mode", "DELIVER_NEWSPAPERS"))
		var ops_range: Array = r_cfg.get("operators_per_depot", [3, 7])
		var min_ops: int = maxi(1, int(ops_range[0])) if ops_range.size() >= 1 else 3
		var max_ops: int = maxi(min_ops, int(ops_range[1])) if ops_range.size() >= 2 else 7
		var res_per_worker: float = maxf(50.0, float(r_cfg.get("residencies_per_worker", 250.0)))

		for d_row in depot_rows:
			var est_id: int = int(d_row.get("establishment_id", 0))
			var shop_dist: String = str(d_row.get("district_id", ""))
			var shop_pos: Vector2 = district_positions.get(shop_dist, Vector2.ZERO)

			var nearby_dists: Array[String] = residential_district_ids.duplicate()
			nearby_dists.sort_custom(func(a: String, b: String) -> bool:
				return shop_pos.distance_squared_to(district_positions.get(a, Vector2.ZERO)) < shop_pos.distance_squared_to(district_positions.get(b, Vector2.ZERO))
			)
			var catchment_dists: Array[String] = nearby_dists.slice(0, mini(3, nearby_dists.size()))
			var catchment_hh: int = 0
			for cd in catchment_dists:
				catchment_hh += int(district_households.get(cd, 0))
			var desired_ops: int = clampi(int(ceil(float(catchment_hh) / res_per_worker)), min_ops, max_ops)

			var assigned_here: int = 0
			for cd in catchment_dists:
				if assigned_here >= desired_ops:
					break
				var pool: Array = residents_by_dist.get(cd, [])
				var i: int = 0
				while i < pool.size() and assigned_here < desired_ops:
					var res_id: int = int(pool[i])
					if not _is_worker_free_for_schedule(worker_window_busy, res_id, deliv_days, deliv_window):
						i += 1
						continue
					pool.remove_at(i)
					_mark_worker_busy_for_schedule(worker_window_busy, res_id, deliv_days, deliv_window)
					assigned_here += 1
					for d_raw in deliv_days:
						var dow: int = int(d_raw)
						route_inserts.append("""
							INSERT INTO service_routes (
								establishment_id, worker_resident_id, service_code, day_of_week,
								time_window, target_district_id, action_mode, is_part_time,
								valid_from, valid_to, change_reason_id
							) VALUES (%d, %d, '%s', %d, '%s', '%s', '%s', 1, %d, NULL, %d);
						""" % [
							est_id, res_id, svc_code, dow, deliv_window,
							cd.replace("'", "''"), deliv_action, sim_start_day, reason_id
						])
						added += 1
						_bump_load(district_day_load, service_district_day_load, worker_day_assigned, cd, svc_code, dow, res_id, 1.0)
	return added

## Seeds un-premised sole-proprietor & secondary rounds (Avon, Catalogue, Pools + Concessionaires, Street Vice)
static func _seed_unpremised_sole_routes(
	route_inserts: Array[String],
	rounds_def: Dictionary,
	district_ids: Array[String],
	district_populations: Dictionary,
	district_households: Dictionary,
	worker_window_busy: Dictionary,
	district_day_load: Dictionary,
	service_district_day_load: Dictionary,
	worker_day_assigned: Dictionary,
	sim_start_day: int,
	reason_id: int
) -> int:
	var unpremised_rounds: Array[Dictionary] = []
	for svc_key in rounds_def.keys():
		var r_cfg = rounds_def[svc_key]
		if not (r_cfg is Dictionary):
			continue
		var depots: Array = r_cfg.get("depot_building_classes", [])
		var elig: Dictionary = r_cfg.get("operator_eligibility", {})
		var fulf: Dictionary = r_cfg.get("fulfillment_config", {})
		if depots.is_empty() and (not elig.is_empty() or not fulf.is_empty()):
			unpremised_rounds.append(r_cfg)

	if unpremised_rounds.is_empty() or district_ids.is_empty():
		return 0

	var added: int = 0
	var total_city_pop: int = 0
	for d_id in district_ids:
		total_city_pop += int(district_populations.get(d_id, 250))

	for r_cfg in unpremised_rounds:
		var svc_code: String = str(r_cfg.get("service_code", "")).strip_edges()
		var elig: Dictionary = r_cfg.get("operator_eligibility", {})
		assert(not elig.is_empty(), "FATAL: [RouteRoundSeeder] Un-premised round '%s' missing 'operator_eligibility' config!" % svc_code)

		var residents_by_dist: Dictionary = _query_eligible_residents_by_district(elig, sim_start_day)
		if residents_by_dist.is_empty():
			continue

		var deliv_cfg: Dictionary = r_cfg.get("delivery_schedule", {})
		var deliv_days: Array = deliv_cfg.get("days_of_week", [5, 6])
		var deliv_window: String = str(deliv_cfg.get("time_window", "EVENING"))
		var deliv_action: String = str(deliv_cfg.get("action_mode", "SOLE_ROUTE"))

		var max_ops: int = maxi(1, int(elig.get("max_operators_per_district", 3)))
		var res_per_worker: float = float(r_cfg.get("residencies_per_worker", 0.0))
		var cap_per_worker: float = maxf(100.0, float(r_cfg.get("demand_capacity_per_worker", 400.0)))
		var cov_scopes: Dictionary = r_cfg.get("coverage_scopes", {})

		# 1. District-level un-premised coverage
		for d_id in district_ids:
			var pool: Array = residents_by_dist.get(d_id, [])
			if pool.is_empty():
				continue
			var desired_operators: int = 0
			if not cov_scopes.is_empty():
				desired_operators = int(cov_scopes.get("per_district", 1))
			elif res_per_worker > 0.0:
				var hh_cnt: float = float(district_households.get(d_id, 0))
				desired_operators = mini(max_ops, int(ceil(hh_cnt / res_per_worker))) if hh_cnt > 0.0 else 0
			else:
				var pop: float = float(district_populations.get(d_id, 250))
				desired_operators = mini(max_ops, int(floor(pop / cap_per_worker)))

			if desired_operators <= 0:
				continue

			var picked: int = 0
			var idx: int = 0
			while idx < pool.size() and picked < desired_operators:
				var res_id: int = int(pool[idx])
				if not _is_worker_free_for_schedule(worker_window_busy, res_id, deliv_days, deliv_window):
					idx += 1
					continue
				pool.remove_at(idx)
				_mark_worker_busy_for_schedule(worker_window_busy, res_id, deliv_days, deliv_window)
				picked += 1
				for d_raw in deliv_days:
					var dow: int = int(d_raw)
					route_inserts.append("""
						INSERT INTO service_routes (
							establishment_id, worker_resident_id, service_code, day_of_week,
							time_window, target_district_id, action_mode, is_part_time,
							valid_from, valid_to, change_reason_id
						) VALUES (NULL, %d, '%s', %d, '%s', '%s', '%s', 1, %d, NULL, %d);
					""" % [
						res_id, svc_code, dow, deliv_window,
						d_id.replace("'", "''"), deliv_action, sim_start_day, reason_id
					])
					added += 1
					_bump_load(district_day_load, service_district_day_load, worker_day_assigned, d_id, svc_code, dow, res_id, 1.0)

		# 2. Optional pub / workplace pools reps + home-based town-level Concessionaire (no route)
		if int(cov_scopes.get("per_pub", 0)) > 0:
			var pub_rows: Array = DB_MANAGER.query_rows("""
				SELECT e.establishment_id, e.district_id
				FROM establishments e
				JOIN system_labels l_cat ON e.category_id = l_cat.label_id
				WHERE e.valid_to IS NULL AND l_cat.code = 'LOCAL_PUB'
				ORDER BY e.establishment_id ASC;
			""")
			for pr in pub_rows:
				var pub_id: int = int(pr.get("establishment_id", 0))
				var p_dist: String = str(pr.get("district_id", ""))
				var p_pool: Array = residents_by_dist.get(p_dist, [])
				for pi in range(p_pool.size()):
					var res_id: int = int(p_pool[pi])
					if not _is_worker_free_for_schedule(worker_window_busy, res_id, deliv_days, deliv_window):
						continue
					p_pool.remove_at(pi)
					_mark_worker_busy_for_schedule(worker_window_busy, res_id, deliv_days, deliv_window)
					for d_raw in deliv_days:
						var dow: int = int(d_raw)
						route_inserts.append("""
							INSERT INTO service_routes (
								establishment_id, worker_resident_id, service_code, day_of_week,
								time_window, target_district_id, action_mode, is_part_time,
								valid_from, valid_to, change_reason_id
							) VALUES (%d, %d, '%s', %d, '%s', '%s', '%s', 1, %d, NULL, %d);
						""" % [
							pub_id, res_id, svc_code, dow, deliv_window,
							p_dist.replace("'", "''"), deliv_action, sim_start_day, reason_id
						])
						added += 1
					break

		var conc_cfg: Dictionary = r_cfg.get("town_tier_concessionaire", {})
		var brand_orgs: Array = r_cfg.get("brand_org_ids", [])
		if not conc_cfg.is_empty() and not brand_orgs.is_empty():
			var conc_role: String = str(conc_cfg.get("role_code", "POOLS_CONCESSIONAIRE")).replace("'", "''")
			var pop_per_op: float = maxf(1000.0, float(conc_cfg.get("population_per_operator", 50000.0)))
			var desired_conc: int = maxi(1, int(round(float(total_city_pop) / pop_per_op)))
			var conc_inserts: Array[String] = []
			for b_org in brand_orgs:
				var org_id_str: String = str(b_org).strip_edges().replace("'", "''")
				if org_id_str.is_empty():
					continue
				var assigned_c: int = 0
				for d_id in district_ids:
					if assigned_c >= desired_conc:
						break
					var c_pool: Array = residents_by_dist.get(d_id, [])
					if not c_pool.is_empty():
						var conc_res_id: int = int(c_pool.pop_front())
						conc_inserts.append("""
							INSERT OR IGNORE INTO organization_members (
								org_id, resident_id, role_code, authority_mask, valid_from, valid_to, change_reason_id
							) VALUES ('%s', %d, '%s', 1, %d, NULL, %d);
						""" % [org_id_str, conc_res_id, conc_role, sim_start_day, reason_id])
						assigned_c += 1
			if not conc_inserts.is_empty():
				DB_MANAGER.execute_batch(conc_inserts)

	return added

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