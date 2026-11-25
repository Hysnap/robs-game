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
const CITY_AUDITOR = preload("res://systems/city_auditor.gd")

static var _lexicon: Dictionary = {}
static var _demographics: Dictionary = {}
static var _cultural: Dictionary = {}
static var _civic_hierarchy: Dictionary = {}
static var _archetypes: Dictionary = {}
static var _building_classes: Dictionary = {}
static var _job_definitions: Dictionary = {}

static var _last_stage_durations_ms: Dictionary = {}

static func get_last_stage_durations_ms() -> Dictionary:
	return _last_stage_durations_ms.duplicate()

static func _load_configs() -> void:
	if not _demographics.is_empty() and not _lexicon.is_empty() and not _cultural.is_empty() and not _civic_hierarchy.is_empty() and not _archetypes.is_empty() and not _building_classes.is_empty() and not _job_definitions.is_empty():
		return

	_demographics = MANIFEST_MGR.load_module("demographics")
	_lexicon = MANIFEST_MGR.load_module("lexicon").duplicate(true)
	var spatial_lexicon: Dictionary = MANIFEST_MGR.load_module("spatial_lexicon")
	assert(not spatial_lexicon.is_empty(), "FATAL: [SocialNetworkGenerator] 'spatial_lexicon' module is empty or missing.")
	for k in spatial_lexicon.keys():
		if k != "_meta":
			_lexicon[k] = spatial_lexicon[k]
	_cultural = MANIFEST_MGR.load_module("cultural_demographics")
	_civic_hierarchy = MANIFEST_MGR.load_module("civic_hierarchy")
	_job_definitions = MANIFEST_MGR.load_module("job_definitions")
	_archetypes = MANIFEST_MGR.load_module("archetypes")
	_building_classes = MANIFEST_MGR.load_module("building_classes")

## Main Generation Pipeline Facade
static func generate_city_society(
	world_state: Dictionary, 
	seed_id: String, 
	force_regenerate: bool = false, 
	on_progress: Callable = Callable(),
	stage_tagged_progress: bool = false
) -> void:
	_last_stage_durations_ms = {
		"SOCIETY_PREMISES": 1,
		"SOCIETY_CITIZENS": 1,
		"SOCIETY_DUNBAR": 1
	}

	if not force_regenerate and DB_MANAGER.is_society_populated(seed_id):
		SystemLogger.log_info("[SocialNetwork] Society for seed '%s' already exists in SQLite. Skipping generation." % seed_id)
		return

	_load_configs()
	if force_regenerate:
		DB_MANAGER.initialize_database(true)
	DB_MANAGER.record_active_seed(seed_id)

	var start_ms: int = Time.get_ticks_msec()
	SystemLogger.log_info("[SocialNetwork] Commencing 4-Pass modular urban society generation...")

	var districts: Dictionary = world_state.get("districts", {})
	assert(not districts.is_empty(), "FATAL: world_state has no districts during society generation.")

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_id.hash())

	var gen_cfg: Dictionary = DB_MANAGER.get_city_generation_config()
	var pipeline_mode: String = str(gen_cfg.get("pipeline_mode", "REWORKED_DEFERRED_INDEX"))
	SystemLogger.log_info("[SocialNetwork] Active city generation mode: %s (district_batch=%d, sql_flush=%d)" % [
		pipeline_mode,
		int(gen_cfg.get("district_batch_size", 25)),
		int(gen_cfg.get("sql_flush_batch_size", 1000))
	])

	if pipeline_mode == "LEGACY_ORDER":
		await _run_legacy_pipeline(world_state, rng, on_progress, stage_tagged_progress)
	else:
		await _run_reworked_pipeline(world_state, rng, gen_cfg, on_progress, stage_tagged_progress)

	var elapsed: int = Time.get_ticks_msec() - start_ms
	if not stage_tagged_progress and on_progress.is_valid():
		on_progress.call(100.0, 100.0, "Living society complete in %d ms." % elapsed)
		await _await_frame_if_available()

	SystemLogger.log_info("[SocialNetwork] Generation complete across all passes in %d ms." % elapsed)

	# -------------------------------------------------------------------------
	# POST-GENERATION HEALTH & LABOR MARKET AUDIT
	# -------------------------------------------------------------------------
	SystemLogger.log_info("[SocialNetwork] Compiling automated city health and labor market audit...")
	var audit_report := CITY_AUDITOR.audit_and_save(world_state, DB_MANAGER)
	if audit_report.has("report_path"):
		SystemLogger.log_info("  ✓ City Audit Report generated: %s" % audit_report["report_path"])
		if not audit_report.get("is_healthy", false):
			for warning in audit_report.get("warnings", []):
				SystemLogger.log_info("    [Audit Warning] %s" % warning)
			for err in audit_report.get("errors", []):
				SystemLogger.log_warn("[Audit Error] %s" % err)
				push_warning("[Audit Error] %s" % err)
	else:
		SystemLogger.log_warn("[SocialNetwork] CityAuditor did not write a report.")
		push_warning("[SocialNetwork] CityAuditor did not write a report.")

