# res://tests/test_crime_impacts_and_bulk_importer.gd
extends SceneTree

const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")

const UI_STRINGS_PATH: String = "res://data_modules/core/localization/ui_strings.csv"
const TEST_ITEM_DIR: String = "res://data_modules/core/commodities/consumables/test_bulk_contraband"
const TEST_VERB_DIR: String = "res://data_modules/core/verbs/test_bulk_verb"

func _init() -> void:
	print("\n========================================================")
	print("🧪 RUNNING HEADLESS TEST: CRIME IMPACTS & CSV BULK IMPORTER")
	print("========================================================")

	var orig_ui_strings: String = _read_text(UI_STRINGS_PATH)
	_cleanup_test_artifacts(orig_ui_strings)

	_test_core_vs_crime_impact_isolation()
	_test_crime_mode_gated_impacts()
	_test_csv_bulk_importer_happy_append_and_fail_loud()

	_cleanup_test_artifacts(orig_ui_strings)
	print("\n✅ ALL CRIME IMPACT & CSV BULK IMPORTER CHECKS PASSED!\n")
	quit(0)

func _test_core_vs_crime_impact_isolation() -> void:
	print("[1/3] Testing core vs. crime impacts_dirs isolation...")
	VerbRouterScript.initialize("core")
	for verb_tok in ["COLLECT_FROM", "INVESTIGATE", "COMMUNICATE"]:
		var core_dirs: Array[String] = VerbRouterScript.get_impacts_dirs(verb_tok)
		for d in core_dirs:
			assert(not d.contains("/crime/"), "Crime impacts leaked into core-only VerbRouter for %s: %s" % [verb_tok, d])

	VerbRouterScript.initialize("crime")
	var crime_collect_dirs: Array[String] = VerbRouterScript.get_impacts_dirs("COLLECT_FROM")
	var has_crime_dir := false
	for d in crime_collect_dirs:
		if d.contains("/crime/"):
			has_crime_dir = true
	assert(has_crime_dir, "Crime overlay failed to mount crime impacts_dir on COLLECT_FROM.")

