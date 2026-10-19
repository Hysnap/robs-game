# res://tests/test_docket_priority_resolver.gd
extends SceneTree

const DOCKET_MGR = preload("res://systems/docket_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       STARTING DOCKET PRIORITY & DEPENDENCY TEST      ")
	print("=======================================================")

	var world_state = {
		"completed_task_ids": []
	}

	# Setup the 4 tasks matching your exact prompt:
	var task_a = {
		"id": "TASK_A",
		"name": "Evening Sales Run (After School)",
		"priority": 10,
		"depends_on": [],
		"earliest_tick": 16, # Locked until 4:00 PM / Tick 16
		"status": "PENDING"
	}
	
	var task_b = {
		"id": "TASK_B",
		"name": "Package Product Batches",
		"priority": 8,
		"depends_on": ["TASK_C"], # Waiting on raw materials from C
		"earliest_tick": 0,
		"status": "PENDING"
	}
	
	var task_c = {
		"id": "TASK_C",
		"name": "Procure Wholesale Raw Supplies",
		"priority": 5,
		"depends_on": ["TASK_DEP_EXTERNAL"], # External courier meet not yet arrived!
		"earliest_tick": 0,
		"status": "PENDING"
	}
	
	var task_d = {
		"id": "TASK_D",
		"name": "Tidy Workshop / Routine Ledger Audit",
		"priority": 1, # Lowest priority!
		"depends_on": [],
		"earliest_tick": 0,
		"status": "PENDING"
	}

	var active_pool = [task_a, task_b, task_c, task_d]

	# -------------------------------------------------------------
	# STEP 1: Morning (Tick 11) - Tasks A, B, and C are blocked
	# -------------------------------------------------------------
	var current_tick = 11
	print("\n--- [CLOCK: TICK %d] Evaluating Task Queue ---" % current_tick)
	
	var chosen_task = DOCKET_MGR.get_next_executable_task(world_state, active_pool, current_tick)
	print("  Chosen Task to Execute: [%s] (Priority %d)" % [chosen_task["id"], chosen_task["priority"]])
	
	# Verify that Task D runs first despite being lowest priority!
	assert(chosen_task["id"] == "TASK_D", "FAILED: Task D should have been selected because A, B, and C are blocked!")
	print("  ✓ PASS: Task D executed first because A was time-locked and B/C were dependency-blocked.")
	DOCKET_MGR.mark_task_completed(world_state, task_d)

	# -------------------------------------------------------------
	# STEP 2: External Courier arrives -> Unblocks Task C
	# -------------------------------------------------------------
	print("\n--- Courier Arrives: Completing External Dependency ---")
	world_state["completed_task_ids"].append("TASK_DEP_EXTERNAL")
	
	chosen_task = DOCKET_MGR.get_next_executable_task(world_state, active_pool, current_tick)
	print("  Chosen Task to Execute: [%s] (Priority %d)" % [chosen_task["id"], chosen_task["priority"]])
	assert(chosen_task["id"] == "TASK_C", "FAILED: Task C should now run!")
	print("  ✓ PASS: Task C executed.")
	DOCKET_MGR.mark_task_completed(world_state, task_c)

	# -------------------------------------------------------------
	# STEP 3: Task C is complete -> Unblocks Task B (Priority 8)
	# -------------------------------------------------------------
	print("\n--- Task C Done: Evaluating Queue at Tick 12 ---")
	chosen_task = DOCKET_MGR.get_next_executable_task(world_state, active_pool, 12)
	print("  Chosen Task to Execute: [%s] (Priority %d)" % [chosen_task["id"], chosen_task["priority"]])
	assert(chosen_task["id"] == "TASK_B", "FAILED: Task B should run now that C is done!")
	print("  ✓ PASS: Task B executed.")
	DOCKET_MGR.mark_task_completed(world_state, task_b)

	# -------------------------------------------------------------
	# STEP 4: Clock advances past school (Tick 16) -> Unblocks Task A
	# -------------------------------------------------------------
	current_tick = 16
	print("\n--- [CLOCK: TICK %d (School Ends)] Evaluating Queue ---" % current_tick)
	chosen_task = DOCKET_MGR.get_next_executable_task(world_state, active_pool, current_tick)
	print("  Chosen Task to Execute: [%s] (Priority %d)" % [chosen_task["id"], chosen_task["priority"]])
	assert(chosen_task["id"] == "TASK_A", "FAILED: Task A should run now that tick >= 16!")
	print("  ✓ PASS: Task A (Highest Priority) finally executed when its time gate unlocked.")

	print("\n=======================================================")
	print("       ALL PRIORITY & DEPENDENCY TESTS PASSED!         ")
	print("=======================================================\n")
	quit()