static func _run_legacy_pipeline(
	world_state: Dictionary,
	rng: RandomNumberGenerator,
	on_progress: Callable,
	stage_tagged_progress: bool
) -> void:
	var t0_premises: int = Time.get_ticks_msec()
	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_PREMISES", 0.05, 5.0, "Pass 1: Generate Initial Land Parcels...")
	await _await_frame_if_available()
	PARCEL_PLANNER.precalculate_district_metrics(world_state, _archetypes, rng)

	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_PREMISES", 0.20, 15.0, "Pass 2: Realignment of dedicated civic parcels...")
	await _await_frame_if_available()
	PARCEL_PLANNER.run_civic_cadence_pass(world_state, _archetypes, rng)

	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_PREMISES", 0.30, 20.0, "Pass 3: Populating physical premises & tenancies...")
	await _await_frame_if_available()
	var physical_state: Dictionary = await PREMISES_BUILDER.run(
		world_state, _archetypes, _building_classes, _job_definitions, _cultural, _lexicon, rng,
		func(c, t, d):
			var frac: float = clampf(float(c) / maxf(float(t), 1.0), 0.0, 1.0)
			if stage_tagged_progress:
				_emit_sub_progress(on_progress, true, "SOCIETY_PREMISES", 0.30 + frac * 0.60, 0.0, str(d))
			elif on_progress.is_valid():
				on_progress.call(20.0 + frac * 25.0, 100.0, d)
	)

	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_PREMISES", 0.92, 46.0, "Pass 4: Creating Boroughs...")
	await _await_frame_if_available()
	BOROUGH_CLUSTERER.cluster_districts_into_boroughs(world_state, _civic_hierarchy, _lexicon, rng)
	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_PREMISES", 1.0, 49.0, "Physical premises & boroughs ready.")
	_last_stage_durations_ms["SOCIETY_PREMISES"] = maxi(1, Time.get_ticks_msec() - t0_premises)

	var t0_citizens: int = Time.get_ticks_msec()
	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_CITIZENS", 0.0, 50.0, "Pass 5: Hydrating citizens into households...")
	await _await_frame_if_available()
	await CITIZEN_HYDRATOR.run(
		physical_state,
		_demographics,
		_lexicon,
		_job_definitions,
		_cultural,
		rng,
		func(c, t, d):
			var raw_frac: float = clampf((float(c) - 50.0) / 35.0, 0.0, 1.0)
			if stage_tagged_progress:
				_emit_sub_progress(on_progress, true, "SOCIETY_CITIZENS", raw_frac, 0.0, str(d))
			elif on_progress.is_valid():
				on_progress.call(c, t, d)
	)
	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_CITIZENS", 1.0, 85.0, "Citizen hydration complete.")
	_last_stage_durations_ms["SOCIETY_CITIZENS"] = maxi(1, Time.get_ticks_msec() - t0_citizens)

	var t0_dunbar: int = Time.get_ticks_msec()
	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_DUNBAR", 0.05, 86.0, "Pass 6: Weaving social relationship graphs...")
	await _await_frame_if_available()
	DUNBAR_WEAVER.run(physical_state, rng)
	_emit_sub_progress(on_progress, stage_tagged_progress, "SOCIETY_DUNBAR", 1.0, 100.0, "Social relationship graphs complete.")
	_last_stage_durations_ms["SOCIETY_DUNBAR"] = maxi(1, Time.get_ticks_msec() - t0_dunbar)

