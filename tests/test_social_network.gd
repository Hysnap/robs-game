# res://tests/test_social_network.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("        TESTING SQLITE LIVING SOCIETY GENERATOR        ")
	print("=======================================================")

	# Mock 4 Districts with authentic population & sectors
	var mock_world = {
		"districts": {
			"block_0_0": {
				"population": 1200,
				"district_type": "high_density_low_rise",
				"unemployment_rate": 0.14,
				"venues": {"VENUE_THE_CROWN": {}}
			},
			"block_0_1": {
				"population": 1800,
				"district_type": "commercial",
				"unemployment_rate": 0.08,
				"venues": {"VENUE_BLACKTHORN": {}}
			},
			"block_1_0": {
				"population": 400,
				"district_type": "industrial",
				"unemployment_rate": 0.20,
				"venues": {"VENUE_ROYAL_OAK": {}}
			},
			"block_1_1": {
				"population": 600,
				"district_type": "suburban_low_density",
				"unemployment_rate": 0.06,
				"venues": {"VENUE_THE_PLOUGH": {}}
			}
		}
	}

	# Run Generation
	SOCIAL_NETWORK_GENERATOR.generate_city_society(mock_world, "test-seed-1984")

	# Query Database Macro Totals
	var total_residents: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM residents;")[0]["count"]
	var total_households: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM households;")[0]["count"]
	var total_estabs: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM establishments;")[0]["count"]
	var total_edges: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM social_relationships;")[0]["count"]

	print("  ✓ Verification: Ingested %d residents across %d households." % [total_residents, total_households])
	print("  ✓ Verification: Ingested %d total establishments." % total_estabs)
	print("  ✓ Verification: Established %d relationship ties." % total_edges)

	assert(total_residents > 3500, "FAILED: Resident population count incorrect!")
	assert(total_households > 1200, "FAILED: Household count incorrect!")
	assert(total_estabs > 5, "FAILED: Establishments missing!")
	assert(total_edges > 6000, "FAILED: Relationship edges missing!")

	# Check Zero NULL Foreign Keys in residents
	var null_check = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM residents WHERE establishment_id IS NULL OR establishment_id = 0;")[0]["count"]
	print("  ✓ Verification: Zero NULL or 0 establishment references found (%d nulls)." % null_check)
	assert(null_check == 0, "FAILED: Found residents with unassigned establishments!")

	# Print Institutional Breakdown
	print("\n--- [ESTABLISHMENTS BREAKDOWN] ---")
	var cat_counts = DB_MANAGER.query_rows("""
		SELECT category, COUNT(*) as count 
		FROM establishments 
		GROUP BY category 
		ORDER BY count DESC;
	""")
	for row in cat_counts:
		print("  • %-18s: %4d facilities" % [row["category"], row["count"]])

	# Verify Civic Peers (e.g. classmates, dole queue, post office)
	var peer_sample = DB_MANAGER.query_rows("""
		SELECT r1.first_name || ' ' || r1.surname as person_1,
		       r2.first_name || ' ' || r2.surname as person_2,
		       e.name, e.category
		FROM social_relationships sr
		JOIN residents r1 ON sr.from_resident_id = r1.resident_id
		JOIN residents r2 ON sr.to_resident_id = r2.resident_id
		JOIN establishments e ON r1.establishment_id = e.establishment_id
		WHERE sr.relationship_type = 'CIVIC_PEER'
		LIMIT 3;
	""")
	print("\n--- [SAMPLE CIVIC PEER TIES] ---")
	for p in peer_sample:
		print("  • %s and %s share anchor: %s [%s]" % [p["person_1"], p["person_2"], p["name"], p["category"]])

	print("\n=======================================================")
	print("      ALL INSTITUTIONAL & CIVIC TESTS PASSED!          ")
	print("=======================================================\n")
	quit()