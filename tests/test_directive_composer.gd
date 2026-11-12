# res://tests/test_directive_composer.gd
extends SceneTree

const CONTROLLER = preload("res://systems/directive_composer_controller.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING DIRECTIVE COMPOSER CONTROLLER TEST         ")
	print("=======================================================")

	# -------------------------------------------------------------
	# TEST SUITE 1: Target Category Extraction & Drill-Down Filtering
	# -------------------------------------------------------------
	print("\n--- [SUITE 1] Testing Category Discovery & Filtering ---")
	var raw_targets: Array[Dictionary] = [
		{"id": "BEER_STRONG_LAGER", "category": "ALCOHOL", "unit_cost": 1.20},
		{"id": "BEER_MILD_ALE", "category": "ALCOHOL", "unit_cost": 0.95},
		{"id": "CIGARETTES_EXPORT", "category": "TOBACCO", "unit_cost": 1.50},
		{"id": "SUGAR_BULK", "category": "RAW_MATERIALS", "unit_cost": 0.40}
	]

	var discovered_categories := CONTROLLER.extract_target_categories(raw_targets)
	print("  Discovered Categories: %s" % str(discovered_categories))
	assert(discovered_categories.has("ALCOHOL"), "FAILED: Missing ALCOHOL category.")
	assert(discovered_categories.has("TOBACCO"), "FAILED: Missing TOBACCO category.")
	assert(discovered_categories.has("RAW_MATERIALS"), "FAILED: Missing RAW_MATERIALS category.")
	assert(!discovered_categories.has("GENERAL"), "FAILED: Phantom 'GENERAL' category should not exist.")

	var alcohol_items := CONTROLLER.filter_targets_by_category(raw_targets, "ALCOHOL")
	assert(alcohol_items.size() == 2, "FAILED: Expected 2 alcohol items, got %d" % alcohol_items.size())

	var tobacco_items := CONTROLLER.filter_targets_by_category(raw_targets, "TOBACCO")
	assert(tobacco_items.size() == 1, "FAILED: Expected 1 tobacco item, got %d" % tobacco_items.size())

	var all_items := CONTROLLER.filter_targets_by_category(raw_targets, "ALL")
	assert(all_items.size() == 4, "FAILED: 'ALL' must return all 4 items.")
	print("  ✓ PASS: Category extraction and drill-down filtering verified.")

	# -------------------------------------------------------------
	# TEST SUITE 2: Authentic District Display Name Resolution
	# -------------------------------------------------------------
	print("\n--- [SUITE 2] Testing District Name Resolution ---")
	var mock_world_state: Dictionary = {
		"player_knowledge": {
			"known_districts": ["DISTRICT_NECHELLS_01", "DISTRICT_DIGBETH_01"]
		},
		"districts": {
			"DISTRICT_NECHELLS_01": {
				"district_id": "DISTRICT_NECHELLS_01",
				"display_name": "Nechells Green"
			},
			"DISTRICT_DIGBETH_01": {
				"district_id": "DISTRICT_DIGBETH_01",
				"display_name": "Digbeth High Street"
			}
		}
	}

	var locations := CONTROLLER.build_locations_cache("BUY", "DISTRICT_NECHELLS_01", mock_world_state)
	var found_nechells := false
	var found_digbeth := false

	for loc in locations:
		if loc.get("id") == "DISTRICT_NECHELLS_01":
			found_nechells = true
			assert(loc.get("display") == "Nechells Green", "FAILED: Expected 'Nechells Green', got '%s'" % loc.get("display"))
		elif loc.get("id") == "DISTRICT_DIGBETH_01":
			found_digbeth = true
			assert(loc.get("display") == "Digbeth High Street", "FAILED: Expected 'Digbeth High Street', got '%s'" % loc.get("display"))

	assert(found_nechells and found_digbeth, "FAILED: Could not find resolved known districts in cache.")
	print("  ✓ PASS: Internal engine tokens cleanly resolved to authentic ward names.")

	# -------------------------------------------------------------
	# TEST SUITE 3: Imprecise Cost Estimation & Perception Fuzzing
	# -------------------------------------------------------------
	print("\n--- [SUITE 3] Testing Imperfect Cost Estimation ---")
	var target_commodity: Dictionary = {
		"id": "BEER_STRONG_LAGER",
		"unit_cost": 2.00
	}
	var venue_known: Dictionary = {"id": "VENUE_WHOLESALER_KNOWN", "is_home_turf": false}
	var venue_unknown: Dictionary = {"id": "VENUE_UNKNOWN_DEPOT", "is_home_turf": false}

	var state_with_history: Dictionary = {
		"player_knowledge": {
			"transacted_prices": {
				"VENUE_WHOLESALER_KNOWN": {
					"BEER_STRONG_LAGER": 1.70
				}
			}
		}
	}

	# Case A: Known Transaction History (Exact)
	var exact_est := CONTROLLER.calculate_estimate_with_intel(10.0, target_commodity, venue_known, state_with_history)
	assert(exact_est.get("is_exact") == true, "FAILED: Prior transaction must yield exact estimate.")
	assert(exact_est.get("perceived_unit_cost") == 1.70, "FAILED: Expected £1.70 known unit cost.")
	assert(exact_est.get("estimated_total") == 17.00, "FAILED: Expected £17.00 total.")
	print("  ✓ Known Venue Estimate: £%.2f (Exact = %s)" % [exact_est.get("estimated_total"), str(exact_est.get("is_exact"))])

	# Case B: Untransacted Venue (Imprecise Fuzzed off £2.00 base)
	var fuzzy_est := CONTROLLER.calculate_estimate_with_intel(10.0, target_commodity, venue_unknown, state_with_history)
	assert(fuzzy_est.get("is_exact") == false, "FAILED: Untransacted venue must yield imprecise estimate.")
	assert(fuzzy_est.get("confidence_token") == "UI_ESTIMATE_SPECULATIVE", "FAILED: Expected SPECULATIVE token.")
	assert(fuzzy_est.get("perceived_unit_cost") > 0.0, "FAILED: Fuzzed unit cost must be positive.")
	print("  ✓ Untransacted Venue Estimate: ~£%.2f (Fuzzed Unit Cost = £%.2f, Exact = %s)" % [
		fuzzy_est.get("estimated_total"),
		fuzzy_est.get("perceived_unit_cost"),
		str(fuzzy_est.get("is_exact"))
	])

	# -------------------------------------------------------------
	# TEST SUITE 4: Data-Driven Directive Assembly & Guardrails
	# -------------------------------------------------------------
	print("\n--- [SUITE 4] Testing Data-Driven Directive Assembly & Guardrails ---")

	# Subtest 4.1: Commodity Procurement (BUY)
	var buy_form: Dictionary = {
		"verb": "BUY",
		"initiator_id": "PLAYER",
		"assigned_to": "Billy (Runner)",
		"counterparty_id": "LANDLORD_BOB",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 20.0,
		"target_node_id": "DISTRICT_NECHELLS_01",
		"target_scope": "DISTRICT",
		"unit_cost": 1.20,
		"exposure_modifier": 1.0
	}
	var buy_packet := CONTROLLER.build_and_validate_directive(buy_form)
	assert(not buy_packet.is_empty(), "FAILED: Valid BUY form must produce a non-empty directive packet.")
	assert(buy_packet.get("verb") == "BUY", "FAILED: Verb mismatch.")
	assert(buy_packet.get("item_id") == "BEER_STRONG_LAGER", "FAILED: item_id was not mapped from target_item.")
	assert(buy_packet.get("amount") == 20.0, "FAILED: Amount mismatch.")
	assert(buy_packet.get("assigned_to") == "Billy (Runner)", "FAILED: Assigned staff mismatch.")
	assert(buy_packet.get("supplier_id") == "LANDLORD_BOB", "FAILED: supplier_id was not mapped.")
	print("  ✓ PASS: BUY directive cleanly built with mapped schema fields.")

	# Subtest 4.2: BUY Intentional Rejections (Core Rule 4)
	print("  [Expecting intentional rejection errors below]:")
	var buy_missing_item := buy_form.duplicate()
	buy_missing_item.erase("target_item")
	var rejected_item := CONTROLLER.build_and_validate_directive(buy_missing_item)
	assert(rejected_item.is_empty(), "FAILED: BUY with missing item must be rejected.")

	var buy_zero_amount := buy_form.duplicate()
	buy_zero_amount["amount"] = 0.0
	var rejected_amount := CONTROLLER.build_and_validate_directive(buy_zero_amount)
	assert(rejected_amount.is_empty(), "FAILED: BUY with zero amount must be rejected.")
	print("  ✓ PASS: BUY mandatory field rejections verified.")

	# Subtest 4.3: District Reconnaissance (SCOUT)
	var scout_form: Dictionary = {
		"verb": "SCOUT",
		"initiator_id": "PLAYER",
		"assigned_to": "op_01",
		"amount": 3.0, # Hours in order pad spinbox
		"target_node_id": "DISTRICT_MARKET",
		"target_scope": "DISTRICT"
	}
	var scout_packet := CONTROLLER.build_and_validate_directive(scout_form)
	assert(not scout_packet.is_empty(), "FAILED: Valid SCOUT form must produce a non-empty directive packet.")
	assert(scout_packet.get("verb") == "SCOUT", "FAILED: Verb mismatch.")
	assert(scout_packet.get("duration_ticks") == 3.0, "FAILED: duration_ticks was not mapped from amount.")
	assert(scout_packet.get("target_node_id") == "DISTRICT_MARKET", "FAILED: target_node_id mismatch.")
	assert(!scout_packet.has("item_id"), "FAILED: SCOUT directive should not contain item_id.")
	print("  ✓ PASS: SCOUT directive cleanly built mapping duration_ticks without commodity.")

	# Subtest 4.4: SCOUT Missing Location Rejection (Core Rule 4)
	var scout_missing_loc := scout_form.duplicate()
	scout_missing_loc.erase("target_node_id")
	var rejected_scout := CONTROLLER.build_and_validate_directive(scout_missing_loc)
	assert(rejected_scout.is_empty(), "FAILED: SCOUT with missing location must be rejected.")
	print("  ✓ PASS: SCOUT location requirement rejection verified.")

	print("\n=======================================================")
	print("   ALL DIRECTIVE COMPOSER TESTS PASSED CLEANLY!        ")
	print("=======================================================\n")
	quit(0)