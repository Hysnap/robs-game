# res://tests/test_cascading_flavour_verbs.gd
extends SceneTree

const VerbRouterScript = preload("res://systems/verb_router.gd")
const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")
const DirectiveComposerControllerScript = preload("res://systems/directive_composer_controller.gd")
const EngineResultScript = preload("res://systems/engine_result.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Cascading Verbs & Flavour Overlay Merging ---")
	var passed: bool = true
	passed = passed and _test_core_only_communicate()
	passed = passed and _test_crime_overlay_communicate()
	passed = passed and _test_target_domain_scope_overlays()
	passed = passed and _test_investigate_cascading_modes()
	passed = passed and _test_collect_from_cascading_modes()
	passed = passed and _test_directive_composer_cascading_ui_rules()

	if passed:
		print("--- [Test] ALL CASCADING VERB & FLAVOUR OVERLAY TESTS PASSED ---\n")
		quit(0)
	else:
		printerr("--- [Test] CASCADING VERB & FLAVOUR OVERLAY TESTS FAILED ---\n")
		quit(1)

func _build_fixture_state() -> Dictionary:
	return {
		"residents": {
			"op_01": {
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 100.0
				}
			},
			"op_away": {
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"CASH": 100.0
				}
			},
			"res_contact_01": {
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 10.0
				}
			}
		},
		"districts": {
			"DISTRICT_MARKET": {},
			"DISTRICT_HQ": {}
		}
	}

func _test_core_only_communicate() -> bool:
	VerbRouterScript.initialize("")
	var ws: Dictionary = _build_fixture_state()

	# Core QUESTION intent
	var q_res: Dictionary = VerbRouterScript.dispatch(ws, {
		"verb": "COMMUNICATE",
		"assigned_to": "op_01",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"intent": "QUESTION"
	})
	if not bool(q_res.get("success", false)):
		printerr("FAIL [Core]: QUESTION intent failed: %s" % str(q_res))
		return false

	# Core-only mode must NOT execute crime BRIBE cash transfer
	var b_res: Dictionary = VerbRouterScript.dispatch(ws, {
		"verb": "COMMUNICATE",
		"assigned_to": "op_01",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"intent": "BRIBE",
		"amount": 25.0
	})
	if not bool(b_res.get("success", false)):
		printerr("FAIL [Core]: Core-only dispatch failed unexpectedly: %s" % str(b_res))
		return false
	if not is_equal_approx(float(ws["residents"]["op_01"]["inventory"]["CASH"]), 100.0):
		printerr("FAIL [Core]: CASH mutated in core-only mode without crime overlay.")
		return false

	print("  PASS [1/2]: Core-only COMMUNICATE cascading intent verified (zero crime leakage).")
	return true

func _test_crime_overlay_communicate() -> bool:
	VerbRouterScript.initialize("crime")
	var ws: Dictionary = _build_fixture_state()

	# 1. Core QUESTION still works with crime overlay active and transfers zero cash
	var q_res: Dictionary = VerbRouterScript.dispatch(ws, {
		"verb": "COMMUNICATE",
		"assigned_to": "op_01",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"intent": "QUESTION"
	})
	if not bool(q_res.get("success", false)) or not is_equal_approx(float(ws["residents"]["op_01"]["inventory"]["CASH"]), 100.0):
		printerr("FAIL [Crime]: QUESTION intent failed or mutated CASH: %s" % str(q_res))
		return false

	# 2. Crime BRIBE transfers CASH cleanly
	var bribe_res: Dictionary = VerbRouterScript.dispatch(ws, {
		"verb": "COMMUNICATE",
		"assigned_to": "op_01",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"intent": "BRIBE",
		"amount": 25.0
	})
	if not bool(bribe_res.get("success", false)):
		printerr("FAIL [Crime]: BRIBE intent failed: %s" % str(bribe_res))
		return false

	var op_cash: float = float(ws["residents"]["op_01"]["inventory"]["CASH"])
	var contact_cash: float = float(ws["residents"]["res_contact_01"]["inventory"]["CASH"])
	if not is_equal_approx(op_cash, 75.0) or not is_equal_approx(contact_cash, 35.0):
		printerr("FAIL [Crime]: BRIBE cash balances mismatch (op=%.2f, contact=%.2f)." % [op_cash, contact_cash])
		return false

	# 3. Crime BRIBE halts on insufficient cash with INSUFFICIENT_RESOURCE
	var broke_res: Dictionary = VerbRouterScript.dispatch(ws, {
		"verb": "COMMUNICATE",
		"assigned_to": "op_01",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"intent": "BRIBE",
		"amount": 500.0
	})
	if bool(broke_res.get("success", true)) or int(broke_res.get("error_code", -1)) != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL [Crime]: Expected INSUFFICIENT_RESOURCE for excessive bribe, got: %s" % str(broke_res))
		return false

	# 4. Core co-location gate preserved under crime overlay
	var away_res: Dictionary = VerbRouterScript.dispatch(ws, {
		"verb": "COMMUNICATE",
		"assigned_to": "op_away",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"intent": "BRIBE",
		"amount": 10.0
	})
	if bool(away_res.get("success", true)) or int(away_res.get("error_code", -1)) != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL [Crime]: Expected INVALID_TARGET when operative is not co-located, got: %s" % str(away_res))
		return false

	print("  PASS [2/6]: Crime flavour overlay COMMUNICATE (QUESTION, BRIBE, gates) verified.")
	return true

