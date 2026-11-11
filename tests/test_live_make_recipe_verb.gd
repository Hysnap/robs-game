# res://tests/test_live_make_recipe_verb.gd
extends SceneTree

const EngineResultScript = preload("res://systems/engine_result.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")

func _init() -> void:
	print("\n--- [Test] Verifying Declarative MAKE_ROLL_CIGARETTE Recipe Verb ---")
	var passed: bool = true

	passed = passed and test_recipe_verb_mounting()
	passed = passed and test_recipe_verb_success()
	passed = passed and test_recipe_verb_shortage_halt()

	if passed:
		print("--- [Test] DECLARATIVE RECIPE VERB FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DECLARATIVE RECIPE VERB VERIFICATION FAILED ---\n")
		quit(1)

func _create_fixture_state() -> Dictionary:
	return {
		"residents": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_HQ",
				"inventory": {
					"ROLLING_TOBACCO": 2.0,
					"ROLLING_PAPERS": 2.0
				}
			}
		},
		"establishments": {},
		"caches": {},
		"districts": {
			"DISTRICT_HQ": { "venues": {} }
		}
	}

func test_recipe_verb_mounting() -> bool:
	VerbRouterScript.initialize()
	var registered: Array[String] = VerbRouterScript.get_registered_verbs()

	if not registered.has("MAKE_ROLL_CIGARETTE"):
		printerr("FAIL: VerbRouter failed to discover and mount 'MAKE_ROLL_CIGARETTE'.")
		return false

	print("PASS: VerbRouter dynamically mounted 'MAKE_ROLL_CIGARETTE'.")
	return true

func test_recipe_verb_success() -> bool:
	var ws := _create_fixture_state()
	var directive := {
		"verb": "MAKE_ROLL_CIGARETTE",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_HQ"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if not res.get("success", false):
		printerr("FAIL: MAKE_ROLL_CIGARETTE dispatch failed unexpectedly: ", res.get("message"))
		return false

	var inv: Dictionary = ws["residents"]["op_01"]["inventory"]
	var tobacco: float = float(inv.get("ROLLING_TOBACCO", 0.0))
	var papers: float = float(inv.get("ROLLING_PAPERS", 0.0))
	var rollups: float = float(inv.get("ROLLUP", 0.0))

	# Started: 2.0 tobacco, 2.0 papers, 0.0 rollups
	# Consumes: 0.8 tobacco, 1.0 paper -> 1.2 tobacco, 1.0 paper, 1.0 rollup
	if not is_equal_approx(tobacco, 1.2) or not is_equal_approx(papers, 1.0) or not is_equal_approx(rollups, 1.0):
		printerr("FAIL: Inventory balances incorrect after crafting. Tobacco: %f, Papers: %f, Rollups: %f" % [tobacco, papers, rollups])
		return false

	print("PASS: MAKE_ROLL_CIGARETTE executed successfully, inputs consumed and yield deposited.")
	return true

func test_recipe_verb_shortage_halt() -> bool:
	var ws := _create_fixture_state()
	# Set papers below required 1.0 unit threshold
	ws["residents"]["op_01"]["inventory"]["ROLLING_PAPERS"] = 0.5

	var directive := {
		"verb": "MAKE_ROLL_CIGARETTE",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_HQ"
	}

	var res: Dictionary = VerbRouterScript.dispatch(ws, directive)
	if res.get("success", true):
		printerr("FAIL: MAKE_ROLL_CIGARETTE should have halted on paper shortage.")
		return false

	var err_code: int = int(res.get("error_code", -1))
	if err_code != EngineResultScript.ErrorCode.INSUFFICIENT_RESOURCE:
		printerr("FAIL: Expected INSUFFICIENT_RESOURCE, got: ", err_code)
		return false

	# Verify zero materials were consumed on failure (fail early, fail clean)
	var inv: Dictionary = ws["residents"]["op_01"]["inventory"]
	var tobacco: float = float(inv.get("ROLLING_TOBACCO", 0.0))
	var papers: float = float(inv.get("ROLLING_PAPERS", 0.0))
	if not is_equal_approx(tobacco, 2.0) or not is_equal_approx(papers, 0.5):
		printerr("FAIL: Inventory altered despite early failure halt!")
		return false

	print("PASS: Shortage halted early with INSUFFICIENT_RESOURCE; zero inventory consumed.")
	return true