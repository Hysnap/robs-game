# res://systems/society/crew_selection/crew_selection_strategy.gd
class_name CrewSelectionStrategy
extends RefCounted

## Pure virtual base strategy for scouting starting crew candidates.
## Concrete strategies implement this method to evaluate candidate clusters.
## Returns an Array[int] of resident_ids matching target_count, or empty if unsatisfiable.
func resolve_candidates(_context: Dictionary) -> Array[int]:
	push_error("[CrewSelectionStrategy] resolve_candidates() must be implemented by subclass.")
	return []
    