func _test_target_domain_scope_overlays() -> bool:
	# 1. Core-only scope check
	TargetDomainRegistryScript.initialize("")
	var core_scope: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition("COMMUNICATE")
	var core_layout: Dictionary = core_scope.get("form_layout", {})
	var core_opts: Array = core_layout.get("intent_section", {}).get("options", [])
	var core_ids: Array[String] = []
	for opt in core_opts:
		if opt is Dictionary:
			core_ids.append(str(opt.get("id", "")))

	if core_ids.size() != 3 or core_ids.has("BRIBE") or core_ids.has("THREATEN"):
		printerr("FAIL [Scope Core]: Expected 3 core intents without crime leakage, got: %s" % str(core_ids))
		return false
	if bool(core_layout.get("amount_section", {}).get("visible", true)):
		printerr("FAIL [Scope Core]: Expected amount_section.visible == false in core-only mode.")
		return false

	# 2. Crime flavour overlay scope check
	TargetDomainRegistryScript.initialize("crime")
	var crime_scope: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition("COMMUNICATE")
	var crime_layout: Dictionary = crime_scope.get("form_layout", {})
	var crime_opts: Array = crime_layout.get("intent_section", {}).get("options", [])
	var crime_ids: Array[String] = []
	for opt in crime_opts:
		if opt is Dictionary:
			crime_ids.append(str(opt.get("id", "")))

	if crime_ids.size() != 6 or not crime_ids.has("FRIENDLY") or not crime_ids.has("THREATEN") or not crime_ids.has("BRIBE") or not crime_ids.has("BRIBE_OFFICIAL"):
		printerr("FAIL [Scope Crime]: Expected 6 merged intents (core + THREATEN/BRIBE/BRIBE_OFFICIAL), got: %s" % str(crime_ids))
		return false

	var amount_sec: Dictionary = crime_layout.get("amount_section", {})
	var visible_when_intents: Array = amount_sec.get("visible_when", {}).get("intent", [])
	if not bool(amount_sec.get("visible", false)) or not visible_when_intents.has("BRIBE"):
		printerr("FAIL [Scope Crime]: Expected conditional amount_section visible_when BRIBE, got: %s" % str(amount_sec))
		return false

	if not bool(crime_layout.get("location_section", {}).get("visible", false)) or not bool(crime_layout.get("contact_section", {}).get("visible", false)):
		printerr("FAIL [Scope Crime]: Core location_section / contact_section were lost during overlay merge.")
		return false

	print("  PASS [3/6]: TargetDomainRegistry core vs. crime target_scope.json overlay merge verified.")
	return true

func _build_mode_test_world_state() -> Dictionary:
	return {
		"residents": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 50.0,
					"BEER_KEG": 0.0
				}
			},
			"victim_01": {
				"name": "Arthur Pendelton",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 40.0
				}
			}
		},
		"establishments": {
			"estab_pub_01": {
				"name": "The Garrison Pub",
				"district_id": "DISTRICT_MARKET",
				"inventory": {
					"CASH": 100.0,
					"BEER_KEG": 10.0
				}
			}
		},
		"caches": {},
		"districts": {
			"DISTRICT_MARKET": {}
		}
	}

