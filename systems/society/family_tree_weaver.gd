# res://systems/society/family_tree_weaver.gd
class_name FamilyTreeWeaver
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SPATIAL_RADIUS_INDEX = preload("res://systems/society/spatial_radius_index.gd")
const BUSINESS_RULES_PATH := "res://data_modules/core/business_rules.cfg"
const SQL_BATCH_FLUSH_LIMIT := 1000
const TUPLES_PER_INSERT := 200
const EXTENDED_FLUSH_STMTS := 10
const PROGRESS_YIELD_INTERVAL_MS := 40
const LOG_HEARTBEAT_INTERVAL := 10000
const INSERT_PREFIX := "INSERT OR IGNORE INTO social_relationships (from_resident_id, to_resident_id, relationship_type_id, context_establishment_id, affinity_score, valid_from, change_reason_id) VALUES "

## Loads [spatial_influence] horizon settings from business_rules.cfg
static func get_spatial_influence_config() -> Dictionary:
	assert(FileAccess.file_exists(BUSINESS_RULES_PATH), "FATAL: [FamilyTreeWeaver] Missing business_rules.cfg at %s." % BUSINESS_RULES_PATH)
	var cfg := ConfigFile.new()
	var err := cfg.load(BUSINESS_RULES_PATH)
	assert(err == OK, "FATAL: [FamilyTreeWeaver] Failed to parse business_rules.cfg (err=%d)." % err)
	assert(cfg.has_section("spatial_influence"), "FATAL: [FamilyTreeWeaver] Missing [spatial_influence] section in business_rules.cfg.")

	var radius_mode: String = str(cfg.get_value("spatial_influence", "radius_mode", "DISTANCE_METERS")).to_upper().strip_edges()
	var radius_m: float = float(cfg.get_value("spatial_influence", "kinship_clan_radius_m", 1500.0))
	assert(radius_m > 0.0, "FATAL: [FamilyTreeWeaver] kinship_clan_radius_m must be > 0.0.")

	return {
		"radius_mode": radius_mode,
		"kinship_clan_radius_m": radius_m
	}

## Extracts and validates the kinship_weaving_rules block from demographics_cfg
static func get_kinship_rules(demographics_cfg: Dictionary) -> Dictionary:
	assert(demographics_cfg.has("fertility_and_family_model"), "FATAL: demographics_cfg missing 'fertility_and_family_model'!")
	var fam_model: Dictionary = demographics_cfg["fertility_and_family_model"]
	assert(fam_model.has("kinship_weaving_rules"), "FATAL: fertility_and_family_model missing 'kinship_weaving_rules'!")
	var rules: Dictionary = fam_model["kinship_weaving_rules"]
	assert(rules.has("bonds") and rules["bonds"] is Dictionary, "FATAL: kinship_weaving_rules missing 'bonds' dictionary!")
	return rules

## Resolves the directional RELATIONSHIP_TYPE label_id and affinity from kinship_weaving_rules.bonds
static func _append_bond_pair_sql(
	sql_out: Array[String],
	bonds_cfg: Dictionary,
	bond_key_a_to_b: String,
	bond_key_b_to_a: String,
	res_a: Dictionary,
	res_b: Dictionary,
	context_estab_id: int,
	valid_from: int,
	reason_id: int
) -> int:
	var id_a: int = int(res_a["resident_id"])
	var id_b: int = int(res_b["resident_id"])
	if id_a == id_b or id_a <= 0 or id_b <= 0:
		return 0

	assert(bonds_cfg.has(bond_key_a_to_b), "FATAL: kinship_weaving_rules.bonds missing '%s'!" % bond_key_a_to_b)
	assert(bonds_cfg.has(bond_key_b_to_a), "FATAL: kinship_weaving_rules.bonds missing '%s'!" % bond_key_b_to_a)

	var def_a_to_b: Dictionary = bonds_cfg[bond_key_a_to_b]
	var def_b_to_a: Dictionary = bonds_cfg[bond_key_b_to_a]

	var gender_a: String = str(res_a["gender_code"]).to_upper()
	var gender_b: String = str(res_b["gender_code"]).to_upper()

	assert(def_a_to_b.has(gender_a), "FATAL: Bond '%s' missing gender key '%s'!" % [bond_key_a_to_b, gender_a])
	assert(def_b_to_a.has(gender_b), "FATAL: Bond '%s' missing gender key '%s'!" % [bond_key_b_to_a, gender_b])

	var rel_id_a_to_b: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", str(def_a_to_b[gender_a]))
	var rel_id_b_to_a: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", str(def_b_to_a[gender_b]))

	var aff_a_to_b: float = float(def_a_to_b["affinity"])
	var aff_b_to_a: float = float(def_b_to_a["affinity"])

	append_directed_edge_sql(sql_out, id_a, id_b, rel_id_a_to_b, context_estab_id, aff_a_to_b, valid_from, reason_id)
	append_directed_edge_sql(sql_out, id_b, id_a, rel_id_b_to_a, context_estab_id, aff_b_to_a, valid_from, reason_id)
	return 2

