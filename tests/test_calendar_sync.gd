# res://tests/test_calendar_sync.gd
extends SceneTree

const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const DB_MGR = preload("res://systems/db_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   STARTING CALENDAR HELPER & TEMPORAL SYNC TEST       ")
	print("=======================================================")

	# -------------------------------------------------------------
	# 1. INITIALIZE TEMPORAL ANCHOR VIA DBMANGER
	# -------------------------------------------------------------
	DB_MGR.initialize_database(false)
	
	var temporal_config: Dictionary = {
		"epoch_date": "1900-01-01",
		"simulation_start_date": "1980-01-01",
		"days_per_tick": 7
	}
	CALENDAR_HELPER.initialize(temporal_config)

	var start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	print("  Initialized start day offset: %d" % start_day)
	assert(start_day > 0, "FAILED: Simulation start day offset must be positive.")
	assert(CALENDAR_HELPER.get_days_per_tick() == 7, "FAILED: Days per tick must be 7.")

	# -------------------------------------------------------------
	# TEST SUITE 1: 14-Day Day-Of-Week Cycling (1 -> 7 -> 1)
	# -------------------------------------------------------------
	print("\n--- [SUITE 1] Testing Day of Week Cycling (1..7) ---")
	for i in range(14):
		var test_day: int = start_day + i
		var dow: int = CALENDAR_HELPER.day_of_week(test_day)
		var expected_dow: int = (i % 7) + 1
		assert(dow == expected_dow, "FAILED: Day %d produced DOW %d, expected %d" % [i, dow, expected_dow])
		assert(dow >= 1 and dow <= 7, "FAILED: DOW out of bounds [1, 7]: %d" % dow)
	print("  ✓ PASS: 14-day day_of_week cycle verified with zero drift.")

	# -------------------------------------------------------------
	# TEST SUITE 2: Week Calculation & Boundary Crossings
	# -------------------------------------------------------------
	print("\n--- [SUITE 2] Testing Week Calculations & Boundary Checks ---")
	# Week 1 boundaries
	assert(CALENDAR_HELPER.day_to_week(start_day + 0) == 1, "FAILED: Start day must be Week 1.")
	assert(CALENDAR_HELPER.day_to_week(start_day + 6) == 1, "FAILED: Day offset 6 must be Week 1.")
	assert(CALENDAR_HELPER.day_to_week(start_day + 7) == 2, "FAILED: Day offset 7 must be Week 2.")
	assert(CALENDAR_HELPER.day_to_week(start_day + 13) == 2, "FAILED: Day offset 13 must be Week 2.")
	assert(CALENDAR_HELPER.day_to_week(start_day + 14) == 3, "FAILED: Day offset 14 must be Week 3.")

	# Boundary crossing triggers
	# Stepping 1 day from Day 6 (offset 5 -> 6): within Week 1
	assert(CALENDAR_HELPER.crosses_week_boundary(start_day + 5, 1) == false, "FAILED: Offset 5 -> 6 should not cross boundary.")
	# Stepping 1 day from Day 7 (offset 6 -> 7): crosses Week 1 -> Week 2
	assert(CALENDAR_HELPER.crosses_week_boundary(start_day + 6, 1) == true, "FAILED: Offset 6 -> 7 must cross week boundary.")
	# Stepping 1 day from Day 8 (offset 7 -> 8): within Week 2
	assert(CALENDAR_HELPER.crosses_week_boundary(start_day + 7, 1) == false, "FAILED: Offset 7 -> 8 should not cross boundary.")
	# Advancing by full week tick (7 days) always crosses boundary
	assert(CALENDAR_HELPER.crosses_week_boundary(start_day + 0, 7) == true, "FAILED: +7 days must cross week boundary.")
	print("  ✓ PASS: Week boundaries and transition flags evaluated accurately.")

	# -------------------------------------------------------------
	# TEST SUITE 3: 20-Year (1,040 Weeks / 7,280 Turns) Continuous Simulation Invariant
	# -------------------------------------------------------------
	print("\n--- [SUITE 3] Testing 20-Year Simulation Step Invariant (7,280 Steps) ---")
	var sim_day: int = start_day
	var boundary_cross_count: int = 0
	var total_turns: int = 1040 * 7 # 7,280 daily turns

	for turn in range(total_turns):
		# Verify DOW for current turn
		var current_dow: int = CALENDAR_HELPER.day_of_week(sim_day)
		var expected_dow: int = (turn % 7) + 1
		if current_dow != expected_dow:
			assert(false, "DRIFT DETECTED at Turn %d: DOW was %d, expected %d" % [turn, current_dow, expected_dow])

		# Check boundary crossing if stepping by 1 day
		var crosses: bool = CALENDAR_HELPER.crosses_week_boundary(sim_day, 1)
		if crosses:
			boundary_cross_count += 1
			# Boundary crossing MUST only happen when transitioning from DOW 7 to DOW 1
			assert(current_dow == 7, "FAILED: Boundary crossed when DOW was %d (expected 7)" % current_dow)

		# Step by 1 day
		sim_day += 1

	print("  Completed %d daily steps." % total_turns)
	print("  Total week boundaries crossed: %d (expected 1,040)" % boundary_cross_count)
	assert(boundary_cross_count == 1040, "FAILED: Expected exactly 1,040 boundary crossings over 7,280 steps.")
	
	var final_week: int = CALENDAR_HELPER.day_to_week(sim_day)
	print("  Final Week after 7,280 steps: Week %d (expected 1,041)" % final_week)
	assert(final_week == 1041, "FAILED: Expected to be at start of Week 1041.")
	print("  ✓ PASS: Zero temporal drift across 20 simulated years.")

	print("\n=======================================================")
	print("   ALL CALENDAR HELPER TESTS PASSED CLEANLY!           ")
	print("=======================================================")
	quit()