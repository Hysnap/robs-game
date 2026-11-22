# res://systems/target_resolvers/resolver_instrument.gd
class_name ResolverInstrument
extends RefCounted

const DOMAIN_TOKEN := "INSTRUMENT"
const DB_MGR = preload("res://systems/db_manager.gd")

## Resolves delivered paper instruments and correspondence (cheques, giros, bank statements, notices) from SQLite postal_mail
static func resolve(config: Dictionary, world_state: Dictionary, category_filter: String = "") -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var allowed_types: Array = config.get("item_types", [])
	var cat_upper := category_filter.strip_edges().to_upper()

	# Gather crew resident IDs and controlled establishment IDs from world_state
	var resident_ids: Array[String] = []
	var residents: Dictionary = world_state.get("residents", {})
	for r_key in residents.keys():
		var rec = residents[r_key]
		if rec is Dictionary and bool(rec.get("is_crew", false)):
			var rid := str(rec.get("resident_id", r_key)).strip_edges()
			if not rid.is_empty():
				resident_ids.append("'%s'" % rid.replace("'", "''"))

	var estab_ids: Array[String] = []
	var estabs: Dictionary = world_state.get("establishments", {})
	for e_key in estabs.keys():
		var erec = estabs[e_key]
		if erec is Dictionary and bool(erec.get("is_player_controlled", true)):
			var eid := str(erec.get("estab_id", e_key)).strip_edges()
			if not eid.is_empty():
				estab_ids.append("'%s'" % eid.replace("'", "''"))

	var scope_clauses: Array[String] = []
	if not resident_ids.is_empty():
		scope_clauses.append("(recipient_scope = 'RESIDENT' AND recipient_id IN (%s))" % ", ".join(resident_ids))
	if not estab_ids.is_empty():
		scope_clauses.append("(recipient_scope = 'ESTABLISHMENT' AND recipient_id IN (%s))" % ", ".join(estab_ids))

	# Always expose optimistic ("planning with hope") instrument-class targets so players can
	# stage deposit/encash runs at a counter without requiring pre-existing inventory in hand.
	const OPTIMISTIC_INSTRUMENTS: Array[Dictionary] = [
		{"id": "ALL_REDEEMABLE_INSTRUMENTS", "label_token": "UI_INSTR_ALL_REDEEMABLE", "category": "INSTRUMENT"},
		{"id": "CHEQUE", "label_token": "UI_INSTR_CHEQUE", "category": "INSTRUMENT"},
		{"id": "GIRO_VOUCHER", "label_token": "UI_INSTR_GIRO_VOUCHER", "category": "INSTRUMENT"},
		{"id": "POSTAL_ORDER", "label_token": "UI_INSTR_POSTAL_ORDER", "category": "INSTRUMENT"}
	]
	for opt in OPTIMISTIC_INSTRUMENTS:
		var opt_type: String = str(opt["id"])
		if not allowed_types.is_empty() and opt_type != "ALL_REDEEMABLE_INSTRUMENTS" and not allowed_types.has(opt_type):
			continue
		if not cat_upper.is_empty() and cat_upper != "ALL" and cat_upper != "INSTRUMENT" and opt_type != cat_upper:
			continue
		var tok: String = str(opt["label_token"])
		var disp: String = str(TranslationServer.translate(tok))
		if disp.is_empty() or disp == tok:
			disp = opt_type.replace("_", " ").capitalize()
		results.append({
			"id": opt_type,
			"label_token": tok,
			"display": disp,
			"category": "INSTRUMENT",
			"unit_cost": 0.0
		})

	if scope_clauses.is_empty() or not DB_MGR.is_database_open():
		results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("display", "")).nocasecmp_to(str(b.get("display", ""))) < 0
		)
		return results

	var sql := """
		SELECT mail_id, item_type, subject_token, payload_json, enclosed_cash, delivery_day
		FROM postal_mail
		WHERE status = 'DELIVERED'
		  AND (%s)
		ORDER BY delivery_day ASC, mail_id ASC;
	""" % " OR ".join(scope_clauses)

	var rows := DB_MGR.query_rows(sql)
	for row in rows:
		var item_type := str(row.get("item_type", "NOTICE")).strip_edges().to_upper()
		if not allowed_types.is_empty() and not allowed_types.has(item_type):
			continue
		if not cat_upper.is_empty() and cat_upper != "ALL" and item_type != cat_upper:
			continue

		var payload_str := str(row.get("payload_json", "{}"))
		var parsed = JSON.parse_string(payload_str)
		var payload: Dictionary = parsed if parsed is Dictionary else {}
		var val := float(payload.get("amount", payload.get("closing_balance", row.get("enclosed_cash", 0.0))))

		var subj_tok: String = str(row.get("subject_token", "UI_MAIL_SUBJECT_DEFAULT"))
		var subj_disp: String = str(TranslationServer.translate(subj_tok))
		if subj_disp.is_empty() or subj_disp == subj_tok:
			subj_disp = item_type.replace("_", " ").capitalize()

		results.append({
			"id": str(row["mail_id"]),
			"label_token": subj_tok,
			"display": "#%s %s" % [str(row["mail_id"]), subj_disp],
			"category": item_type,
			"unit_cost": val,
			"mail_id": int(row["mail_id"]),
			"payload": payload
		})

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display", "")).nocasecmp_to(str(b.get("display", ""))) < 0
	)

	return results