-- res://data_modules/core/schema/tables/31_workplaces_and_relationships.sql
-- Tier 31: Workplace Job Slots, Social Relationships, Livelihood Contracts, and Organization Memberships
CREATE TABLE
    IF NOT EXISTS workplace_job_slots (
        slot_id INTEGER PRIMARY KEY AUTOINCREMENT,
        establishment_id INTEGER NOT NULL,
        sector_category_id INTEGER,
        role_title_id INTEGER NOT NULL,
        contract_class_id INTEGER,
        min_education_level_id INTEGER NOT NULL,
        contract_type_id INTEGER,
        schedule_window_id INTEGER NOT NULL,
        weekly_hours REAL NOT NULL DEFAULT 37.5,
        hourly_rate REAL NOT NULL DEFAULT 3.50,
        is_field_worker INTEGER NOT NULL DEFAULT 0,
        is_filled INTEGER NOT NULL DEFAULT 0,
        active_resident_id INTEGER DEFAULT NULL,
        valid_from INTEGER NOT NULL,
        valid_to INTEGER,
        change_reason_id INTEGER NOT NULL,
        FOREIGN KEY (establishment_id) REFERENCES establishments (establishment_id) ON DELETE CASCADE,
        FOREIGN KEY (sector_category_id) REFERENCES system_labels (label_id),
        FOREIGN KEY (role_title_id) REFERENCES system_labels (label_id),
        FOREIGN KEY (contract_class_id) REFERENCES system_labels (label_id),
        FOREIGN KEY (min_education_level_id) REFERENCES system_labels (label_id),
        FOREIGN KEY (contract_type_id) REFERENCES system_labels (label_id),
        FOREIGN KEY (schedule_window_id) REFERENCES system_labels (label_id),
        FOREIGN KEY (active_resident_id) REFERENCES residents (resident_id) ON DELETE SET NULL
    );

