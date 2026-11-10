# res://tests/test_action_buy_modular.gd
extends SceneTree

const ACTION_PIPELINE_RUNNER = preload("res://systems/action_pipeline/action_pipeline_runner.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")

const BUY_VERB_DEF_PATH := "res://data_modules/core/verbs/buy/verb_definition.json"
const BUY_IMPACTS_DIR := "res://data_modules/core/verbs/buy/impacts/"

func _init() -> void:
	print("\n=======================================================")
	print("   TEST: MODULAR ACTION BUY PIPELINE & IMPACTS")
	print("=======================================================\n")

	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")

	var buy_def := _load_buy_verb_def()

	_test_nominal_buy(buy_def)
	_test_gate_cash_insufficient(buy_def)
	_test_planning_on_margin_out_of_stock(buy_def)

	print("\n=======================================================")
	print("   ALL MODULAR BUY TESTS PASSED CLEANLY")
	print("=======================================================\n")
	quit(0)

func _load_buy_verb_def() -> Dictionary:
	assert(FileAccess.file_exists(BUY_VERB_DEF_PATH), "FATAL: Missing buy definition at %s" % BUY_VERB_DEF_PATH)
	var file := FileAccess.open(BUY_VERB_DEF_PATH, FileAccess.READ)
	assert(file != null, "FATAL: Could not open buy definition file.")
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and not parsed.is_empty(), "FATAL: Failed to parse buy definition JSON.")
	return parsed

func _setup_mock_world_state() -> Dictionary:
	return {
		"metadata": {
			"current_sim_day": 1,
			"current_week_tick": 1
		},
		"obligations": [],
		"operations": {
			"fatigue": 0.0
		},
		"staff": {
			"crew_0": {
				"slot_id": "crew_0",
				"current_district_id": "DISTRICT_HQ",
				"shift_time_spent": 0.0,
				"fatigue": 0.0,
				"inventory": {
					"CASH": 50.0
				}
			}
		},
		"inventory": {},
		"districts": {
			"DISTRICT_HQ": {
				"actual_police_heat": 0.0,
				"zone_health_index": 0.50,
				"venues": {}
			},
			"DISTRICT_MARKET": {
				"actual_police_heat": 0.10,
				"zone_health_index": 0.50,
				"venues": {
					"VENUE_WHOLESALER": {
						"inventory": {
							"CASH": 0.0,
							"BEER_KEG": 10.0
						}
					}
				}
			}
		}
	}

func _test_nominal_buy(buy_def: Dictionary) -> void:
	print("[STEP 1] Testing nominal BUY execution...")
	var ws := _setup_mock_world_state()

	var directive := {
		"verb": "BUY",
		"initiator_id": "crew_0",
		"assigned_to": "crew_0",
		"target_item": "BEER_KEG",
		"amount": 5.0,
		"target_node_id": "DISTRICT_MARKET",
		"config": {
			"unit_cost": 4.0,
			"supplier_id": "VENUE_WHOLESALER"
		}
	}

	var res: Dictionary = ACTION_PIPELINE_RUNNER.run_action_pipeline(ws, directive, buy_def, BUY_IMPACTS_DIR)
	assert(res.get("success", false) == true, "Expected nominal buy to succeed: %s" % res.get("message", ""))

	var staff_inv: Dictionary = ws["staff"]["crew_0"]["inventory"]
	assert(is_equal_approx(staff_inv.get("CASH", 0.0), 30.0), "Operative cash should be £30.00, got: %f" % staff_inv.get("CASH", 0.0))
	assert(is_equal_approx(staff_inv.get("BEER_KEG", 0.0), 5.0), "Operative should have 5 BEER_KEG, got: %f" % staff_inv.get("BEER_KEG", 0.0))

	var venue_inv: Dictionary = ws["districts"]["DISTRICT_MARKET"]["venues"]["VENUE_WHOLESALER"]["inventory"]
	assert(is_equal_approx(venue_inv.get("CASH", 0.0), 20.0), "Venue cash should be £20.00, got: %f" % venue_inv.get("CASH", 0.0))
	assert(is_equal_approx(venue_inv.get("BEER_KEG", 0.0), 5.0), "Venue should retain 5 BEER_KEG, got: %f" % venue_inv.get("BEER_KEG", 0.0))

	assert(ws["staff"]["crew_0"]["current_district_id"] == "DISTRICT_MARKET", "Operative should have relocated to market")
	assert(ws["staff"]["crew_0"]["shift_time_spent"] > 0.0, "Shift time should have elapsed")
	assert(ws["staff"]["crew_0"]["fatigue"] > 0.0, "Fatigue should have been incurred")

	var zh: float = ws["districts"]["DISTRICT_MARKET"].get("zone_health_index", 0.0)
	assert(zh > 0.50, "Zone health should have increased from baseline 0.50, got: %f" % zh)
	print("  ✓ Nominal BUY executed: cash/item transferred, transit applied, zone health boosted.")

