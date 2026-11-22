# res://tests/test_society_factory.gd
class_name TestSocietyFactory
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const SOCIAL_NETWORK_GENERATOR = preload("res://systems/social_network_generator.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")

const DEFAULT_TEST_RADIUS: int = 4
const WORKING_SLOT_ID := "test_active_working_slot"

## Generates (or mounts a copy-on-write cached baseline of) a ~40-district concentric radial city
## using the live CustomCityCrafter + CitySpatialAdapter + SocialNetworkGenerator pipeline.
static func create_test_world(
	radius_a: int = DEFAULT_TEST_RADIUS,
	radius_b: int = DEFAULT_TEST_RADIUS,
	seed_id: String = "test-factory-seed",
	force_rebuild: bool = false
) -> Dictionary:
	var radius: int = maxi(2, maxi(radius_a, radius_b))
	var baseline_slot: String = _get_baseline_slot_id(radius, seed_id, false)
	var fingerprint: String = _compute_baseline_fingerprint(radius, seed_id, false)

	if not force_rebuild and _is_baseline_cache_valid(baseline_slot, fingerprint):
		return _mount_working_copy_from_baseline(baseline_slot)

	return await _build_and_cache_radial_world(radius, seed_id, false, baseline_slot, fingerprint)

## Generates (or mounts a copy-on-write cached baseline of) a ~40-district radial society
## with starting crew scouted, SQLite cognitive/OCEAN columns hydrated, and ORG:CREW_ENTERPRISE persisted.
static func create_test_world_with_crew(
	radius_a: int = DEFAULT_TEST_RADIUS,
	radius_b: int = DEFAULT_TEST_RADIUS,
	seed_id: String = "test-factory-crew-seed",
	time_horizon: String = "day",
	force_rebuild: bool = false
) -> Dictionary:
	var radius: int = maxi(2, maxi(radius_a, radius_b))
	var baseline_slot: String = _get_baseline_slot_id(radius, seed_id, true)
	var fingerprint: String = _compute_baseline_fingerprint(radius, seed_id, true)

	var ws: Dictionary
	if not force_rebuild and _is_baseline_cache_valid(baseline_slot, fingerprint):
		ws = _mount_working_copy_from_baseline(baseline_slot)
	else:
		ws = await _build_and_cache_radial_world(radius, seed_id, true, baseline_slot, fingerprint)

	if not ws.has("metadata") or not (ws["metadata"] is Dictionary):
		ws["metadata"] = {}
	ws["metadata"]["time_horizon"] = time_horizon
	return ws

## Deletes all cached test baseline and working save slots so the next run rebuilds from scratch.
static func invalidate_baseline_cache() -> void:
	var base_da := DirAccess.open("user://saves")
	if base_da == null:
		return
	base_da.list_dir_begin()
	var entry := base_da.get_next()
	while entry != "":
		if base_da.current_is_dir() and (entry.begins_with("test_baseline_") or entry == WORKING_SLOT_ID):
			SaveManager.delete_save_slot(entry)
		entry = base_da.get_next()
	base_da.list_dir_end()

