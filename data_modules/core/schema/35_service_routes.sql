-- res://data_modules/core/schema/tables/35_service_routes.sql
-- Tier 35: Persisted Field & Route Worker Round Schedules (Milk, Pop, Coal, Insurance, Rent/Check)
CREATE TABLE
    IF NOT EXISTS service_routes (
        route_id INTEGER PRIMARY KEY AUTOINCREMENT,
        establishment_id INTEGER NOT NULL,
        worker_resident_id INTEGER NOT NULL,
        service_code TEXT NOT NULL,
        day_of_week INTEGER NOT NULL,
        time_window TEXT NOT NULL,
        target_district_id TEXT NOT NULL,
        action_mode TEXT NOT NULL,
        is_part_time INTEGER NOT NULL DEFAULT 0,
        valid_from INTEGER NOT NULL,
        valid_to INTEGER DEFAULT NULL,
        change_reason_id INTEGER NOT NULL,
        FOREIGN KEY (establishment_id) REFERENCES establishments (establishment_id) ON DELETE CASCADE,
        FOREIGN KEY (worker_resident_id) REFERENCES residents (resident_id) ON DELETE CASCADE,
        FOREIGN KEY (target_district_id) REFERENCES districts (district_id) ON DELETE CASCADE,
        FOREIGN KEY (change_reason_id) REFERENCES system_labels (label_id) ON DELETE NO ACTION
    );

CREATE INDEX IF NOT EXISTS idx_service_routes_worker_day ON service_routes (worker_resident_id, day_of_week, valid_to);

CREATE INDEX IF NOT EXISTS idx_service_routes_district_day ON service_routes (target_district_id, day_of_week, valid_to);

CREATE INDEX IF NOT EXISTS idx_service_routes_depot ON service_routes (establishment_id, service_code, valid_to);