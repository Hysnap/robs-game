# res://systems/society/dunbar_graph_weaver.gd
class_name DunbarGraphWeaver
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")
const QUERY_HELPER = preload("res://systems/society/social_group_query_helper.gd")

const REQUIRED_RULE_KEYS: Array[String] = [
	"relationship_type",
	"affinity_score",
	"link_probability",
	"pairs_per_member",
	"max_pairs_per_venue",
	"reciprocal"
]

## Pass 4: Weaves venue-based Dunbar social relationships across SQLite
## Driven strictly by per-class 'dunbar_weaving' (and 'default_dunbar_weaving') in building_classes.json
static func run(_physical_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	var building_classes: Dictionary = MANIFEST_MGR.load_module("building_classes")
	assert(not building_classes.is_empty(), "FATAL: [DunbarGraphWeaver] Missing 'building_classes' module.")
	assert(building_classes.has("default_dunbar_weaving") and building_classes["default_dunbar_weaving"] is Dictionary,
		"FATAL: [DunbarGraphWeaver] Missing 'default_dunbar_weaving' in building_classes.json.")

	var default_rule: Dictionary = building_classes["default_dunbar_weaving"]
	_validate_weaving_rule("default_dunbar_weaving", default_rule)

	var category_rules: Dictionary = _build_category_rule_map(building_classes, default_rule)
	var flush_batch_size: int = _get_sql_flush_batch_size()
	var rel_id_cache: Dictionary = {}

	var pub_edges: int = _weave_category_grouped_cohorts(
		QUERY_HELPER.query_residents_by_pub(),
		category_rules,
		default_rule,
		rel_id_cache,
		rng,
		sim_start_day,
		reason_id,
		flush_batch_size
	)
	var work_edges: int = _weave_category_grouped_cohorts(
		QUERY_HELPER.query_residents_by_workplace(),
		category_rules,
		default_rule,
		rel_id_cache,
		rng,
		sim_start_day,
		reason_id,
		flush_batch_size
	)
	var church_edges: int = _weave_category_grouped_cohorts(
		QUERY_HELPER.query_residents_by_church(),
		category_rules,
		default_rule,
		rel_id_cache,
		rng,
		sim_start_day,
		reason_id,
		flush_batch_size
	)

	var total_edges: int = pub_edges + work_edges + church_edges
	SystemLogger.log_info("    - Woven %d venue & social relationships (Pub/Club: %d, Work: %d, Parish: %d)." % [
		total_edges, pub_edges, work_edges, church_edges
	])

## Builds flat lookup: category_code -> validated dunbar_weaving rule
static func _build_category_rule_map(building_classes: Dictionary, default_rule: Dictionary) -> Dictionary:
	var rules: Dictionary = {}
	for section_key in ["commercial_tenants", "industrial_tenants", "civic_tenants"]:
		var section = building_classes.get(section_key, {})
		if not (section is Dictionary):
			continue
		for cat_code_raw in section.keys():
			var cat_code: String = str(cat_code_raw).strip_edges().to_upper()
			var class_def = section[cat_code_raw]
			if not (class_def is Dictionary):
				continue
			if class_def.has("dunbar_weaving") and class_def["dunbar_weaving"] is Dictionary:
				var custom_rule: Dictionary = class_def["dunbar_weaving"]
				_validate_weaving_rule(cat_code, custom_rule)
				rules[cat_code] = custom_rule
			else:
				rules[cat_code] = default_rule

	for top_key_raw in building_classes.keys():
		var top_key: String = str(top_key_raw).strip_edges().to_upper()
		if top_key in ["_META", "DEFAULT_FOOTPRINT_SQM", "DEFAULT_DUNBAR_WEAVING", "COMMERCIAL_TENANTS", "INDUSTRIAL_TENANTS", "CIVIC_TENANTS"]:
			continue
		var top_val = building_classes[top_key_raw]
		if top_val is Dictionary and not rules.has(top_key):
			if top_val.has("dunbar_weaving") and top_val["dunbar_weaving"] is Dictionary:
				_validate_weaving_rule(top_key, top_val["dunbar_weaving"])
				rules[top_key] = top_val["dunbar_weaving"]
			else:
				rules[top_key] = default_rule

	return rules

static func _validate_weaving_rule(context_name: String, rule: Dictionary) -> void:
	for req_key in REQUIRED_RULE_KEYS:
		assert(rule.has(req_key), "FATAL: [DunbarGraphWeaver] Missing '%s' in dunbar_weaving rule for '%s'." % [req_key, context_name])

static func _get_sql_flush_batch_size() -> int:
	var cfg := ConfigFile.new()
	if cfg.load("res://data_modules/core/business_rules.cfg") == OK:
		return maxi(50, int(cfg.get_value("generation", "sql_flush_batch_size", 1000)))
	return 1000

## Streams ordered (category_code, group_id, resident_id) rows using a single reusable PackedInt64Array
## and flushes multi-row INSERT OR IGNORE statements in bounded batches.
static func _weave_category_grouped_cohorts(
	ordered_rows: Array,
	category_rules: Dictionary,
	default_rule: Dictionary,
	rel_id_cache: Dictionary,
	rng: RandomNumberGenerator,
	sim_start_day: int,
	reason_id: int,
	flush_batch_size: int
) -> int:
	if ordered_rows.is_empty():
		return 0

	var value_tuples: PackedStringArray = PackedStringArray()
	var sql_statements: Array[String] = []
	var edges_created: int = 0

	var member_ids: PackedInt64Array = PackedInt64Array()
	var current_group_id: int = -1
	var current_cat_code: String = ""

	for row in ordered_rows:
		var gid: int = int(row["group_id"])
		var rid: int = int(row["resident_id"])
		var cat_code: String = str(row["category_code"]).strip_edges().to_upper()

		if gid != current_group_id:
			if member_ids.size() >= 2:
				var rule: Dictionary = category_rules.get(current_cat_code, default_rule)
				edges_created += _emit_group_edges(
					current_group_id, member_ids, rule, rel_id_cache,
					rng, sim_start_day, reason_id, value_tuples, sql_statements, flush_batch_size
				)
			member_ids.resize(0)
			current_group_id = gid
			current_cat_code = cat_code

		member_ids.append(rid)

	if member_ids.size() >= 2:
		var last_rule: Dictionary = category_rules.get(current_cat_code, default_rule)
		edges_created += _emit_group_edges(
			current_group_id, member_ids, last_rule, rel_id_cache,
			rng, sim_start_day, reason_id, value_tuples, sql_statements, flush_batch_size
		)

	_flush_tuples_to_statement(value_tuples, sql_statements)
	if not sql_statements.is_empty():
		DB_MANAGER.execute_batch(sql_statements)
		sql_statements.clear()

	return edges_created

static func _emit_group_edges(
	est_id: int,
	member_ids: PackedInt64Array,
	rule: Dictionary,
	rel_id_cache: Dictionary,
	rng: RandomNumberGenerator,
	sim_start_day: int,
	reason_id: int,
	value_tuples: PackedStringArray,
	sql_statements: Array[String],
	flush_batch_size: int
) -> int:
	var count: int = member_ids.size()
	if count < 2:
		return 0

	var rel_type_code: String = str(rule["relationship_type"])
	var rel_type_id: int = 0
	if rel_id_cache.has(rel_type_code):
		rel_type_id = int(rel_id_cache[rel_type_code])
	else:
		rel_type_id = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", rel_type_code)
		rel_id_cache[rel_type_code] = rel_type_id

	var affinity: float = float(rule["affinity_score"])
	var link_probability: float = float(rule["link_probability"])
	var pairs_per_member: float = float(rule["pairs_per_member"])
	var max_pairs: int = int(rule["max_pairs_per_venue"])
	var reciprocal: bool = bool(rule["reciprocal"])

	var target_pairs: int = clampi(int(round(float(count) * pairs_per_member)), 1, max_pairs)
	var added: int = 0

	for _s in range(target_pairs):
		if link_probability < 1.0 and rng.randf() > link_probability:
			continue

		var idx_a: int = rng.randi() % count
		var idx_b: int = rng.randi() % count
		if idx_a == idx_b:
			continue

		var a: int = member_ids[idx_a]
		var b: int = member_ids[idx_b]

		value_tuples.append("(%d, %d, %d, %d, %.2f, %d, NULL, %d)" % [
			a, b, rel_type_id, est_id, affinity, sim_start_day, reason_id
		])
		added += 1

		if reciprocal:
			value_tuples.append("(%d, %d, %d, %d, %.2f, %d, NULL, %d)" % [
				b, a, rel_type_id, est_id, affinity, sim_start_day, reason_id
			])
			added += 1

		if value_tuples.size() >= 250:
			_flush_tuples_to_statement(value_tuples, sql_statements)
			if sql_statements.size() >= flush_batch_size:
				DB_MANAGER.execute_batch(sql_statements)
				sql_statements.clear()

	return added

static func _flush_tuples_to_statement(value_tuples: PackedStringArray, sql_statements: Array[String]) -> void:
	if value_tuples.is_empty():
		return
	sql_statements.append(
		"INSERT OR IGNORE INTO social_relationships (from_resident_id, to_resident_id, relationship_type_id, context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id) VALUES "
		+ ", ".join(value_tuples)
		+ ";"
	)
	value_tuples.resize(0)