# res://systems/economy/obligation_ledger.gd
class_name ObligationLedger
extends RefCounted

const DB_MGR = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

const VALID_SCOPES: Array[String] = ["RESIDENT", "ESTABLISHMENT", "ORG"]

## Parses a canonical "<SCOPE>:<ID>" string into { "scope": String, "id": String }
static func parse_scoped_entity(scoped_ref: String) -> Dictionary:
	var trimmed := scoped_ref.strip_edges()
	var parts := trimmed.split(":", false, 1)
	assert(parts.size() == 2, "FATAL: [ObligationLedger] Invalid scoped entity '%s'. Expected '<SCOPE>:<ID>'." % scoped_ref)
	var scope := parts[0].to_upper()
	var id := parts[1].strip_edges()
	assert(VALID_SCOPES.has(scope), "FATAL: [ObligationLedger] Unsupported entity scope '%s' in '%s'." % [scope, scoped_ref])
	assert(not id.is_empty(), "FATAL: [ObligationLedger] Empty entity ID in '%s'." % scoped_ref)
	return { "scope": scope, "id": id }

static func format_scoped_entity(scope: String, id: String) -> String:
	var clean_scope := scope.strip_edges().to_upper()
	assert(VALID_SCOPES.has(clean_scope), "FATAL: [ObligationLedger] Unsupported entity scope '%s'." % scope)
	return "%s:%s" % [clean_scope, id.strip_edges()]

## Creates a new bilateral or institutional obligation in SQLite and returns its obligation_id
static func create_obligation(params: Dictionary) -> int:
	var debtor := parse_scoped_entity(str(params.get("debtor", "")))
	var creditor := parse_scoped_entity(str(params.get("creditor", "")))
	var obl_type := str(params.get("obligation_type", "")).strip_edges().to_upper()
	assert(not obl_type.is_empty(), "FATAL: [ObligationLedger] create_obligation requires non-empty 'obligation_type'.")

	var principal := float(params.get("principal", params.get("balance", 0.0)))
	var balance := float(params.get("balance", principal))
	var interest_rate := float(params.get("interest_rate", 0.0))
	var periodic_amount := float(params.get("periodic_amount", 0.0))
	var recurrence_days := int(params.get("recurrence_days", 0))
	var created_day := int(params.get("created_day", CALENDAR_HELPER.get_simulation_start_day()))
	var next_accrual_day := int(params.get("next_accrual_day", (created_day + recurrence_days) if recurrence_days > 0 else -1))
	var due_day := int(params.get("due_day", -1))
	var accepted_rails: Array = params.get("accepted_rails", [])
	var rails_json := JSON.stringify(accepted_rails).replace("'", "''")

	var sql := """
		INSERT INTO obligations (
			debtor_scope, debtor_id, creditor_scope, creditor_id,
			obligation_type, balance, principal, interest_rate,
			periodic_amount, recurrence_days, next_accrual_day, due_day,
			accepted_rails_json, status, created_day, updated_day
		) VALUES (
			'%s', '%s', '%s', '%s',
			'%s', %.4f, %.4f, %.6f,
			%.4f, %d, %d, %d,
			'%s', 'ACTIVE', %d, %d
		);
	""" % [
		debtor["scope"], debtor["id"].replace("'", "''"),
		creditor["scope"], creditor["id"].replace("'", "''"),
		obl_type.replace("'", "''"), balance, principal, interest_rate,
		periodic_amount, recurrence_days, next_accrual_day, due_day,
		rails_json, created_day, created_day
	]

	var ok := DB_MGR.execute_batch([sql])
	assert(ok, "FATAL: [ObligationLedger] Failed to insert obligation record.")
	var id_rows := DB_MGR.query_rows("SELECT last_insert_rowid() AS id;")
	assert(not id_rows.is_empty(), "FATAL: [ObligationLedger] Failed to retrieve last_insert_rowid() for obligation.")
	return int(id_rows[0]["id"])

