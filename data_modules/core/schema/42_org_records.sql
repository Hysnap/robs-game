-- res://data_modules/core/schema/42_org_records.sql
-- Tier 42: Persisted Organizational Paper Trail, Filed Slips, Storage Medium & Soft-Delete Disposal
CREATE TABLE
    IF NOT EXISTS org_records (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        org_id TEXT NOT NULL,
        storage_establishment_id INTEGER DEFAULT NULL,
        standing_order_id INTEGER DEFAULT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        filing_domain TEXT NOT NULL DEFAULT 'DIARY',
        scope_type TEXT DEFAULT NULL,
        scope_id TEXT DEFAULT NULL,
        sim_day INTEGER NOT NULL,
        week_tick INTEGER NOT NULL DEFAULT 1,
        verb TEXT NOT NULL DEFAULT '',
        action_label TEXT NOT NULL DEFAULT '',
        author_resident_id INTEGER DEFAULT NULL,
        author_name TEXT NOT NULL DEFAULT '',
        target_node_id TEXT NOT NULL DEFAULT '',
        display_text TEXT NOT NULL,
        stationery_profile TEXT NOT NULL DEFAULT '',
        storage_medium TEXT NOT NULL DEFAULT 'PAPER',
        volume_units REAL NOT NULL DEFAULT 1.0,
        evidence_weight REAL NOT NULL DEFAULT 0.0,
        payload_json TEXT NOT NULL DEFAULT '{}',
        created_day INTEGER NOT NULL,
        filed_day INTEGER DEFAULT NULL,
        disposed_day INTEGER DEFAULT NULL,
        disposal_method TEXT DEFAULT NULL,
        FOREIGN KEY (org_id) REFERENCES organizations (org_id) ON DELETE CASCADE,
        FOREIGN KEY (storage_establishment_id) REFERENCES establishments (establishment_id) ON DELETE SET NULL,
        FOREIGN KEY (standing_order_id) REFERENCES standing_orders (standing_order_id) ON DELETE SET NULL,
        FOREIGN KEY (author_resident_id) REFERENCES residents (resident_id) ON DELETE SET NULL
    );

CREATE INDEX IF NOT EXISTS idx_org_records_domain_scope ON org_records (org_id, status, filing_domain, scope_id);

CREATE INDEX IF NOT EXISTS idx_org_records_day ON org_records (org_id, status, sim_day);

CREATE INDEX IF NOT EXISTS idx_org_records_author ON org_records (org_id, status, author_resident_id);

CREATE INDEX IF NOT EXISTS idx_org_records_storage ON org_records (storage_establishment_id, status);

CREATE INDEX IF NOT EXISTS idx_org_records_standing_order ON org_records (standing_order_id, sim_day);