func _test_gate_cash_insufficient(buy_def: Dictionary) -> void:
	print("[STEP 2] Testing pre-trip cash gate rejection...")
	var ws := _setup_mock_world_state()
	ws["staff"]["crew_0"]["inventory"]["CASH"] = 5.0 # Need £20.00

	var directive := {
		"verb": "BUY",
		"initiator_id": "crew_0",
		"assigned_to": "crew_0",
		"target_item": "BEER_KEG",
		"amount": 5.0,
		"target_node_id": "DISTRICT_MARKET",
		"config": {
			"unit_cost": 4.0,
			"supplier_id": "VENUE_WHOLESALER"
		}
	}

	var res: Dictionary = ACTION_PIPELINE_RUNNER.run_action_pipeline(ws, directive, buy_def, BUY_IMPACTS_DIR)
	assert(res.get("success", false) == false, "Expected buy to fail due to lack of cash")
	assert(res.get("code", "") == "INSUFFICIENT_RESOURCE", "Expected INSUFFICIENT_RESOURCE code, got: %s" % res.get("code", ""))

	# Assert operative did not move or spend travel time
	assert(ws["staff"]["crew_0"]["current_district_id"] == "DISTRICT_HQ", "Operative should not have traveled")
	assert(ws["staff"]["crew_0"]["shift_time_spent"] == 0.0, "Zero shift time should have elapsed on pre-gate fail")
	assert(ws["staff"]["crew_0"]["inventory"]["CASH"] == 5.0, "Cash should remain unspent")
	print("  ✓ Pre-trip cash gate rejected without wasting travel time.")

func _test_planning_on_margin_out_of_stock(buy_def: Dictionary) -> void:
	print("[STEP 3] Testing planning on margin (stock failure at venue)...")
	var ws := _setup_mock_world_state()
	# Venue only has 2 kegs, operative requests 5
	ws["districts"]["DISTRICT_MARKET"]["venues"]["VENUE_WHOLESALER"]["inventory"]["BEER_KEG"] = 2.0

	var directive := {
		"verb": "BUY",
		"initiator_id": "crew_0",
		"assigned_to": "crew_0",
		"target_item": "BEER_KEG",
		"amount": 5.0,
		"target_node_id": "DISTRICT_MARKET",
		"config": {
			"unit_cost": 4.0,
			"supplier_id": "VENUE_WHOLESALER"
		}
	}

	var res: Dictionary = ACTION_PIPELINE_RUNNER.run_action_pipeline(ws, directive, buy_def, BUY_IMPACTS_DIR)
	assert(res.get("success", false) == false, "Expected buy to fail due to venue out of stock")
	assert(res.get("code", "") == "OUT_OF_STOCK", "Expected OUT_OF_STOCK code, got: %s" % res.get("code", ""))

	# Operative DID travel, so location is market and time was expended + penalty applied
	assert(ws["staff"]["crew_0"]["current_district_id"] == "DISTRICT_MARKET", "Operative should be stranded at market")
	assert(ws["staff"]["crew_0"]["shift_time_spent"] >= 35.0, "Should include travel time (20m) + penalty (15m), got: %f" % ws["staff"]["crew_0"]["shift_time_spent"])
	assert(ws["staff"]["crew_0"]["inventory"]["CASH"] == 50.0, "No cash should have been transferred")
	print("  ✓ Planning on margin verified: travel committed, penalty delays applied, downstream aborted.")