# res://tests/test_travel_investigate_scout.gd
extends SceneTree

const VerbRouterScript = preload("res://systems/verb_router.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING TRAVEL, INVESTIGATE & SCOUT SYSTEM TEST    ")
	print("=======================================================")

	# 1. MOUNT ENGINE INFRASTRUCTURE
	print("\n[STEP 1] Initializing Routers and Sinks...")
	VerbRouterScript.initialize()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")

	# 2. CONSTRUCT MOCK COMMODITY REGISTRY (Transport & Intel Services)
	var commodities = {
		# --- TRANSPORT SERVICES ---
		"SERVICE_BUS_TRANSIT": {
			"id": "SERVICE_BUS_TRANSIT",
			"display_name": "Municipal Bus",
			"category": "SERVICE",
			"base_fare_drop": 0.50,
			"capacity": {
				"max_passengers_per_unit": 64,
				"max_cargo_volume_litres": 15.0,
				"requires_multiple_units_for_groups": false
			},
			"impact_activations": {
				"TRAVEL": [
					{"metric": "CASH", "model": "STEPPED_PER_UNIT", "factor": -0.30, "params": {"step_size": 150.0}},
					{"metric": "WORKER_FATIGUE", "model": "LOG_PER_UNIT", "factor": 2.5, "params": {"log_scale": 0.01}},
					{"metric": "OPERATIONAL_TIME", "model": "LINEAR_PER_UNIT", "factor": 0.08, "params": {}}
				]
			}
		},
		"SERVICE_MINI_CAB": {
			"id": "SERVICE_MINI_CAB",
			"display_name": "Private Minicab",
			"category": "SERVICE",
			"base_fare_drop": 1.20,
			"capacity": {
				"max_passengers_per_unit": 4,
				"max_cargo_volume_litres": 75.0,
				"requires_multiple_units_for_groups": true
			},
			"impact_activations": {
				"TRAVEL": [
					{"metric": "CASH", "model": "LINEAR_PER_UNIT", "factor": -0.010, "params": {}},
					{"metric": "WORKER_FATIGUE", "model": "LINEAR_PER_UNIT", "factor": 0.005, "params": {}},
					{"metric": "OPERATIONAL_TIME", "model": "LINEAR_PER_UNIT", "factor": 0.03, "params": {}}
				]
			}
		},
		"SERVICE_WALK": {
			"id": "SERVICE_WALK",
			"display_name": "Foot Travel",
			"category": "SERVICE",
			"base_fare_drop": 0.00,
			"capacity": {
				"max_passengers_per_unit": 1,
				"max_cargo_volume_litres": 20.0,
				"requires_multiple_units_for_groups": false
			},
			"impact_activations": {
				"TRAVEL": [
					{"metric": "CASH", "model": "LINEAR_PER_UNIT", "factor": 0.00, "params": {}},
					{"metric": "WORKER_FATIGUE", "model": "LINEAR_PER_UNIT", "factor": 0.04, "params": {}},
					{"metric": "OPERATIONAL_TIME", "model": "LINEAR_PER_UNIT", "factor": 0.18, "params": {}}
				]
			}
		},

		# --- INTELLIGENCE RECON SERVICES ---
		"SERVICE_STREET_SCOUT": {
			"id": "SERVICE_STREET_SCOUT",
			"display_name": "Street Survey",
			"category": "SERVICE",
			"intel_properties": {
				"scope": "DISTRICT_PARADE",
				"variance_blur": 0.05,
				"confidence_rating": 0.95
			},
			"impact_activations": {
				"INVESTIGATE": [
					{"metric": "WORKER_FATIGUE", "model": "LINEAR_PER_UNIT", "factor": 15.0, "params": {}},
					{"metric": "OPERATIONAL_TIME", "model": "LINEAR_PER_UNIT", "factor": 120.0, "params": {}}
				]
			}
		},
		"SERVICE_PUB_RECON": {
			"id": "SERVICE_PUB_RECON",
			"display_name": "Pub Taproom Social",
			"category": "SERVICE",
			"intel_properties": {
				"scope": "RUMOUR",
				"variance_blur": 0.30,
				"confidence_rating": 0.60
			},
			"impact_activations": {
				"INVESTIGATE": [
					{"metric": "CASH", "model": "LINEAR_PER_UNIT", "factor": -1.0, "params": {}},
					{"metric": "WORKER_FATIGUE", "model": "LINEAR_PER_UNIT", "factor": -8.0, "params": {}},
					{"metric": "OPERATIONAL_TIME", "model": "LINEAR_PER_UNIT", "factor": 180.0, "params": {}},
					{"metric": "INTOXICATION", "model": "LINEAR_PER_UNIT", "factor": 1.5, "params": {}},
					{"metric": "POLICE_HEAT", "model": "LINEAR_PER_UNIT", "factor": 0.02, "params": {}}
				]
			}
		}
	}

	# 3. CONSTRUCT WORLD STATE
	var world_state = {
		"metadata": {"current_week_tick": 1},
		"finances": {"liquid_cash": 50.0},
		"operations": {
			"fatigue": 0.0,
			"home_district_id": "block_0_0"
		},
		"commodity_registry": commodities,
		"pending_orders": {},
		"staff": {
			"RUNNER_BILLY": {
				"name": "Billy",
				"cash": 2.00,
				"skill_rating": 0.30,
				"current_district_id": "block_0_0",
				"fatigue": 0.0
			},
			"TERRY_COUSIN": {
				"name": "Terry",
				"cash": 40.00,
				"skill_rating": 0.75,
				"current_district_id": "block_0_0",
				"fatigue": 0.0
			}
		},
		"filofax_cache": {
			"districts": {}
		},
		"districts": {
			"block_0_0": {
				"district_id": "block_0_0",
				"display_name": "Aston Central",
				"spatial_anchor": Vector2(0.0, 0.0),
				"actual_police_heat": 0.15,
				"zone_health_index": 70.0,
				"population": 1200,
				"venues": {
					"VENUE_THE_CROWN": {
						"venue_id": "VENUE_THE_CROWN",
						"venue_name": "The Crown & Anchor",
						"catchment_population": 400,
						"staff_reputation": {}
					}
				}
			},
			"block_6_8": {
				"district_id": "block_6_8",
				"display_name": "Moor Rise Estate",
				"spatial_anchor": Vector2(300.0, 400.0), # 3-4-5 Triangle -> Distance = 500.0 units
				"actual_police_heat": 0.40,
				"zone_health_index": 45.0,
				"population": 1600,
				"venues": {
					"VENUE_BLACKTHORN_PUB": {
						"venue_id": "VENUE_BLACKTHORN_PUB",
						"venue_name": "The Blackthorn",
						"catchment_population": 500,
						"staff_reputation": {}
					}
				}
			}
		}
	}

	# -------------------------------------------------------------
	# [SUITE 1] ACTION_TRAVEL: DISTANCE & MINICAB CHARTER
	# -------------------------------------------------------------
	print("\n--- [SUITE 1] Testing ActionTravel: Distance Calculation & Group Scaling ---")
	
	# Scenario: 500m distance from block_0_0 to block_6_8
	# 1 Passenger via Minicab -> Base drop 1.20 + (500 * 0.010) = £6.20
	var travel_cmd = {
		"verb": "TRAVEL",
		"initiator_id": "PLAYER",
		"origin_node_id": "block_0_0",
		"target_node_id": "block_6_8",
		"travel_service_id": "SERVICE_MINI_CAB",
		"passenger_count": 1
	}
	var res_travel = SimControllerScript.execute_directive(world_state, travel_cmd)
	print("  ✓ Result Message: ", res_travel.get("message", ""))
	assert(res_travel.get("success", false) == true, "FAILED: Travel execution failed!")
	
	var cash_after = world_state["finances"]["liquid_cash"]
	print("  ✓ Liquid Cash Post-Cab: £%.2f (Expected £43.80)" % cash_after)
	assert(is_equal_approx(cash_after, 43.80), "FAILED: Did not deduct flag-drop (£1.20) + distance (£5.00) = £6.20!")

	# Scenario: 6 Passengers via Minicab -> Requires 2 vehicles (ceil(6/4)) -> Fare = 2 * £6.20 = £12.40
	var group_travel_cmd = {
		"verb": "TRAVEL",
		"initiator_id": "PLAYER",
		"origin_node_id": "block_0_0",
		"target_node_id": "block_6_8",
		"travel_service_id": "SERVICE_MINI_CAB",
		"passenger_count": 6
	}
	var res_group = SimControllerScript.execute_directive(world_state, group_travel_cmd)
	var expected_fleet_fare: float = 6.20 * 2.0 # £12.40
	assert(res_group.get("success", false) == true, "FAILED: Group minicab charter failed!")
	print("  ✓ Group of 6 chartered 2 minicabs. Deducted £%.2f." % expected_fleet_fare)

	# -------------------------------------------------------------
	# [SUITE 2] ACTION_TRAVEL: AFFORDABILITY FALLBACK CASCADE
	# -------------------------------------------------------------
	print("\n--- [SUITE 2] Testing Travel Downgrade Ladder (Insolvent Runner) ---")
	# Billy only has £2.00 cash. 
	# Minicab costs £6.20 (Cannot afford).
	# Bus costs: Base 0.50 + 3 steps of 150m @ 0.30 = £1.40 (Affordable!).
	# Engine should automatically downgrade Billy to SERVICE_BUS_TRANSIT.
	var billy_travel = {
		"verb": "TRAVEL",
		"initiator_id": "RUNNER_BILLY",
		"origin_node_id": "block_0_0",
		"target_node_id": "block_6_8",
		"travel_service_id": "SERVICE_MINI_CAB"
	}
	var res_billy = SimControllerScript.execute_directive(world_state, billy_travel)
	print("  ✓ Billy Travel Outcome: ", res_billy.get("message", ""))
	assert(res_billy.get("success", false) == true, "FAILED: Billy failed to travel via fallback!")
	assert(res_billy.get("context", {}).get("service_id", "") == "SERVICE_BUS_TRANSIT", "FAILED: Did not downgrade to bus!")
	assert(res_billy.get("context", {}).get("was_downgraded", false) == true, "FAILED: was_downgraded flag was not set!")

	# -------------------------------------------------------------
	# [SUITE 3] ACTION_INVESTIGATE: PUB TAPROOM SOCIAL & REPUTATION
	# -------------------------------------------------------------
	print("\n--- [SUITE 3] Testing ActionInvestigate: Taproom Recon & Social Capital ---")
	# Terry drinks at The Blackthorn in Moor Rise. Spends £12.00 on rounds.
	var pub_cmd = {
		"verb": "INVESTIGATE",
		"initiator_id": "TERRY_COUSIN",
		"target_node_id": "block_6_8",
		"venue_id": "VENUE_BLACKTHORN_PUB",
		"intel_service_id": "SERVICE_PUB_RECON",
		"spend_amount": 12.00
	}
	var res_pub = SimControllerScript.execute_directive(world_state, pub_cmd)
	print("  ✓ Investigation Outcome: ", res_pub.get("message", ""))
	assert(res_pub.get("success", false) == true, "FAILED: Pub investigation failed!")
	
	# Verify that the Filofax received the inked snapshot
	var filofax_entry = world_state["filofax_cache"]["districts"]["block_6_8"]
	print("  ✓ Filofax Perceived Survey Status: ", filofax_entry.get("survey_status", ""))
	print("  ✓ Filofax Inked Police Heat: %d%%" % int(filofax_entry.get("inked_police_heat", 0.0) * 100))
	assert(filofax_entry.get("survey_status", "") == "SURVEYED", "FAILED: District was not marked SURVEYED in Filofax!")

	# Verify Terry's personal social capital in that specific pub
	var moor_rise = world_state["districts"]["block_6_8"]
	var venue = moor_rise["venues"]["VENUE_BLACKTHORN_PUB"]
	var terry_rep = venue["staff_reputation"]["TERRY_COUSIN"]["personal_reputation"]
	print("  ✓ Terry's Personal Reputation at The Blackthorn: %.1f / 100" % terry_rep)
	assert(terry_rep > 0.0, "FAILED: Terry did not gain personal reputation from visit!")

	# -------------------------------------------------------------
	# [SUITE 4] COMPOSITE ACTION_SCOUT: TRAVEL -> RECON -> RETURN
	# -------------------------------------------------------------
	print("\n--- [SUITE 4] Testing Composite ActionScout (Full Loop) ---")
	# Reset Terry's position back to HQ
	world_state["staff"]["TERRY_COUSIN"]["current_district_id"] = "block_0_0"
	var terry_start_cash = world_state["staff"]["TERRY_COUSIN"]["cash"]

	var scout_cmd = {
		"verb": "SCOUT",
		"initiator_id": "TERRY_COUSIN",
		"target_node_id": "block_6_8",
		"travel_service_id": "SERVICE_BUS_TRANSIT",
		"intel_service_id": "SERVICE_STREET_SCOUT"
	}
	var res_scout = SimControllerScript.execute_directive(world_state, scout_cmd)
	print("  ✓ Scout Mission Message: ", res_scout.get("message", ""))
	assert(res_scout.get("success", false) == true, "FAILED: ActionScout composite loop failed!")
	
	# Verify Terry returned to base
	var terry_final_location = world_state["staff"]["TERRY_COUSIN"]["current_district_id"]
	print("  ✓ Terry Final Location: ", terry_final_location)
	assert(terry_final_location == "block_0_0", "FAILED: Terry did not return home after scouting!")

	# Verify 2 bus trips were deducted (Outward £1.40 + Return £1.40 = £2.80)
	var terry_end_cash = world_state["staff"]["TERRY_COUSIN"]["cash"]
	print("  ✓ Terry Cash Post-Scout: £%.2f (Start: £%.2f)" % [terry_end_cash, terry_start_cash])
	assert(is_equal_approx(terry_end_cash, terry_start_cash - 2.80), "FAILED: Did not deduct two-way bus fare (£2.80)!")

	print("\n=======================================================")
	print("   ALL TRAVEL, INVESTIGATE & SCOUT TESTS PASSED!       ")
	print("=======================================================\n")
	quit()