func _test_crime_mode_gated_impacts() -> void:
	print("[2/3] Testing declarative mode-gated crime impacts (ROB vs PICKPOCKET, CASE_JOINT, THREATEN)...")
	VerbRouterScript.initialize("crime")
	ImpactRouterScript.reset()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")
	ImpactRouterScript.autoload_sinks("res://data_modules/crime/impacts/")

	var ws: Dictionary = {
		"current_sim_day": 10,
		"districts": {
			"DIST_CENTRE": {"id": "DIST_CENTRE", "actual_police_heat": 0.0},
			"DIST_SOUTH": {"id": "DIST_SOUTH", "actual_police_heat": 0.0},
			"DIST_NORTH": {"id": "DIST_NORTH", "actual_police_heat": 0.0}
		},
		"residents": {
			"101": {"id": 101, "current_district_id": "DIST_CENTRE", "criminal_suspicion": 0.0, "notoriety": 0.0},
			"102": {"id": 102, "current_district_id": "DIST_SOUTH", "criminal_suspicion": 0.0, "notoriety": 0.0}
		},
		"establishments": {
			"501": {"id": 501, "district_id": "DIST_CENTRE"}
		},
		"knowledge_pools": {}
	}

	# 1. PICKPOCKET (low profile)
	var pickpocket_res: Dictionary = SimControllerScript._dispatch_verb_impacts(
		ws,
		{"verb": "COLLECT_FROM", "mode": "PICKPOCKET", "assigned_to": "101", "target_node_id": "DIST_CENTRE"},
		"COLLECT_FROM",
		"101",
		"DIST_CENTRE"
	)
	assert(is_equal_approx(float(pickpocket_res.get("POLICE_HEAT", 0.0)), 2.0), "PICKPOCKET should dispatch +2.0 POLICE_HEAT delta.")
	assert(float(ws["districts"]["DIST_CENTRE"]["actual_police_heat"]) > 0.0, "PICKPOCKET should raise actual_police_heat on DIST_CENTRE.")
	assert(is_equal_approx(float(ws["residents"]["101"]["notoriety"]), 1.5), "PICKPOCKET should add +1.5 NOTORIETY.")

	# 2. ROB (high profile)
	var rob_res: Dictionary = SimControllerScript._dispatch_verb_impacts(
		ws,
		{"verb": "COLLECT_FROM", "mode": "ROB", "assigned_to": "102", "target_node_id": "DIST_SOUTH"},
		"COLLECT_FROM",
		"102",
		"DIST_SOUTH"
	)
	assert(is_equal_approx(float(rob_res.get("POLICE_HEAT", 0.0)), 14.0), "ROB should dispatch +14.0 POLICE_HEAT delta.")
	assert(float(ws["districts"]["DIST_SOUTH"]["actual_police_heat"]) > 0.0, "ROB should raise actual_police_heat on DIST_SOUTH.")
	assert(is_equal_approx(float(ws["residents"]["102"]["criminal_suspicion"]), 10.0), "ROB should add +10.0 CRIMINAL_SUSPICION.")
	assert(is_equal_approx(float(ws["residents"]["102"]["notoriety"]), 8.0), "ROB should add +8.0 NOTORIETY.")

	# 3. INVESTIGATE (CASE_JOINT) -> INTEL_SCORE + CRIMINAL_SUSPICION
	SimControllerScript._dispatch_verb_impacts(
		ws,
		{"verb": "INVESTIGATE", "mode": "CASE_JOINT", "assigned_to": "101", "target_node_id": "501", "duration_ticks": 1.0},
		"INVESTIGATE",
		"101",
		"501"
	)
	assert(float(ws["residents"]["101"]["criminal_suspicion"]) >= 4.0, "CASE_JOINT should elevate CRIMINAL_SUSPICION by +4.0.")
	var intel_score: float = float(ws.get("knowledge_pools", {}).get("RESIDENT:101", {}).get("ESTABLISHMENT:501", {}).get("score", 0.0))
	assert(intel_score > 0.0, "CASE_JOINT should generate positive INTEL_SCORE on ESTABLISHMENT:501.")

	# 4. COMMUNICATE (THREATEN) -> POLICE_HEAT + NOTORIETY
	var threaten_res: Dictionary = SimControllerScript._dispatch_verb_impacts(
		ws,
		{"verb": "COMMUNICATE", "intent": "THREATEN", "assigned_to": "101", "target_node_id": "DIST_NORTH"},
		"COMMUNICATE",
		"101",
		"DIST_NORTH"
	)
	assert(is_equal_approx(float(threaten_res.get("POLICE_HEAT", 0.0)), 6.0), "THREATEN should dispatch +6.0 POLICE_HEAT delta.")
	assert(float(ws["districts"]["DIST_NORTH"]["actual_police_heat"]) > 0.0, "THREATEN should raise actual_police_heat on DIST_NORTH.")
	assert(is_equal_approx(float(ws["residents"]["101"]["notoriety"]), 5.5), "THREATEN should add +4.0 NOTORIETY (total 5.5).")
	
