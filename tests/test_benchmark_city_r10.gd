# res://tests/test_benchmark_city_r10.gd
extends SceneTree

const CITY_RADIUS: int = 10
const BENCH_SEED: String = "bench-r10-deferred-index"
const BENCH_DB_PATH: String = "user://benchmark_r10.db"

func _initialize() -> void:
	call_deferred("_run_benchmark")

func _run_benchmark() -> void:
	await process_frame

	var gs := ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [BenchmarkR10] GameState autoload unavailable.")
	gs.initialize_fresh_state()
	gs.world_state["metadata"]["active_seed"] = BENCH_SEED

	var gen_cfg: Dictionary = DBManager.get_city_generation_config()
	var mode: String = str(gen_cfg.get("pipeline_mode", "UNKNOWN"))
	print("\n==========================================================================")
	print("   HEADLESS BENCHMARK: RADIUS %d CITY (%s)" % [CITY_RADIUS, mode])
	print("==========================================================================")

	var total_t0: int = Time.get_ticks_msec()
	var mem_start_mb: float = float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)

	# 1. Fresh isolated SQLite DB
	var ok_db: bool = DBManager.initialize_database(true, BENCH_DB_PATH)
	assert(ok_db, "FATAL: [BenchmarkR10] Failed to initialize %s" % BENCH_DB_PATH)

	# 2. Concentric Radial Layout via CustomCityCrafter (no 3D building meshes)
	var city_crafter := CustomCityCrafter.new()
	city_crafter.name = "BenchmarkCityCrafter"
	var base_config: Resource = ScenarioManifestManager.get_city_configuration()
	var config_instance: Resource = base_config.duplicate()
	config_instance.set("city_radius", CITY_RADIUS)
	if "enable_building_spawning" in config_instance:
		config_instance.set("enable_building_spawning", false)
	city_crafter.city_configuration = config_instance
	root.add_child(city_crafter)
	await process_frame

	var t0_streets: int = Time.get_ticks_msec()
	await city_crafter.generate_city_async(BENCH_SEED)
	var streets_ms: int = Time.get_ticks_msec() - t0_streets

	# 3. Ingest Districts
	var t0_districts: int = Time.get_ticks_msec()
	CitySpatialAdapter.ingest_citycrafter_generation(city_crafter, gs.world_state, BENCH_SEED)
	var districts_ms: int = Time.get_ticks_msec() - t0_districts
	var district_count: int = gs.world_state.get("districts", {}).size()

	# 4. Run Society Generation (deferred-index phased pipeline or legacy via business_rules.cfg)
	await SocialNetworkGenerator.generate_city_society(gs.world_state, BENCH_SEED, false)
	var soc_ms: Dictionary = SocialNetworkGenerator.get_last_stage_durations_ms()

	var total_ms: int = Time.get_ticks_msec() - total_t0
	var mem_end_mb: float = float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	var mem_peak_mb: float = float(OS.get_static_memory_peak_usage()) / (1024.0 * 1024.0)

	# 5. Query Final Entity Counts from SQLite
	var counts: Array = SocietyQueries.get_audit_entity_counts(DBManager)

	print("\n==========================================================================")
	print("   BENCHMARK SUMMARY (radius=%d, mode=%s)" % [CITY_RADIUS, mode])
	print("==========================================================================")
	print("  • Districts Generated : %d" % district_count)
	print("  • Streets (Crafter)   : %d ms" % streets_ms)
	print("  • District Ingestion  : %d ms" % districts_ms)
	print("  • Society Premises    : %d ms" % int(soc_ms.get("SOCIETY_PREMISES", 0)))
	print("  • Society Citizens    : %d ms" % int(soc_ms.get("SOCIETY_CITIZENS", 0)))
	print("  • Society Dunbar      : %d ms" % int(soc_ms.get("SOCIETY_DUNBAR", 0)))
	print("  • TOTAL WALL CLOCK    : %d ms (%.2f s)" % [total_ms, float(total_ms) / 1000.0])
	print("  • RAM Start / End     : %.1f MB / %.1f MB" % [mem_start_mb, mem_end_mb])
	print("  • RAM Peak (Static)   : %.1f MB" % mem_peak_mb)
	print("  ------------------------------------------------------------------------")
	for row in counts:
		print("  • %-22s: %d" % [str(row["entity"]), int(row["count"])])
	print("==========================================================================\n")

	# 6. Clean Teardown
	if city_crafter.get_parent():
		city_crafter.get_parent().remove_child(city_crafter)
	city_crafter.free()
	DBManager.close_database()
	quit(0)