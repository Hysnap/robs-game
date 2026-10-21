# res://tests/test_social_network.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("        TESTING SQLITE LIVING SOCIETY GENERATOR        ")
	print("=======================================================")

	# 1. Mock 3 Districts with authentic population & sectors
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
			}
		}
	}

	# 2. Run Generation Pass
	SOCIAL_NETWORK_GENERATOR.generate_city_society(mock_world, "test-seed-1984")

	# 3. Query Database Macro Totals
	var total_residents: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM residents;")[0]["count"]
	var total_households: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM households;")[0]["count"]
	var total_workplaces: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM workplaces;")[0]["count"]
	var total_edges: int = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM social_relationships;")[0]["count"]

	print("  ✓ Verification: Ingested %d residents across %d households." % [total_residents, total_households])
	print("  ✓ Verification: Ingested %d commercial & industrial workplaces." % total_workplaces)
	print("  ✓ Verification: Established %d relationship ties." % total_edges)

	assert(total_residents > 3000, "FAILED: Resident population count incorrect!")
	assert(total_households > 1000, "FAILED: Household count incorrect!")
	assert(total_workplaces > 5, "FAILED: Workplaces missing!")
	assert(total_edges > 6000, "FAILED: Relationship edges missing!")

	# 4. Verify 1980s Statutory Demographics & Cohorts
	var demo_stats = DB_MANAGER.query_rows("""
		SELECT 
			COUNT(CASE WHEN occupation_type = 'CHILD' THEN 1 END) as total_children,
			COUNT(CASE WHEN occupation_type = 'STUDENT' THEN 1 END) as total_students,
			COUNT(CASE WHEN occupation_type IN ('COMMERCIAL_SERVICE', 'MANUAL_WORKS', 'GENERAL_LABOUR') THEN 1 END) as total_workers,
			COUNT(CASE WHEN occupation_type = 'UNEMPLOYED' THEN 1 END) as total_unemployed,
			COUNT(CASE WHEN occupation_type = 'PENSIONER' THEN 1 END) as total_pensioners,
			COUNT(*) as total_pop
		FROM residents;
	""")[0]

	var pct_pensioners: float = (float(demo_stats["total_pensioners"]) / float(demo_stats["total_pop"])) * 100.0
	var pct_children: float = (float(demo_stats["total_children"]) / float(demo_stats["total_pop"])) * 100.0
	var pct_workers: float = (float(demo_stats["total_workers"]) / float(demo_stats["total_pop"])) * 100.0
	var pct_unemp: float = (float(demo_stats["total_unemployed"]) / float(demo_stats["total_pop"])) * 100.0

	print("\n--- [DEMOGRAPHIC COHORTS] ---")
	print("  • Children (Under 16):       %d (%.1f%%)" % [demo_stats["total_children"], pct_children])
	print("  • Active Workforce:          %d (%.1f%%)" % [demo_stats["total_workers"], pct_workers])
	print("  • Benefit Claimants:         %d (%.1f%%)" % [demo_stats["total_unemployed"], pct_unemp])
	print("  • Pensioners (60F / 65M):    %d (%.1f%%)" % [demo_stats["total_pensioners"], pct_pensioners])

	assert(pct_pensioners >= 10.0 and pct_pensioners <= 22.0, "FAILED: Pensioner percentage out of 1980s historical bounds!")
	assert(pct_children >= 15.0 and pct_children <= 30.0, "FAILED: Child percentage out of historical bounds!")

	# 5. Verify Cultural & Ethnic Mix Ingestion
	print("\n--- [ETHNIC & RELIGIOUS DIVERSITY] ---")
	var ethnic_counts = DB_MANAGER.query_rows("""
		SELECT ethnicity, COUNT(*) as count 
		FROM households 
		GROUP BY ethnicity 
		ORDER BY count DESC;
	""")
	for row in ethnic_counts:
		var pct = (float(row["count"]) / float(total_households)) * 100.0
		print("  • %-16s: %4d households (%.1f%%)" % [row["ethnicity"], row["count"], pct])
	assert(ethnic_counts.size() >= 3, "FAILED: Ethnic diversity pool failed to populate multiple groups!")

	# 6. Verify Pass 5 Faith & Parish Social Ties
	var parish_ties = DB_MANAGER.query_rows("""
		SELECT r1.first_name || ' ' || r1.surname as person_1,
		       r2.first_name || ' ' || r2.surname as person_2,
		       r1.ethnicity, r1.religion, sr.affinity_score
		FROM social_relationships sr
		JOIN residents r1 ON sr.from_resident_id = r1.resident_id
		JOIN residents r2 ON sr.to_resident_id = r2.resident_id
		WHERE sr.relationship_type = 'COMMUNITY_PARISH'
		LIMIT 2;
	""")
	print("\n--- [SAMPLE COMMUNITY & PARISH TIES] ---")
	for tie in parish_ties:
		print("  • %s and %s share %s parish circle (%s) [Affinity: %.2f]" % [
			tie["person_1"], tie["person_2"], tie["religion"], tie["ethnicity"], tie["affinity_score"]
		])
	assert(parish_ties.size() > 0, "FAILED: Community/Parish relationship edges missing!")

	print("\n=======================================================")
	print("      ALL SOCIETY & DEMOGRAPHIC SUITES PASSED!         ")
	print("=======================================================\n")
	quit()