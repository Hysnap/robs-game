# res://data_modules/core/impacts/demographics/population/sink_population.gd
extends ImpactSinkBase
class_name SinkActivePopulation

static func get_metric_key() -> String:
	return "ACTIVE_POPULATION"

## Ground-truth query executed when GameState / Filofax requests district metrics
static func query_metric_value(district_id: String) -> Variant:
	assert(not district_id.is_empty(), "FATAL: district_id cannot be empty")
	
	var sql := """
		SELECT COUNT(*) as total_residents 
		FROM residents r 
		JOIN households h ON r.household_id = h.household_id 
		WHERE h.district_id = '%s';
	""" % district_id

	var result: Array = DBManager.query_rows(sql)
	if result.is_empty():
		return 0
	return int(result[0]["total_residents"])

## When an action impacts population (e.g. eviction, migration)
static func apply_delta(_world_state: Dictionary, target_id: String, delta: float) -> void:
	var count: int = int(round(delta))
	if count == 0:
		return
	
	if count < 0:
		# Evict / displace households
		var sql := """
			DELETE FROM households 
			WHERE household_id IN (
				SELECT household_id FROM households WHERE district_id = '%s' LIMIT %d
			);
		""" % [target_id, abs(count)]
		DBManager.query_rows(sql)