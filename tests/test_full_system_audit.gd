# res://tests/test_full_system_audit.gd
extends SceneTree

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CATALOG_VALIDATOR = preload("res://systems/catalog_validator.gd")
const SYSTEM_AUDITOR = preload("res://systems/system_auditor.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")
const PREMISES_BUILDER = preload("res://systems/society/premises_workplace_builder.gd")
const CITIZEN_HYDRATOR = preload("res://systems/society/citizen_demographics_hydrator.gd")
const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")
const VERB_ROUTER = preload("res://systems/verb_router.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       STARTING FULL SYSTEM & CATALOG AUDIT HARNESS    ")
	print("=======================================================")

	# -----------------------------------------------------------------
	# STAGE 1: CATALOG VALIDATOR (Commodities, Recipes & Hierarchy)
	# -----------------------------------------------------------------
	print("\n[STAGE 1] Running Catalog & Hierarchy Validator...")
	VERB_ROUTER.initialize()
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")

	var commodities: Dictionary = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/commodities/")
	var recipes: Dictionary = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/recipes/")

	var world_state := {
		"commodity_registry": commodities,
		"recipe_registry": recipes
	}

	var catalog_report: Dictionary = CATALOG_VALIDATOR.validate_catalogs(world_state, true)
	print("  ✓ Commodities Surfaced: %d" % catalog_report.get("commodity_count", 0))
	print("  ✓ Recipes Surfaced:     %d" % catalog_report.get("recipe_count", 0))
	assert(catalog_report["is_clean"], "FAILED: CatalogValidator found corrupt commodities or recipes!")
	assert(catalog_report["errors"].is_empty(), "FAILED: CatalogValidator emitted unexpected errors!")
	print("  ✓ PASS: Catalog items and recipes are 100% clean.")

	# -----------------------------------------------------------------
	# STAGE 2: CROSS-MANIFEST SOCIETY TAXONOMY & LABELS AUDIT
	# -----------------------------------------------------------------
	print("\n[STAGE 2] Auditing Cross-Manifest Labels & Roster Taxonomies...")
	var society_manifest_report: Dictionary = CATALOG_VALIDATOR.validate_society_manifests()
	print("  ✓ Labels Baseline Scanned: ", society_manifest_report["labels_scanned"])
	print("  ✓ Job Roles Scanned:       ", society_manifest_report["jobs_scanned"])
	print("  ✓ Archetypes Scanned:      ", society_manifest_report["archetypes_scanned"])
	print("  ✓ Tenancies Scanned:       ", society_manifest_report["tenancies_scanned"])

	if not society_manifest_report["errors"].is_empty():
		for err in society_manifest_report["errors"]:
			push_error("  ❌ [Taxonomy Defect]: %s" % err)
	assert(society_manifest_report["is_clean"], "FAILED: Taxonomy/Manifest mismatch detected! Fix missing db_labels before proceeding.")
	print("  ✓ PASS: All job definitions, archetypes, tenancies, and labels cross-resolve cleanly.")

	# -----------------------------------------------------------------
	# STAGE 3: DATABASE GENERATION & RELATIONAL INTEGRITY
	# -----------------------------------------------------------------
	print("\n[STAGE 3] Rebuilding Database & Running Population Passes...")
	var db_ok := DB_MANAGER.initialize_database(true)
	assert(db_ok, "FAILED: DBManager failed to initialize SQLite connection!")

	var archetypes: Dictionary = MANIFEST_MGR.load_module("archetypes")
	var building_classes: Dictionary = MANIFEST_MGR.load_module("building_classes")
	var job_defs: Dictionary = MANIFEST_MGR.load_module("job_definitions").get("roles", {})
	var cultural: Dictionary = MANIFEST_MGR.load_module("cultural_demographics")
	var demographics: Dictionary = MANIFEST_MGR.load_module("demographics")
	var lexicon: Dictionary = MANIFEST_MGR.load_module("lexicon")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1984

	# Controlled multi-district test world
	var test_world := {
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
			"dist_market_parade": {
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
			"dist_foundry_works": {
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

	# Run Pass 2: Workplace & Premises Generation
	var physical_state: Dictionary = await PREMISES_BUILDER.run(
		test_world, archetypes, building_classes, job_defs, cultural, rng, Callable()
	)
	var slots: Array = physical_state.get("available_job_slots", [])
	print("  ✓ Pass 2 Workplace Positions Generated: %d" % slots.size())

	# Run Pass 3: Citizen Demographics & Job Hydration
	await CITIZEN_HYDRATOR.run(
		physical_state, demographics, lexicon, job_defs, rng, Callable()
	)

	# -----------------------------------------------------------------
	# STAGE 4: SYSTEM AUDITOR RUNTIME & RELATIONAL HEALTH CHECK
	# -----------------------------------------------------------------
	print("\n[STAGE 4] Executing SystemAuditor...")
	# Populate population metric on test districts for auditor sanity
	for dist_id in test_world["districts"].keys():
		var res_rows: Array = DB_MANAGER.query_rows(
			"SELECT COUNT(*) AS pop FROM residents r JOIN households h ON r.household_id = h.household_id JOIN establishments e ON h.establishment_id = e.establishment_id WHERE e.district_id = '%s';" % dist_id
		)
		test_world["districts"][dist_id]["population"] = int(res_rows[0]["pop"]) if not res_rows.is_empty() else 0

	var auditor_report: Dictionary = SYSTEM_AUDITOR.audit_generation_health(test_world, DB_MANAGER)
	print("  ✓ Total Districts Audited:    %s" % str(auditor_report["metrics"].get("total_districts", 0)))
	print("  ✓ Total Living Population:    %s" % str(auditor_report["metrics"].get("total_population", 0)))
	print("  ✓ Total Establishments in DB: %s" % str(auditor_report["metrics"].get("total_establishments", 0)))
	print("  ✓ Total Households in DB:     %s" % str(auditor_report["metrics"].get("total_households", 0)))

	assert(auditor_report["is_healthy"], "FAILED: SystemAuditor detected fatal relational defects in SQLite!")

	# -----------------------------------------------------------------
	# STAGE 5: WORKPLACE JOB SLOTS SPECIFIC INTEGRITY
	# -----------------------------------------------------------------
	print("\n[STAGE 5] Checking workplace_job_slots Table & Views...")
	var unlinked_slots: Array = DB_MANAGER.query_rows("""
		SELECT COUNT(*) as count 
		FROM workplace_job_slots 
		WHERE is_filled = 1 AND active_resident_id IS NULL;
	""")
	assert(int(unlinked_slots[0]["count"]) == 0, "FAILED: Found filled job slots with no resident attached!")

	var invalid_worker_slots: Array = DB_MANAGER.query_rows("""
		SELECT COUNT(*) as count 
		FROM workplace_job_slots 
		WHERE active_resident_id IS NOT NULL 
		AND active_resident_id NOT IN (SELECT resident_id FROM residents);
	""")
	assert(int(invalid_worker_slots[0]["count"]) == 0, "FAILED: Job slots reference non-existent resident_id!")

	var view_check: Array = DB_MANAGER.query_rows("SELECT COUNT(*) as count FROM v_workplace_jobs;")
	assert(int(view_check[0]["count"]) > 0, "FAILED: v_workplace_jobs view returned 0 rows!")
	print("  ✓ v_workplace_jobs virtual view query operational.")

	print("\n=======================================================")
	print("     ALL FULL-SYSTEM & AUDIT CHECKS PASSED (100%)      ")
	print("=======================================================\n")
	quit()