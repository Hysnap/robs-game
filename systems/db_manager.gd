# res://systems/db_manager.gd
class_name DBManager
extends RefCounted

const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const TAXONOMY_HARVESTER = preload("res://systems/taxonomy_harvester.gd")
const FILE_CRAWLER = preload("res://systems/file_system_crawler.gd")

static var _db = null
static var active_db_path: String = ""
static var _label_cache: Dictionary = {} # "DOMAIN:CODE" -> label_id
static var _deferred_index_entries: Array[Dictionary] = [] # [{ "table": String, "sql": String, "source": String, "applied": bool }]

## Resolves the default database path strictly from business_rules.cfg [society] default_db_path
static func _resolve_default_db_path() -> String:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	assert(err == OK, "FATAL: [DBManager] Failed to load business_rules.cfg at %s" % MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	var path: String = str(cfg.get_value("society", "default_db_path", "")).strip_edges()
	assert(not path.is_empty(), "FATAL: [DBManager] Missing '[society] default_db_path' in %s" % MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	return path

## Reads [city_generation] settings from business_rules.cfg
static func get_city_generation_config() -> Dictionary:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	assert(err == OK, "FATAL: [DBManager] Failed to load business_rules.cfg at %s" % MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	assert(cfg.has_section("city_generation"), "FATAL: [DBManager] Missing '[city_generation]' section in %s" % MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	return {
		"pipeline_mode": str(cfg.get_value("city_generation", "pipeline_mode", "REWORKED_DEFERRED_INDEX")).strip_edges().to_upper(),
		"defer_secondary_indexes": bool(cfg.get_value("city_generation", "defer_secondary_indexes", true)),
		"district_batch_size": maxi(1, int(cfg.get_value("city_generation", "district_batch_size", 25))),
		"sql_flush_batch_size": maxi(50, int(cfg.get_value("city_generation", "sql_flush_batch_size", 1000))),
		"stage_order": cfg.get_value("city_generation", "stage_order", [])
	}

## Resolves active SQL schema directories from the scenario manifest ('db_schema' and optional 'extra_schema_dir')
static func _resolve_schema_directories() -> Array[String]:
	assert(MANIFEST_MANAGER.has_module("db_schema"), "FATAL: [DBManager] Scenario manifest missing required 'db_schema' module entry.")
	var core_schema_dir: String = MANIFEST_MANAGER.get_module_path("db_schema").strip_edges()
	assert(not core_schema_dir.is_empty() and DirAccess.dir_exists_absolute(core_schema_dir),
		"FATAL: [DBManager] Primary 'db_schema' directory does not exist: %s" % core_schema_dir)

	var dirs: Array[String] = [core_schema_dir]

	if MANIFEST_MANAGER.has_module("extra_schema_dir"):
		var extra_dir: String = MANIFEST_MANAGER.get_module_path("extra_schema_dir").strip_edges()
		if not extra_dir.is_empty() and DirAccess.dir_exists_absolute(extra_dir) and not dirs.has(extra_dir):
			dirs.append(extra_dir)

	return dirs

## Initializes connection and builds the relational society schema
static func initialize_database(reset_existing: bool = false, custom_path: String = "") -> bool:
	var target_path: String = custom_path.strip_edges()
	if target_path.is_empty():
		target_path = active_db_path if not active_db_path.is_empty() else _resolve_default_db_path()

	if _db != null and active_db_path == target_path and not reset_existing:
		return true

	if _db != null:
		close_database()

	if not ClassDB.class_exists("SQLite"):
		SystemLogger.log_critical("[DBManager CRITICAL] 'SQLite' class not found.")
		push_error("[DBManager CRITICAL] 'SQLite' class not found! Is 2shady4u godot-sqlite enabled?")
		return false

	active_db_path = target_path
	_db = ClassDB.instantiate("SQLite")
	var absolute_path: String = ProjectSettings.globalize_path(active_db_path)
	_db.path = absolute_path
	_db.foreign_keys = true

	if not _db.open_db():
		SystemLogger.log_critical("[DBManager CRITICAL] Failed to open SQLite connection at %s" % absolute_path)
		push_error("[DBManager CRITICAL] Failed to open SQLite connection at %s" % absolute_path)
		return false

	_db.query("PRAGMA journal_mode = OFF;")        # Eliminates rollback journal disk writes
	_db.query("PRAGMA synchronous = OFF;")         # Skips OS fsync disk flushing during gen
	_db.query("PRAGMA cache_size = -64000;")       # Allocates 64MB RAM cache to SQLite
	_db.query("PRAGMA temp_store = MEMORY;")       # Keeps temp tables/indices in memory

	if reset_existing:
		_drop_society_schema()

	_create_society_schema()
	SystemLogger.log_info("[DBManager] Connected to SQLite database at: %s" % absolute_path)

	# -------------------------------------------------------------
	# 1. Ingest Core Engine Labels (GENDER, CHANGE_REASON, CONTRACT_CLASS, RELATIONSHIP_TYPE)
	# -------------------------------------------------------------
	populate_core_system_labels()

	# -------------------------------------------------------------
	# 2. Harvest Scenario Content Labels (RESIDENCE_TYPE, ETHNICITY, RELIGION, EDUCATION, ROLES)
	# -------------------------------------------------------------
	harvest_scenario_taxonomies()

	# -------------------------------------------------------------
	# 3. Seed Temporal and Demographic Metadata (Epoch Date, Sim Start Date, Working & Pension Ages)
	# -------------------------------------------------------------
	_init_temporal_metadata()

	return true

## Dynamically drops all existing views and tables in the active database when resetting a seed
static func _drop_society_schema() -> void:
	if _db == null:
		return

	_db.query("PRAGMA foreign_keys = OFF;")

	var views: Array = query_rows("SELECT name FROM sqlite_master WHERE type = 'view';")
	for v in views:
		var view_name: String = str(v.get("name", ""))
		if not view_name.is_empty():
			_db.query("DROP VIEW IF EXISTS %s;" % view_name)

	var tables: Array = query_rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';")
	for t in tables:
		var table_name: String = str(t.get("name", ""))
		if not table_name.is_empty():
			_db.query("DROP TABLE IF EXISTS %s;" % table_name)

	_deferred_index_entries.clear()
	_db.query("PRAGMA foreign_keys = ON;")

## Crawls configured schema directories and executes modular .sql DDL files sorted by numeric tier prefix
static func _create_society_schema() -> void:
	if _db == null:
		return

	var schema_dirs: Array[String] = _resolve_schema_directories()
	var sql_paths: Array[String] = []

	for dir_path in schema_dirs:
		var found: Array[String] = FILE_CRAWLER.find_files_recursive(dir_path, "", ".sql")
		for f_path in found:
			if not sql_paths.has(f_path):
				sql_paths.append(f_path)

	assert(not sql_paths.is_empty(), "FATAL: [DBManager] No .sql schema files found across configured schema directories: %s" % str(schema_dirs))

	sql_paths.sort_custom(func(a: String, b: String) -> bool:
		var tier_a: int = _extract_schema_tier(a)
		var tier_b: int = _extract_schema_tier(b)
		if tier_a != tier_b:
			return tier_a < tier_b
		return a < b
	)

	var gen_cfg: Dictionary = get_city_generation_config()
	var defer_indexes: bool = bool(gen_cfg["defer_secondary_indexes"]) and str(gen_cfg["pipeline_mode"]) != "LEGACY_ORDER"
	_deferred_index_entries.clear()
	var executed_count: int = 0
	var deferred_file_count: int = 0

	for path in sql_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file != null, "FATAL: [DBManager] Cannot read SQL schema file: %s" % path)
		var sql_text: String = file.get_as_text().strip_edges()
		file.close()
		if sql_text.is_empty():
			continue

		if defer_indexes and _is_deferred_index_file(path):
			_queue_deferred_index_sql(sql_text, path)
			deferred_file_count += 1
			continue

		var ok: bool = _db.query(sql_text)
		if not ok:
			var err_msg: String = _db.error_message if "error_message" in _db else "Unknown SQLite error"
			SystemLogger.log_critical("[DBManager CRITICAL] Failed executing schema file %s: %s" % [path, err_msg])
			push_error("[DBManager CRITICAL] Failed executing schema file %s: %s" % [path, err_msg])
			assert(false, "FATAL: [DBManager] Schema execution failed in %s: %s" % [path, err_msg])
		executed_count += 1

	SystemLogger.log_info("[DBManager] Executed %d modular SQL schema files across %s (deferred %d index file(s), %d index statements)." % [
		executed_count, str(schema_dirs), deferred_file_count, _deferred_index_entries.size()
	])

static func _is_deferred_index_file(path: String) -> bool:
	var norm_path: String = path.replace("\\", "/").to_lower()
	return norm_path.contains("/indexes/") or _extract_schema_tier(path) >= 200

static func _queue_deferred_index_sql(sql_text: String, source_path: String) -> void:
	var cleaned_lines: PackedStringArray = PackedStringArray()
	for raw_line in sql_text.split("\n"):
		var stripped: String = raw_line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("--"):
			continue
		cleaned_lines.append(raw_line)

	var combined: String = "\n".join(cleaned_lines)
	var table_regex := RegEx.new()
	table_regex.compile("(?i)\\bON\\s+([a-zA-Z0-9_]+)\\s*\\(")

	for raw_stmt in combined.split(";"):
		var stmt: String = raw_stmt.strip_edges()
		if stmt.is_empty():
			continue
		var target_table: String = ""
		var m: RegExMatch = table_regex.search(stmt)
		if m != null:
			target_table = m.get_string(1).to_lower()
		_deferred_index_entries.append({
			"table": target_table,
			"sql": stmt + ";",
			"source": source_path,
			"applied": false
		})

## Applies deferred secondary SQLite indexes for a named generation wave
static func apply_index_wave(wave_name: String) -> int:
	if _db == null or _deferred_index_entries.is_empty():
		return 0

	var norm_wave: String = wave_name.strip_edges().to_upper()
	var target_tables: Array[String] = []
	var apply_all_remaining: bool = false

	match norm_wave:
		"INDEX_WAVE_HOUSEHOLDS_RESIDENTS":
			target_tables = ["households", "residents"]
		"INDEX_WAVE_ESTABS_SLOTS":
			target_tables = ["districts", "boroughs", "establishments", "workplace_job_slots"]
		"INDEX_WAVE_REMAINING":
			apply_all_remaining = true
		_:
			assert(false, "FATAL: [DBManager] Unknown index wave '%s'." % wave_name)
			return 0

	var to_run: Array[String] = []
	var applied_indices: Array[int] = []
	for i in range(_deferred_index_entries.size()):
		var entry: Dictionary = _deferred_index_entries[i]
		if bool(entry["applied"]):
			continue
		var tbl: String = str(entry["table"])
		if apply_all_remaining or target_tables.has(tbl):
			to_run.append(str(entry["sql"]))
			applied_indices.append(i)

	if to_run.is_empty():
		if apply_all_remaining:
			_db.query("ANALYZE;")
		return 0

	var t0: int = Time.get_ticks_msec()
	var ok: bool = execute_batch(to_run)
	assert(ok, "FATAL: [DBManager] Failed applying index wave '%s'." % norm_wave)
	for idx in applied_indices:
		_deferred_index_entries[idx]["applied"] = true

	if apply_all_remaining:
		_db.query("ANALYZE;")

	var elapsed: int = Time.get_ticks_msec() - t0
	SystemLogger.log_info("[DBManager] Applied %s (%d indexes) in %d ms." % [norm_wave, to_run.size(), elapsed])
	return to_run.size()

## Extracts leading numeric tier prefix (e.g., 21 from '21_households_and_residents.sql') for dependency sorting
static func _extract_schema_tier(path: String) -> int:
	var base: String = path.get_file().get_basename()
	var parts: PackedStringArray = base.split("_")
	if not parts.is_empty() and parts[0].is_valid_int():
		return int(parts[0])
	return 9999

## 1. Populates core engine labels strictly from the scenario manifest's 'db_labels' module,
## plus any active flavour localization/<db_labels_file> overlays.
static func populate_core_system_labels(custom_labels_path: String = "") -> void:
	var labels_file_path: String = custom_labels_path.strip_edges()
	if labels_file_path.is_empty():
		assert(MANIFEST_MANAGER.has_module("db_labels"), "FATAL: [DBManager] Scenario manifest missing required 'db_labels' module entry.")
		labels_file_path = MANIFEST_MANAGER.get_module_path("db_labels").strip_edges()

	var label_paths: Array[String] = [labels_file_path]
	var labels_filename: String = labels_file_path.get_file()
	var data_modules_root: String = labels_file_path.get_base_dir().get_base_dir().get_base_dir()
	var flavour_candidates: Array[String] = MANIFEST_MANAGER.get_active_flavours()
	var manifest_flavours: Variant = MANIFEST_MANAGER.get_manifest().get("active_flavours", [])
	if manifest_flavours is Array:
		for raw_f in manifest_flavours:
			var slug: String = str(raw_f).strip_edges().to_lower()
			if not slug.is_empty() and slug != "core" and not flavour_candidates.has(slug):
				flavour_candidates.append(slug)

	for flavour_name in flavour_candidates:
		var flavour_labels_path: String = data_modules_root.path_join(flavour_name).path_join("localization").path_join(labels_filename)
		if FileAccess.file_exists(flavour_labels_path) and not label_paths.has(flavour_labels_path):
			label_paths.append(flavour_labels_path)

	var inserts: Array[String] = []
	for dict_path in label_paths:
		assert(FileAccess.file_exists(dict_path), "FATAL: System label dictionary missing: %s" % dict_path)
		var file := FileAccess.open(dict_path, FileAccess.READ)
		assert(file != null, "FATAL: Could not read label dictionary: %s" % dict_path)
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()

		assert(parsed is Dictionary and parsed.has("labels"), "FATAL: Invalid dictionary format in: %s" % dict_path)
		for item in parsed["labels"]:
			var dom: String = str(item.get("domain", "")).to_upper().strip_edges()
			var code: String = str(item.get("code", "")).to_upper().strip_edges()
			var title: String = str(item.get("title", "")).replace("'", "''")
			var desc: String = str(item.get("description", "")).replace("'", "''")
			if dom.is_empty() or code.is_empty():
				continue
			inserts.append("""
				INSERT INTO system_labels (domain, code, title, description)
				VALUES ('%s', '%s', '%s', '%s')
				ON CONFLICT(domain, code) DO UPDATE SET title = excluded.title, description = excluded.description;
			""" % [dom, code, title, desc])

	execute_batch(inserts)

## 2. Ingests scenario-specific taxonomies extracted by TaxonomyHarvester
static func harvest_scenario_taxonomies() -> void:
	var raw_taxonomies: Array[Dictionary] = TAXONOMY_HARVESTER.harvest_all_taxonomies()
	var inserts: Array[String] = []

	for item in raw_taxonomies:
		inserts.append("""
			INSERT INTO system_labels (domain, code, title, description)
			VALUES ('%s', '%s', '%s', '')
			ON CONFLICT(domain, code) DO UPDATE SET title = excluded.title;
		""" % [
			item["domain"], 
			item["code"], 
			item["title"].replace("'", "''")
		])

	execute_batch(inserts)
	_rebuild_label_cache()
	SystemLogger.log_info("[DBManager] Synchronized %d total labels (Core JSON + Scenario Harvested)." % _label_cache.size())

static func _append_label_sql(out_array: Array[String], domain: String, code: String, title: String) -> void:
	out_array.append("""
		INSERT INTO system_labels (domain, code, title, description)
		VALUES ('%s', '%s', '%s', '')
		ON CONFLICT(domain, code) DO UPDATE SET title = excluded.title;
	""" % [domain.to_upper(), code.to_upper(), title.replace("'", "''")])

## Follows the Single Source of Truth Chain to seed epoch, temporal, and demographic metadata
static func _init_temporal_metadata() -> void:
	var demo_json: Dictionary = MANIFEST_MANAGER.load_module("demographics")
	assert(demo_json.has("temporal_anchor"), "FATAL: demographics JSON missing 'temporal_anchor'")
	var temp_cfg: Dictionary = demo_json["temporal_anchor"]

	CALENDAR_HELPER.initialize(temp_cfg)

	set_metadata("epoch_date", CALENDAR_HELPER.get_epoch_date())
	set_metadata("simulation_start_date", str(temp_cfg["simulation_start_date"]))
	set_metadata("days_per_tick", str(CALENDAR_HELPER.get_days_per_tick()))
	set_metadata("current_sim_day", "0")

	var thresholds: Dictionary = demo_json.get("legal_and_pension_thresholds", {})
	var pension_f: int = int(thresholds.get("pension_age_female", 60))
	var pension_m: int = int(thresholds.get("pension_age_male", 65))
	
	var min_working_age: int = 16
	for cohort in demo_json.get("cohort_profiles", []):
		if cohort.get("id") == "youth_transition":
			min_working_age = int(cohort.get("age_min", 16))
			break

	set_metadata("min_working_age", str(min_working_age))
	set_metadata("pension_age_female", str(pension_f))
	set_metadata("pension_age_male", str(pension_m))

	SystemLogger.log_info("[DBManager] Seeded metadata -> Epoch: '%s', Start: '%s', MinWorkAge: %d, Pension(F/M): %d/%d" % [
		CALENDAR_HELPER.get_epoch_date(), 
		str(temp_cfg["simulation_start_date"]),
		min_working_age,
		pension_f,
		pension_m
	])

## Fast RAM cache for label IDs to avoid recurring SELECT queries during generation
static func _rebuild_label_cache() -> void:
	_label_cache.clear()
	var rows: Array = query_rows("SELECT label_id, domain, code FROM system_labels;")
	for r in rows:
		var key = "%s:%s" % [r["domain"], r["code"]]
		_label_cache[key] = int(r["label_id"])

## Returns the cached integer label_id for any domain/code pairing, strictly failing if absent
static func get_label_id(domain: String, code: String) -> int:
	var key := "%s:%s" % [domain.to_upper(), code.to_upper()]
	if _label_cache.has(key):
		return _label_cache[key]

	var res = query_rows("SELECT label_id FROM system_labels WHERE domain = '%s' AND code = '%s';" % [domain.to_upper(), code.to_upper()])
	if not res.is_empty():
		var id := int(res[0]["label_id"])
		_label_cache[key] = id
		return id

	SystemLogger.log_error("[DBManager CRITICAL] Missing required taxonomy label in system_labels: [%s:%s]" % [domain, code])
	push_error("[DBManager CRITICAL] Missing required taxonomy label in system_labels: [%s:%s]" % [domain, code])
	assert(false, "FATAL: System label lookup failed for [%s:%s]. Check db_labels_en_gb.json or scenario module definitions!" % [domain, code])
	return -1

## Universal Query Runner
static func query_rows(sql: String) -> Array:
	if _db == null:
		initialize_database()
	_db.query(sql)
	return _db.query_result

## High-Performance Transaction Batch Runner (Wraps thousands of inserts into 1 commit)
static func execute_batch(sql_statements: Array[String]) -> bool:
	if _db == null:
		initialize_database()
	if sql_statements.is_empty():
		return true

	_db.query("BEGIN TRANSACTION;")
	var idx := 0
	for sql in sql_statements:
		if not _db.query(sql):
			var err_msg: String = _db.error_message if "error_message" in _db else "Unknown SQLite error"
			_db.query("ROLLBACK;")
			printerr("\n=======================================================")
			printerr("[DBManager CRITICAL SQL FAILURE]")
			printerr("  • Statement Index: %d / %d" % [idx, sql_statements.size()])
			printerr("  • SQLite Message : %s" % err_msg)
			printerr("  • Failed Query   : %s" % sql)
			printerr("=======================================================\n")
			assert(false, "FATAL: [DBManager] SQLite batch transaction aborted on statement #%d: %s" % [idx, err_msg])
			return false
		idx += 1
	_db.query("COMMIT;")
	return true

## Checks if society exists AND matches the requested seed
static func is_society_populated(expected_seed: String = "") -> bool:
	if _db == null:
		initialize_database(false)

	var res = query_rows("SELECT count(*) as count FROM sqlite_master WHERE type='table' AND name='residents';")
	if res.is_empty() or int(res[0]["count"]) == 0:
		return false

	var count_res = query_rows("SELECT count(*) as count FROM residents;")
	if count_res.is_empty() or int(count_res[0]["count"]) == 0:
		return false

	if not expected_seed.is_empty():
		var seed_row = query_rows("SELECT value FROM world_metadata WHERE key = 'active_seed';")
		if seed_row.is_empty():
			return false
		var db_seed: String = str(seed_row[0].get("value", ""))
		if db_seed != expected_seed:
			SystemLogger.log_warn("[DBManager] Seed mismatch detected (DB: '%s' vs Current: '%s'). Rebuilding." % [db_seed, expected_seed])
			return false

	return true

## Stores arbitrary system metadata key-value pairs (seed, epoch_date, sim_start_date)
static func set_metadata(key: String, value: String) -> void:
	if _db == null:
		return
	_db.query("INSERT OR REPLACE INTO world_metadata (key, value) VALUES ('%s', '%s');" % [
		key.replace("'", "''"), 
		value.replace("'", "''")
	])

## Retrieves metadata values dynamically
static func get_metadata(key: String, default_value: String = "") -> String:
	var res = query_rows("SELECT value FROM world_metadata WHERE key = '%s';" % key.replace("'", "''"))
	if res.is_empty():
		return default_value
	return str(res[0].get("value", default_value))

## Stashes the active seed in metadata
static func record_active_seed(seed_id: String) -> void:
	set_metadata("active_seed", seed_id)

## Clean shutdown of the open database channel
static func close_database() -> void:
	if _db != null:
		_db.close_db()
		_db = null
		_label_cache.clear()
		_deferred_index_entries.clear()
		SystemLogger.log_info("[DBManager] Database connection closed.")

## Returns true if the internal SQLite instance exists and has an open connection
static func is_database_open() -> bool:
	return _db != null