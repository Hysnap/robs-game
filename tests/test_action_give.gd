# res://tests/test_action_give.gd
extends SceneTree

const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")
const ActionGiveScript = preload("res://data_modules/core/verbs/give/action_give.gd")

func _init() -> void:
	print("\n--- [Test] Starting GIVE Action & Target Registry Validation ---")
	var passed: bool = true

	passed = passed and test_target_registry_scopes_and_categories()
	passed = passed and test_target_registry_resolution()
	passed = passed and test_execute_cash_transfer()
	passed = passed and test_execute_commodity_transfer()
	passed = passed and test_insolvent_source_rejection()
	passed = passed and test_missing_recipient_rejection()

	TargetDomainRegistryScript.clear_cache()

	if passed:
		print("--- [Test] ALL GIVE ACTION TESTS PASSED CLEANLY ---\n")
		quit(0)
	else:
		printerr("--- [Test] GIVE ACTION TESTS FAILED ---\n")
		quit(1)

func _create_mock_world_state() -> Dictionary:
	return {
		"finances": {
			"vault_cash": 500.0,
			"liquid_cash": 500.0
		},
		"inventory": {
			"BEER_STRONG_LAGER": 50.0
		},
		"commodities": {
			"BEER_STRONG_LAGER": {
				"display_name": "Crates of Lager",
				"base_cost": 3.50,
				"category": "CONSUMABLE",
				"sub_category": "ALCOHOL"
			}
		},
		"staff": {
			"staff_01": {
				"name": "Mick Jenkins",
				"role": "ENFORCER",
				"pocket_cash": 20.0,
				"inventory": {
					"BEER_STRONG_LAGER": 2.0
				}
			}
		}
	}

func test_target_registry_scopes_and_categories() -> bool:
	TargetDomainRegistryScript.clear_cache()
	var scopes := TargetDomainRegistryScript.get_allowed_scopes("GIVE")
	if not scopes.has("STAFF") or not scopes.has("DISTRICT"):
		printerr("FAIL: TargetDomainRegistry did not return expected scopes for GIVE: ", scopes)
		return false

	var cats := TargetDomainRegistryScript.get_target_categories("GIVE")
	if cats.size() < 2:
		printerr("FAIL: Expected at least 2 target categories for GIVE, found: ", cats.size())
		return false

	print("PASS: GIVE scopes and target categories parsed cleanly.")
	return true

func test_target_registry_resolution() -> bool:
	var ws := _create_mock_world_state()
	var targets := TargetDomainRegistryScript.resolve_targets("GIVE", ws, "ALL")

	var found_cash := false
	var found_beer := false
	for t in targets:
		if t.get("id") == "CASH" and t.get("category") == "CURRENCY":
			found_cash = true
		if t.get("id") == "BEER_STRONG_LAGER" and t.get("category") == "CONSUMABLE":
			found_beer = true

	if not found_cash:
		printerr("FAIL: TargetDomainRegistry failed to resolve virtual CASH target.")
		return false
	if not found_beer:
		printerr("FAIL: TargetDomainRegistry failed to resolve catalog commodity target.")
		return false

	print("PASS: Target candidate resolution for GIVE resolved CASH and commodities cleanly.")
	return true

func test_execute_cash_transfer() -> bool:
	var ws := _create_mock_world_state()
	var directive := {
		"initiator_id": "PLAYER",
		"counterparty_id": "staff_01",
		"target_item": "CASH",
		"amount": 75.0,
		"target_node_id": "HQ"
	}

	var result := ActionGiveScript.execute(ws, directive)
	if not result.get("success", false):
		printerr("FAIL: ActionGive cash transfer rejected: ", result.get("message"))
		return false

	var vault: float = float(ws["finances"]["vault_cash"])
	var pocket: float = float(ws["staff"]["staff_01"]["pocket_cash"])

	if not is_equal_approx(vault, 425.0) or not is_equal_approx(pocket, 95.0):
		printerr("FAIL: Cash balances incorrect post-transfer. Vault: %f, Pocket: %f" % [vault, pocket])
		return false

	print("PASS: Cash transfer executed: £75.00 moved from Player Vault to Operative Pocket.")
	return true

func test_execute_commodity_transfer() -> bool:
	var ws := _create_mock_world_state()
	var directive := {
		"initiator_id": "PLAYER",
		"counterparty_id": "staff_01",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"target_node_id": "HQ"
	}

	var result := ActionGiveScript.execute(ws, directive)
	if not result.get("success", false):
		printerr("FAIL: ActionGive commodity transfer rejected: ", result.get("message"))
		return false

	var player_stock: float = float(ws["inventory"]["BEER_STRONG_LAGER"])
	var staff_stock: float = float(ws["staff"]["staff_01"]["inventory"]["BEER_STRONG_LAGER"])

	if not is_equal_approx(player_stock, 40.0) or not is_equal_approx(staff_stock, 12.0):
		printerr("FAIL: Stock counts incorrect post-transfer. Player: %f, Staff: %f" % [player_stock, staff_stock])
		return false

	print("PASS: Commodity transfer executed: 10 units of BEER_STRONG_LAGER transferred.")
	return true

func test_insolvent_source_rejection() -> bool:
	var ws := _create_mock_world_state()
	var directive := {
		"initiator_id": "PLAYER",
		"counterparty_id": "staff_01",
		"target_item": "CASH",
		"amount": 9999.0, # Exceeds available £500
		"target_node_id": "HQ"
	}

	var result := ActionGiveScript.execute(ws, directive)
	if result.get("success", false):
		printerr("FAIL: Insolvent transfer was permitted unexpectedly!")
		return false

	print("PASS: Insolvent transfer correctly rejected at execution gate.")
	return true

func test_missing_recipient_rejection() -> bool:
	var ws := _create_mock_world_state()
	var directive := {
		"initiator_id": "PLAYER",
		"counterparty_id": "", # No recipient specified
		"target_item": "CASH",
		"amount": 50.0,
		"target_node_id": "HQ"
	}

	var result := ActionGiveScript.execute(ws, directive)
	if result.get("success", false):
		printerr("FAIL: Transfer with missing recipient was permitted unexpectedly!")
		return false

	print("PASS: Transfer with missing recipient correctly rejected.")
	return true