CREATE TABLE
    IF NOT EXISTS social_relationships (
        relationship_id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_resident_id INTEGER NOT NULL,
        to_resident_id INTEGER NOT NULL,
        relationship_type_id INTEGER NOT NULL,
        context_establishment_id INTEGER,
        affinity_score REAL DEFAULT 0.5,
        valid_from INTEGER NOT NULL,
        valid_to INTEGER,
        change_reason_id INTEGER,
        UNIQUE (
            from_resident_id,
            to_resident_id,
            relationship_type_id,
            context_establishment_id
        ),
        FOREIGN KEY (from_resident_id) REFERENCES residents (resident_id) ON DELETE CASCADE,
        FOREIGN KEY (to_resident_id) REFERENCES residents (resident_id) ON DELETE CASCADE,
        FOREIGN KEY (relationship_type_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION,
        FOREIGN KEY (change_reason_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION,
        FOREIGN KEY (context_establishment_id) REFERENCES establishments (establishment_id) ON DELETE NO ACTION
    );

CREATE TABLE
    IF NOT EXISTS livelihood_contracts (
        contract_id INTEGER PRIMARY KEY AUTOINCREMENT,
        resident_id INTEGER NOT NULL,
        employer_org_id TEXT DEFAULT NULL,
        employer_establishment_id INTEGER DEFAULT NULL,
        contract_class_id INTEGER NOT NULL,
        role_title_id INTEGER NOT NULL,
        contract_type_id INTEGER NOT NULL,
        schedule_window_id INTEGER NOT NULL,
        weekly_hours REAL NOT NULL DEFAULT 40.0,
        compensation_rate REAL NOT NULL DEFAULT 0.0,
        valid_from INTEGER NOT NULL,
        valid_to INTEGER,
        change_reason_id INTEGER,
        FOREIGN KEY (resident_id) REFERENCES residents (resident_id) ON DELETE CASCADE,
        FOREIGN KEY (employer_org_id) REFERENCES organizations (org_id) ON DELETE SET NULL,
        FOREIGN KEY (employer_establishment_id) REFERENCES establishments (establishment_id) ON DELETE SET NULL,
        FOREIGN KEY (contract_class_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION,
        FOREIGN KEY (schedule_window_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION,
        FOREIGN KEY (role_title_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION,
        FOREIGN KEY (contract_type_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION,
        FOREIGN KEY (change_reason_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION
    );

CREATE TABLE
    IF NOT EXISTS organization_members (
        membership_id INTEGER PRIMARY KEY AUTOINCREMENT,
        org_id TEXT NOT NULL,
        resident_id INTEGER NOT NULL,
        role_code TEXT NOT NULL,
        authority_mask INTEGER NOT NULL DEFAULT 1,
        valid_from INTEGER NOT NULL,
        valid_to INTEGER,
        change_reason_id INTEGER,
        UNIQUE (org_id, resident_id, role_code, valid_from),
        FOREIGN KEY (org_id) REFERENCES organizations (org_id) ON DELETE CASCADE,
        FOREIGN KEY (resident_id) REFERENCES residents (resident_id) ON DELETE CASCADE,
        FOREIGN KEY (change_reason_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION
    );

CREATE TABLE IF NOT EXISTS standing_orders (
	standing_order_id INTEGER PRIMARY KEY AUTOINCREMENT,
	assigned_resident_id INTEGER NOT NULL,
	issuer_resident_id INTEGER DEFAULT NULL,
	org_id TEXT DEFAULT NULL,
	title TEXT NOT NULL,
	cadence_rule TEXT NOT NULL DEFAULT 'DAILY',
	cadence_params_json TEXT NOT NULL DEFAULT '{}',
	steps_json TEXT NOT NULL DEFAULT '[]',
	estimated_hours REAL NOT NULL DEFAULT 2.0,
	priority INTEGER NOT NULL DEFAULT 50,
	is_active INTEGER NOT NULL DEFAULT 1,
	valid_from INTEGER NOT NULL,
	valid_to INTEGER DEFAULT NULL,
	change_reason_id INTEGER NOT NULL,
	FOREIGN KEY (assigned_resident_id) REFERENCES residents(resident_id) ON DELETE CASCADE,
	FOREIGN KEY (issuer_resident_id) REFERENCES residents(resident_id) ON DELETE SET NULL,
	FOREIGN KEY (org_id) REFERENCES organizations(org_id) ON DELETE SET NULL,
	FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION
);

CREATE TABLE IF NOT EXISTS org_mandates (
	mandate_id INTEGER PRIMARY KEY AUTOINCREMENT,
	org_id TEXT NOT NULL,
	issuer_org_id TEXT DEFAULT NULL,
	target_org_id TEXT DEFAULT NULL,
	manager_resident_id INTEGER DEFAULT NULL,
	reports_to_resident_id INTEGER DEFAULT NULL,
	title TEXT NOT NULL,
	mandate_mode TEXT NOT NULL DEFAULT 'CASHFLOW',
	scope_filter_json TEXT NOT NULL DEFAULT '{}',
	planning_horizon TEXT NOT NULL DEFAULT 'WEEK',
	commitment_lock_until_day INTEGER NOT NULL DEFAULT 0,
	heat_ceiling REAL NOT NULL DEFAULT 0.65,
	target_metric_json TEXT NOT NULL DEFAULT '{}',
	float_obligation_id INTEGER DEFAULT NULL,
	remittance_obligation_id INTEGER DEFAULT NULL,
	assistance_request_expires_day INTEGER NOT NULL DEFAULT -1,
	is_active INTEGER NOT NULL DEFAULT 1,
	valid_from INTEGER NOT NULL,
	valid_to INTEGER DEFAULT NULL,
	change_reason_id INTEGER NOT NULL,
	FOREIGN KEY (org_id) REFERENCES organizations(org_id) ON DELETE CASCADE,
	FOREIGN KEY (issuer_org_id) REFERENCES organizations(org_id) ON DELETE SET NULL,
	FOREIGN KEY (target_org_id) REFERENCES organizations(org_id) ON DELETE CASCADE,
	FOREIGN KEY (manager_resident_id) REFERENCES residents(resident_id) ON DELETE CASCADE,
	FOREIGN KEY (reports_to_resident_id) REFERENCES residents(resident_id) ON DELETE SET NULL,
	FOREIGN KEY (change_reason_id) REFERENCES system_labels(label_id) ON DELETE NO ACTION
);