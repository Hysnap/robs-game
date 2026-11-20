-- res://data_modules/core/schema/tables/41_events_obligations_and_mail.sql
-- Tier 41: Shared Calendar Events, Bilateral Obligations, Pending Clearing Settlements, and Postal Mail
CREATE TABLE
    IF NOT EXISTS calendar_events (
        event_id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        title_token TEXT NOT NULL,
        organizer_scope TEXT DEFAULT NULL,
        organizer_id TEXT DEFAULT NULL,
        location_scope TEXT NOT NULL,
        location_id TEXT NOT NULL,
        start_day INTEGER NOT NULL,
        end_day INTEGER NOT NULL,
        recurrence_days INTEGER NOT NULL DEFAULT 0,
        visibility_scope TEXT NOT NULL DEFAULT 'PUBLIC',
        impacts_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'SCHEDULED',
        created_day INTEGER NOT NULL
    );

CREATE TABLE
    IF NOT EXISTS obligations (
        obligation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        debtor_scope TEXT NOT NULL,
        debtor_id TEXT NOT NULL,
        creditor_scope TEXT NOT NULL,
        creditor_id TEXT NOT NULL,
        obligation_type TEXT NOT NULL,
        linked_event_id INTEGER DEFAULT NULL,
        balance REAL NOT NULL DEFAULT 0.0,
        principal REAL NOT NULL DEFAULT 0.0,
        interest_rate REAL NOT NULL DEFAULT 0.0,
        periodic_amount REAL NOT NULL DEFAULT 0.0,
        recurrence_days INTEGER NOT NULL DEFAULT 0,
        next_accrual_day INTEGER NOT NULL DEFAULT -1,
        due_day INTEGER NOT NULL DEFAULT -1,
        accepted_rails_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_day INTEGER NOT NULL,
        updated_day INTEGER NOT NULL,
        FOREIGN KEY (linked_event_id) REFERENCES calendar_events (event_id) ON DELETE SET NULL
    );

CREATE TABLE
    IF NOT EXISTS pending_settlements (
        settlement_id INTEGER PRIMARY KEY AUTOINCREMENT,
        obligation_id INTEGER NOT NULL,
        payer_scope TEXT NOT NULL,
        payer_id TEXT NOT NULL,
        payee_scope TEXT NOT NULL,
        payee_id TEXT NOT NULL,
        drawer_bank_org_id TEXT DEFAULT NULL,
        rail_code TEXT NOT NULL,
        amount REAL NOT NULL,
        initiated_day INTEGER NOT NULL,
        presented_day INTEGER NOT NULL,
        settles_on_day INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING_CLEARANCE',
        FOREIGN KEY (obligation_id) REFERENCES obligations (obligation_id) ON DELETE CASCADE
    );

CREATE TABLE
    IF NOT EXISTS postal_mail (
        mail_id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender_scope TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        recipient_scope TEXT NOT NULL,
        recipient_id TEXT NOT NULL,
        destination_estab_id INTEGER NOT NULL,
        mail_class TEXT NOT NULL,
        delivery_round TEXT NOT NULL,
        item_type TEXT NOT NULL,
        linked_obligation_id INTEGER DEFAULT NULL,
        linked_settlement_id INTEGER DEFAULT NULL,
        enclosed_cash REAL NOT NULL DEFAULT 0.0,
        postage_due REAL NOT NULL DEFAULT 0.0,
        subject_token TEXT NOT NULL,
        body_token TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        posted_day INTEGER NOT NULL,
        delivery_day INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'IN_TRANSIT',
        opened_day INTEGER DEFAULT NULL,
        FOREIGN KEY (destination_estab_id) REFERENCES establishments (establishment_id) ON DELETE CASCADE,
        FOREIGN KEY (linked_obligation_id) REFERENCES obligations (obligation_id) ON DELETE SET NULL,
        FOREIGN KEY (linked_settlement_id) REFERENCES pending_settlements (settlement_id) ON DELETE SET NULL
    );