# res://data_modules/core/impacts/income/sink_disposable_income.gd
extends ImpactSinkBase
class_name SinkDisposableIncome

static func get_metric_key() -> String:
	return "DISPOSABLE_INCOME_DELTA"

static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	# Target can be a specific Household OR a Macro District Block
	if target_id.begins_with("HH_"):
		var hh_id: int = int(target_id.trim_prefix("HH_"))
		var sql := "UPDATE households SET weekly_income_modifier = weekly_income_modifier + (%f) WHERE household_id = %d;" % [delta, hh_id]
		DBManager.query_rows(sql)
	else:
		# District-wide wage/expense shift (e.g. factory closure or syndicate tax)
		var sql := "UPDATE households SET weekly_income_modifier = weekly_income_modifier + (%f) WHERE district_id = '%s';" % [delta, target_id]
		DBManager.query_rows(sql)
		
		# Also record the macro baseline shift in world_state for reference
		if world_state.get("districts", {}).has(target_id):
			var dist: Dictionary = world_state["districts"][target_id]
			dist["avg_disposable_income"] = max(0.0, float(dist.get("avg_disposable_income", 50.0)) + delta)