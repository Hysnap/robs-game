# res://systems/db_manager.gd
class_name DBManager
extends RefCounted

const DB_PATH: String = "user://game_society.db"
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const TAXONOMY_HARVESTER = preload("res://systems/taxonomy_harvester.gd")

static var _db = null
static var _label_cache: Dictionary = {} # "DOMAIN:CODE" -> label_id

## Initializes connection and builds the relational society schema
static func initialize_database(reset_existing: bool = false) -> bool:
	if _db != null and not reset_existing:
		return true

	if not ClassDB.class_exists("SQLite"):
		push_error("[DBManager CRITICAL] 'SQLite' class not found! Is 2shady4u godot-sqlite enabled?")
		return false

	_db = ClassDB.instantiate("SQLite")
	var absolute_path: String = ProjectSettings.globalize_path(DB_PATH)
	_db.path = absolute_path
	_db.foreign_keys = true

	if not _db.open_db():
		push_error("[DBManager CRITICAL] Failed to open SQLite connection at %s" % absolute_path)
		return false

	_db.query("PRAGMA journal_mode = OFF;")        # Eliminates rollback journal disk writes
	_db.query("PRAGMA synchronous = OFF;")         # Skips OS fsync disk flushing during gen
	_db.query("PRAGMA cache_size = -64000;")       # Allocates 64MB RAM cache to SQLite
	_db.query("PRAGMA temp_store = MEMORY;")       # Keeps temp tables/indices in memory

	if reset_existing:
		_drop_society_schema()

	_create_society_schema()
	print("[DBManager] Connected to SQLite database at: %s" % absolute_path)

	# -------------------------------------------------------------
	# 1. Ingest Core Engine Labels (GENDER, CHANGE_REASON, CONTRACT_CLASS, RELATIONSHIP_TYPE)
	# -------------------------------------------------------------
	populate_core_system_labels("res://data_modules/core/localization/db_labels_en_gb.json")

	# -------------------------------------------------------------
	# 2. Harvest Scenario Content Labels (RESIDENCE_TYPE, ETHNICITY, RELIGION, EDUCATION, ROLES)
	# -------------------------------------------------------------
	harvest_scenario_taxonomies()

	# -------------------------------------------------------------
	# 3. Seed Temporal Metadata (Epoch Date & Simulation Start Date)
	# -------------------------------------------------------------
	_init_temporal_metadata()

	return true

## Drops existing tables if resetting a seed
static func _drop_society_schema() -> void:
	if _db == null: return
	_db.query("DROP VIEW IF EXISTS v_composite_bonds;")
	_db.query("DROP VIEW IF EXISTS v_establishments_overview;")
	_db.query("DROP VIEW IF EXISTS v_active_contracts;")
	_db.query("DROP VIEW IF EXISTS v_households_overview;")
	_db.query("DROP VIEW IF EXISTS v_residents_overview;")
	_db.query("DROP VIEW IF EXISTS v_district_census;")
	_db.query("DROP VIEW IF EXISTS v_borough_census;")
	_db.query("DROP TABLE IF EXISTS livelihood_contracts;")
	_db.query("DROP TABLE IF EXISTS social_relationships;")
	_db.query("DROP TABLE IF EXISTS residents;")
	_db.query("DROP TABLE IF EXISTS households;")
	_db.query("DROP TABLE IF EXISTS establishments;")
	_db.query("DROP TABLE IF EXISTS districts;")
	_db.query("DROP TABLE IF EXISTS boroughs;")
	_db.query("DROP TABLE IF EXISTS system_labels;")
	_db.query("DROP TABLE IF EXISTS world_metadata;")
	
	

