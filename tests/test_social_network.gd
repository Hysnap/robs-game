# res://tests/test_social_network.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("        TESTING SQLITE LIVING SOCIETY GENERATOR        ")
	print("=======================================================")

	# 1. Mock 4 Typical District Types (Physical Building & Unit Model)
	var mock_world = {
		"districts": {
			"block_0_0": {
				"display_name": "St. Jude's Terraces",
				"district_type": "high_density_low_rise",
				"grid_coords": Vector2i(0, 0),
				"grid_size": Vector2i(1, 1),
				"unemployment_rate": 0.14
			},
			"block_0_1": {
				"display_name": "Corporation Street Parade",
				"district_type": "commercial",
				"grid_coords": Vector2i(0, 1),
				"grid_size": Vector2i(1, 1),
				"unemployment_rate": 0.08
			},
			"block_1_0": {
				"display_name": "Soho Foundry & Works",
				"district_type": "industrial",
				"grid_coords": Vector2i(1, 0),
				"grid_size": Vector2i(1, 1),
				"unemployment_rate": 0.20
			},
			"block_1_1": {
				"display_name": "Birchfield Tower Estate",
				"district_type": "high_density_high_rise",
				"grid_coords": Vector2i(1, 1),
				"grid_size": Vector2i(1, 1),
				"unemployment_rate": 0.18
			}
		}
	}

	# 2. Force Regenerate Fresh Database
	var start_ms: int = Time.get_ticks_msec()
	SOCIAL_NETWORK_GENERATOR.generate_city_society(mock_world, "test-seed-1984", true)
	var elapsed_ms: int = Time.get_ticks_msec() - start_ms
	print("  ✓ Generation executed in %d ms." % elapsed_ms)

	# 3. Core Relational Counts
	var total_districts: int = _query_count("districts")
	var total_boroughs: int = _query_count("boroughs")
	var total_estabs: int = _query_count("establishments")
	var total_households: int = _query_count("households")
	var total_residents: int = _query_count("residents")
	var total_contracts: int = _query_count("livelihood_contracts")
	var total_edges: int = _query_count("social_relationships")

	print("\n--- [DATABASE ENTITY TOTALS] ---")
	print("  • Districts:           %d" % total_districts)
	print("  • Boroughs:            %d (Retrospective clustering pending)" % total_boroughs)
	print("  • Establishments:      %d (Physical units & venues)" % total_estabs)
	print("  • Households:          %d (Active tenancies)" % total_households)
	print("  • Living Residents:    %d" % total_residents)
	print("  • Contracts:           %d" % total_contracts)
	print("  • Relationship Edges:  %d" % total_edges)

	# Invariant Assertions
	assert(total_districts == 4, "FAILED: Expected exactly 4 districts in SQLite!")
	assert(total_estabs >= total_households, "FAILED: Every household must have a matching physical establishment unit!")
	assert(total_contracts == total_residents, "FAILED: 100% of citizens must have a contract (work, school, dole, or pension)!")
	assert(total_edges >= total_residents, "FAILED: Social relationships must at least cover immediate kin and peers!")

	# 4. District Physical Geometry & Building Audit
	print("\n--- [DISTRICT BUILDING & TENANCY AUDIT] ---")
	var district_audit = DB_MANAGER.query_rows("""
		SELECT 
			d.district_id,
			d.display_name,
			d.district_type,
			d.target_building_count,
			COUNT(DISTINCT e.building_index) AS actual_bldgs,
			COUNT(DISTINCT e.establishment_id) AS total_doors,
			COUNT(DISTINCT CASE WHEN e.category_id = (SELECT label_id FROM system_labels WHERE domain = 'ESTABLISHMENT_CATEGORY' AND code = 'RESIDENTIAL_UNIT') THEN e.establishment_id END) AS residential_flats,
			COUNT(DISTINCT h.household_id) AS occupied_households,
			COUNT(DISTINCT r.resident_id) AS citizens
		FROM districts d
		LEFT JOIN establishments e ON d.district_id = e.district_id
		LEFT JOIN households h ON e.establishment_id = h.establishment_id
		LEFT JOIN residents r ON h.household_id = r.household_id
		GROUP BY d.district_id
		ORDER BY d.district_id;
	""")

	for row in district_audit:
		print("  • [%s] %s (%s):" % [row["district_id"], row["display_name"], row["district_type"]])
		print("    - Target Bldgs: %d | Actual Physical Bldgs: %d" % [row["target_building_count"], row["actual_bldgs"]])
		print("    - Units/Doors:  %d (Flats: %d, Occupied: %d) | Citizens: %d" % [
			row["total_doors"], row["residential_flats"], row["occupied_households"], row["citizens"]
		])
		# Verify high-rise does not roll runaway towers
		if row["district_type"] == "high_density_high_rise":
			assert(row["actual_bldgs"] <= 3, "FAILED: High-rise generated too many towers (%d)!" % row["actual_bldgs"])
			assert(row["residential_flats"] >= 10, "FAILED: Tower block should contain multiple flats!")

	# 5. Verify Virtual Views
	print("\n--- [TESTING SQLITE VIRTUAL VIEWS] ---")
	
	# View 1: v_district_census
	var census = DB_MANAGER.query_rows("SELECT * FROM v_district_census LIMIT 2;")
	assert(not census.is_empty(), "FAILED: v_district_census returned 0 rows!")
	print("  ✓ v_district_census active: %d districts summarized." % census.size())

	# View 2: v_residents_overview
	var res_sample = DB_MANAGER.query_rows("""
		SELECT resident_id, first_name, current_surname, formatted_birth_date, education_title, ethnicity_title, religion_title
		FROM v_residents_overview
		LIMIT 2;
	""")
	assert(not res_sample.is_empty(), "FAILED: v_residents_overview returned 0 rows!")
	for r in res_sample:
		print("  • Citizen #%d: %s %s | Born: %s | Edu: %s | Eth: %s" % [
			r["resident_id"], r["first_name"], r["current_surname"],
			r["formatted_birth_date"], r["education_title"], r["ethnicity_title"]
		])

	# View 3: v_active_contracts
	var contracts_sample = DB_MANAGER.query_rows("""
		SELECT full_name, employer_name, contract_class_title, role_title, weekly_hours, compensation_rate
		FROM v_active_contracts
		LIMIT 2;
	""")
	assert(not contracts_sample.is_empty(), "FAILED: v_active_contracts returned 0 rows!")
	for c in contracts_sample:
		print("  • Contract: %s -> %s (%s, £%.2f/wk)" % [
			c["full_name"], c["employer_name"], c["role_title"], (c["weekly_hours"] * c["compensation_rate"])
		])

	# View 4: v_households_overview
	var hh_sample = DB_MANAGER.query_rows("""
		SELECT household_id, district_name, residence_type_title, dominant_ethnicity_title
		FROM v_households_overview
		LIMIT 2;
	""")
	assert(not hh_sample.is_empty(), "FAILED: v_households_overview returned 0 rows!")
	for h in hh_sample:
		print("  • Tenancy #%d: %s | Home Type: %s | Ethnicity: %s" % [
			h["household_id"], h["district_name"], h["residence_type_title"], h["dominant_ethnicity_title"]
		])

	# 6. Verify Calendar Translation
	var start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var formatted_start: String = CALENDAR_HELPER.day_to_calendar_date(start_day)
	print("\n  ✓ CalendarHelper Verification: Day offset %d formatted as '%s'" % [start_day, formatted_start])
	assert(not formatted_start.is_empty(), "FAILED: Calendar date translation failed!")

	print("\n=======================================================")
	print("       ALL DATABASE & GENERATION TESTS PASSED!         ")
	print("=======================================================\n")
	quit()

func _query_count(table_name: String) -> int:
	var rows = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM %s;" % table_name)
	if rows.is_empty():
		return 0
	return int(rows[0]["count"])