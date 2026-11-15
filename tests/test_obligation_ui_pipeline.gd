# res://tests/test_obligation_ui_pipeline.gd
extends SceneTree

const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")
const DirectiveComposerControllerScript = preload("res://systems/directive_composer_controller.gd")
const ObligationLedgerScript = preload("res://systems/economy/obligation_ledger.gd")
const DBManagerScript = preload("res://systems/db_manager.gd")

func _init() -> void:
	print("--- [Test] Verifying Obligation & Crew UI Pipeline ---")
	var passed: bool = true

	# 1. Setup clean in-memory SQLite + world_state
	DBManagerScript.close_database()
	var db_ok: bool = DBManagerScript.initialize_database(true, ":memory:")
	if not db_ok:
		printerr("FAIL: Could not open in-memory SQLite database.")
		quit(1)
		return

	TargetDomainRegistryScript.clear_cache()

	var ws: Dictionary = {
		"metadata": { "current_sim_day": 100 },
		"districts": {
			"DISTRICT_MARKET": { "display_name": "Central Market", "is_public_landmark": true }
		},
		"residents": {
			"crew_0": {
				"resident_id": 101,
				"name": "Arthur Pendelton",
				"role_title": "BOSS",
				"is_crew": true,
				"current_district_id": "DISTRICT_MARKET"
			},
			"crew_1": {
				"resident_id": 102,
				"name": "Clara Vance",
				"role_title": "ACCOUNTANT",
				"is_crew": true,
				"current_district_id": "DISTRICT_MARKET"
			},
			"npc_201": {
				"resident_id": 201,
				"name": "Thomas Miller",
				"is_crew": false,
				"current_district_id": "DISTRICT_MARKET"
			}
		}
	}

	# 2. Verify canonical crew resolution (no crew_0 / crew_1 slot keys exposed as names)
	var crew := DirectiveComposerControllerScript.get_crew_actors(ws)
	if crew.size() != 2 or crew[0]["name"] != "Arthur Pendelton" or crew[0]["id"] != "101":
		printerr("FAIL: Expected canonical crew residents [Arthur Pendelton (101), Clara Vance (102)], got: %s" % str(crew))
		passed = false
	else:
		print("PASS: Canonical crew actors resolved with resident names and IDs (no crew_0/crew_1).")

	# 3. Verify pluggable SETTLEMENT_RAIL & POSTAL_CLASS resolvers
	var rails := TargetDomainRegistryScript.resolve_domain("SETTLEMENT_RAIL", ws)
	var has_cheque_post := false
	for r in rails:
		if str(r.get("id", "")) == "CLEARING_BANK_CHEQUE" and bool(r.get("can_post", false)):
			has_cheque_post = true
			break
	var postal_opts := TargetDomainRegistryScript.resolve_domain("POSTAL_CLASS", ws)
	var has_first_class := false
	for p in postal_opts:
		if str(p.get("id", "")) == "FIRST_CLASS":
			has_first_class = true
			break
	if not has_cheque_post or not has_first_class:
		printerr("FAIL: Expected pluggable SETTLEMENT_RAIL (CLEARING_BANK_CHEQUE) and POSTAL_CLASS (FIRST_CLASS). Rails=%s Postal=%s" % [str(rails), str(postal_opts)])
		passed = false
	else:
		print("PASS: Pluggable SETTLEMENT_RAIL & POSTAL_CLASS resolvers mounted and era-filtered.")

	# 4. Verify CREATE_OBLIGATION resolves OBLIGATION_TYPE options and validates directive
	var create_targets := DirectiveComposerControllerScript.resolve_targets_for_verb("CREATE_OBLIGATION", ws)
	var has_term_loan := false
	for t in create_targets:
		if str(t.get("id", "")) == "TERM_LOAN":
			has_term_loan = true
			break
	if not has_term_loan:
		printerr("FAIL: CREATE_OBLIGATION did not resolve TERM_LOAN from pluggable resolver_obligation_type.gd. Got: %s" % str(create_targets))
		passed = false
	else:
		var create_dir := DirectiveComposerControllerScript.build_and_validate_directive({
			"verb": "CREATE_OBLIGATION",
			"initiator_id": "101",
			"assigned_to": "101",
			"target_item": "TERM_LOAN",
			"amount": 50.0,
			"target_node_id": "DISTRICT_MARKET",
			"counterparty_id": "201"
		})
		if str(create_dir.get("obligation_type", "")) != "TERM_LOAN" or float(create_dir.get("amount", 0.0)) != 50.0:
			printerr("FAIL: CREATE_OBLIGATION directive mapping invalid: %s" % str(create_dir))
			passed = false
		else:
			print("PASS: CREATE_OBLIGATION resolved obligation types and built valid directive.")

	# 5. Seed one receivable (201 owes 101) and one payable (101 owes 201) in SQLite
	var rec_id := ObligationLedgerScript.create_obligation({
		"debtor": "RESIDENT:201",
		"creditor": "RESIDENT:101",
		"obligation_type": "TERM_LOAN",
		"principal": 75.0,
		"created_day": 100
	})
	var pay_id := ObligationLedgerScript.create_obligation({
		"debtor": "RESIDENT:101",
		"creditor": "RESIDENT:201",
		"obligation_type": "TRADE_CREDIT",
		"principal": 40.0,
		"created_day": 100
	})

	# 6. Verify COLLECT_OBLIGATION resolves only receivable (#rec_id)
	var collect_targets := DirectiveComposerControllerScript.resolve_targets_for_verb("COLLECT_OBLIGATION", ws)
	if collect_targets.size() != 1 or int(collect_targets[0].get("id", 0)) != rec_id:
		printerr("FAIL: COLLECT_OBLIGATION expected only receivable #%d, got: %s" % [rec_id, str(collect_targets)])
		passed = false
	else:
		var collect_dir := DirectiveComposerControllerScript.build_and_validate_directive({
			"verb": "COLLECT_OBLIGATION",
			"initiator_id": "101",
			"assigned_to": "101",
			"target_item": str(rec_id),
			"amount": 25.0,
			"rail_code": "PHYSICAL_CASH",
			"target_node_id": "DISTRICT_MARKET",
			"counterparty_id": "201"
		})
		if str(collect_dir.get("obligation_id", "")) != str(rec_id) or str(collect_dir.get("rail_code", "")) != "PHYSICAL_CASH":
			printerr("FAIL: COLLECT_OBLIGATION directive mapping invalid: %s" % str(collect_dir))
			passed = false
		else:
			print("PASS: COLLECT_OBLIGATION resolved receivable #%d and built valid directive." % rec_id)

	# 7. Verify SETTLE_OBLIGATION resolves only payable (#pay_id) and maps rail_code + postal_class + item_id
	var settle_targets := DirectiveComposerControllerScript.resolve_targets_for_verb("SETTLE_OBLIGATION", ws)
	if settle_targets.size() != 1 or int(settle_targets[0].get("id", 0)) != pay_id:
		printerr("FAIL: SETTLE_OBLIGATION expected only payable #%d, got: %s" % [pay_id, str(settle_targets)])
		passed = false
	else:
		var settle_dir := DirectiveComposerControllerScript.build_and_validate_directive({
			"verb": "SETTLE_OBLIGATION",
			"initiator_id": "101",
			"assigned_to": "101",
			"target_item": str(pay_id),
			"amount": 40.0,
			"rail_code": "CLEARING_BANK_CHEQUE",
			"postal_class": "FIRST_CLASS",
			"target_node_id": "DISTRICT_MARKET",
			"counterparty_id": "201"
		})
		if str(settle_dir.get("obligation_id", "")) != str(pay_id) \
			or str(settle_dir.get("rail_code", "")) != "CLEARING_BANK_CHEQUE" \
			or str(settle_dir.get("postal_class", "")) != "FIRST_CLASS" \
			or str(settle_dir.get("item_id", "")) != "CASH":
			printerr("FAIL: SETTLE_OBLIGATION directive mapping invalid: %s" % str(settle_dir))
			passed = false
		else:
			print("PASS: SETTLE_OBLIGATION resolved payable #%d with rail & postal delivery." % pay_id)

	DBManagerScript.close_database()

	if passed:
		print("--- [Test] ALL OBLIGATION & CREW UI PIPELINE CHECKS PASSED ---")
		quit(0)
	else:
		printerr("--- [Test] OBLIGATION & CREW UI PIPELINE VERIFICATION FAILED ---")
		quit(1)