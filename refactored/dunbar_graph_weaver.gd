# res://refactored/dunbar_graph_weaver.gd
class_name RefactoredDunbarGraphWeaver
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const BATCH_SIZE: int = 500

## Pass 4: Weaves configurable relationship types across SQLite.
static func run(physical_state: Dictionary, rng: RandomNumberGenerator) -> void:
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var reason_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
	var specs: Array[Dictionary] = _relationship_specs(physical_state)

	for spec in specs:
		_generate_relationships(spec, rng, sim_start_day, reason_id)

static func _relationship_specs(physical_state: Dictionary) -> Array[Dictionary]:
	return [
		{
			"relationship_code": "DRINKING_MATE",
			"source": "districts",
			"district_residents_map": physical_state["district_residents_map"],
			"sample_min": 2,
			"sample_max": 4,
			"sample_scope": "per_resident",
			"accept_probability": 1.0,
			"affinity_score": 0.55,
			"reciprocal": false
		},
		{
			"relationship_code": "EXTENDED_FAMILY",
			"source": "query",
			"query": """
				SELECT current_surname AS surname, e.district_id,
					GROUP_CONCAT(resident_id) AS member_ids, COUNT(*) AS member_count
				FROM residents r
				JOIN households h ON r.household_id = h.household_id
				JOIN establishments e ON h.establishment_id = e.establishment_id
				GROUP BY current_surname, e.district_id
				HAVING member_count > 1;
			""",
			"sample_min": 4,
			"sample_max": 4,
			"accept_probability": 0.60,
			"affinity_score": 0.80,
			"reciprocal": true
		},
		{
			"relationship_code": "CIVIC_PEER",
			"source": "query",
			"query": """
				SELECT employer_entity_id,
					GROUP_CONCAT(resident_id) AS member_ids, COUNT(*) AS member_count
				FROM livelihood_contracts
				GROUP BY employer_entity_id
				HAVING member_count > 1;
			""",
			"sample_min": 30,
			"sample_max": 30,
			"accept_probability": 1.0,
			"affinity_score": 0.50,
			"reciprocal": false
		},
		{
			"relationship_code": "CONGREGATIONAL",
			"source": "query",
			"query": """
				SELECT e.district_id, r.ethnicity_id, r.religion_id,
					GROUP_CONCAT(r.resident_id) AS member_ids, COUNT(*) AS member_count
				FROM residents r
				JOIN households h ON r.household_id = h.household_id
				JOIN establishments e ON h.establishment_id = e.establishment_id
				WHERE r.dod IS NULL
				GROUP BY e.district_id, r.ethnicity_id, r.religion_id
				HAVING member_count > 1;
			""",
			"sample_min": 5,
			"sample_max": 5,
			"accept_probability": 0.40,
			"affinity_score": 0.65,
			"reciprocal": true
		}
	]

static func _generate_relationships(
	spec: Dictionary,
	rng: RandomNumberGenerator,
	sim_start_day: int,
	reason_id: int
) -> int:
	var relationship_code: String = str(spec["relationship_code"])
	var relationship_id: int = DB_MANAGER.get_label_id("RELATIONSHIP_TYPE", relationship_code)
	var edges: Array[String] = []
	var generated_count: int = 0

	if spec["source"] == "districts":
		for resident_ids in spec["district_residents_map"].values():
			generated_count += _generate_cluster_edges(
				resident_ids, spec, relationship_id, rng, sim_start_day, reason_id, edges
			)
	else:
		for cluster in DB_MANAGER.query_rows(str(spec["query"])):
			var resident_ids: Array[int] = _parse_member_ids(cluster.get("member_ids", ""))
			generated_count += _generate_cluster_edges(
				resident_ids, spec, relationship_id, rng, sim_start_day, reason_id, edges
			)

	_flush_edges(edges)
	return generated_count

static func _generate_cluster_edges(
	resident_ids: Array,
	spec: Dictionary,
	relationship_id: int,
	rng: RandomNumberGenerator,
	sim_start_day: int,
	reason_id: int,
	edges: Array[String]
) -> int:
	if resident_ids.size() < 2:
		return 0

	var generated_count: int = 0
	var seen_pairs: Dictionary = {}

	var source_ids: Array = resident_ids
	if str(spec.get("sample_scope", "per_cluster")) != "per_resident":
		source_ids = [null]

	for source in source_ids:
		var sample_count: int = min(
			resident_ids.size(),
			rng.randi_range(int(spec["sample_min"]), int(spec["sample_max"]))
		)
		for _sample in range(sample_count):
			var from_id: int = int(source) if source != null else int(resident_ids[rng.randi() % resident_ids.size()])
			var to_id: int = int(resident_ids[rng.randi() % resident_ids.size()])
			if from_id == to_id or rng.randf() > float(spec["accept_probability"]):
				continue

			var pair_key := "%d:%d" % [from_id, to_id]
			if seen_pairs.has(pair_key):
				continue
			seen_pairs[pair_key] = true

			_append_edge(edges, from_id, to_id, relationship_id, spec, sim_start_day, reason_id)
			generated_count += 1

			if bool(spec["reciprocal"]):
				var reverse_key := "%d:%d" % [to_id, from_id]
				if not seen_pairs.has(reverse_key):
					seen_pairs[reverse_key] = true
					_append_edge(edges, to_id, from_id, relationship_id, spec, sim_start_day, reason_id)
					generated_count += 1

			if edges.size() >= BATCH_SIZE:
				_flush_edges(edges)

	return generated_count

static func _append_edge(
	edges: Array[String],
	from_id: int,
	to_id: int,
	relationship_id: int,
	spec: Dictionary,
	sim_start_day: int,
	reason_id: int
) -> void:
	edges.append("""
		INSERT OR IGNORE INTO social_relationships (
			from_resident_id, to_resident_id, relationship_type_id,
			context_establishment_id, affinity_score, valid_from, valid_to, change_reason_id
		) VALUES (%d, %d, %d, NULL, %.2f, %d, NULL, %d);
	""" % [
		from_id,
		to_id,
		relationship_id,
		float(spec["affinity_score"]),
		sim_start_day,
		reason_id
	])

static func _flush_edges(edges: Array[String]) -> void:
	if edges.is_empty():
		return
	if not DB_MANAGER.execute_batch(edges):
		push_error("[DunbarGraphWeaver] Failed to persist relationship batch.")
	edges.clear()

static func _parse_member_ids(raw_ids: Variant) -> Array[int]:
	var ids: Array[int] = []
	for raw_id in str(raw_ids).split(","):
		var resident_id: int = int(raw_id)
		if resident_id > 0:
			ids.append(resident_id)
	return ids
