-- res://data_modules/core/schema/tables/02_spatial_and_establishments.sql
-- Tier 11: Spatial Hierarchy (Boroughs, Districts), Organizations, and Physical Establishments

CREATE TABLE IF NOT EXISTS boroughs (
	borough_id TEXT PRIMARY KEY,
	display_name TEXT NOT NULL,
	controlling_party_id INTEGER,
	police_division_code TEXT,
	base_council_tax_rate REAL,
	valid_from INTEGER NOT NULL,
	valid_to INTEGER,
	change_reason_id INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS districts (
	district_id TEXT PRIMARY KEY,
	borough_id TEXT,
	display_name TEXT,
	district_type TEXT NOT NULL,
	grid_x INTEGER NOT NULL,
	grid_z INTEGER NOT NULL,
	grid_width INTEGER DEFAULT 1,
	grid_height INTEGER DEFAULT 1,
	target_building_count INTEGER DEFAULT 0,
	expected_pop_min INTEGER DEFAULT 0,
	expected_pop_max INTEGER DEFAULT 0,
	base_unemployment_rate REAL DEFAULT 0.0,
	base_disposable_income REAL DEFAULT 0.0,
	base_zone_health REAL DEFAULT 50.0,
	base_police_heat REAL DEFAULT 0.20,
	is_home_turf INTEGER DEFAULT 0,
	valid_from INTEGER NOT NULL,
	valid_to INTEGER,
	change_reason_id INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS organizations (
	org_id TEXT PRIMARY KEY,
	display_name TEXT NOT NULL,
	org_type TEXT NOT NULL,
	legal_status TEXT NOT NULL DEFAULT 'FORMAL',
	institution_rail_class TEXT NOT NULL DEFAULT 'STANDARD',
	hq_establishment_id INTEGER DEFAULT NULL,
	valid_from INTEGER NOT NULL,
	valid_to INTEGER,
	change_reason_id INTEGER
);

CREATE TABLE IF NOT EXISTS establishments (
	establishment_id INTEGER PRIMARY KEY AUTOINCREMENT,
	district_id TEXT NOT NULL,
	building_index INTEGER DEFAULT 0,
	unit_door_number TEXT,
	owner_org_id TEXT DEFAULT NULL,
	name TEXT NOT NULL,
	category_id INTEGER NOT NULL,
	capacity INTEGER NOT NULL,
	is_vacant INTEGER DEFAULT 0,
	valid_from INTEGER NOT NULL,
	valid_to INTEGER,
	change_reason_id INTEGER,
	FOREIGN KEY (owner_org_id) REFERENCES organizations(org_id) ON DELETE SET NULL,
	FOREIGN KEY (category_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
	FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION,
	FOREIGN KEY (district_id) REFERENCES districts(district_id) ON DELETE NO ACTION
);