func _test_investigate_cascading_modes() -> bool:
	# 1. Core-only mode isolation
	VerbRouterScript.initialize("")
	TargetDomainRegistryScript.initialize("")
	var core_scope: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition("INVESTIGATE")
	var core_opts: Array = core_scope.get("form_layout", {}).get("mode_section", {}).get("options", [])
	if core_opts.size() != 1 or str(core_opts[0].get("id", "")) != "CASUAL_PROBE":
		printerr("FAIL [INVESTIGATE Core]: Expected only CASUAL_PROBE in core mode, got: %s" % str(core_opts))
		return false

	var ws_core := _build_mode_test_world_state()
	var res_core: Dictionary = VerbRouterScript.dispatch(ws_core, {
		"verb": "INVESTIGATE",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"target_entity_id": "estab_pub_01",
		"mode": "CASUAL_PROBE",
		"amount": 2.0
	})
	if not bool(res_core.get("success", false)):
		printerr("FAIL [INVESTIGATE Core]: CASUAL_PROBE failed: %s" % str(res_core))
		return false

	# 2. Crime flavour overlay modes (STAKEOUT, CASE_JOINT) + invalid mode fail-loud
	VerbRouterScript.initialize("crime")
	TargetDomainRegistryScript.initialize("crime")
	var crime_scope: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition("INVESTIGATE")
	var crime_opts: Array = crime_scope.get("form_layout", {}).get("mode_section", {}).get("options", [])
	var mode_ids: Array[String] = []
	for opt in crime_opts:
		if opt is Dictionary:
			mode_ids.append(str(opt.get("id", "")))

	if mode_ids.size() != 4 or not mode_ids.has("CASUAL_PROBE") or not mode_ids.has("STAKEOUT") or not mode_ids.has("CASE_JOINT") or not mode_ids.has("TAIL_TARGET"):
		printerr("FAIL [INVESTIGATE Crime]: Expected 4 merged modes (core + STAKEOUT/CASE_JOINT/TAIL_TARGET), got: %s" % str(mode_ids))
		return false

	var ws_crime := _build_mode_test_world_state()
	var res_stakeout: Dictionary = VerbRouterScript.dispatch(ws_crime, {
		"verb": "INVESTIGATE",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"target_entity_id": "estab_pub_01",
		"mode": "STAKEOUT",
		"amount": 4.0
	})
	if not bool(res_stakeout.get("success", false)) or not res_stakeout.get("context", {}).get("steps_completed", []).has("branch_crime_stakeout"):
		printerr("FAIL [INVESTIGATE Crime]: STAKEOUT branch failed: %s" % str(res_stakeout))
		return false

	var res_case: Dictionary = VerbRouterScript.dispatch(ws_crime, {
		"verb": "INVESTIGATE",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"target_entity_id": "estab_pub_01",
		"mode": "CASE_JOINT",
		"amount": 3.0
	})
	if not bool(res_case.get("success", false)) or not res_case.get("context", {}).get("steps_completed", []).has("branch_crime_case_joint"):
		printerr("FAIL [INVESTIGATE Crime]: CASE_JOINT branch failed: %s" % str(res_case))
		return false

	var res_bad_mode: Dictionary = VerbRouterScript.dispatch(ws_crime, {
		"verb": "INVESTIGATE",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"target_entity_id": "estab_pub_01",
		"mode": "UNKNOWN_MODE_TOKEN"
	})
	if bool(res_bad_mode.get("success", true)) or int(res_bad_mode.get("error_code", -1)) != EngineResultScript.ErrorCode.INVALID_PARAMETER:
		printerr("FAIL [INVESTIGATE Crime]: Expected INVALID_PARAMETER on unknown mode, got: %s" % str(res_bad_mode))
		return false

	print("  PASS [4/6]: INVESTIGATE core vs. crime cascading modes (CASUAL_PROBE, STAKEOUT, CASE_JOINT) verified.")
	return true

