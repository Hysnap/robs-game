# res://tests/test_standing_orders_and_billy_issue.gd
extends SceneTree

const TestSocietyFactoryScript = preload("res://tests/test_society_factory.gd")
const DBManagerScript = preload("res://systems/db_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const StandingOrderProcessorScript = preload("res://systems/standing_order_processor.gd")
const DirectiveComposerControllerScript = preload("res://systems/directive_composer_controller.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")

var _frame_count: int = 0
var _executed: bool = false

func _init() -> void:
	print("\n--- [Test] Verifying Step 1B: Standing Orders, Planning Fat, Billy Issue & PAUSE_STANDING_ORDERS ---")

func _process(_delta: float) -> bool:
	if _executed:
		return false
	_frame_count += 1
	if _frame_count < 2:
		return false
	_executed = true
	_run_tests_async()
	return false

func _run_tests_async() -> void:
	# 1. Generate standardized radial test society via TestSocietyFactory
	var world_state: Dictionary = await TestSocietyFactoryScript.create_test_world(4, 4, "standing-orders-billy-seed")
	var tbl_check: Array = DBManagerScript.query_rows(
		"SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='standing_orders';"
	)
	assert(not tbl_check.is_empty() and int(tbl_check[0]["cnt"]) == 1, "FAIL: standing_orders table missing from schema.")
	print("PASS [1]: TestSocietyFactory world generated and standing_orders table verified.")

	# 2. Verify VerbRouter & ImpactRouter mount PAUSE_STANDING_ORDERS
	VerbRouterScript.initialize()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")
	assert(VerbRouterScript.get_registered_verbs().has("PAUSE_STANDING_ORDERS"), "FAIL: VerbRouter did not mount PAUSE_STANDING_ORDERS.")
	assert(ImpactRouterScript.has_sink("PAUSE_STANDING_ORDERS"), "FAIL: ImpactRouter did not mount PAUSE_STANDING_ORDERS sink.")
	print("PASS [2]: VerbRouter and ImpactRouter mounted PAUSE_STANDING_ORDERS.")

	var start_day: int = CalendarHelperScript.get_current_sim_day(world_state)
	var change_reason_id: int = DBManagerScript.get_label_id("CHANGE_REASON", "WORLD_GENERATION")

	# Pick 4 generated residents and 1 generated establishment from the factory world
	var res_rows: Array = DBManagerScript.query_rows("SELECT resident_id, first_name, current_surname FROM residents ORDER BY resident_id ASC LIMIT 4;")
	assert(res_rows.size() == 4, "FAIL: Expected at least 4 generated residents from TestSocietyFactory.")

	var billy_id: int = int(res_rows[0]["resident_id"])
	var arthur_id: int = int(res_rows[1]["resident_id"])
	var tommy_id: int = int(res_rows[2]["resident_id"])
	var danny_id: int = int(res_rows[3]["resident_id"])

	var est_rows: Array = DBManagerScript.query_rows("SELECT establishment_id, district_id FROM establishments WHERE is_vacant = 0 ORDER BY establishment_id ASC LIMIT 1;")
	assert(not est_rows.is_empty(), "FAIL: Expected at least 1 generated establishment in SQLite.")
	var est_id: int = int(est_rows[0]["establishment_id"])
	var home_dist: String = str(world_state.get("operations", {}).get("home_district_id", ""))
	if home_dist.is_empty():
		home_dist = str(est_rows[0].get("district_id", world_state.get("districts", {}).keys()[0]))

	if not world_state.has("establishments"):
		world_state["establishments"] = {}
	world_state["establishments"][est_id] = {
		"establishment_id": est_id,
		"district_id": home_dist,
		"inventory": {"BEER_KEG": 8.0}
	}

	# Configure OCEAN/cognitive profiles on the 4 generated operatives
	_configure_operative(world_state, billy_id, "Billy Carter", home_dist, 8.0, 0.85,
		{"conscientiousness": 0.30, "agreeableness": 0.80, "openness": 0.50, "neuroticism": 0.45, "mental_agility": 0.45}, ["ND_ADHD"])
	_configure_operative(world_state, arthur_id, "Arthur Dent", home_dist, 8.0, 0.90,
		{"conscientiousness": 0.82, "agreeableness": 0.55, "openness": 0.25, "neuroticism": 0.65, "mental_agility": 0.60}, ["ND_AUTISM_SPECTRUM"])
	_configure_operative(world_state, tommy_id, "Tommy Shelby", home_dist, 8.0, 0.95,
		{"conscientiousness": 0.85, "agreeableness": 0.40, "openness": 0.75, "neuroticism": 0.30, "mental_agility": 0.85}, [])
	_configure_operative(world_state, danny_id, "Danny Price", home_dist, 8.0, 0.75,
		{"conscientiousness": 0.50, "agreeableness": 0.50, "openness": 0.50, "neuroticism": 0.50, "mental_agility": 0.50}, [])

	world_state["standing_orders"] = {
		str(billy_id): true,
		str(arthur_id): true,
		str(tommy_id): true,
		str(danny_id): true
	}
	if not world_state["establishments"][est_id].has("inventory"):
		world_state["establishments"][est_id]["inventory"] = {}
	world_state["establishments"][est_id]["inventory"]["BEER_KEG"] = 8.0

	var step_rest_json := JSON.stringify([ {"verb": "REST", "duration_ticks": 1.0, "estimated_hours": 6.0}])
	var stock_params_json := JSON.stringify({"establishment_id": est_id, "item_id": "BEER_KEG", "min_qty": 5.0})

	DBManagerScript.execute_batch([
		"""
		INSERT INTO standing_orders (standing_order_id, assigned_resident_id, title, cadence_rule, cadence_params_json, steps_json, estimated_hours, priority, is_active, valid_from, change_reason_id)
		VALUES (1, %d, 'Morning Stock Check', 'DAILY', '{}', '%s', 6.0, 50, 1, %d, %d);
		""" % [billy_id, step_rest_json.replace("'", "''"), start_day, change_reason_id],
		"""
		INSERT INTO standing_orders (standing_order_id, assigned_resident_id, title, cadence_rule, cadence_params_json, steps_json, estimated_hours, priority, is_active, valid_from, change_reason_id)
		VALUES (2, %d, 'Ledger Reconciliation', 'DAILY', '{}', '%s', 6.0, 60, 1, %d, %d);
		""" % [arthur_id, step_rest_json.replace("'", "''"), start_day, change_reason_id],
		"""
		INSERT INTO standing_orders (standing_order_id, assigned_resident_id, title, cadence_rule, cadence_params_json, steps_json, estimated_hours, priority, is_active, valid_from, change_reason_id)
		VALUES (3, %d, 'Pub Restock Trigger', 'ON_STOCK_BELOW_THRESHOLD', '%s', '%s', 6.0, 70, 1, %d, %d);
		""" % [tommy_id, stock_params_json.replace("'", "''"), step_rest_json.replace("'", "''"), start_day, change_reason_id],
		"""
		INSERT INTO standing_orders (standing_order_id, assigned_resident_id, title, cadence_rule, cadence_params_json, steps_json, estimated_hours, priority, is_active, valid_from, change_reason_id)
		VALUES (4, %d, 'Evening Sweep', 'DAILY', '{}', '%s', 4.0, 50, 1, %d, %d);
		""" % [danny_id, step_rest_json.replace("'", "''"), start_day, change_reason_id]
	])

	# 3. Test ON_STOCK_BELOW_THRESHOLD cadence (BEER_KEG = 8.0 >= 5.0 -> not due; 2.0 < 5.0 -> due)
	var tommy_before: Array[Dictionary] = StandingOrderProcessorScript.hydrate_for_day(world_state, start_day, func(t): return t.duplicate(true), tommy_id)
	assert(tommy_before.is_empty(), "FAIL: ON_STOCK_BELOW_THRESHOLD should not fire when stock (8.0) >= min_qty (5.0).")
	world_state["establishments"][est_id]["inventory"]["BEER_KEG"] = 2.0
	var tommy_after: Array[Dictionary] = StandingOrderProcessorScript.hydrate_for_day(world_state, start_day, func(t): return t.duplicate(true), tommy_id)
	assert(tommy_after.size() == 1, "FAIL: ON_STOCK_BELOW_THRESHOLD should fire when stock (2.0) < min_qty (5.0).")
	print("PASS [3]: ON_STOCK_BELOW_THRESHOLD cadence triggered accurately upon stock drop.")

	# 4. Test non-blocking composer conflict warning
	var built_dir: Dictionary = DirectiveComposerControllerScript.build_and_validate_directive({
		"verb": "REST",
		"assigned_to": billy_id,
		"target_node_id": home_dist,
		"amount": 1.0
	})
	assert(not built_dir.is_empty(), "FAIL: Composer should still allow staging manual directive for operative with standing orders.")
	assert(str(built_dir.get("standing_order_warning", "")) == "UI_WARN_STANDING_ORDER_CONFLICT",
		"FAIL: Expected non-blocking UI_WARN_STANDING_ORDER_CONFLICT token on directive.")
	print("PASS [4]: DirectiveComposerController attached non-blocking UI_WARN_STANDING_ORDER_CONFLICT.")

	# 5. Test Planning Fat & OCEAN Conflict Outcomes
	var adhoc_4h: Array = [ {"verb": "REST", "assigned_to": billy_id, "estimated_hours": 4.0}]
	var adhoc_3h: Array = [ {"verb": "REST", "assigned_to": danny_id, "estimated_hours": 3.0}]

	var danny_standing: Array[Dictionary] = StandingOrderProcessorScript.hydrate_for_day(world_state, start_day, func(t): return t.duplicate(true), danny_id)
	var danny_plan: Dictionary = StandingOrderProcessorScript.resolve_operative_shift_plan(world_state, danny_id, adhoc_3h, danny_standing)
	assert(danny_plan["mode"] == "STANDARD_COMBINED" and danny_plan["queue"].size() == 2,
		"FAIL: Ample planning fat should combine both ad-hoc and standing tasks.")

	var billy_standing: Array[Dictionary] = StandingOrderProcessorScript.hydrate_for_day(world_state, start_day, func(t): return t.duplicate(true), billy_id)
	var billy_plan: Dictionary = StandingOrderProcessorScript.resolve_operative_shift_plan(world_state, billy_id, adhoc_4h, billy_standing)
	assert(billy_plan["mode"] == "PRIORITIZE_NEW_DROP_STANDING", "FAIL: Expected PRIORITIZE_NEW_DROP_STANDING for Billy, got: %s" % billy_plan["mode"])
	assert(billy_plan["dropped_standing"].size() == 1 and billy_plan["memos"].size() == 1,
		"FAIL: Expected Billy to drop standing order and emit a Billy Issue memo.")

	var arthur_standing: Array[Dictionary] = StandingOrderProcessorScript.hydrate_for_day(world_state, start_day, func(t): return t.duplicate(true), arthur_id)
	var arthur_plan: Dictionary = StandingOrderProcessorScript.resolve_operative_shift_plan(world_state, arthur_id, adhoc_4h, arthur_standing)
	assert(arthur_plan["mode"] == "RAISE_ISSUE_TO_BOSS" and arthur_plan["memos"].size() == 1,
		"FAIL: Expected RAISE_ISSUE_TO_BOSS escalation memo for Arthur.")

	var tommy_plan: Dictionary = StandingOrderProcessorScript.resolve_operative_shift_plan(world_state, tommy_id, adhoc_4h, tommy_after)
	assert(tommy_plan["mode"] == "CAN_MANAGE_BOTH" and tommy_plan["queue"].size() == 2,
		"FAIL: Expected CAN_MANAGE_BOTH for Tommy.")
	print("PASS [5]: Planning fat and OCEAN conflict outcomes (STANDARD_COMBINED, Billy Issue, RAISE_ISSUE_TO_BOSS, CAN_MANAGE_BOTH) verified.")

	# 6. Test PAUSE_STANDING_ORDERS verb stamps start_day and auto-expires on start_day + 1
	var pause_res: Dictionary = SimControllerScript.execute_directive(world_state, {
		"verb": "PAUSE_STANDING_ORDERS",
		"assigned_to": billy_id
	})
	assert(pause_res.get("success", false), "FAIL: PAUSE_STANDING_ORDERS directive failed: %s" % str(pause_res))
	assert(StandingOrderProcessorScript.is_paused_for_day(world_state, billy_id, start_day),
		"FAIL: Operative %d should be paused on start_day (%d)." % [billy_id, start_day])
	assert(StandingOrderProcessorScript.hydrate_for_day(world_state, start_day, func(t): return t.duplicate(true), billy_id).is_empty(),
		"FAIL: Paused operative should hydrate 0 standing tasks on start_day.")
	assert(not StandingOrderProcessorScript.is_paused_for_day(world_state, billy_id, start_day + 1),
		"FAIL: Day-stamped pause must automatically expire on start_day + 1.")
	assert(StandingOrderProcessorScript.hydrate_for_day(world_state, start_day + 1, func(t): return t.duplicate(true), billy_id).size() == 1,
		"FAIL: Operative %d standing order should automatically resume on start_day + 1." % billy_id)
	print("PASS [6]: PAUSE_STANDING_ORDERS stamped start_day and auto-expired cleanly on the following day.")

	DBManagerScript.close_database()
	print("--- [Test] ALL STEP 1B STANDING ORDERS & BILLY ISSUE TESTS PASSED ---\n")
	quit(0)

static func _configure_operative(
	world_state: Dictionary,
	res_id: int,
	display_name: String,
	district_id: String,
	shift_limit: float,
	loyalty: float,
	ocean: Dictionary,
	tags: Array
) -> void:
	if not world_state.has("residents"):
		world_state["residents"] = {}
	var existing: Dictionary = world_state["residents"].get(res_id, {})
	existing["resident_id"] = res_id
	existing["name"] = display_name
	existing["current_district_id"] = district_id
	existing["daily_operational_limit_hours"] = shift_limit
	existing["loyalty"] = loyalty
	existing["ocean_traits"] = ocean
	existing["behavioral_tags"] = tags
	if not existing.has("inventory"):
		existing["inventory"] = {"CASH": 50.0}
	world_state["residents"][res_id] = existing