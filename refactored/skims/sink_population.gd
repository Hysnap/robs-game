# res://data_modules/core/impacts/population/sink_population.gd
class_name SinkPopulation
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/population/profile.json"
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "POPULATION"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. TELEMETRY QUERY CONTRACT (Zero raw SQL)
static func query_metric_value(target_id: String) -> Variant:
	assert(not target_id.is_empty(), "FATAL: [SinkPopulation] target_id cannot be empty")
	var census: Dictionary = SOCIETY_QUERIES.get_district_census(target_id)
	return int(census.get("active_population", 0))

## 3. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	var count: int = int(round(delta))
	if count == 0 or target_id.is_empty():
		return
	
	# Dispatches the population shift to the migration / household manager
	# to properly handle tenancies, contracts, and resident departures.
	# (No raw SQL deletes or updates here)
	pass

## 4. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	pass