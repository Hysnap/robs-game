# res://data_modules/core/impacts/employment/sink_employment.gd
class_name SinkEmployment
extends ImpactSinkBase

const DB_MANAGER = preload("res://systems/db_manager.gd")

## 1. IDENTITY
static func get_metric_key() -> String:
	return "EMPLOYMENT_DELTA"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return
		
	# Mutate world_state district cache if present
	var districts: Dictionary = world_state.get("districts", {})
	if districts.has(target_id):
		var cur_emp: float = float(districts[target_id].get("employment_rate", 0.88))
		districts[target_id]["employment_rate"] = clampf(cur_emp + delta, 0.0, 1.0)
		districts[target_id]["unemployment_rate"] = 1.0 - districts[target_id]["employment_rate"]

## 3. SQLITE LIVE TELEMETRY QUERY
static func query_metric_value(target_id: String) -> Variant:
	# Queries ground truth directly from SQLite view v_district_census
	var sql := "SELECT formally_employed_count, active_living_population FROM v_district_census WHERE district_id = '%s';" % target_id
	var rows := DB_MANAGER.query_rows(sql)
	if rows.is_empty():
		return 0.0
	
	var active_pop: int = int(rows[0].get("active_living_population", 0))
	if active_pop <= 0:
		return 0.0
		
	var employed: int = int(rows[0].get("formally_employed_count", 0))
	return float(employed) / float(active_pop)