## Pre-resolves all kinship_weaving_rules.bonds label IDs and affinity strings once per pass
static func _build_bond_cache(bonds_cfg: Dictionary) -> Dictionary:
	var cache: Dictionary = {}
	for bond_key in bonds_cfg.keys():
		var def: Dictionary = bonds_cfg[bond_key]
		assert(def.has("affinity"), "FATAL: Bond '%s' missing 'affinity'!" % str(bond_key))
		var entry: Dictionary = {
			"affinity_str": "%.2f" % float(def["affinity"])
		}
		for k in def.keys():
			if str(k) == "affinity":
				continue
			entry[str(k).to_upper()] = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", str(def[k]))
		cache[str(bond_key)] = entry
	return cache

static var _valid_resident_ids_cache: Dictionary = {}

static func _refresh_valid_resident_ids_cache() -> void:
	_valid_resident_ids_cache.clear()
	if not DB_MANAGER.is_database_open():
		return
	var rows: Array = DB_MANAGER.query_rows("SELECT resident_id FROM residents;")
	for r in rows:
		var rid: int = int(r.get("resident_id", 0))
		if rid > 0:
			_valid_resident_ids_cache[rid] = true

## Multi-row tuple packer for high-volume extended kinship weaving using pre-resolved bond_cache
static func _append_bond_pair_tuples(
	tuples_out: PackedStringArray,
	sql_out: Array[String],
	bond_cache: Dictionary,
	bond_key_a_to_b: String,
	bond_key_b_to_a: String,
	res_a: Dictionary,
	res_b: Dictionary,
	context_estab_id: int,
	valid_from: int,
	reason_id: int
) -> int:
	var id_a: int = int(res_a["resident_id"])
	var id_b: int = int(res_b["resident_id"])
	if id_a == id_b or id_a <= 0 or id_b <= 0:
		return 0
	if not _valid_resident_ids_cache.is_empty():
		if not _valid_resident_ids_cache.has(id_a) or not _valid_resident_ids_cache.has(id_b):
			return 0

	var def_a_to_b: Dictionary = bond_cache[bond_key_a_to_b]
	var def_b_to_a: Dictionary = bond_cache[bond_key_b_to_a]

	var rel_id_a_to_b: int = int(def_a_to_b[res_a["gender_code"]])
	var rel_id_b_to_a: int = int(def_b_to_a[res_b["gender_code"]])
	var ctx_str: String = "NULL" if context_estab_id <= 0 else str(context_estab_id)

	tuples_out.append("(%d,%d,%d,%s,%s,%d,%d)" % [id_a, id_b, rel_id_a_to_b, ctx_str, def_a_to_b["affinity_str"], valid_from, reason_id])
	tuples_out.append("(%d,%d,%d,%s,%s,%d,%d)" % [id_b, id_a, rel_id_b_to_a, ctx_str, def_b_to_a["affinity_str"], valid_from, reason_id])

	if tuples_out.size() >= TUPLES_PER_INSERT:
		sql_out.append(INSERT_PREFIX + ", ".join(tuples_out) + ";")
		tuples_out.clear()
		if sql_out.size() >= EXTENDED_FLUSH_STMTS:
			DB_MANAGER.execute_batch(sql_out)
			sql_out.clear()

	return 2

