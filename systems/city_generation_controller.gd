# res://systems/city_generation_controller.gd
class_name CityGenerationController
extends RefCounted

const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")
const GENERATION_TELEMETRY = preload("res://systems/generation_telemetry.gd")

signal progress_updated(percent: float, stage_title: String, detail_text: String)
signal generation_completed(target_slot_id: String)
signal generation_failed(error_message: String)

## Executes the complete city generation lifecycle
static func run_pipeline(
	gen_seed: String, 
	target_slot_id: String, 
	settings_override: Dictionary = {},
	on_progress: Callable = Callable()
) -> bool:
	var active_weights: Dictionary = GENERATION_TELEMETRY.load_active_weights()
	var stage_ranges: Dictionary = GENERATION_TELEMETRY.compute_stage_ranges(active_weights)
	var stage_durations_ms: Dictionary = {}

	# 1. Prepare Storage Slot & Fresh SQLite DB
	if not SaveManager.prepare_new_slot(target_slot_id):
		SystemLogger.log_error("[CityGenerationController] Failed to prepare slot: %s" % target_slot_id)
		push_error("[CityGenerationController] Failed to prepare slot: %s" % target_slot_id)
		return false

	# 2. Instantiate and Configure CityCrafter Engine
	var city_crafter := CustomCityCrafter.new()
	SystemLogger.log_info("[CityGenerationController] Starting city generation for seed '%s' in slot '%s'." % [gen_seed, target_slot_id])
	city_crafter.name = "CityCrafterGenerator"
	var base_config: Resource = ScenarioManifestManager.get_city_configuration()
	var config_instance: Resource = base_config.duplicate()
	
	for key in settings_override.keys():
		if key in config_instance:
			config_instance.set(key, settings_override[key])
	city_crafter.city_configuration = config_instance

	# Attach to SceneTree so get_tree().process_frame resolves during async generation
	var main_loop := Engine.get_main_loop()
	var tree: SceneTree = main_loop as SceneTree
	assert(tree != null and tree.root != null, "FATAL: SceneTree root missing during city generation.")
	tree.root.add_child(city_crafter)
	await tree.process_frame

	# Step A: Streets & Arterial Layout
	var t0_streets: int = Time.get_ticks_msec()
	if on_progress.is_valid():
		on_progress.call(GENERATION_TELEMETRY.map_stage_progress(stage_ranges, "STREETS", 0.05), "STREETS", "Mapping Arterial Infrastructure...")
	await city_crafter.generate_city_async(gen_seed)
	stage_durations_ms["STREETS"] = maxi(1, Time.get_ticks_msec() - t0_streets)

	# Step B: Classify Urban Wards into GameState
	var t0_districts: int = Time.get_ticks_msec()
	if on_progress.is_valid():
		on_progress.call(GENERATION_TELEMETRY.map_stage_progress(stage_ranges, "DISTRICTS", 0.1), "DISTRICTS", "Classifying Urban Wards...")
	var gs := ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [CityGenerationController] Active GameState node unavailable.")
	gs.initialize_fresh_state()
	gs.world_state["metadata"]["active_seed"] = gen_seed
	CitySpatialAdapter.ingest_citycrafter_generation(city_crafter, gs.world_state, gen_seed)
	stage_durations_ms["DISTRICTS"] = maxi(1, Time.get_ticks_msec() - t0_districts)

	# Step C: Populate Social Network & Citizens in SQLite (SOCIETY_PREMISES, SOCIETY_CITIZENS, SOCIETY_DUNBAR)
	if on_progress.is_valid():
		on_progress.call(GENERATION_TELEMETRY.map_stage_progress(stage_ranges, "SOCIETY_PREMISES", 0.0), "SOCIETY", "Seeding Living Population & Ties...")
	await SocialNetworkGenerator.generate_city_society(
		gs.world_state,
		gen_seed,
		false,
		func(sub_stage_id: String, local_frac: float, desc: String):
			if on_progress.is_valid():
				var mapped_pct: float = GENERATION_TELEMETRY.map_stage_progress(stage_ranges, sub_stage_id, local_frac)
				on_progress.call(mapped_pct, "SOCIETY", desc),
		true
	)
	var soc_durations: Dictionary = SocialNetworkGenerator.get_last_stage_durations_ms()
	for sub_k in soc_durations.keys():
		stage_durations_ms[sub_k] = int(soc_durations[sub_k])

	# Step D: Spatial Resolution of Home Ward & Starting Crew Recruitment
	var t0_roster: int = Time.get_ticks_msec()
	if on_progress.is_valid():
		on_progress.call(GENERATION_TELEMETRY.map_stage_progress(stage_ranges, "ROSTER", 0.1), "DISTRICTS", "Locating Home Neighborhood...")
	var home_id: String = CitySpatialAdapter.resolve_verified_home_district(gs.world_state, gen_seed)
	assert(not home_id.is_empty(), "FATAL: [CityGenerationController] Failed to resolve home district.")
	gs.set_home_district(home_id)

	if on_progress.is_valid():
		on_progress.call(GENERATION_TELEMETRY.map_stage_progress(stage_ranges, "ROSTER", 0.5), "ROSTER", "Recruiting Starting Operatives...")
	var crew_ok: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(gs.world_state, home_id)
	if not crew_ok:
		SystemLogger.log_error("[CityGenerationController] Failed to scout and bind starting crew in %s." % home_id)
		push_error("[CityGenerationController] Failed to scout and bind starting crew in %s." % home_id)
		if city_crafter.get_parent():
			city_crafter.get_parent().remove_child(city_crafter)
		city_crafter.queue_free()
		return false

	assert(gs.has_method("set_home_district"), "FATAL: [CityGenerationController] Active GameState missing set_home_district().")
	gs.set_home_district(home_id)
	stage_durations_ms["ROSTER"] = maxi(1, Time.get_ticks_msec() - t0_roster)

	# Step E: Commit to Disk
	var t0_save: int = Time.get_ticks_msec()
	if on_progress.is_valid():
		on_progress.call(GENERATION_TELEMETRY.map_stage_progress(stage_ranges, "SAVE", 0.2), "SAVE", "Finalizing Municipal Dossier...")
	if city_crafter.has_method("export_visual_layout"):
		gs.world_state["city_layout"] = city_crafter.export_visual_layout()

	var save_ok = SaveManager.save_game(target_slot_id, city_crafter)
	stage_durations_ms["SAVE"] = maxi(1, Time.get_ticks_msec() - t0_save)
	SystemLogger.log_info("[CityGenerationController] City generation pipeline completed with save status: %s." % save_ok)

	# Clean up temporary generator node from tree
	if city_crafter.get_parent():
		city_crafter.get_parent().remove_child(city_crafter)
	city_crafter.queue_free()

	if save_ok:
		GENERATION_TELEMETRY.record_run_durations(stage_durations_ms)
		if on_progress.is_valid():
			on_progress.call(100.0, "COMPLETE", "City Ready")

	return save_ok