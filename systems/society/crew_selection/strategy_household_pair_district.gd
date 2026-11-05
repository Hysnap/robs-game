# res://systems/society/crew_selection/strategy_household_pair_district.gd
class_name StrategyHouseholdPairDistrict
extends CrewSelectionStrategy

## Priority 2: Finds a household pair of kin and links them to an external kin candidate in the district.
func resolve_candidates(context: Dictionary) -> Array[int]:
	var by_household: Dictionary = context.get("by_household", {})
	var candidate_rows: Array = context.get("candidate_rows", [])
	var unique_candidates: Dictionary = context.get("unique_candidates", {})
	var target_count: int = int(context.get("target_count", 3))

	if by_household.is_empty() or candidate_rows.is_empty() or target_count < 3:
		return []

	# Iterate over households that contain at least 2 members
	for h_id in by_household.keys():
		var members: Array = by_household[h_id]
		if members.size() < 2:
			continue

		var r1: int = int(members[0])
		var r2: int = int(members[1])

		# Search for a 3rd candidate in the pool linked by family edge to r1 or r2
		for row in candidate_rows:
			var from_id: int = int(row.get("resident_id", 0))
			var rel_id: int = int(row.get("relative_id", 0))

			if (from_id == r1 or from_id == r2) and unique_candidates.has(rel_id):
				if rel_id != r1 and rel_id != r2:
					var result: Array[int] = [r1, r2, rel_id]
					return result

	return []