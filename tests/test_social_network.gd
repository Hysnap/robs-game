# res://tests/test_social_network.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("        TESTING SQLITE LIVING SOCIETY GENERATOR        ")
	print("=======================================================")

	# 1. Mock 4 Districts with authentic population & sectors
# 1. Mock 3 Districts (Physical Building & Unit Model)
	var mock_world = {
		"districts": {
			"block_0_0": {
				"district_type": "high_density_low_rise",
				"grid_size": Vector2i(1, 1),
				"unemployment_rate": 0.14
			},
			"block_0_1": {
				"district_type": "commercial",
				"grid_size": Vector2i(1, 1),
				"unemployment_rate": 0.08
			},
			"block_1_0": {
				"district_type": "industrial",
				"grid_size": Vector2i(1, 1),
				"unemployment_rate": 0.20
			}
		}
	}

	# 2. Run Generation (Force rebuild to test schema and view migrations cleanly)
	SOCIAL_NETWORK_GENERATOR.generate_city_society(mock_world, "test-seed-1984", true)

	# 3. Query Macro Relational Totals
	var total_residents: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM residents;")[0]["count"])
	var total_households: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM households;")[0]["count"])
	var total_estabs: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM establishments;")[0]["count"])
	var total_contracts: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM livelihood_contracts;")[0]["count"])
	var total_edges: int = int(DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM social_relationships;")[0]["count"])

	print("  ✓ Verification: Ingested %d residents across %d households." % [total_residents, total_households])
	print("  ✓ Verification: Ingested %d normalized establishments." % total_estabs)
	print("  ✓ Verification: Created %d active livelihood contracts." % total_contracts)
	print("  ✓ Verification: Established %d relationship ties." % total_edges)

	assert(total_residents > 100 and total_residents <=300, "FAILED: Resident population count incorrect!")
	assert(total_households > 40 and total_households <= 100, "FAILED: Household count incorrect!")
	assert(total_estabs > 50, "FAILED: Establishments missing!")
	assert(total_contracts == total_residents, "FAILED: every resident must have a contract")
	assert(total_edges > 500, "FAILED: Relationship edges missing!")

	# 4. Verify Institutional Establishment Breakdown via Virtual View
	print("\n--- [ESTABLISHMENTS BREAKDOWN] ---")
	var cat_counts = DB_MANAGER.query_rows("""
		SELECT category_title, COUNT(*) as count, SUM(capacity) as total_capacity
		FROM v_establishments_overview
		GROUP BY category_title
		ORDER BY count DESC;
	""")
	assert(not cat_counts.is_empty(), "FAILED: v_establishments_overview returned empty!")
	for row in cat_counts:
		print("  • %-22s: %4d facilities (Capacity: %d)" % [row["category_title"], row["count"], row["total_capacity"]])

	# 5. Verify Virtual Views (Town Planner & Citizen Dossier)
	print("\n--- [TESTING SQLITE VIRTUAL VIEWS] ---")
	var census_rows = DB_MANAGER.query_rows("SELECT * FROM v_district_census LIMIT 4;")
	assert(census_rows.size() == 3, "FAILED: v_district_census returned empty!")
	print("  ✓ v_district_census Sample (Block 0,0):", census_rows[0])

	var res_rows = DB_MANAGER.query_rows("""
		SELECT resident_id, first_name, current_surname, formatted_birth_date, education_title, ethnicity_title, religion_title
		FROM v_residents_overview
		LIMIT 3;
	""")
	assert(res_rows.size() == 3, "FAILED: v_residents_overview returned empty!")
	for r in res_rows:
		print("  • Citizen #%d: %s %s | Born: %s | Edu: %s | Eth: %s | Rel: %s" % [
			r["resident_id"], r["first_name"], r["current_surname"],
			r["formatted_birth_date"], r["education_title"], r["ethnicity_title"], r["religion_title"]
		])

	# 6. Verify Active Livelihood Contracts
	print("\n--- [SAMPLE LIVELIHOOD CONTRACTS] ---")
	var contracts_sample = DB_MANAGER.query_rows("""
		SELECT full_name, employer_name, contract_class_title, role_title, contract_start_date
		FROM v_active_contracts
		LIMIT 3;
	""")
	assert(contracts_sample.size() == 3, "FAILED: v_active_contracts returned empty!")
	for c in contracts_sample:
		print("  • %s -> %s [%s: %s] (Started: %s)" % [
			c["full_name"], c["employer_name"], c["contract_class_title"], c["role_title"], c["contract_start_date"]
		])

	# 7. Verify CalendarHelper Date Conversion
	var sample_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var formatted_date: String = CALENDAR_HELPER.day_to_calendar_date(sample_day)
	print("\n  ✓ CalendarHelper Verification: Day offset %d formatted as '%s'" % [sample_day, formatted_date])
	assert(not formatted_date.is_empty() and formatted_date != "Unknown Date", "FAILED: CalendarHelper formatting error!")

	print("\n=======================================================")
	print("      ALL NORMALIZED SOCIETY & DB TESTS PASSED!        ")
	print("=======================================================\n")
	quit()