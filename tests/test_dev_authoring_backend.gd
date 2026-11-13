# res://tests/test_dev_authoring_backend.gd
extends SceneTree

const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")
const ControllerScript = preload("res://systems/dev_authoring/dev_authoring_controller.gd")

func _init() -> void:
	print("\n--- [Test] Starting Developer Authoring Backend & Logic Branch Suite ---")
	var passed: bool = true

	passed = passed and test_condition_evaluator_logic_and_branches()
	passed = passed and test_impact_whitelist_enforcement()
	passed = passed and test_macro_verb_wip_soft_lock_and_resume()

	if passed:
		print("--- [Test] ALL DEV AUTHORING BACKEND & LOGIC TESTS PASSED ---\n")
		quit(0)
	else:
		printerr("--- [Test] DEV AUTHORING BACKEND VERIFICATION FAILED ---\n")
		quit(1)

func test_condition_evaluator_logic_and_branches() -> bool:
	# 1. Test BETWEEN operator and OR gate routing to on_true
	var gates_or: Array = [
		{ "current": 25.0, "target": 100.0, "operator": ">=" }, # False
		{ "current": 50.0, "lower": 10.0, "upper": 60.0, "operator": "BETWEEN" } # True
	]
	var branch_true: Dictionary = ConditionEvaluatorScript.evaluate_decision_branch(
		"OR",
		gates_or,
		"step_pay_cash",
		"step_visit_atm",
		"PAYMENT_REQUIRED"
	)
	if not bool(branch_true.get("passed", false)) or str(branch_true.get("next_step", "")) != "step_pay_cash":
		printerr("FAIL: Expected OR gate with BETWEEN to pass and route to 'step_pay_cash'.")
		return false

	# 2. Test NOR gate and routing to on_false step (without halting)
	var branch_false: Dictionary = ConditionEvaluatorScript.evaluate_decision_branch(
		"AND",
		gates_or,
		"step_pay_cash",
		"step_visit_atm",
		"PAYMENT_REQUIRED"
	)
	if bool(branch_false.get("passed", true)) or bool(branch_false.get("halt", true)) or str(branch_false.get("next_step", "")) != "step_visit_atm":
		printerr("FAIL: Expected failed AND gate with on_false target to branch to 'step_visit_atm' without halting.")
		return false

	# 3. Test NAND and NOR gates directly
	var both_false: Array = [
		{ "current": 5.0, "target": 10.0, "operator": ">=" },
		{ "current": "DISTRICT_A", "target": "DISTRICT_B", "operator": "==" }
	]
	if not ConditionEvaluatorScript.evaluate_logic_block("NOR", both_false):
		printerr("FAIL: Expected NOR gate to return true when all inputs are false.")
		return false
	if not ConditionEvaluatorScript.evaluate_logic_block("NAND", gates_or):
		printerr("FAIL: Expected NAND gate to return true when not all inputs are true.")
		return false

	print("PASS: ConditionEvaluator BETWEEN, AND, OR, NAND, NOR, and on_true/on_false branching verified.")
	return true

func test_impact_whitelist_enforcement() -> bool:
	var catalog: Dictionary = ControllerScript.get_workbench_catalog_snapshot()
	var allowed_impacts: Array = catalog.get("impacts", [])
	if allowed_impacts.is_empty():
		printerr("FAIL: Expected get_workbench_catalog_snapshot() to discover existing impacts on disk.")
		return false

	var bad_commodity_spec: Dictionary = {
		"module": "core",
		"id": "TEST_BAD_ITEM",
		"category": "consumables",
		"unit_mass_kg": 1.0,
		"unit_volume_l": 1.0,
		"base_cost": 10.0,
		"impacts": [
			{
				"verb_context": "consume",
				"metric_key": "NON_EXISTENT_BOGUS_IMPACT",
				"model": "LINEAR_PER_UNIT",
				"factor": 5.0
			}
		]
	}

	var check: Dictionary = ControllerScript.preview_validation("COMMODITY", bad_commodity_spec)
	if bool(check.get("can_save_draft", true)):
		printerr("FAIL: Validator allowed an unregistered impact metric to pass!")
		return false

	print("PASS: Strict Impact Whitelisting blocked unmounted impact metric ('NON_EXISTENT_BOGUS_IMPACT').")
	return true

func test_macro_verb_wip_soft_lock_and_resume() -> bool:
	# 1. Prevent self-recursion (Hard Block)
	var recursive_spec: Dictionary = {
		"module": "core",
		"verb_token": "TEST_WIP_MACRO",
		"sequence": [
			{
				"step_id": "step_1",
				"primitive": "CALL_VERB",
				"params": { "verb_token": "TEST_WIP_MACRO" }
			}
		]
	}
	var rec_check: Dictionary = ControllerScript.preview_validation("MACRO_VERB", recursive_spec)
	if bool(rec_check.get("can_save_draft", true)):
		printerr("FAIL: Validator failed to hard-block self-recursive CALL_VERB.")
		return false

	# 2. Construct half-finished Macro Verb (unbuilt branch target & unbuilt sub-verb)
	var wip_spec: Dictionary = {
		"module": "core",
		"verb_token": "TEST_WIP_MACRO",
		"sequence": [
			{
				"step_id": "check_cash_or_credit",
				"primitive": "REQUIRE",
				"params": {
					"logic_gate": "OR",
					"conditions": [
						ControllerScript.create_condition_template("COMMODITY", "ORDER_ACTOR", "CASH", ">=", 100.0)
					]
				},
				"on_true": "execute_sub_routine",
				"on_false": "step_not_built_yet"
			},
			{
				"step_id": "execute_sub_routine",
				"primitive": "CALL_VERB",
				"params": {
					"verb_token": "FUTURE_SUB_VERB_NOT_BUILT"
				}
			}
		]
	}

	# Attempt to save with request_make_live = true; soft-lock must downgrade it to WIP draft!
	var save_res: Dictionary = ControllerScript.save_macro_verb(wip_spec, true)
	if not bool(save_res.get("success", false)):
		printerr("FAIL: Soft-lock prevented saving WIP Macro Verb draft! Errors: ", save_res.get("validation", {}))
		return false
	if bool(save_res.get("is_live", true)):
		printerr("FAIL: Soft-lock allowed incomplete Macro Verb with missing step/sub-verb to go LIVE!")
		_cleanup_test_verb_dir()
		return false

	# 3. Reload the saved WIP draft and verify everything was preserved
	var loaded: Dictionary = ControllerScript.load_existing_verb("TEST_WIP_MACRO")
	var seq: Array = loaded.get("sequence", [])
	var scope: Dictionary = loaded.get("target_scope", {})
	var passed_reload: bool = (
		seq.size() == 2
		and not bool(loaded.get("is_live", true))
		and not bool(scope.get("visible_in_composer", true))
	)

	_cleanup_test_verb_dir()

	if not passed_reload:
		printerr("FAIL: Reloaded WIP Macro Verb did not preserve sequence or composer visibility soft-lock.")
		return false

	print("PASS: WIP Macro Verb saved with soft-lock, blocked from live composer, and reloaded cleanly.")
	return true

func _cleanup_test_verb_dir() -> void:
	var test_dir: String = ProjectSettings.globalize_path("res://data_modules/core/verbs/test_wip_macro")
	if not DirAccess.dir_exists_absolute(test_dir):
		return
	var dir := DirAccess.open(test_dir)
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				dir.remove(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(test_dir)