static func _flush_tuples_and_sql(tuples_out: PackedStringArray, sql_out: Array[String]) -> void:
	if not tuples_out.is_empty():
		sql_out.append(INSERT_PREFIX + ", ".join(tuples_out) + ";")
		tuples_out.clear()
	if not sql_out.is_empty():
		DB_MANAGER.execute_batch(sql_out)
		sql_out.clear()

## Appends a single directed relationship SQL statement into sql_out
static func append_directed_edge_sql(
	sql_out: Array[String],
	from_id: int,
	to_id: int,
	rel_type_id: int,
	context_estab_id: int,
	affinity: float,
	valid_from: int,
	reason_id: int
) -> void:
	if from_id == to_id or from_id <= 0 or to_id <= 0:
		return
	var ctx_str: String = "NULL" if context_estab_id <= 0 else str(context_estab_id)
	sql_out.append("INSERT OR IGNORE INTO social_relationships (from_resident_id, to_resident_id, relationship_type_id, context_establishment_id, affinity_score, valid_from, change_reason_id) VALUES (%d, %d, %d, %s, %.2f, %d, %d);" % [
		from_id, to_id, rel_type_id, ctx_str, affinity, valid_from, reason_id
	])

static func _maybe_yield_progress(
	on_progress: Callable,
	last_yield_ms: int,
	pct: float,
	msg: String,
	is_headless: bool
) -> int:
	var now_ms: int = Time.get_ticks_msec()
	if (now_ms - last_yield_ms) < PROGRESS_YIELD_INTERVAL_MS:
		return last_yield_ms
	if on_progress.is_valid():
		on_progress.call(pct, 100.0, msg)
	if not is_headless:
		var main_loop = Engine.get_main_loop()
		if main_loop is SceneTree:
			await (main_loop as SceneTree).process_frame
	return Time.get_ticks_msec()

## Weaves intra-household directional nuclear edges (Spouses, Parents/Children, Siblings, or Flatmates)
static func weave_intra_household_edges(
	sql_out: Array[String],
	members: Array[Dictionary],
	is_married_couple: bool,
	home_estab_id: int,
	kinship_rules: Dictionary,
	reason_id: int,
	out_kin_graph: Dictionary
) -> void:
	var bonds_cfg: Dictionary = kinship_rules["bonds"]
	var parents: Array[Dictionary] = []
	var children: Array[Dictionary] = []
	var peers: Array[Dictionary] = []

	for m in members:
		var role: String = str(m["household_role"])
		if role == "HEAD" or role == "SPOUSE":
			parents.append(m)
		elif role == "CHILD":
			children.append(m)
		else:
			peers.append(m)

	# 1. Spousal / Partner Bond
	if parents.size() >= 2:
		var p1: Dictionary = parents[0]
		var p2: Dictionary = parents[1]
		var bond_start: int = maxi(int(p1["dob"]), int(p2["dob"]))
		var couple_bond_key: String = "MARRIED_SPOUSE" if is_married_couple else "UNMARRIED_COUPLE"
		_append_bond_pair_sql(sql_out, bonds_cfg, couple_bond_key, couple_bond_key, p1, p2, home_estab_id, bond_start, reason_id)

	# 2. Parent <-> Child Directional Edges
	for p in parents:
		var p_id: int = int(p["resident_id"])
		for c in children:
			var c_id: int = int(c["resident_id"])
			var c_dob: int = int(c["dob"])
			_append_bond_pair_sql(sql_out, bonds_cfg, "PARENT_TO_CHILD", "CHILD_TO_PARENT", p, c, home_estab_id, c_dob, reason_id)
			_register_parent_child_in_graph(out_kin_graph, p_id, c_id)

	# 3. Intra-Household Sibling <-> Sibling Directional Edges
	for i in range(children.size()):
		var c1: Dictionary = children[i]
		var id1: int = int(c1["resident_id"])
		for j in range(i + 1, children.size()):
			var c2: Dictionary = children[j]
			var id2: int = int(c2["resident_id"])
			var shared_dob: int = maxi(int(c1["dob"]), int(c2["dob"]))
			_append_bond_pair_sql(sql_out, bonds_cfg, "SIBLING", "SIBLING", c1, c2, home_estab_id, shared_dob, reason_id)
			_register_sibling_in_graph(out_kin_graph, id1, id2)

	# 4. Flatshare / Shared Household Peer Edges
	if not peers.is_empty():
		var all_flatmates: Array[Dictionary] = []
		all_flatmates.append_array(parents)
		all_flatmates.append_array(peers)
		for i in range(all_flatmates.size()):
			var f1: Dictionary = all_flatmates[i]
			for j in range(i + 1, all_flatmates.size()):
				var f2: Dictionary = all_flatmates[j]
				var shared_start: int = maxi(int(f1["dob"]), int(f2["dob"]))
				_append_bond_pair_sql(sql_out, bonds_cfg, "HOUSEHOLD_PEER", "HOUSEHOLD_PEER", f1, f2, home_estab_id, shared_start, reason_id)

