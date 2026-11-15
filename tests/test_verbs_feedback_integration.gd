# res://tests/test_verbs_feedback_integration.gd
extends SceneTree

const VERB_ROUTER = preload("res://systems/verb_router.gd")
const FEEDBACK_MGR = preload("res://systems/feedback_manager.gd")
const SIM_CONTROLLER = preload("res://systems/sim_controller.gd")
const IMPACT_ROUTER = preload("res://systems/impacts/impact_router.gd")
const COMMODITY_MGR = preload("res://systems/commodity_manager.gd")
const FEEDBACK_TRANSLATOR = preload("res://scenes/ui/feedback/feedback_translator.gd")
const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")

func _init() -> void:
	print("\n=======================================================")
	print("    TESTING REAL ACTIONS + MODULAR FEEDBACK PIPELINE   ")
	print("=======================================================")

	assert(DB_MANAGER.initialize_database(true, ":memory:"), "Failed to initialize in-memory DB!")
	VERB_ROUTER.initialize()
	IMPACT_ROUTER.autoload_sinks("res://data_modules/core/impacts/")

	var feedback_data: Dictionary = FEEDBACK_MGR.load_all_feedback()
	assert(feedback_data.has("shared") and feedback_data.has("verbs"), "Invalid feedback matrix shape!")

	var commodities: Dictionary = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/commodities/")
	var recipes: Dictionary = COMMODITY_MGR.load_hierarchical_commodities("res://data_modules/core/recipes/")

	if not commodities.has("BEER_STRONG_LAGER"):
		commodities["BEER_STRONG_LAGER"] = {"id": "BEER_STRONG_LAGER", "base_cost": 1.20}
	if not commodities.has("ROLLING_TOBACCO"):
		commodities["ROLLING_TOBACCO"] = {"id": "ROLLING_TOBACCO", "base_cost": 0.08}
	if not commodities.has("ROLLING_PAPERS"):
		commodities["ROLLING_PAPERS"] = {"id": "ROLLING_PAPERS", "base_cost": 0.02}
	if not commodities.has("ROLLUP"):
		commodities["ROLLUP"] = {"id": "ROLLUP", "base_cost": 0.50}

	var start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var world_state := {
		"metadata": {
			"current_sim_day": start_day,
			"current_week_tick": CALENDAR_HELPER.day_to_week(start_day),
			"time_horizon": "day"
		},
		"residents": {
			"PLAYER": {
				"resident_id": "PLAYER",
				"name": "Billy",
				"is_crew": true,
				"current_district_id": "DIST_ASTON_01",
				"fatigue": 0.0,
				"inventory": {
					"CASH": 100.0,
					"BEER_STRONG_LAGER": 0.0,
					"ROLLING_TOBACCO": 50.0,
					"ROLLING_PAPERS": 50.0,
					"ROLLUP": 0.0
				}
			}
		},
		"establishments": {
			"WHOLESALER_01": {
				"establishment_id": "WHOLESALER_01",
				"name": "Midlands Brewery Depot",
				"district_id": "DIST_ASTON_01",
				"inventory": {
					"CASH": 5000.0,
					"BEER_STRONG_LAGER": 500.0
				}
			},
			"MARKET_CONSUMERS": {
				"establishment_id": "MARKET_CONSUMERS",
				"name": "Aston Street Consumers",
				"district_id": "DIST_ASTON_01",
				"inventory": {
					"CASH": 200.0,
					"BEER_STRONG_LAGER": 0.0
				}
			}
		},
		"commodity_registry": commodities,
		"recipe_registry": recipes
	}

	# 1. BUY Action
	var buy_cmd := {
		"verb": "BUY",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 20.0,
		"initiator_id": "PLAYER",
		"counterparty_id": "WHOLESALER_01",
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_cost": 1.20}
	}
	var res_buy := SIM_CONTROLLER.execute_directive(world_state, buy_cmd)
	assert(res_buy.get("success", false) == true, "FAILED: BUY execution failed!")
	assert(is_equal_approx(float(world_state["residents"]["PLAYER"]["inventory"]["CASH"]), 76.0), "FAILED: Cash not reduced by £24!")
	assert(is_equal_approx(float(world_state["residents"]["PLAYER"]["inventory"]["BEER_STRONG_LAGER"]), 20.0), "FAILED: Stock not received!")

	# 2. MAKE Action
	var target_recipe_id: String = "ROLL_CIGARETTE" if world_state["recipe_registry"].has("ROLL_CIGARETTE") else "RECIPE_ROLL_CIGARETTE"
	var make_cmd := {
		"verb": "MAKE",
		"recipe_id": target_recipe_id,
		"amount": 10,
		"initiator_id": "PLAYER",
		"target_node_id": "DIST_ASTON_01"
	}
	var res_make := SIM_CONTROLLER.execute_directive(world_state, make_cmd)
	assert(res_make.get("success", false) == true, "FAILED: MAKE execution failed!")
	assert(is_equal_approx(float(world_state["residents"]["PLAYER"]["inventory"]["ROLLING_TOBACCO"]), 42.0), "FAILED: Tobacco deduction incorrect!")
	assert(is_equal_approx(float(world_state["residents"]["PLAYER"]["inventory"]["ROLLING_PAPERS"]), 40.0), "FAILED: Papers deduction incorrect!")
	assert(is_equal_approx(float(world_state["residents"]["PLAYER"]["inventory"]["ROLLUP"]), 10.0), "FAILED: Finished yield not placed in inventory!")

	# 3. SELL Action
	var sell_cmd := {
		"verb": "SELL",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"initiator_id": "PLAYER",
		"counterparty_id": "MARKET_CONSUMERS",
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_price": 2.50}
	}
	var res_sell := SIM_CONTROLLER.execute_directive(world_state, sell_cmd)
	assert(res_sell.get("success", false) == true, "FAILED: SELL execution failed!")
	assert(is_equal_approx(float(world_state["residents"]["PLAYER"]["inventory"]["BEER_STRONG_LAGER"]), 10.0), "FAILED: Stock not reduced!")
	assert(is_equal_approx(float(world_state["residents"]["PLAYER"]["inventory"]["CASH"]), 101.0), "FAILED: Revenue not deposited (+£25.00)!")

	# 4. Solvency Failure + FeedbackTranslator Slip Card Generation
	var excessive_buy := {
		"verb": "BUY",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 500.0,
		"initiator_id": "PLAYER",
		"counterparty_id": "WHOLESALER_01",
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_cost": 1.20}
	}
	var cycle_report := SIM_CONTROLLER.process_turn_cycle(world_state, [excessive_buy])
	var cards: Array = FEEDBACK_TRANSLATOR.triggers_to_slip_cards(cycle_report.get("executed_events", []))
	assert(not cards.is_empty(), "FAILED: Expected feedback slip cards from cycle report!")
	assert(cards[0].get("success", true) == false, "FAILED: Expected failed slip card for insolvent BUY!")

	DB_MANAGER.close_database()
	print("\n=======================================================")
	print("     ALL VERBS & FEEDBACK RESOLUTION TESTS PASSED!     ")
	print("=======================================================\n")
	quit(0)