## Builds the Living Society & Dunbar Graph Relational Schema
static func _create_society_schema() -> void:
	if _db == null: return

	# 1. Metadata tracking table
	_db.query("""
		CREATE TABLE IF NOT EXISTS world_metadata (
			key TEXT PRIMARY KEY,
			value TEXT NOT NULL
		);
	""")

	# 2. System Labels table
	_db.query("""
		CREATE TABLE IF NOT EXISTS system_labels (
			label_id INTEGER PRIMARY KEY AUTOINCREMENT,
			domain TEXT NOT NULL,
			code TEXT NOT NULL,
			title TEXT NOT NULL,
			description TEXT NOT NULL DEFAULT '',
			UNIQUE(domain, code)
		);
	""")

	# 2.5 borough and district tables
	_db.query("""
		CREATE TABLE IF NOT EXISTS boroughs (
    		borough_id TEXT PRIMARY KEY,
    		display_name TEXT NOT NULL,         -- e.g., "Aston Borough Council", "Solihull Metropolitan"
    		controlling_party_id INTEGER,       -- Political control / council majority
    		police_division_code TEXT,          -- "D_DIVISION" (patrol division)
    		base_council_tax_rate REAL,         -- Local rates / levies
    		valid_from INTEGER NOT NULL,
    		valid_to INTEGER,
    		change_reason_id INTEGER NOT NULL,
			FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION
		);
	""")

	_db.query("""
		CREATE TABLE IF NOT EXISTS districts (
    		district_id TEXT PRIMARY KEY,
    		borough_id TEXT NOT NULL,
    		display_name TEXT NOT NULL,
    		district_type TEXT NOT NULL,
    		grid_x INTEGER NOT NULL,
    		grid_z INTEGER NOT NULL,
    		grid_width INTEGER DEFAULT 1,
    		grid_height INTEGER DEFAULT 1,
    
    		-- Design Baseline Expectations (from Archetypes & World Gen)
    		target_building_count INTEGER DEFAULT 0,
    		expected_pop_min INTEGER DEFAULT 0,
    		expected_pop_max INTEGER DEFAULT 0,
    		base_unemployment_rate REAL DEFAULT 0.0,
    		base_disposable_income REAL DEFAULT 0.0,
    		base_zone_health REAL DEFAULT 50.0,
    		base_police_heat REAL DEFAULT 0.20,
    
    		-- Simulation & Auditing Flags
    		is_home_turf INTEGER DEFAULT 0,
    		valid_from INTEGER NOT NULL,
    		valid_to INTEGER,
    		change_reason_id INTEGER NOT NULL,
    		FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (borough_id) REFERENCES boroughs(borough_id) ON DELETE NO ACTION
		);
	""")


	# 3. Establishments Table (Commercial & Industrial Establishments, Civic Enclaves)
	_db.query("""
		CREATE TABLE IF NOT EXISTS establishments (
			establishment_id INTEGER PRIMARY KEY AUTOINCREMENT,
			borough_id TEXT NOT NULL,
			district_id TEXT NOT NULL,
			building_id INTEGER DEFAULT 0,
			unit_door_number TEXT,
			owning_entity TEXT NOT NULL DEFAULT 'CIVIC', -- 'COUNCIL', 'PRIVATE_FREEHOLD', 'PRIVATE_LANDLORD'
			name TEXT NOT NULL,							 -- e.g. "Flat 4B, Birch Towers" or "The Crown & Anchor"
			category_id INTEGER NOT NULL,				 -- Links to system_labels (RESIDENTIAL_UNIT, COMMERCIAL, etc.)
			capacity INTEGER NOT NULL,					 -- Resident capacity for flats, employee/patron for commercial
			is_vacant INTEGER DEFAULT 0,				 -- 1 = Vacant property, 0 = Occupied
			valid_from INTEGER NOT NULL,
			valid_to INTEGER,
			change_reason_id INTEGER,
			FOREIGN KEY (category_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (district_id) REFERENCES districts(district_id) ON DELETE NO ACTION
		);
	""")

	# 4. Households Table (~46,000 across ~405 blocks)
	_db.query("""
		CREATE TABLE IF NOT EXISTS households (
			household_id INTEGER PRIMARY KEY AUTOINCREMENT,
			establishment_id INTEGER NOT NULL,  			-- The physical flat/unit they reside in
			residence_type_id INTEGER NOT NULL, 			-- COUNCIL_FLAT, TERRACE, SEMI_DETACHED
			wealth_bracket_id INTEGER NOT NULL DEFAULT 1,	-- 1 to 5
			local_pub_id INTEGER,							-- Preferred taproom / social anchor
			ethnicity_id INTEGER NOT NULL,
			religion_id INTEGER NOT NULL,
			valid_from INTEGER NOT NULL,
			valid_to INTEGER,
			change_reason_id INTEGER,
			FOREIGN KEY (residence_type_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (establishment_id) REFERENCES establishments(establishment_id) ON DELETE NO ACTION,
			FOREIGN KEY (wealth_bracket_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (local_pub_id) REFERENCES establishments(establishment_id) ON DELETE NO ACTION,
			FOREIGN KEY (ethnicity_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (religion_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION
		);
	""")

	# 5. Residents Table (~120,000 citizens)
	_db.query("""
		CREATE TABLE IF NOT EXISTS residents (
			resident_id INTEGER PRIMARY KEY AUTOINCREMENT,
			household_id INTEGER NOT NULL,
			first_name TEXT NOT NULL,
			birth_surname TEXT NOT NULL,
			current_surname TEXT NOT NULL,
			dob INTEGER NOT NULL,
			dod INTEGER,
			death_reason_id INTEGER,
			gender_id INTEGER NOT NULL,
			education_level_id INTEGER NOT NULL,
			ethnicity_id INTEGER NOT NULL,
			religion_id INTEGER NOT NULL,
			is_active_agent INTEGER DEFAULT 0,
			valid_from INTEGER NOT NULL,
			valid_to INTEGER,
			change_reason_id INTEGER,
			FOREIGN KEY (household_id) REFERENCES households(household_id) ON DELETE NO ACTION,
			FOREIGN KEY (death_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (gender_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (education_level_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (ethnicity_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (religion_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION
		);
	""")

	# 6. Social Relationships Table (Directed Dunbar Graph Edges)
	_db.query("""
		CREATE TABLE IF NOT EXISTS social_relationships (
			relationship_id INTEGER PRIMARY KEY AUTOINCREMENT,
			from_resident_id INTEGER NOT NULL,
			to_resident_id INTEGER NOT NULL,
			relationship_type_id INTEGER NOT NULL,
			context_establishment_id INTEGER,
			affinity_score REAL DEFAULT 0.5,
			valid_from INTEGER NOT NULL,
			valid_to INTEGER,
			change_reason_id INTEGER,
			UNIQUE(from_resident_id, to_resident_id, relationship_type_id, context_establishment_id),
			FOREIGN KEY (from_resident_id) REFERENCES residents(resident_id) ON DELETE CASCADE,
			FOREIGN KEY (to_resident_id) REFERENCES residents(resident_id) ON DELETE CASCADE,
			FOREIGN KEY (relationship_type_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (context_establishment_id) REFERENCES establishments(establishment_id) ON DELETE NO ACTION
		);
	""")

	# 7. Livelihood Contracts Table
	_db.query("""
		CREATE TABLE IF NOT EXISTS livelihood_contracts (
			contract_id INTEGER PRIMARY KEY AUTOINCREMENT,
			resident_id INTEGER NOT NULL,
			employer_entity_id TEXT NOT NULL,
			contract_class_id INTEGER NOT NULL,
			role_title_id INTEGER NOT NULL,
			contract_type_id INTEGER NOT NULL,
			schedule_window TEXT NOT NULL DEFAULT 'DAYTIME',
			weekly_hours REAL NOT NULL DEFAULT 40.0,
			compensation_rate REAL NOT NULL DEFAULT 0.0,
			valid_from INTEGER NOT NULL,
			valid_to INTEGER,
			change_reason_id INTEGER,
			FOREIGN KEY (resident_id) REFERENCES residents(resident_id) ON DELETE CASCADE,
			FOREIGN KEY (contract_class_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (role_title_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (contract_type_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
			FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION
		);
	""")

	# -------------------------------------------------------------
	# 8. VIRTUAL VIEWS
	# -------------------------------------------------------------
	_db.query("""
		CREATE VIEW IF NOT EXISTS v_district_census AS
		SELECT 
			d.district_id,
			d.display_name as district_name,
			COUNT(DISTINCT h.household_id) AS total_households,
			COUNT(DISTINCT r.resident_id) AS total_residents,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL THEN r.resident_id END) AS active_living_population,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL AND c.contract_id IS NOT NULL AND l_class.code = 'FORMAL_LEGAL' THEN r.resident_id END) AS formally_employed_count,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL AND c.contract_id IS NOT NULL AND l_class.code IN ('INFORMAL_GREY', 'ILLICIT_SYNDICATE') THEN r.resident_id END) AS street_informal_count,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL AND c.contract_id IS NOT NULL AND l_class.code = 'CUSTODIAL_INMATE' THEN r.resident_id END) AS incarcerated_count
		From districts d
		LEFT JOIN establishments e on d.district_id = e.district_id
		LEFT JOIN households h ON h.establishment_id = e.establishment_id
		LEFT JOIN residents r ON h.household_id = r.household_id
		LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id AND c.valid_to IS NULL
		LEFT JOIN system_labels l_class ON c.contract_class_id = l_class.label_id
		GROUP BY d.district_id, d.display_name;
	""")

	_db.query("""
		CREATE VIEW IF NOT EXISTS v_borough_census AS
		SELECT 
			b.borough_id,
			b.display_name as borough_name
			COUNT(DISTINCT d.district_id) as total_districts
			COUNT(DISTINCT h.household_id) AS total_households,
			COUNT(DISTINCT r.resident_id) AS total_residents,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL THEN r.resident_id END) AS active_living_population,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL AND c.contract_id IS NOT NULL AND l_class.code = 'FORMAL_LEGAL' THEN r.resident_id END) AS formally_employed_count,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL AND c.contract_id IS NOT NULL AND l_class.code IN ('INFORMAL_GREY', 'ILLICIT_SYNDICATE') THEN r.resident_id END) AS street_informal_count,
			COUNT(DISTINCT CASE WHEN r.dod IS NULL AND c.contract_id IS NOT NULL AND l_class.code = 'CUSTODIAL_INMATE' THEN r.resident_id END) AS incarcerated_count
		From boroughs b
		LEFT JOIN districts d on b.borough_id = d.borough_id
		LEFT JOIN establishments e on d.district_id = e.district_id
		LEFT JOIN households h ON h.establishment_id = e.establishment_id
		LEFT JOIN residents r ON h.household_id = r.household_id
		LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id AND c.valid_to IS NULL
		LEFT JOIN system_labels l_class ON c.contract_class_id = l_class.label_id
		GROUP BY b.borough_id, b.display_name;
	""")

	_db.query("""
		CREATE VIEW IF NOT EXISTS v_residents_overview AS
		SELECT 
			r.resident_id,
			r.household_id,
			e.district_id,
			r.first_name,
			r.current_surname,
			r.birth_surname,
			l_gender.code AS gender_code,
			l_gender.title AS gender_title,
			r.dob AS dob_day_offset,
			date((SELECT value FROM world_metadata WHERE key = 'epoch_date'), '+' || r.dob || ' days') AS formatted_birth_date,
			r.dod AS dod_day_offset,
			CASE 
				WHEN r.dod IS NOT NULL THEN date((SELECT value FROM world_metadata WHERE key = 'epoch_date'), '+' || r.dod || ' days') 
				ELSE NULL 
			END AS formatted_death_date,
			CASE WHEN r.dod IS NULL THEN 1 ELSE 0 END AS is_alive,
			l_edu.code AS education_code,
			l_edu.title AS education_title,
			l_eth.title AS ethnicity_title,
			l_rel.title AS religion_title,
			r.is_active_agent
		FROM residents r
		JOIN households h ON r.household_id = h.household_id
		JOIN establishments e on h.establishment_id = e.establishment_id
		JOIN system_labels l_gender ON r.gender_id = l_gender.label_id
		JOIN system_labels l_edu ON r.education_level_id = l_edu.label_id
		JOIN system_labels l_eth ON r.ethnicity_id = l_eth.label_id
		JOIN system_labels l_rel ON r.religion_id = l_rel.label_id;
	""")

	_db.query("""
		CREATE VIEW IF NOT EXISTS v_households_overview AS
		SELECT 
			h.household_id,
			b.display_name as borough_name,
			b.borough_id,
			d.display_name as district_name,
			d.district_id,
			l_res.code AS residence_type_code,
			l_res.title AS residence_type_title,
			h.wealth_bracket_id,
			h.local_pub_id,
			e_pub.name AS local_pub_name,
			l_eth.title AS dominant_ethnicity_title,
			l_rel.title AS dominant_religion_title
		FROM households h
		JOIN establishments e on h.establishment_id = e.establishment_id
		JOIN districts d on e.district_id = d.district_id
		JOIN boroughs b on d.borough_id = b.borough_id
		JOIN system_labels l_res ON h.residence_type_id = l_res.label_id
		JOIN system_labels l_eth ON h.ethnicity_id = l_eth.label_id
		JOIN system_labels l_rel ON h.religion_id = l_rel.label_id
		LEFT JOIN establishments e_pub ON h.local_pub_id = e_pub.establishment_id;
	""")

	_db.query("""
		CREATE VIEW IF NOT EXISTS v_active_contracts AS
		SELECT 
			c.contract_id,
			c.resident_id,
			r.first_name || ' ' || r.current_surname AS full_name,
			e.district_id AS home_district_id,
			c.employer_entity_id,
			COALESCE(e.name, c.employer_entity_id) AS employer_name,
			l_class.code AS contract_class_code,
			l_class.title AS contract_class_title,
			l_role.code AS role_title_code,
			l_role.title AS role_title,
			c.schedule_window,
			c.weekly_hours,
			c.compensation_rate,
			date((SELECT value FROM world_metadata WHERE key = 'epoch_date'), '+' || c.valid_from || ' days') AS contract_start_date
		FROM livelihood_contracts c
		JOIN residents r ON c.resident_id = r.resident_id
		JOIN households h ON r.household_id = h.household_id
		JOIN system_labels l_class ON c.contract_class_id = l_class.label_id
		JOIN system_labels l_role ON c.role_title_id = l_role.label_id
		LEFT JOIN establishments e ON ('ESTAB_' || e.establishment_id) = c.employer_entity_id
		WHERE c.valid_to IS NULL AND r.dod IS NULL;
	""")

	_db.query("""
		CREATE VIEW IF NOT EXISTS v_establishments_overview AS
		SELECT 
			e.establishment_id,
			e.borough_id,
			e.district_id,
			e.name,
			e.owning_entity,
			l_cat.code AS category_code,
			l_cat.title AS category_title,
			e.capacity,
			COUNT(c.contract_id) AS active_contract_count
		FROM establishments e
		JOIN system_labels l_cat ON e.category_id = l_cat.label_id
		LEFT JOIN livelihood_contracts c ON ('ESTAB_' || e.establishment_id) = c.employer_entity_id AND c.valid_to IS NULL
		WHERE e.valid_to IS NULL
		GROUP BY e.establishment_id;
	""")

	_db.query("""
		CREATE VIEW IF NOT EXISTS v_composite_bonds AS
		SELECT 
			r.from_resident_id, 
			r.to_resident_id,
			COUNT(*) AS shared_ties_count,
			SUM(r.affinity_score) AS total_affinity,
			GROUP_CONCAT(l.title, ', ') AS ties_summary
		FROM social_relationships r
		JOIN system_labels l ON r.relationship_type_id = l.label_id
		WHERE r.valid_to IS NULL
		GROUP BY r.from_resident_id, r.to_resident_id;
	""")

	# 9. Performance Indexes
	_db.query("CREATE INDEX IF NOT EXISTS idx_labels_lookup ON system_labels(domain, code);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_res_living ON residents(dod) WHERE dod IS NULL;")
	_db.query("CREATE INDEX IF NOT EXISTS idx_res_household ON residents(household_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_est_district ON establishments(district_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_dis_borough ON districts(borough_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_est_category ON establishments(category_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_est_vacant ON establishments(is_vacant) WHERE is_vacant = 1;")
	_db.query("CREATE INDEX IF NOT EXISTS idx_hh_pub ON households(local_pub_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_rel_pair ON social_relationships(from_resident_id, to_resident_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_contracts_resident ON livelihood_contracts(resident_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_contracts_employer ON livelihood_contracts(employer_entity_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_households_estab ON households(establishment_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_districts_borough ON districts(borough_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_rel_to ON social_relationships(to_resident_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_res_surname ON residents(current_surname);")


