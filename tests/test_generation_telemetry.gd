# res://tests/test_generation_telemetry.gd
extends SceneTree

const GENERATION_TELEMETRY = preload("res://systems/generation_telemetry.gd")

func _init() -> void:
	print("=== RUNNING GENERATION TELEMETRY EMA TEST SUITE ===")

	var telemetry_path := GENERATION_TELEMETRY.TELEMETRY_PATH
	var backup_content: String = ""
	var had_existing: bool = FileAccess.file_exists(telemetry_path)
	if had_existing:
		var rf := FileAccess.open(telemetry_path, FileAccess.READ)
		if rf != null:
			backup_content = rf.get_as_text()
			rf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(telemetry_path))

	# 1. Cold-start seeding from business_rules.cfg [generation_pacing]
	var baseline: Dictionary = GENERATION_TELEMETRY.load_baseline_config()
	var alpha: float = float(baseline["ema_alpha"])
	assert(alpha > 0.0 and alpha <= 1.0, "FAIL [Test 1]: Invalid ema_alpha in business_rules.cfg.")

	var cold_weights: Dictionary = GENERATION_TELEMETRY.load_active_weights()
	var sum_cold: float = 0.0
	for k in cold_weights.keys():
		sum_cold += float(cold_weights[k])
	assert(absf(sum_cold - 1.0) < 0.0001, "FAIL [Test 1]: Cold weights must normalize to 1.0, got %f." % sum_cold)

	# 2. Monotonic cumulative stage ranges
	var ranges: Dictionary = GENERATION_TELEMETRY.compute_stage_ranges(cold_weights)
	var prev_end: float = 0.0
	for stage_id in GENERATION_TELEMETRY.ORDERED_STAGES:
		var r: Dictionary = ranges[stage_id]
		assert(absf(float(r["start"]) - prev_end) < 0.0001, "FAIL [Test 2]: Non-contiguous range at %s." % stage_id)
		assert(float(r["end"]) > float(r["start"]), "FAIL [Test 2]: Zero/negative span at %s." % stage_id)
		prev_end = float(r["end"])
	assert(absf(prev_end - 100.0) < 0.0001, "FAIL [Test 2]: Final stage must end at 100.0%%, got %f." % prev_end)

	var mid_pct: float = GENERATION_TELEMETRY.map_stage_progress(ranges, "SOCIETY_CITIZENS", 0.5)
	assert(mid_pct > float(ranges["SOCIETY_CITIZENS"]["start"]) and mid_pct < float(ranges["SOCIETY_CITIZENS"]["end"]),
		"FAIL [Test 2]: Midpoint interpolation out of bounds.")

	# 3. EMA update & user://gen_telemetry.json persistence
	var observed_ms: Dictionary = {
		"STREETS": 200,
		"DISTRICTS": 20,
		"SOCIETY_PREMISES": 150,
		"SOCIETY_CITIZENS": 500,
		"SOCIETY_DUNBAR": 80,
		"ROSTER": 25,
		"SAVE": 25
	}
	var updated_weights: Dictionary = GENERATION_TELEMETRY.record_run_durations(observed_ms)
	assert(FileAccess.file_exists(telemetry_path), "FAIL [Test 3]: user://gen_telemetry.json was not written.")

	var reloaded_weights: Dictionary = GENERATION_TELEMETRY.load_active_weights()
	for stage_id in GENERATION_TELEMETRY.ORDERED_STAGES:
		assert(absf(float(updated_weights[stage_id]) - float(reloaded_weights[stage_id])) < 0.0001,
			"FAIL [Test 3]: Reloaded weight mismatch for %s." % stage_id)

	# Restore pre-existing telemetry file if one existed before test
	if had_existing:
		var wf := FileAccess.open(telemetry_path, FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup_content)
			wf.close()
	elif FileAccess.file_exists(telemetry_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(telemetry_path))

	print("PASS [All Tests]: GenerationTelemetry seeding, monotonic range mapping, and EMA persistence verified.")
	quit(0)