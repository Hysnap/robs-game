# res://systems/economy/org_mandate_manager.gd
class_name OrgMandateManager
extends RefCounted

const DBManagerScript = preload("res://systems/db_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const ObligationLedgerScript = preload("res://systems/economy/obligation_ledger.gd")

## Creates a 4-axis mandate (intra-org manager or inter-org ARMS_LENGTH affiliate) and syncs world_state
static func create_mandate(world_state: Dictionary, params: Dictionary) -> Dictionary:
	var org_id: String = str(params.get("org_id", "")).strip_edges()
	assert(not org_id.is_empty(), "FATAL: [OrgMandateManager] 'org_id' is required to create a mandate.")

	var issuer_org_id: String = str(params.get("issuer_org_id", "")).strip_edges()
	var target_org_id: String = str(params.get("target_org_id", "")).strip_edges()
	var manager_res_id: int = int(params.get("manager_resident_id", 0))
	var reports_to_id: int = int(params.get("reports_to_resident_id", 0))
	var title: String = str(params.get("title", "UI_MANDATE_DEFAULT")).strip_edges()
	var mandate_mode: String = str(params.get("mandate_mode", "CASHFLOW")).strip_edges().to_upper()
	var planning_horizon: String = str(params.get("planning_horizon", "WEEK")).strip_edges().to_upper()
	var heat_ceiling: float = float(params.get("heat_ceiling", 0.65))
	var current_day: int = int(params.get("valid_from", CalendarHelperScript.get_current_sim_day(world_state)))
	var lock_days: int = int(params.get("commitment_lock_days", _default_lock_days_for_horizon(planning_horizon)))
	var lock_until_day: int = int(params.get("commitment_lock_until_day", current_day + lock_days))

	var raw_scope: Variant = params.get("scope_filter", {})
	var scope_filter: Dictionary = normalize_scope_filter(raw_scope if raw_scope is Dictionary else {})
	var target_metrics: Dictionary = params.get("target_metrics", {}) if params.get("target_metrics", {}) is Dictionary else {}

	var float_obl_id: int = int(params.get("float_obligation_id", 0))
	var remit_obl_id: int = int(params.get("remittance_obligation_id", 0))

	var mandate_id: int = int(params.get("mandate_id", 0))
	if DBManagerScript.is_database_open() and _has_org_mandates_table():
		var reason_id: int = DBManagerScript.get_label_id("CHANGE_REASON", "WORLD_GENERATION")
		var issuer_sql := "'%s'" % issuer_org_id.replace("'", "''") if not issuer_org_id.is_empty() else "NULL"
		var target_org_sql := "'%s'" % target_org_id.replace("'", "''") if not target_org_id.is_empty() else "NULL"
		var mgr_sql := "%d" % manager_res_id if manager_res_id > 0 else "NULL"
		var rep_sql := "%d" % reports_to_id if reports_to_id > 0 else "NULL"
		var float_sql := "%d" % float_obl_id if float_obl_id > 0 else "NULL"
		var remit_sql := "%d" % remit_obl_id if remit_obl_id > 0 else "NULL"

		DBManagerScript.query_rows("""
			INSERT INTO org_mandates (
				org_id, issuer_org_id, target_org_id, manager_resident_id, reports_to_resident_id,
				title, mandate_mode, scope_filter_json, planning_horizon, commitment_lock_until_day,
				heat_ceiling, target_metric_json, float_obligation_id, remittance_obligation_id,
				assistance_request_expires_day, is_active, valid_from, valid_to, change_reason_id
			) VALUES (
				'%s', %s, %s, %s, %s,
				'%s', '%s', '%s', '%s', %d,
				%.3f, '%s', %s, %s,
				-1, 1, %d, NULL, %d
			);
		""" % [
			org_id.replace("'", "''"),
			issuer_sql, target_org_sql, mgr_sql, rep_sql,
			title.replace("'", "''"),
			mandate_mode.replace("'", "''"),
			JSON.stringify(scope_filter).replace("'", "''"),
			planning_horizon.replace("'", "''"),
			lock_until_day,
			heat_ceiling,
			JSON.stringify(target_metrics).replace("'", "''"),
			float_sql, remit_sql,
			current_day,
			reason_id
		])
		var id_rows: Array = DBManagerScript.query_rows("SELECT last_insert_rowid() AS id;")
		if not id_rows.is_empty():
			mandate_id = int(id_rows[0].get("id", 0))

	if mandate_id <= 0:
		mandate_id = _next_memory_mandate_id(world_state)

	var record: Dictionary = {
		"mandate_id": mandate_id,
		"org_id": org_id,
		"issuer_org_id": issuer_org_id,
		"target_org_id": target_org_id,
		"manager_resident_id": manager_res_id,
		"reports_to_resident_id": reports_to_id,
		"title": title,
		"mandate_mode": mandate_mode,
		"scope_filter": scope_filter,
		"planning_horizon": planning_horizon,
		"commitment_lock_until_day": lock_until_day,
		"heat_ceiling": heat_ceiling,
		"target_metrics": target_metrics,
		"float_obligation_id": float_obl_id,
		"remittance_obligation_id": remit_obl_id,
		"assistance_request_expires_day": - 1,
		"is_active": true,
		"valid_from": current_day
	}

	if not world_state.has("org_mandates") or not (world_state["org_mandates"] is Dictionary):
		world_state["org_mandates"] = {}
	world_state["org_mandates"][mandate_id] = record
	return record

## Normalizes the 4-axis scope_filter dictionary (spatial, premises, commodities, verbs)
static func normalize_scope_filter(raw: Dictionary) -> Dictionary:
	var spatial: Array[String] = []
	for s in raw.get("spatial", raw.get("district_ids", ["*"])):
		var clean := str(s).strip_edges()
		if not clean.is_empty():
			spatial.append(clean)
	if spatial.is_empty():
		spatial.append("*")

	var premises: Array = []
	for p in raw.get("premises", raw.get("establishment_ids", ["*"])):
		if p is int:
			premises.append(p)
		else:
			var s_p := str(p).strip_edges()
			if s_p.is_valid_int():
				premises.append(int(s_p))
			elif not s_p.is_empty():
				premises.append(s_p.to_upper())
	if premises.is_empty():
		premises.append("*")

	var commodities: Array[String] = []
	for c in raw.get("commodities", raw.get("commodity_categories", ["*"])):
		var clean_c := str(c).strip_edges().to_upper()
		if not clean_c.is_empty():
			commodities.append(clean_c)
	if commodities.is_empty():
		commodities.append("*")

	var verbs: Array[String] = []
	for v in raw.get("verbs", raw.get("allowed_verbs", ["*"])):
		var clean_v := str(v).strip_edges().to_upper()
		if not clean_v.is_empty():
			verbs.append(clean_v)
	if verbs.is_empty():
		verbs.append("*")

	return {
		"spatial": spatial,
		"premises": premises,
		"commodities": commodities,
		"verbs": verbs
	}

## Evaluates whether an operation context matches all 4 axes of a mandate's scope_filter
static func matches_scope(scope_filter: Dictionary, context: Dictionary) -> bool:
	var norm := normalize_scope_filter(scope_filter)

	# 1. Spatial axis (district_id)
	var district_id: String = str(context.get("district_id", "")).strip_edges()
	if not norm["spatial"].has("*") and not district_id.is_empty():
		if not norm["spatial"].has(district_id):
			return false

	# 2. Premises axis (establishment_id int or sector_code String)
	var estab_id: int = int(context.get("establishment_id", 0))
	var sector_code: String = str(context.get("sector_code", "")).strip_edges().to_upper()
	if not norm["premises"].has("*"):
		var matched_premise := false
		if estab_id > 0 and norm["premises"].has(estab_id):
			matched_premise = true
		if not sector_code.is_empty() and norm["premises"].has(sector_code):
			matched_premise = true
		if (estab_id > 0 or not sector_code.is_empty()) and not matched_premise:
			return false

	# 3. Commodity axis (exact item_id or hierarchical category prefix)
	var item_id: String = str(context.get("item_id", "")).strip_edges().to_upper()
	var item_cat: String = str(context.get("category", "")).strip_edges().to_upper()
	if not norm["commodities"].has("*") and (not item_id.is_empty() or not item_cat.is_empty()):
		var matched_comm := false
		for entry in norm["commodities"]:
			if entry == item_id or entry == item_cat or item_cat.begins_with(entry + " / "):
				matched_comm = true
				break
		if not matched_comm:
			return false

	# 4. Verb axis
	var verb_code: String = str(context.get("verb", "")).strip_edges().to_upper()
	if not norm["verbs"].has("*") and not verb_code.is_empty():
		if not norm["verbs"].has(verb_code):
			return false

	return true

## Returns which of the 4 axes overlap between two mandates (empty array = disjoint scopes)
static func detect_scope_overlap(scope_a: Dictionary, scope_b: Dictionary) -> Array[String]:
	var a := normalize_scope_filter(scope_a)
	var b := normalize_scope_filter(scope_b)
	var overlapping_axes: Array[String] = []

	for axis in ["spatial", "premises", "commodities", "verbs"]:
		var list_a: Array = a[axis]
		var list_b: Array = b[axis]
		if list_a.has("*") or list_b.has("*"):
			overlapping_axes.append(axis)
			continue
		for item in list_a:
			if list_b.has(item):
				overlapping_axes.append(axis)
				break

	return overlapping_axes

## Opens a solicited assistance window allowing superior/player intervention without loyalty penalty
static func grant_assistance_window(world_state: Dictionary, mandate_id: int, expires_day: int) -> void:
	var mandates: Dictionary = world_state.get("org_mandates", {})
	if mandates.has(mandate_id) and mandates[mandate_id] is Dictionary:
		mandates[mandate_id]["assistance_request_expires_day"] = expires_day
	if DBManagerScript.is_database_open() and _has_org_mandates_table():
		DBManagerScript.query_rows(
			"UPDATE org_mandates SET assistance_request_expires_day = %d WHERE mandate_id = %d;" % [expires_day, mandate_id]
		)

## Revokes an active mandate, persists valid_to / is_active in SQLite, and applies mid-horizon loyalty friction if locked
static func revoke_mandate(world_state: Dictionary, mandate_id: int, current_sim_day: int = -1) -> Dictionary:
	var mandates: Dictionary = world_state.get("org_mandates", {})
	if not mandates.has(mandate_id) or not (mandates[mandate_id] is Dictionary):
		return {"revoked": false, "mandate_id": mandate_id}

	var mandate: Dictionary = mandates[mandate_id]
	var sim_day: int = current_sim_day if current_sim_day >= 0 else CalendarHelperScript.get_current_sim_day(world_state)
	var target_org_id: String = str(mandate.get("target_org_id", "")).strip_edges()
	var orgs: Dictionary = world_state.get("organizations", {})
	var is_arms_length: bool = false
	if not target_org_id.is_empty() and orgs.has(target_org_id) and orgs[target_org_id] is Dictionary:
		is_arms_length = str(orgs[target_org_id].get("autonomy_mode", "")).to_upper() == "ARMS_LENGTH"

	var auth: Dictionary = evaluate_intervention_authorization(mandate, sim_day, is_arms_length)
	var loyalty_delta: float = 0.0
	if not bool(auth.get("authorized", true)):
		loyalty_delta = float(auth.get("loyalty_delta", 0.0))
	mandate["is_active"] = false
	mandate["valid_to"] = sim_day

	if loyalty_delta != 0.0:
		if not target_org_id.is_empty() and orgs.has(target_org_id) and orgs[target_org_id] is Dictionary:
			orgs[target_org_id]["loyalty"] = clampf(float(orgs[target_org_id].get("loyalty", 0.75)) + loyalty_delta, 0.0, 1.0)
		var mgr_id: int = int(mandate.get("manager_resident_id", 0))
		var residents: Dictionary = world_state.get("residents", {})
		if mgr_id > 0:
			var res_key: Variant = mgr_id if residents.has(mgr_id) else str(mgr_id)
			if residents.has(res_key) and residents[res_key] is Dictionary:
				residents[res_key]["loyalty"] = clampf(float(residents[res_key].get("loyalty", 0.75)) + loyalty_delta, 0.0, 1.0)

	if DBManagerScript.is_database_open() and _has_org_mandates_table():
		DBManagerScript.query_rows(
			"UPDATE org_mandates SET is_active = 0, valid_to = %d WHERE mandate_id = %d;" % [sim_day, mandate_id]
		)

	return {
		"revoked": true,
		"mandate_id": mandate_id,
		"reason": str(auth.get("reason", "")),
		"loyalty_delta": loyalty_delta
	}

## Evaluates whether a direct intervention on a delegated mandate is authorized or triggers friction
static func evaluate_intervention_authorization(mandate: Dictionary, current_sim_day: int, is_arms_length_org: bool = false) -> Dictionary:
	var assist_until: int = int(mandate.get("assistance_request_expires_day", -1))
	if assist_until >= current_sim_day:
		return {
			"authorized": true,
			"reason": "SOLICITED_ASSISTANCE",
			"loyalty_delta": 0.04,
			"excuse_granted": false
		}

	var lock_until: int = int(mandate.get("commitment_lock_until_day", 0))
	if current_sim_day >= lock_until and not is_arms_length_org:
		return {
			"authorized": true,
			"reason": "HORIZON_WINDOW_OPEN",
			"loyalty_delta": 0.0,
			"excuse_granted": false
		}

	return {
		"authorized": false,
		"reason": "UNSOLICITED_ARMS_LENGTH_MEDDLING" if is_arms_length_org else "UNSOLICITED_MID_HORIZON_OVERRIDE",
		"loyalty_delta": - 0.22 if is_arms_length_org else -0.12,
		"excuse_granted": true
	}

## Resolves macro aggregate performance for an ARMS_LENGTH subsidiary organization on its reporting cadence
static func resolve_arms_length_macro_cycle(world_state: Dictionary, mandate: Dictionary, current_sim_day: int) -> Dictionary:
	var target_org_id: String = str(mandate.get("target_org_id", "")).strip_edges()
	var target_metrics: Dictionary = mandate.get("target_metrics", {})
	var expected_remittance: float = float(target_metrics.get("remittance_target", 0.0))
	var heat_ceiling: float = float(mandate.get("heat_ceiling", 0.65))

	var org_state: Dictionary = world_state.get("organizations", {}).get(target_org_id, {})
	var current_heat: float = float(org_state.get("police_heat", 0.15))
	var org_loyalty: float = float(org_state.get("loyalty", 0.75))

	# Skimming & variance driven by subsidiary loyalty and heat
	var skim_ratio: float = clampf((0.85 - org_loyalty) * 0.35, 0.0, 0.30)
	var actual_remittance: float = roundf(expected_remittance * (1.0 - skim_ratio) * 100.0) / 100.0
	var heat_breached: bool = current_heat > heat_ceiling
	var target_missed: bool = expected_remittance > 0.0 and actual_remittance < (expected_remittance * 0.85)

	var remit_obl_id: int = int(mandate.get("remittance_obligation_id", 0))
	if remit_obl_id > 0 and actual_remittance > 0.0 and DBManagerScript.is_database_open():
		var obl_row: Dictionary = ObligationLedgerScript.get_obligation(remit_obl_id)
		if not obl_row.is_empty():
			var payer_ref: String = ObligationLedgerScript.format_scoped_entity(str(obl_row["debtor_scope"]), str(obl_row["debtor_id"]))
			var payee_ref: String = ObligationLedgerScript.format_scoped_entity(str(obl_row["creditor_scope"]), str(obl_row["creditor_id"]))
			ObligationLedgerScript.initiate_settlement(
				remit_obl_id,
				payer_ref,
				payee_ref,
				actual_remittance,
				"PHYSICAL_CASH",
				current_sim_day
			)

	return {
		"target_org_id": target_org_id,
		"mandate_id": int(mandate.get("mandate_id", 0)),
		"expected_remittance": expected_remittance,
		"actual_remittance": actual_remittance,
		"skim_ratio": skim_ratio,
		"current_heat": current_heat,
		"heat_breached": heat_breached,
		"target_missed": target_missed,
		"requires_exception_alert": heat_breached or target_missed
	}

static func _default_lock_days_for_horizon(horizon: String) -> int:
	match horizon.to_upper():
		"DAY": return 0
		"WEEK": return 7
		"MONTH": return 28
		"QUARTER": return 84
		_: return 7

static func _next_memory_mandate_id(world_state: Dictionary) -> int:
	var max_id: int = 0
	var mandates: Dictionary = world_state.get("org_mandates", {})
	for k in mandates.keys():
		if int(k) > max_id:
			max_id = int(k)
	return max_id + 1

static func _has_org_mandates_table() -> bool:
	var rows: Array = DBManagerScript.query_rows(
		"SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='org_mandates';"
	)
	return not rows.is_empty() and int(rows[0].get("cnt", 0)) > 0