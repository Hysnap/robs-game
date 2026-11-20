-- res://data_modules/core/schema/tables/01_core_metadata_and_labels.sql
-- Tier 01: Core Metadata, System Labels, and Sparse Ad-Hoc Measures (EAV)
CREATE TABLE
    IF NOT EXISTS world_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE
    IF NOT EXISTS system_labels (
        label_id INTEGER PRIMARY KEY AUTOINCREMENT,
        domain TEXT NOT NULL,
        code TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        UNIQUE (domain, code)
    );

CREATE TABLE
    IF NOT EXISTS adhoc_measure_definitions (
        measure_id INTEGER PRIMARY KEY AUTOINCREMENT,
        domain TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        data_type TEXT NOT NULL DEFAULT 'FLOAT'
    );

CREATE TABLE
    IF NOT EXISTS entity_adhoc_measures (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        measure_id INTEGER NOT NULL,
        num_value REAL DEFAULT 0.0,
        text_value TEXT DEFAULT '',
        valid_from INTEGER NOT NULL,
        valid_to INTEGER,
        PRIMARY KEY (entity_type, entity_id, measure_id),
        FOREIGN KEY (measure_id) REFERENCES adhoc_measure_definitions (measure_id) ON DELETE CASCADE
    );