## Retrieves a single obligation row by ID, or empty Dictionary if not found
static func get_obligation(obligation_id: int) -> Dictionary:
	var rows := DB_MGR.query_rows("SELECT * FROM obligations WHERE obligation_id = %d;" % obligation_id)
	return rows[0] if not rows.is_empty() else {}

## Queries active obligations where the given scoped entity is debtor, creditor, or either ("ANY")
static func get_obligations_for_entity(scoped_ref: String, role: String = "ANY", status_filter: String = "ACTIVE") -> Array:
	var ent := parse_scoped_entity(scoped_ref)
	var scope_esc: String = ent["scope"]
	var id_esc: String = ent["id"].replace("'", "''")
	var status_esc: String = status_filter.strip_edges().to_upper().replace("'", "''")

	var clauses: Array[String] = []
	if not status_esc.is_empty() and status_esc != "ALL":
		clauses.append("status = '%s'" % status_esc)

	match role.strip_edges().to_upper():
		"DEBTOR":
			clauses.append("(debtor_scope = '%s' AND debtor_id = '%s')" % [scope_esc, id_esc])
		"CREDITOR":
			clauses.append("(creditor_scope = '%s' AND creditor_id = '%s')" % [scope_esc, id_esc])
		_:
			clauses.append("((debtor_scope = '%s' AND debtor_id = '%s') OR (creditor_scope = '%s' AND creditor_id = '%s'))" % [
				scope_esc, id_esc, scope_esc, id_esc
			])

	var where_sql := "WHERE " + " AND ".join(clauses)
	return DB_MGR.query_rows("SELECT * FROM obligations %s ORDER BY obligation_id ASC;" % where_sql)

## Adjusts an obligation's balance by delta (negative reduces balance, positive increases balance).
## Non-revolving obligations with periodic_amount == 0 automatically mark SETTLED when balance reaches <= 0.0001.
static func adjust_obligation_balance(obligation_id: int, delta: float, current_day: int, auto_settle_zero: bool = true) -> Dictionary:
	var obl := get_obligation(obligation_id)
	assert(not obl.is_empty(), "FATAL: [ObligationLedger] Cannot adjust missing obligation_id=%d." % obligation_id)

	var old_balance := float(obl["balance"])
	var new_balance := maxf(0.0, old_balance + delta)
	var obl_type := str(obl["obligation_type"])
	var periodic := float(obl["periodic_amount"])
	var is_revolving := (obl_type == "DEMAND_DEPOSIT" or periodic > 0.0)

	var new_status := str(obl["status"])
	if auto_settle_zero and not is_revolving and new_balance <= 0.0001:
		new_balance = 0.0
		new_status = "SETTLED"

	var sql := """
		UPDATE obligations
		SET balance = %.4f, status = '%s', updated_day = %d
		WHERE obligation_id = %d;
	""" % [new_balance, new_status, current_day, obligation_id]
	DB_MGR.execute_batch([sql])

	return {
		"obligation_id": obligation_id,
		"old_balance": old_balance,
		"new_balance": new_balance,
		"applied_delta": new_balance - old_balance,
		"status": new_status
	}

## Resolves the active settlement rail config for the current simulation year from civic_hierarchy
static func get_settlement_rail_config(rail_code: String, current_year: int) -> Dictionary:
	assert(MANIFEST_MGR.has_module("civic_hierarchy"), "FATAL: [ObligationLedger] Scenario manifest missing 'civic_hierarchy' module.")
	var civic_data: Dictionary = MANIFEST_MGR.load_module("civic_hierarchy")
	var rails: Dictionary = civic_data.get("settlement_rails", {})
	assert(not rails.is_empty(), "FATAL: [ObligationLedger] 'civic_hierarchy' module missing 'settlement_rails'.")
	var key := rail_code.strip_edges().to_upper()
	assert(rails.has(key), "FATAL: [ObligationLedger] Unknown settlement rail '%s'." % rail_code)
	var cfg: Dictionary = rails[key]
	var from_yr := int(cfg.get("valid_from_year", -9999))
	var to_yr := int(cfg.get("valid_to_year", 9999))
	assert(current_year >= from_yr and current_year <= to_yr, "FATAL: [ObligationLedger] Settlement rail '%s' is invalid in year %d (%d..%d)." % [
		key, current_year, from_yr, to_yr
	])
	return cfg

