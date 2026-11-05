# res://tests/test_society_factory.gd
class_name TestSocietyFactory
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")

## Generates a schema-compliant mock city and living society in SQLite for headless tests.
## Returns a standard world_state dictionary ready for simulation execution.
static func create_test_world(grid_w: int = 2, grid_h: int = 2, seed_id: String = "test-factory-seed") -> Dictionary:
	var mock_world: Dictionary = {"districts": {}}
	var start_sim_day: int = 29219 # 1980-01-01

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
		"player_knowledge": {
			"home_district_id": chosen_district
		},
		"districts": mock_world["districts"],
		"staff": {}
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