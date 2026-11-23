# res://systems/society/dunbar_graph_weaver.gd
class_name DunbarGraphWeaver
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const SOCIAL_QUERY_HELPER = preload("res://systems/society/social_group_query_helper.gd")

const TUPLES_PER_INSERT: int = 200
const INSERT_PREFIX: String = "INSERT OR IGNORE INTO social_relationships (from_resident_id, to_resident_id, relationship_type_id, context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id) VALUES "

## Pass 4: Weaves venue-based Dunbar social relationships across SQLite using config-driven rules
static func run(_physical_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var t0: int = Time.get_ticks_msec()
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	var ocean_rules: Dictionary = MANIFEST_MANAGER.load_module("ocean_personality")
	assert(ocean_rules.has("dunbar_venue_weaving"), "FATAL: [DunbarGraphWeaver] Missing 'dunbar_venue_weaving' in ocean_personality_rules.json.")
	var weaving_cfg: Dictionary = ocean_rules["dunbar_venue_weaving"]

	var gen_cfg: Dictionary = DB_MANAGER.get_city_generation_config()
	var sql_flush_budget: int = maxi(TUPLES_PER_INSERT, int(gen_cfg.get("sql_flush_batch_size", 1000)))
	var max_stmts_per_flush: int = maxi(1, int(ceil(float(sql_flush_budget) / float(TUPLES_PER_INSERT))))

	SystemLogger.log_info("  [Pass 4] Weaving venue-based Dunbar social networks (Pubs, Workplaces, Churches)...")

	var pub_edges: int = _weave_venue_cohort_edges(
		SOCIAL_QUERY_HELPER.query_residents_by_pub(),
		_require_venue_rule(weaving_cfg, "pub"),
		sim_start_day,
		reason_world_gen_id,
		max_stmts_per_flush,
		rng
	)
	var work_edges: int = _weave_venue_cohort_edges(
		SOCIAL_QUERY_HELPER.query_residents_by_workplace(),
		_require_venue_rule(weaving_cfg, "workplace"),
		sim_start_day,
		reason_world_gen_id,
		max_stmts_per_flush,
		rng
	)
	var church_edges: int = _weave_venue_cohort_edges(
		SOCIAL_QUERY_HELPER.query_residents_by_church(),
		_require_venue_rule(weaving_cfg, "church"),
		sim_start_day,
		reason_world_gen_id,
		max_stmts_per_flush,
		rng
	)

	var elapsed: int = Time.get_ticks_msec() - t0
	SystemLogger.log_info("  ✓ Pass 4 Completed in %dms | Dunbar edges: %d pub, %d workplace, %d church." % [
		elapsed, pub_edges, work_edges, church_edges
	])

static func _require_venue_rule(weaving_cfg: Dictionary, venue_key: String) -> Dictionary:
	assert(weaving_cfg.has(venue_key) and weaving_cfg[venue_key] is Dictionary,
		"FATAL: [DunbarGraphWeaver] Missing 'dunbar_venue_weaving.%s' in ocean_personality_rules.json." % venue_key)
	var rule: Dictionary = weaving_cfg[venue_key]
	for req_key in ["relationship_type", "affinity_score", "link_probability", "pairs_per_member", "max_pairs_per_venue", "reciprocal"]:
		assert(rule.has(req_key), "FATAL: [DunbarGraphWeaver] Missing '%s' in dunbar_venue_weaving.%s." % [req_key, venue_key])
	return rule

static func _weave_venue_cohort_edges(
	ordered_rows: Array,
	rule: Dictionary,
	sim_start_day: int,
	reason_id: int,
	max_stmts_per_flush: int,
	rng: RandomNumberGenerator
) -> int:
	if ordered_rows.is_empty():
		return 0

	var rel_type_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", str(rule["relationship_type"]))
	var affinity: float = float(rule["affinity_score"])
	var link_prob: float = float(rule["link_probability"])
	var pairs_per_member: float = float(rule["pairs_per_member"])
	var max_pairs_per_venue: int = maxi(1, int(rule["max_pairs_per_venue"]))
	var reciprocal: bool = bool(rule["reciprocal"])

	var value_tuples: PackedStringArray = PackedStringArray()
	var pending_sql: Array[String] = []
	var members: PackedInt64Array = PackedInt64Array()
	var current_group_id: int = -1
	var edge_count: int = 0

	for row in ordered_rows:
		var gid: int = int(row["group_id"])
		if gid != current_group_id:
			if members.size() >= 2:
				edge_count += _emit_venue_pairs(
					current_group_id, members, rel_type_id, affinity, link_prob,
					pairs_per_member, max_pairs_per_venue, reciprocal,
					sim_start_day, reason_id, value_tuples, pending_sql, max_stmts_per_flush, rng
				)
			members.clear()
			current_group_id = gid
		members.append(int(row["resident_id"]))

	if members.size() >= 2:
		edge_count += _emit_venue_pairs(
			current_group_id, members, rel_type_id, affinity, link_prob,
			pairs_per_member, max_pairs_per_venue, reciprocal,
			sim_start_day, reason_id, value_tuples, pending_sql, max_stmts_per_flush, rng
		)

	if not value_tuples.is_empty():
		pending_sql.append(INSERT_PREFIX + ", ".join(value_tuples) + ";")
		value_tuples.clear()

	if not pending_sql.is_empty():
		DB_MANAGER.execute_batch(pending_sql)
		pending_sql.clear()

	return edge_count

static func _emit_venue_pairs(
	group_id: int,
	members: PackedInt64Array,
	rel_type_id: int,
	affinity: float,
	link_prob: float,
	pairs_per_member: float,
	max_pairs_per_venue: int,
	reciprocal: bool,
	sim_start_day: int,
	reason_id: int,
	value_tuples: PackedStringArray,
	pending_sql: Array[String],
	max_stmts_per_flush: int,
	rng: RandomNumberGenerator
) -> int:
	var count: int = members.size()
	var target_pairs: int = clampi(int(round(float(count) * pairs_per_member)), 1, max_pairs_per_venue)
	var emitted: int = 0

	for _p in range(target_pairs):
		if link_prob < 1.0 and rng.randf() >= link_prob:
			continue
		var idx_a: int = rng.randi() % count
		var idx_b: int = rng.randi() % count
		if idx_a == idx_b:
			idx_b = (idx_b + 1) % count
		var a: int = members[idx_a]
		var b: int = members[idx_b]
		if a == b:
			continue

		value_tuples.append("(%d,%d,%d,%d,%.2f,%d,NULL,%d)" % [a, b, rel_type_id, group_id, affinity, sim_start_day, reason_id])
		emitted += 1
		if reciprocal:
			value_tuples.append("(%d,%d,%d,%d,%.2f,%d,NULL,%d)" % [b, a, rel_type_id, group_id, affinity, sim_start_day, reason_id])
			emitted += 1

		if value_tuples.size() >= TUPLES_PER_INSERT:
			pending_sql.append(INSERT_PREFIX + ", ".join(value_tuples) + ";")
			value_tuples.clear()
			if pending_sql.size() >= max_stmts_per_flush:
				DB_MANAGER.execute_batch(pending_sql)
				pending_sql.clear()

	return emitted