# res://systems/society/crew_selection/strategy_same_household_kin.gd
class_name StrategySameHouseholdKin
extends CrewSelectionStrategy

## Priority 1: Finds target_count eligible young adults living under the same household roof.
func resolve_candidates(context: Dictionary) -> Array[int]:
	var by_household: Dictionary = context.get("by_household", {})
	var target_count: int = int(context.get("target_count", 3))
	
	if by_household.is_empty() or target_count <= 0:
		return []

	# Search for any household that has at least target_count candidate residents
	for h_id in by_household.keys():
		var members: Array = by_household[h_id]
		if members.size() >= target_count:
			var selected: Array[int] = []
			for i in range(target_count):
				selected.append(int(members[i]))
			return selected

	return []
    