## Initiates a payment against an obligation via a specific settlement rail (instant cash vs clearing float).
static func initiate_settlement(
	obligation_id: int,
	payer_ref: String,
	payee_ref: String,
	amount: float,
	rail_code: String,
	initiated_day: int,
	presented_day: int = -1,
	drawer_bank_org_id: String = ""
) -> Dictionary:
	assert(amount > 0.0, "FATAL: [ObligationLedger] Settlement amount must be positive.")
	var obl := get_obligation(obligation_id)
	assert(not obl.is_empty(), "FATAL: [ObligationLedger] Unknown obligation_id=%d." % obligation_id)

	var payer := parse_scoped_entity(payer_ref)
	var payee := parse_scoped_entity(payee_ref)
	var effective_presented := presented_day if presented_day >= 0 else initiated_day
	var sim_year := CALENDAR_HELPER.day_to_year(effective_presented)
	var rail_cfg := get_settlement_rail_config(rail_code, sim_year)

	var clearing_days := int(rail_cfg.get("clearing_working_days", 0))
	var clearing_mode := str(rail_cfg.get("clearing_mode", "BANKING"))
	var settles_on_day := CALENDAR_HELPER.add_working_days(effective_presented, clearing_days, clearing_mode)

	# Instant on-the-spot settlement (0 clearing days and already presented)
	if clearing_days == 0 and effective_presented <= initiated_day:
		var adj := adjust_obligation_balance(obligation_id, -amount, initiated_day, true)
		return {
			"settled_immediately": true,
			"settlement_id": 0,
			"settles_on_day": initiated_day,
			"obligation_result": adj
		}

	var bank_sql := "'%s'" % drawer_bank_org_id.replace("'", "''") if not drawer_bank_org_id.is_empty() else "NULL"
	var sql := """
		INSERT INTO pending_settlements (
			obligation_id, payer_scope, payer_id, payee_scope, payee_id,
			drawer_bank_org_id, rail_code, amount,
			initiated_day, presented_day, settles_on_day, status
		) VALUES (
			%d, '%s', '%s', '%s', '%s',
			%s, '%s', %.4f,
			%d, %d, %d, 'PENDING_CLEARANCE'
		);
	""" % [
		obligation_id,
		payer["scope"], payer["id"].replace("'", "''"),
		payee["scope"], payee["id"].replace("'", "''"),
		bank_sql, rail_code.strip_edges().to_upper(), amount,
		initiated_day, effective_presented, settles_on_day
	]
	DB_MGR.execute_batch([sql])
	var id_rows := DB_MGR.query_rows("SELECT last_insert_rowid() AS id;")
	var settlement_id := int(id_rows[0]["id"]) if not id_rows.is_empty() else 0

	return {
		"settled_immediately": false,
		"settlement_id": settlement_id,
		"presented_day": effective_presented,
		"settles_on_day": settles_on_day
	}