func _test_collect_from_cascading_modes() -> bool:
	# 1. Core-only COLLECT_FROM (CONSENSUAL only)
	VerbRouterScript.initialize("")
	TargetDomainRegistryScript.initialize("")
	var core_scope: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition("COLLECT_FROM")
	var core_opts: Array = core_scope.get("form_layout", {}).get("mode_section", {}).get("options", [])
	if core_opts.size() != 1 or str(core_opts[0].get("id", "")) != "CONSENSUAL":
		printerr("FAIL [COLLECT_FROM Core]: Expected only CONSENSUAL mode in core, got: %s" % str(core_opts))
		return false

	var ws_core := _build_mode_test_world_state()
	var res_consensual: Dictionary = VerbRouterScript.dispatch(ws_core, {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_01",
		"source_id": "estab_pub_01",
		"target_node_id": "DISTRICT_MARKET",
		"item_id": "BEER_KEG",
		"amount": 3.0,
		"mode": "CONSENSUAL"
	})
	if not bool(res_consensual.get("success", false)):
		printerr("FAIL [COLLECT_FROM Core]: Consensual collection failed: %s" % str(res_consensual))
		return false
	if not is_equal_approx(float(ws_core["residents"]["op_01"]["inventory"]["BEER_KEG"]), 3.0):
		printerr("FAIL [COLLECT_FROM Core]: Expected op_01 BEER_KEG == 3.0, got: %s" % str(ws_core["residents"]["op_01"]["inventory"]))
		return false

	# 2. Crime flavour overlay COLLECT_FROM (BURGLE, SHOPLIFT, PICKPOCKET, MUG, ROB)
	VerbRouterScript.initialize("crime")
	TargetDomainRegistryScript.initialize("crime")
	var crime_scope: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition("COLLECT_FROM")
	var crime_opts: Array = crime_scope.get("form_layout", {}).get("mode_section", {}).get("options", [])
	if crime_opts.size() != 7:
		printerr("FAIL [COLLECT_FROM Crime]: Expected 7 merged extraction modes, got: %s" % str(crime_opts))
		return false

	var ws_crime := _build_mode_test_world_state()

	# 2a. Premises BURGLE without source_id
	var res_burgle: Dictionary = VerbRouterScript.dispatch(ws_crime, {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"target_entity_id": "estab_pub_01",
		"item_id": "BEER_KEG",
		"amount": 2.0,
		"mode": "BURGLE"
	})
	if not bool(res_burgle.get("success", false)):
		printerr("FAIL [COLLECT_FROM Crime]: BURGLE premises extraction failed: %s" % str(res_burgle))
		return false
	if not is_equal_approx(float(ws_crime["establishments"]["estab_pub_01"]["inventory"]["BEER_KEG"]), 8.0) or not is_equal_approx(float(ws_crime["residents"]["op_01"]["inventory"]["BEER_KEG"]), 2.0):
		printerr("FAIL [COLLECT_FROM Crime]: BURGLE inventory balances mismatch.")
		return false

	# 2b. Premises SHOPLIFT cash without source_id
	var res_shoplift: Dictionary = VerbRouterScript.dispatch(ws_crime, {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"target_entity_id": "estab_pub_01",
		"item_id": "CASH",
		"amount": 15.0,
		"mode": "SHOPLIFT"
	})
	if not bool(res_shoplift.get("success", false)):
		printerr("FAIL [COLLECT_FROM Crime]: SHOPLIFT failed: %s" % str(res_shoplift))
		return false
	if not is_equal_approx(float(ws_crime["establishments"]["estab_pub_01"]["inventory"]["CASH"]), 85.0) or not is_equal_approx(float(ws_crime["residents"]["op_01"]["inventory"]["CASH"]), 65.0):
		printerr("FAIL [COLLECT_FROM Crime]: SHOPLIFT cash balances mismatch.")
		return false

	# 2c. Person-targeted PICKPOCKET missing source_id must fail loud with INVALID_TARGET
	var res_pickpocket_no_target: Dictionary = VerbRouterScript.dispatch(ws_crime, {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"item_id": "CASH",
		"amount": 10.0,
		"mode": "PICKPOCKET",
		"source_id": ""
	})
	if bool(res_pickpocket_no_target.get("success", true)) or int(res_pickpocket_no_target.get("error_code", -1)) != EngineResultScript.ErrorCode.INVALID_TARGET:
		printerr("FAIL [COLLECT_FROM Crime]: Expected INVALID_TARGET when PICKPOCKET omits source_id, got: %s" % str(res_pickpocket_no_target))
		return false

	# 2d. Person-targeted ROB with valid victim_01
	var res_rob: Dictionary = VerbRouterScript.dispatch(ws_crime, {
		"verb": "COLLECT_FROM",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"source_id": "victim_01",
		"item_id": "CASH",
		"amount": 10.0,
		"mode": "ROB"
	})
	if not bool(res_rob.get("success", false)):
		printerr("FAIL [COLLECT_FROM Crime]: ROB victim_01 failed: %s" % str(res_rob))
		return false
	if not is_equal_approx(float(ws_crime["residents"]["victim_01"]["inventory"]["CASH"]), 30.0) or not is_equal_approx(float(ws_crime["residents"]["op_01"]["inventory"]["CASH"]), 75.0):
		printerr("FAIL [COLLECT_FROM Crime]: ROB cash balances mismatch.")
		return false

	print("  PASS [5/6]: COLLECT_FROM core vs. crime cascading modes (BURGLE, SHOPLIFT, PICKPOCKET, ROB) verified.")
	return true