static func _run_reworked_pipeline(
	world_state: Dictionary,
	rng: RandomNumberGenerator,
	gen_cfg: Dictionary,
	on_progress: Callable,
	stage_tagged_progress: bool
) -> void:
	var stage_order: Array = gen_cfg.get("stage_order", [])
	assert(not stage_order.is_empty(), "FATAL: [SocialNetwork] '[city_generation] stage_order' is empty in business_rules.cfg.")

	var ctx: Dictionary = {
		"world_state": world_state,
		"rng": rng,
		"gen_cfg": gen_cfg,
		"premises_state": {},
		"physical_state": {},
		"hydration_ctx": {},
		"premises_ms": 0,
		"citizens_ms": 0,
		"dunbar_ms": 0
	}

	for raw_stage in stage_order:
		var stage_key: String = str(raw_stage).strip_edges().to_upper()
		var t0: int = Time.get_ticks_msec()
		match stage_key:
			"DISTRICTS_AND_CIVICS":
				await _stage_districts_and_civics(ctx, on_progress, stage_tagged_progress)
				ctx["premises_ms"] += Time.get_ticks_msec() - t0
			"RESIDENTIAL_AND_HOUSEHOLDS":
				await _stage_residential_and_households(ctx, on_progress, stage_tagged_progress)
				ctx["premises_ms"] += Time.get_ticks_msec() - t0
			"INDEX_WAVE_HOUSEHOLDS_RESIDENTS":
				DB_MANAGER.apply_index_wave(stage_key)
				ctx["premises_ms"] += Time.get_ticks_msec() - t0
			"COMMERCIAL_INDUSTRIAL_AND_SLOTS":
				await _stage_comm_ind_and_slots(ctx, on_progress, stage_tagged_progress)
				ctx["premises_ms"] += Time.get_ticks_msec() - t0
			"INDEX_WAVE_ESTABS_SLOTS":
				DB_MANAGER.apply_index_wave(stage_key)
				ctx["premises_ms"] += Time.get_ticks_msec() - t0
			"ALLOCATE_ROLES_AND_HOUSING":
				await _stage_allocate_roles_and_housing(ctx, on_progress, stage_tagged_progress)
				ctx["citizens_ms"] += Time.get_ticks_msec() - t0
			"SOCIAL_AND_DUNBAR":
				await _stage_social_and_dunbar(ctx, on_progress, stage_tagged_progress)
				ctx["dunbar_ms"] += Time.get_ticks_msec() - t0
			"INDEX_WAVE_REMAINING":
				DB_MANAGER.apply_index_wave(stage_key)
				ctx["dunbar_ms"] += Time.get_ticks_msec() - t0
			_:
				assert(false, "FATAL: [SocialNetwork] Unknown stage_order entry '%s' in business_rules.cfg." % stage_key)

	_last_stage_durations_ms["SOCIETY_PREMISES"] = maxi(1, int(ctx["premises_ms"]))
	_last_stage_durations_ms["SOCIETY_CITIZENS"] = maxi(1, int(ctx["citizens_ms"]))
	_last_stage_durations_ms["SOCIETY_DUNBAR"] = maxi(1, int(ctx["dunbar_ms"]))

static func _stage_districts_and_civics(ctx: Dictionary, on_progress: Callable, stage_tagged: bool) -> void:
	var world_state: Dictionary = ctx["world_state"]
	var rng: RandomNumberGenerator = ctx["rng"]
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_PREMISES", 0.05, 5.0, "Stage 1: Generating Districts & Civic Entities...")
	await _await_frame_if_available()
	PARCEL_PLANNER.precalculate_district_metrics(world_state, _archetypes, rng)
	PARCEL_PLANNER.run_civic_cadence_pass(world_state, _archetypes, rng)
	BOROUGH_CLUSTERER.cluster_districts_into_boroughs(world_state, _civic_hierarchy, _lexicon, rng)

	var p_state: Dictionary = PREMISES_BUILDER.create_build_context(
		world_state, _archetypes, _building_classes, _job_definitions, _cultural, _lexicon, rng
	)
	ctx["premises_state"] = p_state
	await PREMISES_BUILDER.build_districts_and_civics(
		p_state,
		func(c, t, d):
			var frac: float = clampf(float(c) / maxf(float(t), 1.0), 0.0, 1.0)
			_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_PREMISES", 0.15 + frac * 0.25, 10.0 + frac * 10.0, str(d))
	)

static func _stage_residential_and_households(ctx: Dictionary, on_progress: Callable, stage_tagged: bool) -> void:
	var p_state: Dictionary = ctx["premises_state"]
	var rng: RandomNumberGenerator = ctx["rng"]
	assert(not p_state.is_empty(), "FATAL: [SocialNetwork] RESIDENTIAL_AND_HOUSEHOLDS requires DISTRICTS_AND_CIVICS to run first.")
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_PREMISES", 0.42, 22.0, "Stage 2: Building Residential Establishments & Households...")
	await _await_frame_if_available()
	await PREMISES_BUILDER.build_residential_and_households(
		p_state,
		func(c, t, d):
			var frac: float = clampf(float(c) / maxf(float(t), 1.0), 0.0, 1.0)
			_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_PREMISES", 0.42 + frac * 0.28, 22.0 + frac * 13.0, str(d))
	)

	var pre_index_state: Dictionary = {
		"districts": p_state["districts"],
		"households": p_state["generated_households"],
		"district_residents_map": p_state["district_residents_map"]
	}
	var t0_hyd: int = Time.get_ticks_msec()
	ctx["hydration_ctx"] = await CITIZEN_HYDRATOR.hydrate_households_and_residents(
		pre_index_state,
		_demographics,
		_lexicon,
		rng,
		func(c, t, d):
			var raw_frac: float = clampf((float(c) - 50.0) / 35.0, 0.0, 0.40)
			if stage_tagged:
				_emit_sub_progress(on_progress, true, "SOCIETY_CITIZENS", raw_frac, 0.0, str(d))
			elif on_progress.is_valid():
				on_progress.call(c, t, d)
	)
	ctx["citizens_ms"] += Time.get_ticks_msec() - t0_hyd