## Dispatches physical or electronic mail using era-windowed postal_rules and working-day delivery rules
## Dispatches physical or electronic mail using era-windowed postal_rules from civic_hierarchy and working-day delivery rules
static func dispatch_mail(params: Dictionary) -> Dictionary:
	assert(MANIFEST_MGR.has_module("civic_hierarchy"), "FATAL: [ObligationLedger] Scenario manifest missing 'civic_hierarchy' module.")
	var civic_data: Dictionary = MANIFEST_MGR.load_module("civic_hierarchy")
	var postal_cfg: Dictionary = civic_data.get("postal_rules", {})
	assert(not postal_cfg.is_empty(), "FATAL: [ObligationLedger] 'civic_hierarchy' module missing 'postal_rules'.")

	var sender := parse_scoped_entity(str(params.get("sender", "")))
	var recipient := parse_scoped_entity(str(params.get("recipient", "")))
	var dest_estab_id := int(params.get("destination_estab_id", 0))
	assert(dest_estab_id > 0, "FATAL: [ObligationLedger] dispatch_mail requires valid 'destination_estab_id'.")

	var mail_class := str(params.get("mail_class", "SECOND_CLASS")).strip_edges().to_upper()
	var item_type := str(params.get("item_type", "NOTICE")).strip_edges().to_upper()
	var subject_token := str(params.get("subject_token", "UI_MAIL_SUBJECT_DEFAULT"))
	var body_token := str(params.get("body_token", "UI_MAIL_BODY_DEFAULT"))
	var posted_day := int(params.get("posted_day", CALENDAR_HELPER.get_simulation_start_day()))
	var distance_hops := float(params.get("distance_hops", 0.0))
	var enclosed_cash := float(params.get("enclosed_cash", 0.0))
	var postage_due := float(params.get("postage_due", 0.0))
	var payload_json := JSON.stringify(params.get("payload", {})).replace("'", "''")

	var sim_year := CALENDAR_HELPER.day_to_year(posted_day)
	var active_schedule: Dictionary = {}
	for sched in postal_cfg.get("era_schedules", []):
		if sched is Dictionary:
			var from_yr := int(sched.get("valid_from_year", -9999))
			var to_yr := int(sched.get("valid_to_year", 9999))
			if sim_year >= from_yr and sim_year <= to_yr:
				active_schedule = sched
				break
	assert(not active_schedule.is_empty(), "FATAL: [ObligationLedger] No postal era_schedule configured for year %d." % sim_year)

	var transit_map: Dictionary = active_schedule.get("transit_days", {})
	assert(transit_map.has(mail_class), "FATAL: [ObligationLedger] Mail class '%s' unavailable in year %d." % [mail_class, sim_year])

	var base_transit := int(transit_map[mail_class])
	var dist_factor := float(active_schedule.get("distance_days_per_hop", 0.0))
	var total_transit := base_transit + int(round(distance_hops * dist_factor))

	var class_def: Dictionary = postal_cfg.get("classes", {}).get(mail_class, {})
	var is_physical := bool(class_def.get("is_physical", true))
	var raw_arrival := posted_day + total_transit
	var delivery_day := CALENDAR_HELPER.next_valid_delivery_day(raw_arrival) if is_physical else raw_arrival

	var windows: Array = active_schedule.get("delivery_windows", ["MORNING_ROUND"])
	var requested_round := str(params.get("delivery_round", "")).strip_edges().to_upper()
	var delivery_round := requested_round if (not requested_round.is_empty() and windows.has(requested_round)) else str(windows[0])

	var linked_obl_sql := str(int(params["linked_obligation_id"])) if params.has("linked_obligation_id") and int(params["linked_obligation_id"]) > 0 else "NULL"
	var linked_set_sql := str(int(params["linked_settlement_id"])) if params.has("linked_settlement_id") and int(params["linked_settlement_id"]) > 0 else "NULL"
	var initial_status := "DELIVERED" if delivery_day <= posted_day else "IN_TRANSIT"

	var sql := """
		INSERT INTO postal_mail (
			sender_scope, sender_id, recipient_scope, recipient_id,
			destination_estab_id, mail_class, delivery_round, item_type,
			linked_obligation_id, linked_settlement_id,
			enclosed_cash, postage_due, subject_token, body_token, payload_json,
			posted_day, delivery_day, status, opened_day
		) VALUES (
			'%s', '%s', '%s', '%s',
			%d, '%s', '%s', '%s',
			%s, %s,
			%.4f, %.4f, '%s', '%s', '%s',
			%d, %d, '%s', NULL
		);
	""" % [
		sender["scope"], sender["id"].replace("'", "''"),
		recipient["scope"], recipient["id"].replace("'", "''"),
		dest_estab_id, mail_class, delivery_round, item_type.replace("'", "''"),
		linked_obl_sql, linked_set_sql,
		enclosed_cash, postage_due,
		subject_token.replace("'", "''"), body_token.replace("'", "''"), payload_json,
		posted_day, delivery_day, initial_status
	]
	DB_MGR.execute_batch([sql])
	var id_rows := DB_MGR.query_rows("SELECT last_insert_rowid() AS id;")
	var mail_id := int(id_rows[0]["id"]) if not id_rows.is_empty() else 0

	return {
		"mail_id": mail_id,
		"delivery_day": delivery_day,
		"delivery_round": delivery_round,
		"status": initial_status
	}

