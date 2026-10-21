# res://systems/db_manager.gd
class_name DBManager
extends RefCounted

const DB_PATH: String = "user://game_society.db"

static var _db = null

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

	if reset_existing:
		_drop_society_schema()

	_create_society_schema()
	print("[DBManager] Connected to SQLite database at: %s" % absolute_path)
	return true

## Drops existing tables if resetting a seed
static func _drop_society_schema() -> void:
	if _db == null: return
	_db.query("DROP TABLE IF EXISTS social_relationships;")
	_db.query("DROP TABLE IF EXISTS residents;")
	_db.query("DROP TABLE IF EXISTS households;")
	_db.query("DROP TABLE IF EXISTS establishments;")

## Builds the Living Society & Dunbar Graph Relational Schema
static func _create_society_schema() -> void:
	if _db == null: return

	# Establishments Table (Commercial & Industrial Establishments)
	_db.query("""
		CREATE TABLE IF NOT EXISTS establishments (
			establishment_id INTEGER PRIMARY KEY,
			borough_id TEST NOT NULL,
			district_id TEXT NOT NULL,
			name TEXT NOT NULL,
			category TEXT NOT NULL,
			capacity INTEGER NOT NULL
		);
	""")

	# Households Table (~46,000 across ~405 blocks)
	_db.query("""
		CREATE TABLE IF NOT EXISTS households (
			household_id INTEGER PRIMARY KEY,
			borough_id TEST NOT NULL,
			district_id TEXT NOT NULL,
			residence_type TEXT NOT NULL,
			wealth_bracket INTEGER NOT NULL,
			local_pub_id TEXT NOT NULL,
			ethnicity TEXT NOT NULL,
			religion TEXT NOT NULL
		);
	""")

	# Residents Table (~120,000 citizens)
	_db.query("""
		CREATE TABLE IF NOT EXISTS residents (
			resident_id INTEGER PRIMARY KEY,
			household_id INTEGER NOT NULL,
			establishment_id INTERGER DEFAULT 0,
			first_name TEXT NOT NULL,
			surname TEXT NOT NULL,
			age INTEGER NOT NULL,
			occupation_type TEXT NOT NULL,
			ethnicity TEXT NOT NULL,
			religion TEST NOT NULL,
			is_active_agent INTEGER DEFAULT 0,
			FOREIGN KEY (household_id) REFERENCES households(household_id) ON DELETE CASCADE,
			FOREIGN KEY (establishment_id) REFERENCES establishments(establishment_id) ON DELETE SET NULL
		);
	""")

	# Social Relationships Table (Directed Dunbar Graph Edges)
	_db.query("""
		CREATE TABLE IF NOT EXISTS social_relationships (
			from_resident_id INTEGER NOT NULL,
			to_resident_id INTEGER NOT NULL,
			relationship_type TEXT NOT NULL,
			affinity_score REAL DEFAULT 0.5,
			PRIMARY KEY (from_resident_id, to_resident_id)
		);
	""")

	# 4. Crucial Performance Indexes (Enables 0.05ms graph lookups)
	_db.query("CREATE INDEX IF NOT EXISTS idx_hh_district ON households(district_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_hh_pub ON households(local_pub_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_hh_ethnicity ON households(ethnicity);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_hh_religion ON households(religion);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_res_household ON residents(household_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_res_establishment ON residents(establishment_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_res_ethnicity ON residents(ethnicity);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_res_religion ON residents(religion);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_rel_from ON social_relationships(from_resident_id);")
	_db.query("CREATE INDEX IF NOT EXISTS idx_rel_to ON social_relationships(to_resident_id);")

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