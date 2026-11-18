# res://systems/society/family_tree_weaver.gd
class_name FamilyTreeWeaver
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SQL_BATCH_FLUSH_LIMIT := 1000

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
	sql_out.append("""
		INSERT OR IGNORE INTO social_relationships (
			from_resident_id, to_resident_id, relationship_type_id,
			context_establishment_id, affinity_score, valid_from, change_reason_id
		) VALUES (%d, %d, %d, %s, %.2f, %d, %d);
	""" % [from_id, to_id, rel_type_id, ctx_str, affinity, valid_from, reason_id])

static func _flush_sql_buffer_if_needed(sql_out: Array[String], force: bool = false) -> void:
	if sql_out.is_empty():
		return
	if force or sql_out.size() >= SQL_BATCH_FLUSH_LIMIT:
		DB_MANAGER.execute_batch(sql_out)
		sql_out.clear()

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

## Links cross-household extended family trees in memory-bounded batches with front-end progress updates
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
	var max_sib_age_diff: int = int(kinship_rules["dispersed_sibling_max_age_diff"])
	var sib_link_prob: float = float(kinship_rules["dispersed_sibling_link_prob"])
	var min_parent_age_diff: int = int(kinship_rules["dispersed_parent_min_age_diff"])
	var max_parent_age_diff: int = int(kinship_rules["dispersed_parent_max_age_diff"])
	var parent_link_prob: float = float(kinship_rules["dispersed_parent_link_prob"])
	var max_dispersed_siblings: int = int(kinship_rules.get("max_dispersed_siblings", 3))
	var max_offspring_per_parent: int = int(kinship_rules.get("max_dispersed_offspring", 4))

	var total_edges_emitted: int = 0
	var is_headless: bool = (DisplayServer.get_name() == "headless")

	# Group adult household heads/spouses by (birth_surname + ethnicity_id) to link dispersed clans
	var clan_buckets: Dictionary = {}
	for res_id in residents_by_id.keys():
		var r: Dictionary = residents_by_id[res_id]
		var role: String = str(r["household_role"])
		if role != "HEAD" and role != "SPOUSE":
			continue
		var b_surname: String = str(r["birth_surname"])
		if b_surname.is_empty():
			continue
		var clan_key: String = "%s:%d" % [b_surname, int(r["ethnicity_id"])]
		if not clan_buckets.has(clan_key):
			clan_buckets[clan_key] = []
		clan_buckets[clan_key].append(r)

	var clan_keys: Array = clan_buckets.keys()
	var total_clans: int = clan_keys.size()

	for c_idx in range(total_clans):
		var clan_key = clan_keys[c_idx]
		var clan: Array = clan_buckets[clan_key]
		if clan.size() >= 2:
			# Sort oldest to youngest (lowest dob day offset first)
			clan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a["dob"]) < int(b["dob"])
			)

			for i in range(clan.size()):
				var r1: Dictionary = clan[i]
				var id1: int = int(r1["resident_id"])
				var hh1: int = int(r1["household_id"])
				var age1: int = int(r1["age_years"])

				for j in range(i + 1, clan.size()):
					var r2: Dictionary = clan[j]
					var age2: int = int(r2["age_years"])
					var age_diff: int = age1 - age2 # Sorted oldest->youngest so age1 >= age2

					# Early exit: since clan is sorted oldest-to-youngest, age_diff only grows larger
					if age_diff > max_parent_age_diff:
						break

					var id2: int = int(r2["resident_id"])
					var hh2: int = int(r2["household_id"])
					if hh1 == hh2:
						continue

					# 1. Link dispersed adult siblings in different households (capped per person)
					if age_diff <= max_sib_age_diff:
						var sibs1: Array = _get_graph_list(inout_kin_graph, id1, "siblings")
						var sibs2: Array = _get_graph_list(inout_kin_graph, id2, "siblings")
						if sibs1.size() < max_dispersed_siblings and sibs2.size() < max_dispersed_siblings and rng.randf() < sib_link_prob:
							var start_day: int = maxi(int(r1["dob"]), int(r2["dob"]))
							total_edges_emitted += _append_bond_pair_sql(sql_out, bonds_cfg, "DISPERSED_SIBLING", "DISPERSED_SIBLING", r1, r2, -1, start_day, reason_id)
							_register_sibling_in_graph(inout_kin_graph, id1, id2)
							_flush_sql_buffer_if_needed(sql_out)

					# 2. Link older generation household to younger adult offspring household
					elif age_diff >= min_parent_age_diff:
						var children1: Array = _get_graph_list(inout_kin_graph, id1, "children")
						var existing_parents2: Array = _get_graph_list(inout_kin_graph, id2, "parents")
						if children1.size() < max_offspring_per_parent and existing_parents2.is_empty() and rng.randf() < parent_link_prob:
							var c_dob: int = int(r2["dob"])
							total_edges_emitted += _append_bond_pair_sql(sql_out, bonds_cfg, "DISPERSED_PARENT", "DISPERSED_CHILD", r1, r2, -1, c_dob, reason_id)
							_register_parent_child_in_graph(inout_kin_graph, id1, id2)
							_flush_sql_buffer_if_needed(sql_out)

		if (c_idx + 1) % 100 == 0 and on_progress.is_valid():
			var pct: float = 76.0 + ((float(c_idx + 1) / float(max(1, total_clans))) * 5.0)
			on_progress.call(pct, 100.0, "Weaving Extended Clans: %d/%d surnames (%d links)" % [c_idx + 1, total_clans, total_edges_emitted])
			if not is_headless:
				var main_loop = Engine.get_main_loop()
				if main_loop is SceneTree:
					await (main_loop as SceneTree).process_frame

	clan_buckets.clear()
	_flush_sql_buffer_if_needed(sql_out, true)

	# 3. Derive 2nd-Degree Extended Kinship (Grandparents, Uncles/Aunts, Cousins) from the 1st-degree graph
	total_edges_emitted += await _derive_second_degree_kinship_edges(
		sql_out, residents_by_id, bonds_cfg, reason_id, inout_kin_graph, on_progress
	)
	_flush_sql_buffer_if_needed(sql_out, true)
	return total_edges_emitted