## Executes daily ledger rollover: delivers arrived mail, clears matured settlements, accrues periodic obligations/interest, and flags overdue defaults.
static func process_daily_tick(current_sim_day: int) -> Dictionary:
	var summary := {
		"delivered_mail": [],
		"cleared_settlements": [],
		"dishonoured_settlements": [],
		"accrued_obligations": [],
		"overdue_obligations": []
	}

	# 1. Deliver IN_TRANSIT postal mail arriving on or before current_sim_day
	var arriving_mail := DB_MGR.query_rows("""
		SELECT * FROM postal_mail
		WHERE status = 'IN_TRANSIT' AND delivery_day <= %d
		ORDER BY delivery_day ASC, mail_id ASC;
	""" % current_sim_day)
	if not arriving_mail.is_empty():
		DB_MGR.execute_batch([
			"UPDATE postal_mail SET status = 'DELIVERED' WHERE status = 'IN_TRANSIT' AND delivery_day <= %d;" % current_sim_day
		])
		summary["delivered_mail"] = arriving_mail

	# 2. Finalize PENDING_CLEARANCE settlements maturing on or before current_sim_day
	var maturing := DB_MGR.query_rows("""
		SELECT * FROM pending_settlements
		WHERE status = 'PENDING_CLEARANCE' AND settles_on_day <= %d
		ORDER BY settles_on_day ASC, settlement_id ASC;
	""" % current_sim_day)
	for s in maturing:
		var s_id := int(s["settlement_id"])
		var obl_id := int(s["obligation_id"])
		var amt := float(s["amount"])
		var cleared := true
		var raw_bank = s.get("drawer_bank_org_id", null)
		var bank_org := str(raw_bank).strip_edges() if raw_bank != null else ""

		# If drawn against a bank demand deposit, verify drawer has sufficient deposit balance
		if not bank_org.is_empty() and bank_org != "None":
			var p_scope := str(s["payer_scope"])
			var p_id := str(s["payer_id"]).replace("'", "''")
			var dep_rows := DB_MGR.query_rows("""
				SELECT obligation_id, balance FROM obligations
				WHERE debtor_scope = 'ORG' AND debtor_id = '%s'
				  AND creditor_scope = '%s' AND creditor_id = '%s'
				  AND obligation_type = 'DEMAND_DEPOSIT' AND status = 'ACTIVE'
				LIMIT 1;
			""" % [bank_org.replace("'", "''"), p_scope, p_id])
			if dep_rows.is_empty() or float(dep_rows[0]["balance"]) < amt:
				cleared = false
			else:
				adjust_obligation_balance(int(dep_rows[0]["obligation_id"]), -amt, current_sim_day, false)

		if cleared:
			var adj := adjust_obligation_balance(obl_id, -amt, current_sim_day, true)
			DB_MGR.execute_batch([
				"UPDATE pending_settlements SET status = 'SETTLED' WHERE settlement_id = %d;" % s_id
			])
			summary["cleared_settlements"].append({
				"settlement_id": s_id,
				"obligation_id": obl_id,
				"amount": amt,
				"obligation_result": adj
			})
		else:
			DB_MGR.execute_batch([
				"UPDATE pending_settlements SET status = 'DISHONOURED' WHERE settlement_id = %d;" % s_id
			])
			summary["dishonoured_settlements"].append({
				"settlement_id": s_id,
				"obligation_id": obl_id,
				"amount": amt
			})

	# 3. Accrue periodic obligations (pensions, benefits, rent, protection tithes) & interest
	var due_accruals := DB_MGR.query_rows("""
		SELECT * FROM obligations
		WHERE status = 'ACTIVE' AND next_accrual_day >= 0 AND next_accrual_day <= %d
		ORDER BY obligation_id ASC;
	""" % current_sim_day)
	var accrual_updates: Array[String] = []
	for obl in due_accruals:
		var obl_id := int(obl["obligation_id"])
		var bal := float(obl["balance"])
		var rate := float(obl["interest_rate"])
		var periodic := float(obl["periodic_amount"])
		var rec_days := int(obl["recurrence_days"])
		var next_day := int(obl["next_accrual_day"])

		var interest_delta := bal * rate
		var new_bal := bal + interest_delta + periodic
		var new_next := (next_day + rec_days) if rec_days > 0 else -1

		accrual_updates.append("""
			UPDATE obligations
			SET balance = %.4f, next_accrual_day = %d, updated_day = %d
			WHERE obligation_id = %d;
		""" % [new_bal, new_next, current_sim_day, obl_id])

		summary["accrued_obligations"].append({
			"obligation_id": obl_id,
			"obligation_type": str(obl["obligation_type"]),
			"old_balance": bal,
			"new_balance": new_bal,
			"periodic_added": periodic,
			"interest_added": interest_delta
		})
	if not accrual_updates.is_empty():
		DB_MGR.execute_batch(accrual_updates)

	# 4. Identify overdue active obligations past due_day
	var overdue := DB_MGR.query_rows("""
		SELECT * FROM obligations
		WHERE status = 'ACTIVE' AND due_day > 0 AND due_day < %d AND balance > 0.0
		ORDER BY due_day ASC, obligation_id ASC;
	""" % current_sim_day)
	summary["overdue_obligations"] = overdue

	return summary

