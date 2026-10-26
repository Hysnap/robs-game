# res://systems/social_network_generator.gd
class_name SocialNetworkGenerator
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")
const PARCEL_PLANNER = preload("res://systems/society/parcel_civic_planner.gd")
const PREMISES_BUILDER = preload("res://systems/society/premises_workplace_builder.gd")
const BOROUGH_CLUSTERER = preload("res://systems/society/borough_clusterer.gd")
const CITIZEN_HYDRATOR = preload("res://systems/society/citizen_demographics_hydrator.gd")
const DUNBAR_WEAVER = preload("res://systems/society/dunbar_graph_weaver.gd")

static var _lexicon: Dictionary = {}
static var _demographics: Dictionary = {}
static var _cultural: Dictionary = {}
static var _civic_hierarchy: Dictionary = {}
static var _archetypes: Dictionary = {}
static var _building_classes: Dictionary = {}
static var _job_definitions: Dictionary = {}

static func _load_configs() -> void:
	if not _demographics.is_empty() and not _lexicon.is_empty() and not _cultural.is_empty() and not _civic_hierarchy.is_empty() and not _archetypes.is_empty() and not _building_classes.is_empty() and not _job_definitions.is_empty():
		return

	_demographics = MANIFEST_MGR.load_module("demographics")
	_lexicon = MANIFEST_MGR.load_module("lexicon")
	_cultural = MANIFEST_MGR.load_module("cultural_demographics")
	_civic_hierarchy = MANIFEST_MGR.load_module("civic_hierarchy")
	_job_definitions = MANIFEST_MGR.load_module("job_definitions").get("roles", {})
	_archetypes = MANIFEST_MGR.load_module("archetypes")
	_building_classes = MANIFEST_MGR.load_module("building_classes")

## Main Generation Pipeline Facade
static func generate_city_society(
	world_state: Dictionary, 
	seed_id: String, 
	force_regenerate: bool = false, 
	on_progress: Callable = Callable()
) -> void:
	if not force_regenerate and DB_MANAGER.is_society_populated(seed_id):
		print("[SocialNetwork] Society for seed '%s' already exists in SQLite. Skipping generation." % seed_id)
		return

	_load_configs()
	DB_MANAGER.initialize_database(true)
	DB_MANAGER.record_active_seed(seed_id)

	var start_ms: int = Time.get_ticks_msec()
	print("[SocialNetwork] Commencing 4-Pass modular urban society generation...")

	var districts: Dictionary = world_state.get("districts", {})
	assert(not districts.is_empty(), "FATAL: world_state has no districts during society generation.")

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_id.hash())

	# -------------------------------------------------------------------------
	# PASS 0.5: LAND PARCEL DENSITY & INITIAL VACANCY
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(5.0, 100.0, "Pass 1: Generate Initial Land Parcels...")
		await Engine.get_main_loop().process_frame
	PARCEL_PLANNER.precalculate_district_metrics(world_state, _archetypes, rng)

	# -------------------------------------------------------------------------
	# PASS 1: CIVIC CADENCE REALIGNMENT (Universal Vacancy Absorption)
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(10.0, 100.0, "Pass 2: Realignment of dedicated civic parcels...")
		await Engine.get_main_loop().process_frame
	PARCEL_PLANNER.run_civic_cadence_pass(world_state, _archetypes, rng)

	# -------------------------------------------------------------------------
	# PASS 2: PHYSICAL PREMISES, ESTABLISHMENTS & WORKPLACES
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(20.0, 100.0, "Pass 3: Populating physical premises & tenancies...")
		await Engine.get_main_loop().process_frame
	var physical_state: Dictionary = await PREMISES_BUILDER.run(
		world_state, _archetypes, _building_classes, _job_definitions, _cultural, rng, on_progress
	)

	# -------------------------------------------------------------------------
	# PASS 2.5: MUNICIPAL BOROUGH CLUSTERING
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(25.0, 100.0, "Pass 4: Creating Boroughs...")
		await Engine.get_main_loop().process_frame
	BOROUGH_CLUSTERER.cluster_districts_into_boroughs(world_state, _civic_hierarchy, _lexicon, rng)

	# -------------------------------------------------------------------------
	# PASS 3: CITIZENS, CONTRACTS & QUALIFICATIONS (Distance-Decayed Commute)
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(50.0, 100.0, "Pass 5: Hydrating citizens into households...")
		await Engine.get_main_loop().process_frame
	await CITIZEN_HYDRATOR.run(
		physical_state, _demographics, _lexicon, _job_definitions, rng, on_progress
	)

	# -------------------------------------------------------------------------
	# PASS 4: DUNBAR NETWORK EDGES (Kinship, Workplace, Parish)
	# -------------------------------------------------------------------------
	if on_progress.is_valid():
		on_progress.call(90.0, 100.0, "Pass 6: Weaving social relationship graphs...")
		await Engine.get_main_loop().process_frame
	DUNBAR_WEAVER.run(physical_state, rng)

	var elapsed: int = Time.get_ticks_msec() - start_ms
	if on_progress.is_valid():
		on_progress.call(100.0, 100.0, "Living society complete in %d ms." % elapsed)
		await Engine.get_main_loop().process_frame

	print("[SocialNetwork] Generation complete across all passes in %d ms." % elapsed)