# res://tests/test_ui_pipeline_diary.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")

const SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/diary_log.json"
const GENERATED_SCRIPT_PATH := "res://generated/ui/gen_diary_log.gd"

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   TEST: UI PIPELINE - DIARY LOG COMPILATION & BINDING")
	SystemLogger.log_info("=======================================================")

	# 1. Compile target schema
	SystemLogger.log_info("\n[STEP 1] Compiling diary_log.json schema...")
	assert(FileAccess.file_exists(SCHEMA_PATH), "Schema missing at: %s" % SCHEMA_PATH)
	UICompilerScript.compile_schema(SCHEMA_PATH)
	assert(FileAccess.file_exists(GENERATED_SCRIPT_PATH), "Generated file missing: %s" % GENERATED_SCRIPT_PATH)
	SystemLogger.log_info("  ✓ Successfully compiled to: %s" % GENERATED_SCRIPT_PATH)

	# 2. Instantiate View
	SystemLogger.log_info("\n[STEP 2] Instantiating GenDiaryLog headlessly...")
	var diary_script = load(GENERATED_SCRIPT_PATH)
	assert(diary_script != null, "Failed to load generated script resource: %s" % GENERATED_SCRIPT_PATH)

	var diary_view: Control = diary_script.new() as Control
	assert(diary_view != null, "Failed to instantiate GenDiaryLog instance")
	root.add_child(diary_view)

	var week_lbl: Label = diary_view.find_child("current_week_value", true, false) as Label
	var orders_lbl: Label = diary_view.find_child("dispatched_count_value", true, false) as Label
	assert(week_lbl != null, "current_week_value label missing in GenDiaryLog hierarchy!")
	assert(orders_lbl != null, "dispatched_count_value label missing in GenDiaryLog hierarchy!")
	SystemLogger.log_info("  ✓ GenDiaryLog instantiated and metric nodes resolved.")

	# 3. Test Full Snapshot Binding
	SystemLogger.log_info("\n[STEP 3] Testing bind_data() metric formatting...")
	diary_view.bind_data({
		"current_week_tick": 4,
		"total_dispatched_orders": 18
	})

	assert(week_lbl.text.contains("4"), "Expected current week formatted with 4, got: %s" % week_lbl.text)
	assert(orders_lbl.text.contains("18"), "Expected dispatched orders formatted with 18, got: %s" % orders_lbl.text)
	SystemLogger.log_info("  ✓ Metric snapshot bound cleanly: Week %s | Orders %s" % [week_lbl.text, orders_lbl.text])

	# 4. Test Snapshot Reset Behavior (Pipeline Rule #9)
	SystemLogger.log_info("\n[STEP 4] Testing snapshot reset behavior on empty payload...")
	diary_view.bind_data({})
	var masked_text: String = tr("UI_INTEL_MASKED_BLANK")
	assert(week_lbl.text == masked_text, "Current week failed to reset on empty snapshot! Got: %s" % week_lbl.text)
	assert(orders_lbl.text == masked_text, "Dispatched orders failed to reset on empty snapshot! Got: %s" % orders_lbl.text)
	SystemLogger.log_info("  ✓ Omitted fields reset to placeholder (%s) cleanly." % masked_text)

	# 5. Test Inscription Capability (First-Class Section)
	SystemLogger.log_info("\n[STEP 5] Testing inscribe_entry() for operational logs...")
	assert(diary_view.has_method("inscribe_entry"), "GenDiaryLog must implement inscribe_entry()")

	var insc_container: VBoxContainer = null
	if "_value_labels" in diary_view and diary_view._value_labels.has("__inscriptions__"):
		insc_container = diary_view._value_labels["__inscriptions__"] as VBoxContainer
	assert(insc_container != null, "Missing '__inscriptions__' container in GenDiaryLog!")
	assert(insc_container.get_child_count() == 0, "Inscriptions container should initially be empty")

	diary_view.inscribe_entry({
		"tick": 28,
		"author": "Runner Dispatch",
		"text": "OPERATIONAL DISPATCH: 5x CIGARETTES_UNFILTERED to The Rusty Anchor"
	})

	assert(insc_container.get_child_count() == 1, "Failed to mount inscribed memo label in container!")
	var entry_node: Control = insc_container.get_child(0) as Control
	assert(entry_node != null, "Inscribed entry node is null!")
	SystemLogger.log_info("  ✓ Successfully inscribed memo into diary container.")

	# Teardown
	root.remove_child(diary_view)
	_deep_free_node(diary_view)

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL DIARY LOG PIPELINE TESTS PASSED")
	SystemLogger.log_info("=======================================================\n")
	quit(0)

func _deep_free_node(node: Node) -> void:
	for child in node.get_children():
		_deep_free_node(child)
	node.free()