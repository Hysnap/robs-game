# res://systems/target_resolvers/resolver_obligation.gd
extends RefCounted

const ObligationLedgerScript = preload("res://systems/economy/obligation_ledger.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

const DOMAIN_TOKEN := "OBLIGATION"

static func resolve(target_cat: Dictionary, world_state: Dictionary, _verb_code: String) -> Array[Dictionary]:
	var direction: String = str(target_cat.get("direction", "ALL")).strip_edges().to_upper()
	var role_filter: String = "ANY"
	if direction == "RECEIVABLE":
		role_filter = "CREDITOR"
	elif direction == "PAYABLE":
		role_filter = "DEBTOR"

	var crew_list: Array[Dictionary] = IntelManagerScript.get_crew_residents(world_state)
	var seen_ids: Dictionary = {}
	var matched_rows: Array[Dictionary] = []

	for member in crew_list:
		var res_id: String = str(member.get("id", "")).strip_edges()
		if res_id.is_empty():
			continue
		var scoped_ref: String = ObligationLedgerScript.format_scoped_entity("RESIDENT", res_id)
		var rows: Array = ObligationLedgerScript.get_obligations_for_entity(scoped_ref, role_filter, "ACTIVE")
		for row in rows:
			if not (row is Dictionary):
				continue
			var obl_id: int = int(row.get("obligation_id", 0))
			if obl_id <= 0 or seen_ids.has(obl_id):
				continue
			seen_ids[obl_id] = true
			matched_rows.append(row)

	matched_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("obligation_id", 0)) < int(b.get("obligation_id", 0))
	)

	var results: Array[Dictionary] = []
	var any_tok: String = "UI_OBL_ANY_ACTIVE"
	var any_disp: String = str(TranslationServer.translate(any_tok))
	if any_disp.is_empty() or any_disp == any_tok:
		any_disp = "Any Active Obligation"
	results.append({
		"id": "ANY_ACTIVE_OBLIGATION",
		"label_token": any_tok,
		"display": any_disp,
		"unit_cost": 0.0,
		"balance": 0.0,
		"category": "OBLIGATION",
		"sub_category": "ANY",
		"taxonomy_path": []
	})

	for row in matched_rows:
		var obl_id_str: String = str(row.get("obligation_id", ""))
		var obl_type: String = str(row.get("obligation_type", "OBLIGATION")).strip_edges().to_upper()
		var bal: float = float(row.get("balance", 0.0))
		results.append({
			"id": obl_id_str,
			"label_token": "UI_OBL_" + obl_type,
			"display": "#%s %s (%s)" % [obl_id_str, obl_type, String.num(bal, 2)],
			"unit_cost": 0.0,
			"balance": bal,
			"category": "OBLIGATION",
			"sub_category": obl_type,
			"taxonomy_path": []
		})

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display", "")).nocasecmp_to(str(b.get("display", ""))) < 0
	)

	return results