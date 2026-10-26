# res://tests/test_social_network.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("    TESTING LIVING SOCIETY AT SCALE (40 DISTRICTS)    ")
	print("=======================================================")

	# 1. Procedurally construct an 8x5 grid (40 districts) with concentric urban zoning
	var mock_world: Dictionary = {"districts": {}}
	var grid_w := 8
	var grid_h := 5
	var center_x := 3.5
	var center_y := 2.0

	var street_names := [
		"Corporation St", "High St", "Broad St", "Bull Ring", "New St",
		"St. Jude's", "Victoria Terraces", "Albert Rd", "Gravelly Hill", "Soho Hill",
		"Aston Rd", "Foundry Lane", "Tyburn Works", "Canal Basin", "Depot Yard",
		"Birchfield Tower", "Parkview Estate", "St. Luke's Mount", "Clarendon Rise",
		"Kings Heath", "Moseley Green", "Selly Oak", "Edgbaston Park", "Harborne Gate"
	]

	var name_idx := 0

	for gy in range(grid_h):
		for gx in range(grid_w):
			var dist_id := "block_%d_%d" % [gx, gy]
			var dx: float = float(gx) - center_x
			var dy: float = float(gy) - center_y
			var dist_from_center: float = sqrt(dx * dx + dy * dy) # 0.0 to ~4.0

			# Authentic 1980s UK Concentric Zoning:
			# - Core (r <= 1.2): Commercial High Streets & Civic Parcels
			# - Inner Ring (1.2 < r <= 2.5): Victorian Terraces & Municipal High-Rise Estates
			# - Eastern / Canal Flank: Industrial Works & Rail Depots
			# - Outer Ring (r > 2.5): Suburban Commuter Semi-Detached
			var dtype := "suburban_low_density"
			var unemp := 0.08

			if dist_from_center <= 1.2:
				dtype = "commercial"
				unemp = 0.10
			elif gx >= 6: # Eastern industrial transit corridor
				dtype = "industrial"
				unemp = 0.22
			elif dist_from_center <= 2.6:
				if (gx + gy) % 3 == 0:
					dtype = "high_density_high_rise"
					unemp = 0.35
				else:
					dtype = "high_density_low_rise"
					unemp = 0.18
			else:
				dtype = "suburban_low_density"
				unemp = 0.06

			var disp_name: String = street_names[name_idx % street_names.size()]
			name_idx += 1

			# Real-world 200m x 200m standard spatial anchor (origin at 0,0)
			var world_pos := Vector2(float(gx - 4) * 200.0, float(gy - 2) * 200.0)

			mock_world["districts"][dist_id] = {
				"district_id": dist_id,
				"display_name": disp_name,
				"district_type": dtype,
				"grid_coords": Vector2i(gx, gy),
				"grid_size": Vector2i(1, 1),
				"spatial_anchor": world_pos,
				"unemployment_rate": unemp
			}

	print("  ✓ Procedurally generated 40 mock districts across concentric urban rings.")

	# 2. Force Regenerate Fresh Database
	var start_ms: int = Time.get_ticks_msec()
	SOCIAL_NETWORK_GENERATOR.generate_city_society(mock_world, "scale-test-seed-40", true)
	var elapsed_ms: int = Time.get_ticks_msec() - start_ms
	print("  ✓ 40-District Society generated in %d ms." % elapsed_ms)

	# 3. Core Relational Counts
	var total_districts: int = _query_count("districts")
	var total_boroughs: int = _query_count("boroughs")
	var total_estabs: int = _query_count("establishments")
	var total_households: int = _query_count("households")
	var total_residents: int = _query_count("residents")
	var total_contracts: int = _query_count("livelihood_contracts")
	var total_edges: int = _query_count("social_relationships")

	print("\n--- [DATABASE ENTITY TOTALS (40 DISTRICTS)] ---")
	print("  • Districts:           %d" % total_districts)
	print("  • Municipal Wards:     %d" % total_boroughs)
	print("  • Total Establishments:%d (Units, civic, retail, industrial)" % total_estabs)
	print("  • Active Households:   %d" % total_households)
	print("  • Living Residents:    %d" % total_residents)
	print("  • Contracts:           %d" % total_contracts)
	print("  • Dunbar Social Edges: %d" % total_edges)

	# Invariants
	assert(total_districts == 40, "FAILED: Expected exactly 40 districts!")
	assert(total_boroughs >= 1, "FAILED: Borough clustering failed!")
	assert(total_estabs >= total_households, "FAILED: Establishments count must encompass all households!")
	assert(total_contracts == total_residents, "FAILED: 100% of citizens must hold a livelihood contract!")
	assert(total_edges >= (total_residents * 2), "FAILED: Relationship network underpopulated!")

	# 4. Civic Cadence Audit
	print("\n--- [CIVIC & CADENCE INSTITUTION AUDIT] ---")
	var civic_counts = DB_MANAGER.query_rows("""
		SELECT l.code AS category, COUNT(e.establishment_id) AS facility_count
		FROM establishments e
		JOIN system_labels l ON e.category_id = l.label_id
		WHERE l.code IN ('PRIMARY_SCHOOL', 'SECONDARY_SCHOOL', 'PLACE_OF_WORSHIP', 'JOBCENTRE', 'COMMUNITY_CENTRE', 'ALLOTMENTS')
		GROUP BY l.code;
	""")
	if civic_counts.is_empty():
		print("  ⚠ Notice: Zero cadence facilities spawned (check quotas).")
	else:
		for row in civic_counts:
			print("  • %-22s: %d facilities placed on map" % [row["category"], row["facility_count"]])

	# 5. Workplace Staffing Range Audit (True Employees on the Books)
	print("\n--- [WORKPLACE STAFFING RANGE AUDIT] ---")
	var workplace_staff_stats = DB_MANAGER.query_rows("""
		SELECT 
			e.establishment_id,
			e.name,
			l.code AS category,
			COUNT(c.resident_id) AS staff_count
		FROM establishments e
		JOIN system_labels l ON e.category_id = l.label_id
		JOIN livelihood_contracts c ON c.employer_entity_id = ('ESTAB_' || e.establishment_id)
		JOIN system_labels c_cls ON c.contract_class_id = c_cls.label_id
		WHERE l.code NOT IN ('RESIDENTIAL_UNIT')
		  AND c_cls.code = 'FORMAL_LEGAL'
		GROUP BY e.establishment_id
		ORDER BY staff_count DESC
		LIMIT 10;
	""")

	for wp in workplace_staff_stats:
		print("  • Workplace #%-4d [%-24s] (%-16s): %2d staff members" % [
			wp["establishment_id"], wp["name"], wp["category"], wp["staff_count"]
		])
		assert(int(wp["staff_count"]) <= 45, "FAILED: Business staffing exceeded physical bounds!")

	# 6. Verify SQLite Virtual Views
	print("\n--- [TESTING SQLITE VIRTUAL VIEWS] ---")
	var census = DB_MANAGER.query_rows("SELECT * FROM v_district_census LIMIT 3;")
	assert(not census.is_empty(), "FAILED: v_district_census returned 0 rows!")
	for c in census:
		print("  • Ward Census [%s]: %d homes | %d residents | %d formal workers | %d claimants" % [
			c["district_name"], c["total_households"], c["total_residents"],
			c["formally_employed_count"], c["street_informal_count"]
		])

	var contracts_sample = DB_MANAGER.query_rows("""
		SELECT full_name, employer_name, contract_class_title, role_title, weekly_hours, compensation_rate
		FROM v_active_contracts
		LIMIT 3;
	""")
	assert(not contracts_sample.is_empty(), "FAILED: v_active_contracts returned 0 rows!")
	for c in contracts_sample:
		print("  • Contract: %-20s -> %-22s | %-16s | £%.2f/wk" % [
			c["full_name"], c["employer_name"], c["role_title"], (c["weekly_hours"] * c["compensation_rate"])
		])

	print("\n=======================================================")
	print("    ALL 40-DISTRICT AT-SCALE TESTS COMPLETED!         ")
	print("=======================================================")
	quit()

func _query_count(table_name: String) -> int:
	var rows = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM %s;" % table_name)
	if rows.is_empty():
		return 0
	return int(rows[0]["count"])
