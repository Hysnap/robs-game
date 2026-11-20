# res://systems/society/dunbar_graph_weaver.gd
class_name DunbarGraphWeaver
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SOCIAL_QUERY_HELPER = preload("res://systems/society/social_group_query_helper.gd")

## Pass 4: Weaves venue-based and peer Dunbar social relationships across SQLite
static func run(physical_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_world_gen_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	SystemLogger.log_info("  [Pass 4] Weaving venue-based Dunbar social networks (Pubs, Workplaces, Churches)...")

	_generate_pub_drinking_mates(rng, sim_start_day, reason_world_gen_id)
	_generate_establishment_peer_ties(rng, sim_start_day, reason_world_gen_id)
	_generate_faith_and_cultural_ties(rng, sim_start_day, reason_world_gen_id)

static func _generate_pub_drinking_mates(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var pub_edges: Array[String] = []
	var edge_count: int = 0
	var rel_drinking_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "DRINKING_MATE")

	var pub_clusters: Array[Dictionary] = SOCIAL_QUERY_HELPER.query_residents_by_pub()

	for cluster in pub_clusters:
		var pub_id: int = int(cluster["local_pub_id"])
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var samples: int = min(ids.size(), 4)
		for _s in range(samples):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a != b and rng.randf() < 0.65:
				pub_edges.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, %d, 0.55, %d, NULL, %d);
				""" % [a, b, rel_drinking_id, pub_id, sim_start_day, reason_id])
				pub_edges.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, %d, 0.55, %d, NULL, %d);
				""" % [b, a, rel_drinking_id, pub_id, sim_start_day, reason_id])
				edge_count += 2

		if pub_edges.size() >= 500:
			DB_MANAGER.execute_batch(pub_edges)
			pub_edges.clear()

	if not pub_edges.is_empty():
		DB_MANAGER.execute_batch(pub_edges)

	return edge_count

static func _generate_establishment_peer_ties(rng: RandomNumberGenerator, sim_start_day: int, reason_id: int) -> int:
	var peer_edges: Array[String] = []
	var edge_count: int = 0
	var peer_rel_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", "CIVIC_PEER")

	var est_clusters: Array[Dictionary] = SOCIAL_QUERY_HELPER.query_residents_by_workplace()

	for cluster in est_clusters:
		var est_id: int = int(cluster["employer_establishment_id"])
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
					) VALUES (%d, %d, %d, %d, 0.50, %d, NULL, %d);
				""" % [a, b, peer_rel_id, est_id, sim_start_day, reason_id])
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

	var congregation_clusters: Array[Dictionary] = SOCIAL_QUERY_HELPER.query_residents_by_church()

	for cluster in congregation_clusters:
		var church_id: int = int(cluster["church_id"])
		var id_strings: PackedStringArray = str(cluster["member_ids"]).split(",")
		if id_strings.size() < 2:
			continue

		var ids: Array[int] = []
		for s in id_strings:
			ids.append(int(s))

		var samples: int = min(ids.size(), 8)
		for _s in range(samples):
			var a: int = ids[rng.randi() % ids.size()]
			var b: int = ids[rng.randi() % ids.size()]
			if a != b and rng.randf() < 0.50:
				ties.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, %d, 0.65, %d, NULL, %d);
				""" % [a, b, congregational_rel_id, church_id, sim_start_day, reason_id])
				ties.append("""
					INSERT OR IGNORE INTO social_relationships (
						from_resident_id, to_resident_id, relationship_type_id,
						context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
					) VALUES (%d, %d, %d, %d, 0.65, %d, NULL, %d);
				""" % [b, a, congregational_rel_id, church_id, sim_start_day, reason_id])
				edge_count += 2

		if ties.size() >= 500:
			DB_MANAGER.execute_batch(ties)
			ties.clear()

	if not ties.is_empty():
		DB_MANAGER.execute_batch(ties)

	return edge_count