func _test_directive_composer_cascading_ui_rules() -> bool:
	DirectiveComposerControllerScript.sync_active_variant("crime")

	# 1. COMMUNICATE visible_when evaluation: FRIENDLY hides amount_section, BRIBE reveals it
	var comm_friendly: Dictionary = DirectiveComposerControllerScript.resolve_effective_form_layout("COMMUNICATE", {"intent": "FRIENDLY"})
	if bool(comm_friendly.get("amount_section", {}).get("visible", true)):
		printerr("FAIL [Composer UI]: Expected amount_section hidden for COMMUNICATE + FRIENDLY.")
		return false

	var comm_bribe: Dictionary = DirectiveComposerControllerScript.resolve_effective_form_layout("COMMUNICATE", {"intent": "BRIBE"})
	if not bool(comm_bribe.get("amount_section", {}).get("visible", false)):
		printerr("FAIL [Composer UI]: Expected amount_section visible for COMMUNICATE + BRIBE.")
		return false

	# 2. COLLECT_FROM visible_when evaluation: BURGLE hides contact_section, PICKPOCKET requires it
	var collect_burgle: Dictionary = DirectiveComposerControllerScript.resolve_effective_form_layout("COLLECT_FROM", {"mode": "BURGLE"})
	if bool(collect_burgle.get("contact_section", {}).get("visible", true)) or bool(collect_burgle.get("contact_section", {}).get("effective_required", true)):
		printerr("FAIL [Composer UI]: Expected contact_section hidden and non-required for COLLECT_FROM + BURGLE.")
		return false

	var collect_pickpocket: Dictionary = DirectiveComposerControllerScript.resolve_effective_form_layout("COLLECT_FROM", {"mode": "PICKPOCKET"})
	if not bool(collect_pickpocket.get("contact_section", {}).get("visible", false)) or not bool(collect_pickpocket.get("contact_section", {}).get("effective_required", false)):
		printerr("FAIL [Composer UI]: Expected contact_section visible and required for COLLECT_FROM + PICKPOCKET.")
		return false

	# 3. End-to-end directive assembly with cascading mode
	var burgle_directive: Dictionary = DirectiveComposerControllerScript.build_and_validate_directive({
		"verb": "COLLECT_FROM",
		"initiator_id": "op_01",
		"assigned_to": "op_01",
		"mode": "BURGLE",
		"target_item": "BEER_KEG",
		"amount": 2.0,
		"target_node_id": "estab_pub_01"
	})
	if burgle_directive.is_empty() or str(burgle_directive.get("mode", "")) != "BURGLE":
		printerr("FAIL [Composer UI]: Expected valid directive with mode == BURGLE without counterparty_id, got: %s" % str(burgle_directive))
		return false

	var invalid_pickpocket: Dictionary = DirectiveComposerControllerScript.build_and_validate_directive({
		"verb": "COLLECT_FROM",
		"initiator_id": "op_01",
		"assigned_to": "op_01",
		"mode": "PICKPOCKET",
		"target_item": "CASH",
		"amount": 10.0,
		"target_node_id": "DISTRICT_MARKET"
	})
	if not invalid_pickpocket.is_empty():
		printerr("FAIL [Composer UI]: Expected PICKPOCKET without counterparty_id to be rejected by build_and_validate_directive.")
		return false

	print("  PASS [6/6]: DirectiveComposerController cascading layout & visible_when validation verified.")
	return true