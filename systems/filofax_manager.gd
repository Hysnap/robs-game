# res://systems/filofax_manager.gd
class_name FilofaxManager extends RefCounted

## Initializes the perceived cache from world state
static func init_cache(world_state: Dictionary) -> Dictionary:
	var cache = {
		"metadata": {
			"viewed_tick": world_state.get("metadata", {}).get("current_week_tick", 1),
			"active_hardware": "DIRECT_DESK" # Placeholder for future comms tech
		},
		"finances": {
			"reported_cash": world_state.get("finances", {}).get("liquid_cash", 0.0)
		},
		"districts": {},
		"pinned_memos": []
	}
	
	refresh_cache_instant(world_state, cache)
	return cache

## TODAY: Instant 1:1 synchronization (Zero Lag, Zero Noise)
## LATER: This will push into an asynchronous transit queue instead!
static func refresh_cache_instant(world_state: Dictionary, cache: Dictionary) -> void:
	var current_tick: int = world_state.get("metadata", {}).get("current_week_tick", 1)
	cache["metadata"]["viewed_tick"] = current_tick
	cache["finances"]["reported_cash"] = world_state.get("finances", {}).get("liquid_cash", 0.0)
	
	# Districts Telemetry
	for dist_id in world_state.get("districts", {}).keys():
		var true_dist = world_state["districts"][dist_id]
		cache["districts"][dist_id] = {
			"display_name": true_dist.get("display_name", dist_id),
			"inked_police_heat": true_dist.get("actual_police_heat", 0.0),
			"inked_zone_health": true_dist.get("zone_health_index", 100.0),
			"data_age_ticks": 0,       # Instant!
			"confidence_score": 1.0     # 100% crisp!
		}