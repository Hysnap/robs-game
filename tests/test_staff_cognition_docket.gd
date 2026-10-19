# res://tests/test_staff_cognition_docket.gd
extends SceneTree

const DOCKET_MGR = preload("res://systems/docket_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       STAFF COGNITION & PLANNING HORIZON TEST         ")
	print("=======================================================")

	var world_state = {"completed_task_ids": []}

	# Setup the exact prompt tasks:
	var task_a = {"id": "TASK_A", "priority": 10, "depends_on": [], "earliest_tick": 16}
	var task_b = {"id": "TASK_B", "priority": 8, "depends_on": ["TASK_C"], "earliest_tick": 0}
	var task_c = {"id": "TASK_C", "priority": 5, "depends_on": ["TASK_EXT"], "earliest_tick": 0}
	var task_d = {"id": "TASK_D", "priority": 1, "depends_on": [], "earliest_tick": 0} # Lowest priority, but ready!

	var queue = [task_a, task_b, task_c, task_d]
	var current_tick = 11 # Morning (before school @ 16)

	# Profile 1: Simple / Raw Runner
	var simple_staff = {
		"name": "Billy (Low-tier Runner)",
		"planning_horizon_limit": 3,   # Only sees top 3 (A, B, C)
		"max_dependency_depth": 1,     # Can only handle 1 prereq
		"opportunity_scanning": false  # Blindsided by top bottlenecks
	}

	# Profile 2: Senior Steerer / Manager
	var skilled_staff = {
		"name": "Marcus (Experienced Steerer)",
		"planning_horizon_limit": 10,  # Sees full queue
		"max_dependency_depth": 4,     # Handles complex chains
		"opportunity_scanning": true   # Opportunistic backfilling
	}

	# -------------------------------------------------------------
	# TEST 1: Simple Staff Evaluation
	# -------------------------------------------------------------
	print("\n--- [TEST 1] Dispatching: %s ---" % simple_staff["name"])
	var simple_choice = DOCKET_MGR.get_next_task_for_staff(world_state, queue, current_tick, simple_staff)
	print("  Evaluation Result: ", simple_choice.get("id", "NONE (IDLE / WAITING)"))
	
	assert(simple_choice.is_empty(), "FAILED: Simple worker should not have found a task due to tunnel vision!")
	print("  ✓ PASS: Simple worker idled because A, B, and C were blocked, failing to notice Task D.")

	# -------------------------------------------------------------
	# TEST 2: Skilled Staff Evaluation
	# -------------------------------------------------------------
	print("\n--- [TEST 2] Dispatching: %s ---" % skilled_staff["name"])
	var skilled_choice = DOCKET_MGR.get_next_task_for_staff(world_state, queue, current_tick, skilled_staff)
	print("  Evaluation Result: Selected [%s] (Priority %d)" % [skilled_choice["id"], skilled_choice["priority"]])
	
	assert(skilled_choice.get("id") == "TASK_D", "FAILED: Skilled worker should have found Task D!")
	print("  ✓ PASS: Skilled worker scanned past blocked tasks and executed Task D early.")

	print("\n=======================================================")
	print("       STAFF COGNITION TESTS PASSED CLEANLY!           ")
	print("=======================================================\n")
	quit()