## Declarative verb-impact entry point invoked by SimController when a directive's impacts/*.json targets OBLIGATION
static func process_verb_impact(world_state: Dictionary, directive: Dictionary, impact_cfg: Dictionary) -> Dictionary:
	var model: String = str(impact_cfg.get("model", "")).to_upper().strip_edges()
	var current_day: int = int(world_state.get("metadata", {}).get("current_sim_day", CALENDAR_HELPER.get_simulation_start_day()))

	match model:
		"CREATE_OBLIGATION":
			var debtor_ref: String = _resolve_directive_entity_ref(directive, impact_cfg, "debtor", "counterparty_id", "RESIDENT")
			var creditor_ref: String = _resolve_directive_entity_ref(directive, impact_cfg, "creditor", "assigned_to", "RESIDENT")
			var obl_type: String = str(directive.get("obligation_type", impact_cfg.get("obligation_type", ""))).to_upper().strip_edges()
			assert(not obl_type.is_empty(), "FATAL: [ObligationLedger] CREATE_OBLIGATION impact requires explicit 'obligation_type'.")
			var principal: float = float(directive.get("amount", impact_cfg.get("default_principal", 0.0)))
			assert(principal > 0.0, "FATAL: [ObligationLedger] CREATE_OBLIGATION impact requires positive 'amount'.")

			var due_offset: int = int(directive.get("due_in_days", impact_cfg.get("default_due_in_days", -1)))
			var due_day: int = (current_day + due_offset) if due_offset > 0 else int(directive.get("due_day", -1))

			var create_params: Dictionary = {
				"debtor": debtor_ref,
				"creditor": creditor_ref,
				"obligation_type": obl_type,
				"principal": principal,
				"balance": float(directive.get("initial_balance", principal)),
				"interest_rate": float(directive.get("interest_rate", impact_cfg.get("interest_rate", 0.0))),
				"periodic_amount": float(directive.get("periodic_amount", impact_cfg.get("periodic_amount", 0.0))),
				"recurrence_days": int(directive.get("recurrence_days", impact_cfg.get("recurrence_days", 0))),
				"due_day": due_day,
				"created_day": current_day
			}
			var rails = directive.get("accepted_rails", impact_cfg.get("accepted_rails", []))
			if rails is Array and not rails.is_empty():
				create_params["accepted_rails"] = rails

			var new_id: int = create_obligation(create_params)
			directive["created_obligation_id"] = new_id
			return {
				"model": model,
				"obligation_id": new_id,
				"debtor": debtor_ref,
				"creditor": creditor_ref,
				"balance": create_params["balance"]
			}

		"SETTLE_OBLIGATION":
			var obl_id: int = int(directive.get("obligation_id", directive.get("target_obligation_id", 0)))
			assert(obl_id > 0, "FATAL: [ObligationLedger] SETTLE_OBLIGATION impact requires valid 'obligation_id'.")
			var obl: Dictionary = get_obligation(obl_id)
			assert(not obl.is_empty(), "FATAL: [ObligationLedger] Unknown obligation_id=%d in SETTLE_OBLIGATION impact." % obl_id)

			var payer_ref: String = format_scoped_entity(str(obl["debtor_scope"]), str(obl["debtor_id"]))
			var payee_ref: String = format_scoped_entity(str(obl["creditor_scope"]), str(obl["creditor_id"]))
			var amount: float = float(directive.get("amount", obl["balance"]))
			var rail_code: String = str(directive.get("rail_code", impact_cfg.get("default_rail_code", "PHYSICAL_CASH"))).to_upper().strip_edges()
			var presented_day: int = int(directive.get("presented_day", current_day))
			var drawer_bank: String = str(directive.get("drawer_bank_org_id", "")).strip_edges()

			var outcome: Dictionary = initiate_settlement(
				obl_id, payer_ref, payee_ref, amount, rail_code, current_day, presented_day, drawer_bank
			)
			outcome["model"] = model
			outcome["obligation_id"] = obl_id
			return outcome

		_:
			assert(false, "FATAL: [ObligationLedger] Unsupported OBLIGATION impact model '%s'." % model)
			return {}

static func _resolve_directive_entity_ref(
	directive: Dictionary,
	impact_cfg: Dictionary,
	role_key: String,
	fallback_directive_key: String,
	default_scope: String
) -> String:
	var explicit_key := "%s_ref" % role_key
	if directive.has(explicit_key) and not str(directive[explicit_key]).strip_edges().is_empty():
		return str(directive[explicit_key]).strip_edges()
	if impact_cfg.has(explicit_key) and not str(impact_cfg[explicit_key]).strip_edges().is_empty():
		return str(impact_cfg[explicit_key]).strip_edges()

	var raw_id := str(directive.get(fallback_directive_key, "")).strip_edges()
	assert(not raw_id.is_empty(), "FATAL: [ObligationLedger] Missing entity reference for '%s' (checked '%s' and '%s')." % [
		role_key, explicit_key, fallback_directive_key
	])
	if raw_id.contains(":"):
		return raw_id
	var scope := str(directive.get("%s_scope" % role_key, impact_cfg.get("%s_scope" % role_key, default_scope))).to_upper().strip_edges()
	return format_scoped_entity(scope, raw_id)