static func _stage_comm_ind_and_slots(ctx: Dictionary, on_progress: Callable, stage_tagged: bool) -> void:
	var p_state: Dictionary = ctx["premises_state"]
	assert(not p_state.is_empty(), "FATAL: [SocialNetwork] COMMERCIAL_INDUSTRIAL_AND_SLOTS requires DISTRICTS_AND_CIVICS to run first.")
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_PREMISES", 0.72, 36.0, "Stage 4: Allocating Commercial & Industrial Establishments + Job Slots...")
	await _await_frame_if_available()
	await PREMISES_BUILDER.build_commercial_industrial_and_slots(
		p_state,
		func(c, t, d):
			var frac: float = clampf(float(c) / maxf(float(t), 1.0), 0.0, 1.0)
			_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_PREMISES", 0.72 + frac * 0.26, 36.0 + frac * 12.0, str(d))
	)
	ctx["physical_state"] = PREMISES_BUILDER.finalize_physical_state(p_state)
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_PREMISES", 1.0, 49.0, "Physical premises & job slots ready.")

static func _stage_allocate_roles_and_housing(ctx: Dictionary, on_progress: Callable, stage_tagged: bool) -> void:
	var physical_state: Dictionary = ctx["physical_state"]
	var hydration_ctx: Dictionary = ctx["hydration_ctx"]
	var rng: RandomNumberGenerator = ctx["rng"]
	assert(not physical_state.is_empty(), "FATAL: [SocialNetwork] ALLOCATE_ROLES_AND_HOUSING requires COMMERCIAL_INDUSTRIAL_AND_SLOTS to run first.")
	assert(not hydration_ctx.is_empty(), "FATAL: [SocialNetwork] ALLOCATE_ROLES_AND_HOUSING requires RESIDENTIAL_AND_HOUSEHOLDS to run first.")
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_CITIZENS", 0.40, 62.0, "Stage 6: Allocating Roles, Students & Tied Accommodation...")
	await _await_frame_if_available()
	await CITIZEN_HYDRATOR.allocate_roles_and_housing(
		physical_state,
		hydration_ctx,
		_demographics,
		_lexicon,
		_job_definitions,
		_cultural,
		rng,
		func(c, t, d):
			var raw_frac: float = clampf((float(c) - 50.0) / 35.0, 0.40, 1.0)
			if stage_tagged:
				_emit_sub_progress(on_progress, true, "SOCIETY_CITIZENS", raw_frac, 0.0, str(d))
			elif on_progress.is_valid():
				on_progress.call(c, t, d)
	)
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_CITIZENS", 1.0, 85.0, "Citizen & role allocation complete.")

static func _stage_social_and_dunbar(ctx: Dictionary, on_progress: Callable, stage_tagged: bool) -> void:
	var physical_state: Dictionary = ctx["physical_state"]
	var rng: RandomNumberGenerator = ctx["rng"]
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_DUNBAR", 0.05, 86.0, "Stage 7: Weaving Social & Dunbar Graphs...")
	await _await_frame_if_available()
	DUNBAR_WEAVER.run(physical_state, rng)
	_emit_sub_progress(on_progress, stage_tagged, "SOCIETY_DUNBAR", 1.0, 100.0, "Social relationship graphs complete.")

static func _await_frame_if_available() -> void:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		await (main_loop as SceneTree).process_frame

static func _emit_sub_progress(
	on_progress: Callable,
	stage_tagged: bool,
	stage_id: String,
	local_frac: float,
	legacy_pct: float,
	desc: String
) -> void:
	if not on_progress.is_valid():
		return
	if stage_tagged:
		on_progress.call(stage_id, clampf(local_frac, 0.0, 1.0), desc)
	else:
		on_progress.call(legacy_pct, 100.0, desc)