# res://tests/test_society_factory.gd
class_name TestSocietyFactory
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")

## Generates a schema-compliant mock city and living society in SQLite for headless tests.
## Returns a standard world_state dictionary ready for simulation execution.
static func create_test_world(grid_w: int = 2, grid_h: int = 2, seed_id: String = "test-factory-seed") -> Dictionary:
	var mock_world: Dictionary = {"districts": {}}
	var start_sim_day: int = CalendarHelperScript.get_simulation_start_day()

	var names: Array[String] = [
		"Aston", "Nechells", "Highgate", "Sparkbrook", 
		"Ladywood", "Small Heath", "Digbeth", "Derry"
	]
	var name_idx := 0

	for gy in range(grid_h):
		for gx in range(grid_w):
			var dist_id: String = "block_%d_%d" % [gx, gy]
			var disp_name: String = names[name_idx % names.size()]
			name_idx += 1

			mock_world["districts"][dist_id] = {
				"district_id": dist_id,
				"display_name": disp_name,
				"district_type": "high_density_low_rise",
				"grid_coords": Vector2i(gx, gy),
				"grid_size": Vector2i(1, 1),
				"spatial_anchor": Vector2(float(gx) * 200.0, float(gy) * 200.0),
				"unemployment_rate": 0.15
			}

	# Run production procedural generator (wipes and seeds SQLite cleanly)
	SOCIAL_NETWORK_GENERATOR.generate_city_society(mock_world, seed_id, true)

	# Select a home district that genuinely contains residential candidates
	var chosen_district: String = _find_best_residential_district(mock_world, start_sim_day)

	return {
		"metadata": {
			"current_sim_day": start_sim_day,
			"current_week_tick": 1,
			"calendar_year": 1980
		},
		"operations": {
			"home_district_id": chosen_district
		},
		"knowledge_pools": {},
		"districts": mock_world["districts"],
		"residents": {},
		"establishments": {},
		"caches": {}
	}

## Finds a district with verified candidate young adults or dense households
static func _find_best_residential_district(mock_world: Dictionary, start_sim_day: int) -> String:
	var min_dob: int = start_sim_day - int(round(27.0 * 365.25))
	var max_dob: int = start_sim_day - int(round(18.0 * 365.25))

	var candidate_districts: Array = DB_MANAGER.query_rows("""
		SELECT e.district_id, COUNT(r.resident_id) AS candidate_count
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e ON h.establishment_id = e.establishment_id
		WHERE r.dod IS NULL 
		  AND r.dob >= %d AND r.dob <= %d
		GROUP BY e.district_id
		ORDER BY candidate_count DESC
		LIMIT 1;
	""" % [min_dob, max_dob])

	if not candidate_districts.is_empty():
		return str(candidate_districts[0].get("district_id", ""))

	# Fallback: District with the most households
	var hh_districts: Array = DB_MANAGER.query_rows("""
		SELECT e.district_id, COUNT(h.household_id) AS hh_count
		FROM households h
		JOIN establishments e ON h.establishment_id = e.establishment_id
		GROUP BY e.district_id
		ORDER BY hh_count DESC
		LIMIT 1;
	""")

	if not hh_districts.is_empty():
		return str(hh_districts[0].get("district_id", ""))

	return mock_world["districts"].keys()[0]

## Generates a full test society, scouts starting crew, hydrates SQLite cognitive/OCEAN traits into world_state,
## and ensures canonical organization records exist for mandate and hierarchy testing.
static func create_test_world_with_crew(
	grid_w: int = 2,
	grid_h: int = 2,
	seed_id: String = "test-factory-crew-seed",
	time_horizon: String = "day"
) -> Dictionary:
	var ws: Dictionary = create_test_world(grid_w, grid_h, seed_id)
	ws["metadata"]["time_horizon"] = time_horizon
	var home_district: String = str(ws.get("operations", {}).get("home_district_id", ""))
	if not home_district.is_empty():
		CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(ws, home_district)

	# Hydrate SQLite cognitive & OCEAN columns onto in-memory crew dictionaries
	var residents: Dictionary = ws.get("residents", {})
	for r_key in residents.keys():
		var rec = residents[r_key]
		if not (rec is Dictionary):
			continue
		var r_id: int = int(rec.get("resident_id", r_key))
		if r_id <= 0:
			continue
		var rows: Array = DB_MANAGER.query_rows("""
			SELECT iq_score, mental_agility, openness, conscientiousness,
			       extraversion, agreeableness, neuroticism
			FROM residents WHERE resident_id = %d LIMIT 1;
		""" % r_id)
		if not rows.is_empty():
			var row: Dictionary = rows[0]
			rec["iq_score"] = float(row.get("iq_score", 100.0))
			rec["mental_agility"] = float(row.get("mental_agility", 0.50))
			rec["ocean"] = {
				"openness": float(row.get("openness", 0.50)),
				"conscientiousness": float(row.get("conscientiousness", 0.50)),
				"extraversion": float(row.get("extraversion", 0.50)),
				"agreeableness": float(row.get("agreeableness", 0.50)),
				"neuroticism": float(row.get("neuroticism", 0.50))
			}

	ws["organizations"] = {}
	ensure_test_organization(ws, "ORG:CREW_ENTERPRISE", "Crew Enterprise", "", "DIRECT", 1.0)
	return ws

## Persists a canonical organization row in SQLite and syncs it into world_state["organizations"]
static func ensure_test_organization(
	world_state: Dictionary,
	org_id: String,
	display_name: String,
	parent_org_id: String = "",
	autonomy_mode: String = "DIRECT",
	loyalty: float = 1.0,
	police_heat: float = 0.0
) -> void:
	if not world_state.has("organizations") or not (world_state["organizations"] is Dictionary):
		world_state["organizations"] = {}
	world_state["organizations"][org_id] = {
		"org_id": org_id,
		"parent_org_id": parent_org_id,
		"display_name": display_name,
		"autonomy_mode": autonomy_mode,
		"loyalty": loyalty,
		"police_heat": police_heat
	}
	if DB_MANAGER.is_database_open():
		var start_day: int = int(world_state.get("metadata", {}).get("current_sim_day", CalendarHelperScript.get_simulation_start_day()))
		var reason_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
		var parent_sql: String = "'%s'" % parent_org_id.replace("'", "''") if not parent_org_id.is_empty() else "NULL"
		DB_MANAGER.query_rows("""
			INSERT OR REPLACE INTO organizations (
				org_id, parent_org_id, autonomy_mode, display_name, org_type,
				legal_status, institution_rail_class, valid_from, valid_to, change_reason_id
			) VALUES (
				'%s', %s, '%s', '%s', 'SYNDICATE',
				'INFORMAL', 'STANDARD', %d, NULL, %d
			);
		""" % [
			org_id.replace("'", "''"),
			parent_sql,
			autonomy_mode.replace("'", "''"),
			display_name.replace("'", "''"),
			start_day,
			reason_id
		])