## Links cross-household extended family trees within a moving spatial radius of influence
static func weave_extended_family_trees(
	sql_out: Array[String],
	residents_by_id: Dictionary,
	kinship_rules: Dictionary,
	reason_id: int,
	inout_kin_graph: Dictionary,
	rng: RandomNumberGenerator,
	on_progress: Callable = Callable()
) -> int:
	var bonds_cfg: Dictionary = kinship_rules["bonds"]
	var bond_cache: Dictionary = _build_bond_cache(bonds_cfg)
	var max_sib_age_diff: int = int(kinship_rules["dispersed_sibling_max_age_diff"])
	var sib_link_prob: float = float(kinship_rules["dispersed_sibling_link_prob"])
	var min_parent_age_diff: int = int(kinship_rules["dispersed_parent_min_age_diff"])
	var max_parent_age_diff: int = int(kinship_rules["dispersed_parent_max_age_diff"])
	var parent_link_prob: float = float(kinship_rules["dispersed_parent_link_prob"])
	var max_dispersed_siblings: int = int(kinship_rules.get("max_dispersed_siblings", 3))
	var max_offspring_per_parent: int = int(kinship_rules.get("max_dispersed_offspring", 4))

	var spatial_cfg: Dictionary = get_spatial_influence_config()
	var clan_radius_m: float = float(spatial_cfg["kinship_clan_radius_m"])
	var spatial_index := SPATIAL_RADIUS_INDEX.new(clan_radius_m)

	_refresh_valid_resident_ids_cache()
	var value_tuples: PackedStringArray = PackedStringArray()
	var total_edges_emitted: int = 0
	var is_headless: bool = (DisplayServer.get_name() == "headless")
	var phase1_t0: int = Time.get_ticks_msec()
	var last_yield_ms: int = phase1_t0

	var candidates: Array[Dictionary] = []
	for res_id in residents_by_id.keys():
		var r: Dictionary = residents_by_id[res_id]
		var role: String = str(r["household_role"])
		if role != "HEAD" and role != "SPOUSE":
			continue
		var b_surname: String = str(r["birth_surname"])
		if b_surname.is_empty():
			continue
		var clan_key: String = "%s:%d" % [b_surname, int(r["ethnicity_id"])]
		r["_ck"] = clan_key
		var pos: Vector2 = r.get("home_pos", Vector2.ZERO) as Vector2
		spatial_index.insert(pos, r, clan_key)
		candidates.append(r)

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["dob"]) < int(b["dob"])
	)

	var total_candidates: int = candidates.size()
	for idx in range(total_candidates):
		var r1: Dictionary = candidates[idx]
		var id1: int = int(r1["resident_id"])
		var hh1: int = int(r1["household_id"])
		var age1: int = int(r1["age_years"])
		var clan_key: String = str(r1["_ck"])
		var pos1: Vector2 = r1.get("home_pos", Vector2.ZERO) as Vector2

		var sibs1_init: Array = _get_graph_list(inout_kin_graph, id1, "siblings")
		var children1_init: Array = _get_graph_list(inout_kin_graph, id1, "children")
		if sibs1_init.size() < max_dispersed_siblings or children1_init.size() < max_offspring_per_parent:
			var nearby: Array = spatial_index.query_radius(pos1, clan_radius_m, clan_key)
			for item in nearby:
				if not (item is Dictionary):
					continue
				var r2: Dictionary = item
				var id2: int = int(r2["resident_id"])
				if id2 <= id1:
					continue
				var hh2: int = int(r2["household_id"])
				if hh1 == hh2:
					continue

				var age2: int = int(r2["age_years"])
				var older: Dictionary = r1 if age1 >= age2 else r2
				var younger: Dictionary = r2 if age1 >= age2 else r1
				var older_id: int = int(older["resident_id"])
				var younger_id: int = int(younger["resident_id"])
				var age_diff: int = int(older["age_years"]) - int(younger["age_years"])
				var linked: bool = false

				if age_diff <= max_sib_age_diff:
					var sibs_o: Array = _get_graph_list(inout_kin_graph, older_id, "siblings")
					if sibs_o.size() < max_dispersed_siblings:
						var sibs_y: Array = _get_graph_list(inout_kin_graph, younger_id, "siblings")
						if sibs_y.size() < max_dispersed_siblings and rng.randf() < sib_link_prob:
							var start_day: int = maxi(int(older["dob"]), int(younger["dob"]))
							total_edges_emitted += _append_bond_pair_tuples(value_tuples, sql_out, bond_cache, "DISPERSED_SIBLING", "DISPERSED_SIBLING", older, younger, -1, start_day, reason_id)
							_register_sibling_in_graph(inout_kin_graph, older_id, younger_id)
							linked = true

				elif age_diff >= min_parent_age_diff and age_diff <= max_parent_age_diff:
					var children_o: Array = _get_graph_list(inout_kin_graph, older_id, "children")
					if children_o.size() < max_offspring_per_parent:
						var parents_y: Array = _get_graph_list(inout_kin_graph, younger_id, "parents")
						if parents_y.is_empty() and rng.randf() < parent_link_prob:
							var c_dob: int = int(younger["dob"])
							total_edges_emitted += _append_bond_pair_tuples(value_tuples, sql_out, bond_cache, "DISPERSED_PARENT", "DISPERSED_CHILD", older, younger, -1, c_dob, reason_id)
							_register_parent_child_in_graph(inout_kin_graph, older_id, younger_id)
							linked = true

				if linked:
					var sibs1_now: Array = _get_graph_list(inout_kin_graph, id1, "siblings")
					var children1_now: Array = _get_graph_list(inout_kin_graph, id1, "children")
					if sibs1_now.size() >= max_dispersed_siblings and children1_now.size() >= max_offspring_per_parent:
						break

		if (idx + 1) % LOG_HEARTBEAT_INTERVAL == 0:
			SystemLogger.log_info("  [Pass 3B.3a] Dispersed Clans: %d/%d | Edges: %d | Elapsed: %dms" % [
				idx + 1, total_candidates, total_edges_emitted, Time.get_ticks_msec() - phase1_t0
			])

		var pct: float = 76.0 + ((float(idx + 1) / float(maxi(1, total_candidates))) * 5.0)
		last_yield_ms = await _maybe_yield_progress(
			on_progress,
			last_yield_ms,
			pct,
			"Weaving Extended Clans (%.0fm radius): %d/%d (%d links)" % [clan_radius_m, idx + 1, total_candidates, total_edges_emitted],
			is_headless
		)

	spatial_index.clear()
	candidates.clear()
	_flush_tuples_and_sql(value_tuples, sql_out)

	# 3. Derive 2nd-Degree Extended Kinship (Grandparents, Uncles/Aunts, Cousins) from the 1st-degree graph
	total_edges_emitted += await _derive_second_degree_kinship_edges(
		value_tuples, sql_out, residents_by_id, bond_cache, reason_id, inout_kin_graph, on_progress, last_yield_ms
	)
	_flush_tuples_and_sql(value_tuples, sql_out)
	return total_edges_emitted

