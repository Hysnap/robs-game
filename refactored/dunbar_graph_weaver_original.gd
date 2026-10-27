# res://systems/society/dunbar_graph_weaver.gd
class_name DunbarGraphWeaverOriginal
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

## Pass 4: Weaves multi-tier Dunbar social relationships across SQLite
static func run(physical_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var rel_drinking_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "DRINKING_MATE")
	var district_residents_map: Dictionary = physical_state["district_residents_map"]

	# 1. Pub Catchment Edges per District
	var pub_edges: Array[String] = []
	for dist_id in district_residents_map.keys():
		var res_ids: Array = district_residents_map[dist_id]
		if res_ids.size() < 2:
			continue
		for r_id in res_ids:
			var buddy_count := rng.randi_range(2, 4)
			for _b in range(buddy_count):
				var target_id: int = res_ids[rng.randi() % res_ids.size()]
				if target_id != r_id:
					pub_edges.append("""
						INSERT INTO social_relationships (
							from_resident_id, to_resident_id, relationship_type_id,
							context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, %d, NULL, 0.55, %d, NULL, %d);
					""" % [r_id, target_id, rel_drinking_id, sim_start_day, reason_world_gen_id])
		if pub_edges.size() >= 500:
			DB_MANAGER.execute_batch(pub_edges)
			pub_edges.clear()

	if not pub_edges.is_empty():
		DB_MANAGER.execute_batch(pub_edges)

	# 2. Extended Kinship, Coworkers, and Congregational Faith Ties
	_generate_extended_kinship(rng, sim_start_day, reason_world_gen_id)
	_generate_establishment_peer_ties(rng, sim_start_day, reason_world_gen_id)
	_generate_faith_and_cultural_ties(rng, sim_start_day, reason_world_gen_id)

static func _generate_extended_kinship(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var kinship_edges: Array[String] = []
	var edge_count: int = 0
	var ext_fam_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "EXTENDED_FAMILY")

	var surname_clusters = DB_MANAGER.query_rows("""
		SELECT current_surname as surname, e.district_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		GROUP BY current_surname, e.district_id
		HAVING count > 1;
	""")

	for cluster in surname_clusters:
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var pairs_to_attempt: int = min(ids.size(), 4)
		for _p in range(pairs_to_attempt):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a == b or rng.randf() > 0.60:
				continue

			kinship_edges.append("""
				INSERT OR IGNORE INTO social_relationships (
					from_resident_id, to_resident_id, relationship_type_id,
					context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
				) VALUES (%d, %d, %d, NULL, 0.80, %d, NULL, %d);
			""" % [a, b, ext_fam_id, sim_start_day, reason_id])
			kinship_edges.append("""
				INSERT OR IGNORE INTO social_relationships (
					from_resident_id, to_resident_id, relationship_type_id,
					context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
				) VALUES (%d, %d, %d, NULL, 0.80, %d, NULL, %d);
			""" % [b, a, ext_fam_id, sim_start_day, reason_id])
			edge_count += 2

		if kinship_edges.size() >= 500:
			DB_MANAGER.execute_batch(kinship_edges)
			kinship_edges.clear()

	if not kinship_edges.is_empty():
		DB_MANAGER.execute_batch(kinship_edges)

	return edge_count

static func _generate_establishment_peer_ties(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var peer_edges: Array[String] = []
	var edge_count: int = 0
	var peer_rel_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CIVIC_PEER")

	var est_clusters = DB_MANAGER.query_rows("""
		SELECT employer_entity_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM livelihood_contracts
		GROUP BY employer_entity_id
		HAVING count > 1;
	""")

	for cluster in est_clusters:
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var samples: int = min(ids.size(), 30)
		for _s in range(samples):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a != b:
				peer_edges.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, NULL, 0.50, %d, NULL, %d);
				""" % [a, b, peer_rel_id, sim_start_day, reason_id])
				edge_count += 1

		if peer_edges.size() >= 500:
			DB_MANAGER.execute_batch(peer_edges)
			peer_edges.clear()

	if not peer_edges.is_empty():
		DB_MANAGER.execute_batch(peer_edges)

	return edge_count

static func _generate_faith_and_cultural_ties(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var ties: Array[String] = []
	var edge_count: int = 0
	var congregational_rel_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CONGREGATIONAL")

	var congregation_clusters = DB_MANAGER.query_rows("""
		SELECT e.district_id, r.ethnicity_id, r.religion_id, GROUP_CONCAT(r.resident_id) as member_ids, COUNT(*) as count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		WHERE r.dod IS NULL
		GROUP BY e.district_id, r.ethnicity_id, r.religion_id
		HAVING count > 1;
	""")

	for cluster in congregation_clusters:
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var samples: int = min(ids.size(), 5)
		for _s in range(samples):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a != b and rng.randf() < 0.40:
				ties.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, NULL, 0.65, %d, NULL, %d);
				""" % [a, b, congregational_rel_id, sim_start_day, reason_id])
				ties.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, NULL, 0.65, %d, NULL, %d);
				""" % [b, a, congregational_rel_id, sim_start_day, reason_id])
				edge_count += 2

		if ties.size() >= 500:
			DB_MANAGER.execute_batch(ties)
			ties.clear()

	if not ties.is_empty():
		DB_MANAGER.execute_batch(ties)

	return edge_count
