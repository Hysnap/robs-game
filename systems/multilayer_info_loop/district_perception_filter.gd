# res://systems/multilayer_info_loop/district_perception_filter.gd
class_name DistrictPerceptionFilter
extends RefCounted

const DB_MGR = preload("res://systems/db_manager.gd")
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")

## Filters raw district telemetry and establishment rolls against player knowledge/fog of war
static func get_perceived_district_view(world_state: Dictionary, district_id: String) -> Dictionary:
	assert(not district_id.is_empty(), "FATAL: [DistrictPerceptionFilter] district_id cannot be empty.")

	var known_districts: Array = world_state.get("player_knowledge", {}).get("known_districts", [])
	var is_known: bool = known_districts.has(district_id)

	var view_data: Dictionary = {}
	var districts: Dictionary = world_state.get("districts", {})

	# 1. Base Spatial Identity (Macro Geography is publicly visible)
	if districts.has(district_id):
		view_data = districts[district_id].duplicate(true)
	else:
		view_data["district_id"] = district_id
		view_data["display_name"] = district_id.capitalize().replace("_", " ")

	view_data["is_known"] = is_known

	# 2. Masked / Fog-of-War District (Unsurveyed)
	if not is_known:
		view_data["active_population"] = 0
		view_data["total_households"] = 0
		view_data["formally_employed_count"] = 0
		view_data["street_informal_count"] = 0
		view_data["incarcerated_count"] = 0
		view_data["establishments_summary"] = []
		view_data["intel_status"] = "INTEL_STATUS_UNEXPLORED"
		return view_data

	# 3. Known District Ground Truth (Hydrated via SQLite)
	view_data["intel_status"] = "INTEL_STATUS_VERIFIED"

	if DB_MGR.is_database_open():
		var census_rows = DB_MGR.query_rows("""
			SELECT total_households, total_residents, active_living_population, 
			       formally_employed_count, street_informal_count, incarcerated_count 
			FROM v_district_census 
			WHERE district_id = '%s';
		""" % district_id)

		if not census_rows.is_empty():
			var row: Dictionary = census_rows[0]
			view_data["active_population"] = int(row.get("active_living_population", 0))
			view_data["total_households"] = int(row.get("total_households", 0))
			view_data["formally_employed_count"] = int(row.get("formally_employed_count", 0))
			view_data["street_informal_count"] = int(row.get("street_informal_count", 0))
			view_data["incarcerated_count"] = int(row.get("incarcerated_count", 0))
		else:
			view_data["active_population"] = view_data.get("population", 0)
			view_data["total_households"] = int(round(float(view_data["active_population"]) / 2.6))
			view_data["formally_employed_count"] = 0
			view_data["street_informal_count"] = 0
			view_data["incarcerated_count"] = 0

		# Hydrate detailed establishments through SocietyQueries ground truth
		view_data["establishments_summary"] = SOCIETY_QUERIES.get_district_establishments(district_id)
	else:
		view_data["establishments_summary"] = []

	return view_data