static func _build_and_cache_radial_world(
	radius: int,
	seed_id: String,
	with_crew: bool,
	baseline_slot: String,
	fingerprint: String
) -> Dictionary:
	DB_MANAGER.close_database()
	SaveManager.delete_save_slot(baseline_slot)
	var prep_ok: bool = SaveManager.prepare_new_slot(baseline_slot)
	assert(prep_ok, "FATAL: [TestSocietyFactory] Failed to prepare baseline slot: %s" % baseline_slot)

	var city_crafter := CustomCityCrafter.new()
	city_crafter.name = "TestRadialCityCrafter"
	var base_cfg: Resource = ScenarioManifestManager.get_city_configuration()
	assert(base_cfg != null, "FATAL: [TestSocietyFactory] City configuration resource unavailable.")
	var cfg_inst: Resource = base_cfg.duplicate()
	if "city_radius" in cfg_inst:
		cfg_inst.set("city_radius", radius)
	if "enable_building_spawning" in cfg_inst:
		cfg_inst.set("enable_building_spawning", false)
	city_crafter.city_configuration = cfg_inst

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(city_crafter)
		await tree.process_frame

	await city_crafter.generate_city_async(seed_id)

	var start_sim_day: int = CalendarHelperScript.get_simulation_start_day()
	var ws: Dictionary = {
		"metadata": {
			"current_sim_day": start_sim_day,
			"current_week_tick": 1,
			"calendar_year": 1975,
			"active_seed": seed_id
		},
		"operations": {},
		"knowledge_pools": {},
		"districts": {},
		"residents": {},
		"establishments": {},
		"caches": {}
	}

	var gs = ScenarioManifestManager.get_game_state()
	if gs != null and "world_state" in gs:
		gs.world_state = ws

	CitySpatialAdapter.ingest_citycrafter_generation(city_crafter, ws, seed_id)
	await SOCIAL_NETWORK_GENERATOR.generate_city_society(ws, seed_id, false, Callable(), true)

	var home_district: String = CitySpatialAdapter.resolve_verified_home_district(ws, seed_id)
	assert(not home_district.is_empty(), "FATAL: [TestSocietyFactory] Failed to resolve verified home district.")
	ws["operations"]["home_district_id"] = home_district
	if gs != null and gs.has_method("set_home_district"):
		gs.set_home_district(home_district)

	if with_crew:
		var crew_ok: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(ws, home_district)
		assert(crew_ok, "FATAL: [TestSocietyFactory] CrewScoutBootstrapper failed in %s." % home_district)
		_hydrate_crew_sql_traits(ws)
		ws["organizations"] = {}
		ensure_test_organization(ws, "ORG:CREW_ENTERPRISE", "Crew Enterprise", "", "DIRECT", 1.0)

	if city_crafter.has_method("export_visual_layout"):
		ws["city_layout"] = city_crafter.export_visual_layout()

	SaveManager.save_game(baseline_slot, city_crafter, ws)
	_write_baseline_fingerprint(baseline_slot, fingerprint)

	if city_crafter.get_parent() != null:
		city_crafter.get_parent().remove_child(city_crafter)
	_deep_free_node(city_crafter)

	return _mount_working_copy_from_baseline(baseline_slot)

static func _hydrate_crew_sql_traits(ws: Dictionary) -> void:
	var residents: Dictionary = ws.get("residents", {})
	for r_key in residents.keys():
		var rec = residents[r_key]
		if not (rec is Dictionary):
			continue
		var r_id: int = int(rec.get("resident_id", r_key))
		if r_id <= 0:
			continue
		var rows: Array = DB_MANAGER.query_rows("""
			SELECT iq_score, mental_agility, openness, conscientiousness,
			       extraversion, agreeableness, neuroticism
			FROM residents WHERE resident_id = %d LIMIT 1;
		""" % r_id)
		if not rows.is_empty():
			var row: Dictionary = rows[0]
			rec["iq_score"] = float(row.get("iq_score", 100.0))
			rec["mental_agility"] = float(row.get("mental_agility", 0.50))
			rec["ocean"] = {
				"openness": float(row.get("openness", 0.50)),
				"conscientiousness": float(row.get("conscientiousness", 0.50)),
				"extraversion": float(row.get("extraversion", 0.50)),
				"agreeableness": float(row.get("agreeableness", 0.50)),
				"neuroticism": float(row.get("neuroticism", 0.50))
			}

static func _mount_working_copy_from_baseline(baseline_slot: String) -> Dictionary:
	DB_MANAGER.close_database()
	SaveManager.delete_save_slot(WORKING_SLOT_ID)
	SaveManager.ensure_slot_dir(WORKING_SLOT_ID)

	var src_dir: String = SaveManager.get_slot_dir(baseline_slot)
	var dst_dir: String = SaveManager.get_slot_dir(WORKING_SLOT_ID)
	for fname in ["game_state.json", "meta.json", "city_layout.json", "society.db"]:
		var src_file: String = src_dir.path_join(fname)
		if FileAccess.file_exists(src_file):
			var err: Error = DirAccess.copy_absolute(src_file, dst_dir.path_join(fname))
			assert(err == OK, "FATAL: [TestSocietyFactory] Failed copying %s to working slot (err=%d)." % [fname, err])

	var loaded: bool = SaveManager.load_game(WORKING_SLOT_ID)
	assert(loaded, "FATAL: [TestSocietyFactory] SaveManager.load_game failed for working slot.")
	var gs = ScenarioManifestManager.get_game_state()
	assert(gs != null and "world_state" in gs, "FATAL: [TestSocietyFactory] GameState unavailable after loading working slot.")
	return gs.world_state

static func _get_baseline_slot_id(radius: int, seed_id: String, with_crew: bool) -> String:
	var sanitized_seed: String = seed_id.replace(":", "_").replace("/", "_").replace(" ", "_")
	return "test_baseline_r%d_%s_%s" % [radius, "crew" if with_crew else "world", sanitized_seed]

