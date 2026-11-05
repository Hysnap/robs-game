# res://systems/city_generation_controller.gd
class_name CityGenerationController
extends RefCounted

const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")

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
	if on_progress.is_valid():
		on_progress.call(10.0, "STREETS", "Mapping Arterial Infrastructure...")
	await city_crafter.generate_city_async(gen_seed)

	# Step B: Classify Urban Wards into GameState
	if on_progress.is_valid():
		on_progress.call(35.0, "DISTRICTS", "Classifying Urban Wards...")
	GameState.initialize_fresh_state()
	GameState.world_state["metadata"]["active_seed"] = gen_seed
	CitySpatialAdapter.ingest_citycrafter_generation(city_crafter, GameState.world_state, gen_seed)

	# Step C: Populate Social Network & Citizens in SQLite
	if on_progress.is_valid():
		on_progress.call(50.0, "SOCIETY", "Seeding Living Population & Ties...")
	await SocialNetworkGenerator.generate_city_society(
		GameState.world_state,
		gen_seed,
		false,
		func(curr, tot, desc):
			if on_progress.is_valid():
				var sub_pct = 50.0 + (float(curr) / float(tot)) * 30.0
				on_progress.call(sub_pct, "SOCIETY", desc)
	)

	# Step D: Spatial Resolution of Home Ward & Universal Landmarks
	if on_progress.is_valid():
		on_progress.call(82.0, "DISTRICTS", "Locating Home Neighborhood...")
	var home_id: String = CitySpatialAdapter.resolve_verified_home_district(GameState.world_state, gen_seed)
	assert(not home_id.is_empty(), "FATAL: [CityGenerationController] Failed to resolve home district.")
	GameState.set_home_district(home_id)

	# Step D.2: Scout Autonomous Starting Crew & Bind Grey-Economy Contracts
	if on_progress.is_valid():
		on_progress.call(88.0, "ROSTER", "Recruiting Starting Operatives...")
	var crew_ok: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(GameState.world_state, home_id)
	if not crew_ok:
		SystemLogger.log_error("[CityGenerationController] Failed to scout and bind starting crew in %s." % home_id)
		push_error("[CityGenerationController] Failed to scout and bind starting crew in %s." % home_id)
		# Clean up generator before exit
		if city_crafter.get_parent():
			city_crafter.get_parent().remove_child(city_crafter)
		city_crafter.queue_free()
		return false

	# Step E: Commit to Disk
	if on_progress.is_valid():
		on_progress.call(95.0, "SAVE", "Finalizing Municipal Dossier...")
	if city_crafter.has_method("export_visual_layout"):
		GameState.world_state["city_layout"] = city_crafter.export_visual_layout()

	var save_ok = SaveManager.save_game(target_slot_id, city_crafter)
	SystemLogger.log_info("[CityGenerationController] City generation pipeline completed with save status: %s." % save_ok)

	# Clean up temporary generator node from tree
	if city_crafter.get_parent():
		city_crafter.get_parent().remove_child(city_crafter)
	city_crafter.queue_free()

	if on_progress.is_valid():
		on_progress.call(100.0, "COMPLETE", "City Ready")

	return save_ok