func _test_csv_bulk_importer_happy_append_and_fail_loud() -> void:
	print("[3/3] Testing CSV bulk importer (create, additive append, and fail-loud conflict/overwrite protection)...")
	var comm_csv_1 := "user://test_bulk_comm_1.csv"
	var verb_csv_1 := "user://test_bulk_verb_1.csv"
	_write_text(comm_csv_1,
		"id,module,category,display_name_token,base_cost,label_en,tags\n" +
		"TEST_BULK_CONTRABAND,core,consumables,UI_ITEM_TEST_BULK_CONTRABAND,12.50,Test Bulk Contraband,CONTRABAND|TEST\n"
	)
	_write_text(verb_csv_1,
		"verb_token,module,label_token,allowed_scopes,label_en,mode,impact_metric,impact_delta\n" +
		"TEST_BULK_VERB,core,UI_VERB_TEST_BULK,DISTRICT|ESTABLISHMENT,Test Bulk Verb,SCOUT_TEST,POLICE_HEAT,3.5\n"
	)

	var godot_bin: String = OS.get_executable_path()
	var output_1: Array = []
	var exit_1: int = OS.execute(godot_bin, ["--headless", "--path", ".", "--script", "res://tools/importers/csv_bulk_importer.gd", "--", "--commodities=" + comm_csv_1, "--verbs=" + verb_csv_1], output_1, true)
	assert(exit_1 == 0, "Expected exit code 0 on valid initial CSV import, got %d:\n%s" % [exit_1, "\n".join(output_1)])

	var created_item_path := TEST_ITEM_DIR.path_join("item_profile.json")
	var created_verb_path := TEST_VERB_DIR.path_join("verb_definition.json")
	assert(FileAccess.file_exists(created_item_path), "Expected commodity profile to be created at %s" % created_item_path)
	assert(FileAccess.file_exists(created_verb_path), "Expected verb definition to be created at %s" % created_verb_path)

	var updated_ui: String = _read_text(UI_STRINGS_PATH)
	assert(updated_ui.contains("\"UI_ITEM_TEST_BULK_CONTRABAND\""), "Expected new commodity localization token appended to ui_strings.csv.")
	assert(updated_ui.contains("\"UI_VERB_TEST_BULK\""), "Expected new verb localization token appended to ui_strings.csv.")

	# Additive append test: add new property (tax_class) and new mode (SECOND_TEST) without overwriting existing fields
	var comm_csv_2 := "user://test_bulk_comm_2.csv"
	var verb_csv_2 := "user://test_bulk_verb_2.csv"
	_write_text(comm_csv_2,
		"id,module,category,display_name_token,base_cost,tax_class\n" +
		"TEST_BULK_CONTRABAND,core,consumables,UI_ITEM_TEST_BULK_CONTRABAND,12.50,STANDARD\n"
	)
	_write_text(verb_csv_2,
		"verb_token,module,label_token,allowed_scopes,label_en,mode\n" +
		"TEST_BULK_VERB,core,UI_VERB_TEST_BULK_2,DISTRICT,Test Bulk Verb Mode 2,SECOND_TEST\n"
	)
	var output_2: Array = []
	var exit_2: int = OS.execute(godot_bin, ["--headless", "--path", ".", "--script", "res://tools/importers/csv_bulk_importer.gd", "--", "--commodities=" + comm_csv_2, "--verbs=" + verb_csv_2], output_2, true)
	assert(exit_2 == 0, "Expected exit code 0 on non-destructive additive append, got %d:\n%s" % [exit_2, "\n".join(output_2)])

	var appended_item := JSON.parse_string(_read_text(created_item_path)) as Dictionary
	assert(str(appended_item.get("tax_class", "")) == "STANDARD", "Expected additive append to add missing 'tax_class' property.")

	# Fail-loud conflict test: changing base_cost on existing item must fail with exit code 1
	var comm_csv_conflict := "user://test_bulk_comm_conflict.csv"
	_write_text(comm_csv_conflict,
		"id,module,category,display_name_token,base_cost\n" +
		"TEST_BULK_CONTRABAND,core,consumables,UI_ITEM_TEST_BULK_CONTRABAND,99.99\n"
	)
	var output_3: Array = []
	var exit_3: int = OS.execute(godot_bin, ["--headless", "--path", ".", "--script", "res://tools/importers/csv_bulk_importer.gd", "--", "--commodities=" + comm_csv_conflict], output_3, true)
	assert(exit_3 != 0, "Expected non-zero fail-loud exit code when attempting to overwrite existing base_cost.")

	# Fail-loud --overwrite flag rejection test
	var output_4: Array = []
	var exit_4: int = OS.execute(godot_bin, ["--headless", "--path", ".", "--script", "res://tools/importers/csv_bulk_importer.gd", "--", "--commodities=" + comm_csv_2, "--overwrite"], output_4, true)
	assert(exit_4 != 0, "Expected non-zero fail-loud exit code when --overwrite flag is passed.")

	for tmp in [comm_csv_1, verb_csv_1, comm_csv_2, verb_csv_2, comm_csv_conflict]:
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

func _cleanup_test_artifacts(orig_ui_strings: String) -> void:
	_remove_dir_recursive(TEST_ITEM_DIR)
	_remove_dir_recursive(TEST_VERB_DIR)
	if not orig_ui_strings.is_empty():
		_write_text(UI_STRINGS_PATH, orig_ui_strings)

func _remove_dir_recursive(res_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(res_dir):
		return
	var d := DirAccess.open(res_dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := res_dir.path_join(entry)
			if d.current_is_dir():
				_remove_dir_recursive(child)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(res_dir))

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt

func _write_text(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()