## Derives Grandparent/Grandchild, Uncle/Aunt/Nephew/Niece, and Cousin edges in memory-bounded batches
static func _derive_second_degree_kinship_edges(
	sql_out: Array[String],
	residents_by_id: Dictionary,
	bonds_cfg: Dictionary,
	reason_id: int,
	kin_graph: Dictionary,
	on_progress: Callable = Callable()
) -> int:
	var emitted: int = 0
	var graph_keys: Array = kin_graph.keys()
	var total_nodes: int = graph_keys.size()
	var is_headless: bool = (DisplayServer.get_name() == "headless")

	for idx in range(total_nodes):
		var res_id = graph_keys[idx]
		if not residents_by_id.has(res_id):
			continue
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
				emitted += _append_bond_pair_sql(sql_out, bonds_cfg, "GRANDPARENT", "GRANDCHILD", gp_dict, res_dict, -1, res_dob, reason_id)
				_flush_sql_buffer_if_needed(sql_out)

			# B. Uncles / Aunts (Siblings of my Parents) & Cousins (Children of my Parents' Siblings)
			var parent_siblings: Array = _get_graph_list(kin_graph, p_id, "siblings")
			for ps_id in parent_siblings:
				if not residents_by_id.has(ps_id):
					continue
				var ps_dict: Dictionary = residents_by_id[ps_id]
				emitted += _append_bond_pair_sql(sql_out, bonds_cfg, "AVUNCULAR", "NIBLING", ps_dict, res_dict, -1, res_dob, reason_id)
				_flush_sql_buffer_if_needed(sql_out)

				# Cousins
				var cousins: Array = _get_graph_list(kin_graph, ps_id, "children")
				for c_id in cousins:
					if c_id <= res_id or not residents_by_id.has(c_id):
						continue
					var c_dict: Dictionary = residents_by_id[c_id]
					var start_day: int = maxi(res_dob, int(c_dict["dob"]))
					emitted += _append_bond_pair_sql(sql_out, bonds_cfg, "COUSIN", "COUSIN", res_dict, c_dict, -1, start_day, reason_id)
					_flush_sql_buffer_if_needed(sql_out)

		if (idx + 1) % 2000 == 0 and on_progress.is_valid():
			var pct: float = 81.0 + ((float(idx + 1) / float(max(1, total_nodes))) * 4.0)
			on_progress.call(pct, 100.0, "Deriving Extended Kinship: %d/%d citizens (%d links)" % [idx + 1, total_nodes, emitted])
			if not is_headless:
				var main_loop = Engine.get_main_loop()
				if main_loop is SceneTree:
					await (main_loop as SceneTree).process_frame

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