static func _compute_baseline_fingerprint(radius: int, seed_id: String, with_crew: bool) -> String:
	var parts: PackedStringArray = PackedStringArray([
		"v1",
		"r=%d" % radius,
		"seed=%s" % seed_id,
		"crew=%s" % str(with_crew),
		"manifest=%s" % ScenarioManifestManager.get_manifest_path()
	])
	var watch_paths: Array[String] = [
		ScenarioManifestManager.BUSINESS_RULES_PATH,
		ScenarioManifestManager.get_manifest_path(),
		"res://scripts/world/custom_city_crafter.gd",
		"res://systems/city_spatial_adapter.gd",
		"res://systems/social_network_generator.gd",
		"res://systems/society/crew_scout_bootstrapper.gd",
		"res://systems/society/premises_workplace_builder.gd",
		"res://systems/society/citizen_demographics_hydrator.gd",
		"res://systems/society/dunbar_graph_weaver.gd"
	]
	for p in watch_paths:
		if FileAccess.file_exists(p):
			parts.append("%s:%d" % [p, FileAccess.get_modified_time(p)])

	for schema_dir: String in ["res://data_modules/core/schema", "res://data_modules/crime/schema"]:
		var da := DirAccess.open(schema_dir)
		if da != null:
			da.list_dir_begin()
			var f: String = da.get_next()
			while f != "":
				if not da.current_is_dir() and f.ends_with(".sql"):
					var full_p: String = schema_dir.path_join(f)
					parts.append("%s:%d" % [full_p, FileAccess.get_modified_time(full_p)])
				f = da.get_next()
			da.list_dir_end()

	return "|".join(parts).sha256_text()

static func _is_baseline_cache_valid(baseline_slot: String, expected_fp: String) -> bool:
	var slot_dir: String = SaveManager.get_slot_dir(baseline_slot)
	var meta_path: String = slot_dir.path_join("meta.json")
	var state_path: String = slot_dir.path_join("game_state.json")
	var db_path: String = slot_dir.path_join("society.db")
	if not (FileAccess.file_exists(meta_path) and FileAccess.file_exists(state_path) and FileAccess.file_exists(db_path)):
		return false
	var mf := FileAccess.open(meta_path, FileAccess.READ)
	if mf == null:
		return false
	var parsed = JSON.parse_string(mf.get_as_text())
	mf.close()
	if not (parsed is Dictionary):
		return false
	return str(parsed.get("baseline_fingerprint", "")) == expected_fp

static func _write_baseline_fingerprint(baseline_slot: String, fingerprint: String) -> void:
	var meta_path: String = SaveManager.get_slot_dir(baseline_slot).path_join("meta.json")
	if not FileAccess.file_exists(meta_path):
		return
	var mf := FileAccess.open(meta_path, FileAccess.READ)
	if mf == null:
		return
	var parsed = JSON.parse_string(mf.get_as_text())
	mf.close()
	if parsed is Dictionary:
		parsed["baseline_fingerprint"] = fingerprint
		var wf := FileAccess.open(meta_path, FileAccess.WRITE)
		if wf != null:
			wf.store_string(JSON.stringify(parsed, "\t"))
			wf.close()

static func _deep_free_node(node: Node) -> void:
	for child in node.get_children():
		_deep_free_node(child)
	node.free()

## Persists a canonical organization row in SQLite and syncs it into world_state["organizations"]
static func ensure_test_organization(
	world_state: Dictionary,
	org_id: String,
	display_name: String,
	parent_org_id: String = "",
	autonomy_mode: String = "DIRECT",
	loyalty: float = 1.0,
	police_heat: float = 0.0
) -> void:
	if not world_state.has("organizations") or not (world_state["organizations"] is Dictionary):
		world_state["organizations"] = {}
	world_state["organizations"][org_id] = {
		"org_id": org_id,
		"parent_org_id": parent_org_id,
		"display_name": display_name,
		"autonomy_mode": autonomy_mode,
		"loyalty": loyalty,
		"police_heat": police_heat
	}
	if DB_MANAGER.is_database_open():
		var start_day: int = int(world_state.get("metadata", {}).get("current_sim_day", CalendarHelperScript.get_simulation_start_day()))
		var reason_id: int = DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
		var parent_sql: String = "'%s'" % parent_org_id.replace("'", "''") if not parent_org_id.is_empty() else "NULL"
		DB_MANAGER.query_rows("""
			INSERT OR REPLACE INTO organizations (
				org_id, parent_org_id, autonomy_mode, display_name, org_type,
				legal_status, institution_rail_class, valid_from, valid_to, change_reason_id
			) VALUES (
				'%s', %s, '%s', '%s', 'SYNDICATE',
				'INFORMAL', 'STANDARD', %d, NULL, %d
			);
		""" % [
			org_id.replace("'", "''"),
			parent_sql,
			autonomy_mode.replace("'", "''"),
			display_name.replace("'", "''"),
			start_day,
			reason_id
		])