## Derives Grandparent/Grandchild, Uncle/Aunt/Nephew/Niece, and Cousin edges in memory-bounded batches
static func _derive_second_degree_kinship_edges(
	value_tuples: PackedStringArray,
	sql_out: Array[String],
	residents_by_id: Dictionary,
	bond_cache: Dictionary,
	reason_id: int,
	kin_graph: Dictionary,
	on_progress: Callable = Callable(),
	last_yield_ms: int = 0
) -> int:
	var emitted: int = 0
	var graph_keys: Array = kin_graph.keys()
	var total_nodes: int = graph_keys.size()
	var is_headless: bool = (DisplayServer.get_name() == "headless")
	var phase2_t0: int = Time.get_ticks_msec()
	var yield_ms: int = last_yield_ms if last_yield_ms > 0 else phase2_t0

	for idx in range(total_nodes):
		var res_id = graph_keys[idx]
		if residents_by_id.has(res_id):
			var res_dict: Dictionary = residents_by_id[res_id]
			var res_dob: int = int(res_dict["dob"])
			var parents: Array = _get_graph_list(kin_graph, res_id, "parents")

			for p_id in parents:
				# A. Grandparents (Parents of my Parents)
				var grandparents: Array = _get_graph_list(kin_graph, p_id, "parents")
				for gp_id in grandparents:
					if not residents_by_id.has(gp_id):
						continue
					var gp_dict: Dictionary = residents_by_id[gp_id]
					emitted += _append_bond_pair_tuples(value_tuples, sql_out, bond_cache, "GRANDPARENT", "GRANDCHILD", gp_dict, res_dict, -1, res_dob, reason_id)

				# B. Uncles / Aunts (Siblings of my Parents) & Cousins (Children of my Parents' Siblings)
				var parent_siblings: Array = _get_graph_list(kin_graph, p_id, "siblings")
				for ps_id in parent_siblings:
					if not residents_by_id.has(ps_id):
						continue
					var ps_dict: Dictionary = residents_by_id[ps_id]
					emitted += _append_bond_pair_tuples(value_tuples, sql_out, bond_cache, "AVUNCULAR", "NIBLING", ps_dict, res_dict, -1, res_dob, reason_id)

					# Cousins
					var cousins: Array = _get_graph_list(kin_graph, ps_id, "children")
					for c_id in cousins:
						if c_id <= res_id or not residents_by_id.has(c_id):
							continue
						var c_dict: Dictionary = residents_by_id[c_id]
						var start_day: int = maxi(res_dob, int(c_dict["dob"]))
						emitted += _append_bond_pair_tuples(value_tuples, sql_out, bond_cache, "COUSIN", "COUSIN", res_dict, c_dict, -1, start_day, reason_id)

		if (idx + 1) % LOG_HEARTBEAT_INTERVAL == 0:
			SystemLogger.log_info("  [Pass 3B.3b] 2nd-Degree Kin: %d/%d | Edges: %d | Elapsed: %dms" % [
				idx + 1, total_nodes, emitted, Time.get_ticks_msec() - phase2_t0
			])

		var pct: float = 81.0 + ((float(idx + 1) / float(maxi(1, total_nodes))) * 4.0)
		yield_ms = await _maybe_yield_progress(
			on_progress,
			yield_ms,
			pct,
			"Deriving Extended Kinship: %d/%d citizens (%d links)" % [idx + 1, total_nodes, emitted],
			is_headless
		)

	return emitted