## 1. Populates core engine labels from external localized JSON dictionary
static func populate_core_system_labels(labels_file_path: String = "res://data_modules/core/localization/db_labels_en_gb.json") -> void:
	assert(FileAccess.file_exists(labels_file_path), "FATAL: Core system label dictionary missing: %s" % labels_file_path)
	var file := FileAccess.open(labels_file_path, FileAccess.READ)
	assert(file != null, "FATAL: Could not read core label dictionary: %s" % labels_file_path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	assert(parsed is Dictionary and parsed.has("labels"), "FATAL: Invalid dictionary format in: %s" % labels_file_path)
	
	var inserts: Array[String] = []
	for item in parsed["labels"]:
		var dom: String = str(item.get("domain", "")).to_upper()
		var code: String = str(item.get("code", "")).to_upper()
		var title: String = str(item.get("title", "")).replace("'", "''")
		var desc: String = str(item.get("description", "")).replace("'", "''")
		
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
	print("[DBManager] Synchronized %d total labels (Core JSON + Scenario Harvested)." % _label_cache.size())

static func _append_label_sql(out_array: Array[String], domain: String, code: String, title: String) -> void:
	out_array.append("""
		INSERT INTO system_labels (domain, code, title, description)
		VALUES ('%s', '%s', '%s', '')
		ON CONFLICT(domain, code) DO UPDATE SET title = excluded.title;
	""" % [domain.to_upper(), code.to_upper(), title.replace("'", "''")])

## Follows the Single Source of Truth Chain to seed epoch metadata from configs
static func _init_temporal_metadata() -> void:
	var demo_json: Dictionary = MANIFEST_MANAGER.load_module("demographics")
	assert(demo_json.has("temporal_anchor"), "FATAL: demographics JSON missing 'temporal_anchor'")
	var temp_cfg: Dictionary = demo_json["temporal_anchor"]

	CALENDAR_HELPER.initialize(temp_cfg)

	set_metadata("epoch_date", CALENDAR_HELPER.get_epoch_date())
	set_metadata("simulation_start_date", str(temp_cfg["simulation_start_date"]))
	set_metadata("days_per_tick", str(CALENDAR_HELPER.get_days_per_tick()))
	print("[DBManager] Seeded temporal metadata -> Epoch: '%s', Start: '%s'" % [
		CALENDAR_HELPER.get_epoch_date(), 
		str(temp_cfg["simulation_start_date"])
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

	# Fallback: Check if inserted directly in DB but missed by cache
	var res = query_rows("SELECT label_id FROM system_labels WHERE domain = '%s' AND code = '%s';" % [domain.to_upper(), code.to_upper()])
	if not res.is_empty():
		var id := int(res[0]["label_id"])
		_label_cache[key] = id
		return id

	# Hard fail: No silent fallbacks, no auto-inserts
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
	for sql in sql_statements:
		if not _db.query(sql):
			_db.query("ROLLBACK;")
			push_error("[DBManager] Batch transaction failed on: %s" % sql)
			return false
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
			print("[DBManager] Seed mismatch detected (DB: '%s' vs Current: '%s'). Rebuilding." % [db_seed, expected_seed])
			return false

	return true

## Stores arbitrary system metadata key-value pairs (seed, epoch_date, sim_start_date)
static func set_metadata(key: String, value: String) -> void:
	if _db == null: return
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

## Closes the active database connection cleanly
static func close_database() -> void:
	if _db != null:
		_db.close_db()
		_db = null
		_label_cache.clear()
		print("[DBManager] Database connection closed.")

## Returns true if the internal SQLite instance exists and has an open connection
static func is_database_open() -> bool:
	return _db != null