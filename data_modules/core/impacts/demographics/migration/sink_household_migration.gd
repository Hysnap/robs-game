# res://data_modules/core/impacts/demographics/migration/sink_household_migration.gd
class_name SinkHouseholdMigration
extends ImpactSinkBase

const DB_MANAGER = preload("res://systems/db_manager.gd")

## 1. IDENTITY
static func get_metric_key() -> String:
	return "HOUSEHOLD_MIGRATION"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return
		
	var districts: Dictionary = world_state.get("districts", {})
	if districts.has(target_id):
		var cur_hh: int = int(districts[target_id].get("total_households", 0))
		districts[target_id]["total_households"] = maxi(0, cur_hh + int(round(delta)))

## 3. SQLITE LIVE TELEMETRY QUERY
static func query_metric_value(target_id: String) -> Variant:
	var sql := "SELECT total_households FROM v_district_census WHERE district_id = '%s';" % target_id
	var rows := DB_MANAGER.query_rows(sql)
	if rows.is_empty():
		return 0
	return int(rows[0].get("total_households", 0))