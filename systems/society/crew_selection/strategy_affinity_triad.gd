# res://systems/society/crew_selection/strategy_affinity_triad.gd
class_name StrategyAffinityTriad
extends CrewSelectionStrategy

## Priority 3 Fallback: Selects candidates in the district based on highest mutual affinity/connectivity.
func resolve_candidates(context: Dictionary) -> Array[int]:
	var unique_candidates: Dictionary = context.get("unique_candidates", {})
	var candidate_rows: Array = context.get("candidate_rows", [])
	var target_count: int = int(context.get("target_count", 3))

	if unique_candidates.size() < target_count:
		return []

	# Calculate cumulative affinity weight for each candidate
	var scores: Dictionary = {}
	for r_id in unique_candidates.keys():
		scores[r_id] = 0.0

	for row in candidate_rows:
		var from_id: int = int(row.get("resident_id", 0))
		var affinity: float = float(row.get("affinity_score", 0.0))
		if scores.has(from_id):
			scores[from_id] += affinity

	# Sort candidates descending by score
	var sorted_ids: Array = unique_candidates.keys()
	sorted_ids.sort_custom(func(a, b):
		return float(scores.get(a, 0.0)) > float(scores.get(b, 0.0))
	)

	var result: Array[int] = []
	for i in range(target_count):
		result.append(int(sorted_ids[i]))

	return result