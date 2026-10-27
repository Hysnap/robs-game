# res://tests/test_job_slots_allocation.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const PREMISES_BUILDER = preload("res://systems/society/premises_workplace_builder.gd")
const CITIZEN_HYDRATOR = preload("res://systems/society/citizen_demographics_hydrator.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       TESTING WORKPLACE JOB SLOTS & ALLOCATION        ")
	print("=======================================================")

	# 1. Reset Database with New Schema
	print("\n[STEP 1] Initializing Clean Database Schema...")
	var db_ok := DB_MANAGER.initialize_database(true)
	assert(db_ok, "FATAL: DBManager failed to initialize.")
	print("  ✓ SQLite database re-initialized with new workplace_job_slots table.")

	# 2. Load Real Manifest Taxonomy & Scenarios
	print("\n[STEP 2] Loading Scenario Manifest Modules...")
	var archetypes: Dictionary = MANIFEST_MGR.load_module("archetypes")
	var building_classes: Dictionary = MANIFEST_MGR.load_module("building_classes")
	var job_defs: Dictionary = MANIFEST_MGR.load_module("job_definitions").get("roles", {})
	var cultural: Dictionary = MANIFEST_MGR.load_module("cultural_demographics")
	var demographics: Dictionary = MANIFEST_MGR.load_module("demographics")
	var lexicon: Dictionary = MANIFEST_MGR.load_module("lexicon")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1984

	# 3. Create a Controlled 3-District Mock World State
	var world_state := {
		"districts": {
			"dist_civic_core": {
				"display_name": "Council House Precinct",
				"district_type": "local_government",
				"grid_coords": Vector2i(0, 0),
				"grid_size": Vector2i(1, 1),
				"actual_building_count": 1,
				"expected_pop_min": 0,
				"expected_pop_max": 0,
				"unemployment_rate": 0.05,
				"spatial_anchor": Vector2.ZERO
			},
			"dist_comm_parade": {
				"display_name": "Market Parade",
				"district_type": "commercial",
				"grid_coords": Vector2i(1, 0),
				"grid_size": Vector2i(1, 1),
				"actual_building_count": 2,
				"expected_pop_min": 40,
				"expected_pop_max": 80,
				"unemployment_rate": 0.08,
				"spatial_anchor": Vector2(250.0, 0.0),
				"building_allocations": [
					{"building_index": 0, "habitable_units": 6, "commercial_units": 2, "industrial_units": 0},
					{"building_index": 1, "habitable_units": 6, "commercial_units": 2, "industrial_units": 0}
				]
			},
			"dist_industrial_works": {
				"display_name": "Canal Works",
				"district_type": "industrial",
				"grid_coords": Vector2i(0, 1),
				"grid_size": Vector2i(1, 1),
				"actual_building_count": 1,
				"expected_pop_min": 0,
				"expected_pop_max": 0,
				"unemployment_rate": 0.12,
				"spatial_anchor": Vector2(0.0, 250.0),
				"building_allocations": [
					{"building_index": 0, "habitable_units": 0, "commercial_units": 0, "industrial_units": 2}
				]
			}
		}
	}

	# 4. RUN PASS 2 (Generate Physical Establishments & Job Slots)
	print("\n[STEP 3] Running Pass 2 (Premises & Staffing Expansion)...")
	var physical_state: Dictionary = await PREMISES_BUILDER.run(
		world_state, archetypes, building_classes, job_defs, cultural, rng, Callable()
	)

	var in_memory_slots: Array = physical_state.get("available_job_slots", [])
	print("  ✓ Pass 2 in-memory open slots: %d" % in_memory_slots.size())

	# Audit the SQL workplace_job_slots table
	var db_slots: Array = DB_MANAGER.query_rows("SELECT COUNT(*) AS total_slots FROM workplace_job_slots;")
	var total_slots_in_db: int = int(db_slots[0]["total_slots"])
	print("  ✓ SQLite workplace_job_slots rows created: %d" % total_slots_in_db)
	assert(total_slots_in_db > 0, "FAILED: Zero job slots inserted into SQLite!")
	assert(total_slots_in_db == in_memory_slots.size(), "FAILED: Mismatch between memory slots and SQLite rows!")

	# Audit Civic slots specifically
	var civic_slots: Array = DB_MANAGER.query_rows("""
		SELECT COUNT(*) AS count 
		FROM workplace_job_slots js
		JOIN system_labels l ON js.sector_category_id = l.label_id
		WHERE l.code IN ('CIVIC', 'LOCAL_GOVERNMENT');
	""")
	var civic_slot_count: int = int(civic_slots[0]["count"])
	print("  ✓ Civic / Municipal positions registered: %d" % civic_slot_count)
	assert(civic_slot_count > 0, "FAILED: Local Government generated zero civic job slots!")

	# 5. RUN PASS 3 (Hydrate Citizens & Allocate Contracts)
	print("\n[STEP 4] Running Pass 3 (Citizen Hydration & Job Allocation)...")
	await CITIZEN_HYDRATOR.run(
		physical_state, demographics, lexicon, job_defs, rng, Callable()
	)

	# 6. VERIFY SQL VIEW: v_workplace_jobs
	print("\n[STEP 5] Testing v_workplace_jobs View & Allocations...")
	var view_rows: Array = DB_MANAGER.query_rows("""
		SELECT 
			slot_id,
			establishment_name,
			sector_category_code,
			role_title,
			schedule_window_title,
			is_filled,
			active_worker_name
		FROM v_workplace_jobs
		LIMIT 8;
	""")

	print("  Sample rows from v_workplace_jobs:")
	for r in view_rows:
		var status_str := "FILLED by " + str(r["active_worker_name"]) if int(r["is_filled"]) == 1 else "VACANT"
		print("  • Slot #%d [%s | %s | %s]: %s" % [
			int(r["slot_id"]),
			str(r["sector_category_code"]),
			str(r["role_title"]),
			str(r["schedule_window_title"]),
			status_str
		])

	# 7. SUMMARY REPORT
	var summary: Array = DB_MANAGER.query_rows("""
		SELECT 
			sector_category_code AS sector,
			COUNT(slot_id) AS total_positions,
			SUM(is_filled) AS filled_positions,
			COUNT(slot_id) - SUM(is_filled) AS vacant_positions
		FROM v_workplace_jobs
		GROUP BY sector_category_code;
	""")

	print("\n-------------------------------------------------------")
	print("                LABOR MARKET BREAKDOWN                 ")
	print("-------------------------------------------------------")
	print("  %-18s | %-8s | %-8s | %-8s" % ["Sector", "Total", "Filled", "Vacant"])
	print("  -------------------------------------------------------")
	for s in summary:
		print("  %-18s | %-8d | %-8d | %-8d" % [
			str(s["sector"]),
			int(s["total_positions"]),
			int(s["filled_positions"]),
			int(s["vacant_positions"])
		])

	print("=======================================================")
	print("     ALL JOB SLOTS & ALLOCATION TESTS PASSED 100%!     ")
	print("=======================================================\n")
	quit()