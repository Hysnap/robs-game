-- res://data_modules/core/schema/indexes/201_performance_indexes.sql
-- Tier 201: Relational Lookup & Query Performance Indexes
CREATE INDEX IF NOT EXISTS idx_labels_lookup ON system_labels (domain, code);

CREATE INDEX IF NOT EXISTS idx_adhoc_entity ON entity_adhoc_measures (entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_adhoc_measure ON entity_adhoc_measures (measure_id);

CREATE INDEX IF NOT EXISTS idx_res_living ON residents (dod)
WHERE
    dod IS NULL;

CREATE INDEX IF NOT EXISTS idx_res_household ON residents (household_id);

CREATE INDEX IF NOT EXISTS idx_res_pub ON residents (local_pub_id);

CREATE INDEX IF NOT EXISTS idx_res_church ON residents (church_id);

CREATE INDEX IF NOT EXISTS idx_res_surname ON residents (current_surname);

CREATE INDEX IF NOT EXISTS idx_hh_head ON households (head_resident_id);

CREATE INDEX IF NOT EXISTS idx_households_estab ON households (establishment_id);

CREATE INDEX IF NOT EXISTS idx_est_district ON establishments (district_id);

CREATE INDEX IF NOT EXISTS idx_est_category ON establishments (category_id);

CREATE INDEX IF NOT EXISTS idx_est_vacant ON establishments (is_vacant)
WHERE
    is_vacant = 1;

CREATE INDEX IF NOT EXISTS idx_est_owner_org ON establishments (owner_org_id);

CREATE INDEX IF NOT EXISTS idx_dis_borough ON districts (borough_id);

CREATE INDEX IF NOT EXISTS idx_rel_pair ON social_relationships (from_resident_id, to_resident_id);

CREATE INDEX IF NOT EXISTS idx_rel_to ON social_relationships (to_resident_id);

CREATE INDEX IF NOT EXISTS idx_contracts_resident ON livelihood_contracts (resident_id);

CREATE INDEX IF NOT EXISTS idx_contracts_employer_org ON livelihood_contracts (employer_org_id);

CREATE INDEX IF NOT EXISTS idx_contracts_employer_estab ON livelihood_contracts (employer_establishment_id);

CREATE INDEX IF NOT EXISTS idx_org_members_org ON organization_members (org_id, valid_to);

CREATE INDEX IF NOT EXISTS idx_org_members_res ON organization_members (resident_id, valid_to);

CREATE INDEX IF NOT EXISTS idx_calendar_events_window ON calendar_events (status, start_day, end_day);

CREATE INDEX IF NOT EXISTS idx_calendar_events_loc ON calendar_events (location_scope, location_id);

CREATE INDEX IF NOT EXISTS idx_obligations_debtor ON obligations (debtor_scope, debtor_id, status);

CREATE INDEX IF NOT EXISTS idx_obligations_creditor ON obligations (creditor_scope, creditor_id, status);

CREATE INDEX IF NOT EXISTS idx_obligations_due ON obligations (status, due_day);

CREATE INDEX IF NOT EXISTS idx_obligations_accrual ON obligations (status, next_accrual_day);

CREATE INDEX IF NOT EXISTS idx_obligations_event ON obligations (linked_event_id);

CREATE INDEX IF NOT EXISTS idx_settlements_day ON pending_settlements (status, settles_on_day);

CREATE INDEX IF NOT EXISTS idx_settlements_obl ON pending_settlements (obligation_id, status);

CREATE INDEX IF NOT EXISTS idx_postal_delivery ON postal_mail (delivery_day, status);

CREATE INDEX IF NOT EXISTS idx_postal_dest ON postal_mail (destination_estab_id, status);

CREATE INDEX IF NOT EXISTS idx_slots_vacancy ON workplace_job_slots (is_filled, min_education_level_id);

CREATE INDEX IF NOT EXISTS idx_slots_estab ON workplace_job_slots (establishment_id);

CREATE INDEX IF NOT EXISTS idx_slots_cat ON workplace_job_slots (sector_category_id);

CREATE INDEX IF NOT EXISTS idx_standing_orders_resident ON standing_orders(assigned_resident_id, is_active, valid_to);

CREATE INDEX IF NOT EXISTS idx_standing_orders_org ON standing_orders(org_id, is_active, valid_to);