static func _ensure_graph_node(kin_graph: Dictionary, res_id: int) -> void:
	if not kin_graph.has(res_id):
		kin_graph[res_id] = {
			"parents": [],
			"children": [],
			"siblings": []
		}

static func _register_parent_child_in_graph(kin_graph: Dictionary, parent_id: int, child_id: int) -> void:
	_ensure_graph_node(kin_graph, parent_id)
	_ensure_graph_node(kin_graph, child_id)
	if not kin_graph[parent_id]["children"].has(child_id):
		kin_graph[parent_id]["children"].append(child_id)
	if not kin_graph[child_id]["parents"].has(parent_id):
		kin_graph[child_id]["parents"].append(parent_id)

static func _register_sibling_in_graph(kin_graph: Dictionary, id1: int, id2: int) -> void:
	_ensure_graph_node(kin_graph, id1)
	_ensure_graph_node(kin_graph, id2)
	if not kin_graph[id1]["siblings"].has(id2):
		kin_graph[id1]["siblings"].append(id2)
	if not kin_graph[id2]["siblings"].has(id1):
		kin_graph[id2]["siblings"].append(id1)

static func _get_graph_list(kin_graph: Dictionary, res_id: int, key: String) -> Array:
	if kin_graph.has(res_id) and kin_graph[res_id].has(key):
		return kin_graph[res_id][key]
	return []