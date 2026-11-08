# res://tests/test_ui_pipeline_roster.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")

const SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/roster_docket.json"
const GENERATED_SCRIPT_PATH := "res://generated/ui/gen_roster_docket.gd"

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   TEST: UI PIPELINE - ROSTER DOCKET COMPILATION")
	SystemLogger.log_info("=======================================================")

	# 1. Compile target schema
	SystemLogger.log_info("\n[STEP 1] Compiling roster_docket.json schema...")
	assert(FileAccess.file_exists(SCHEMA_PATH), "Schema missing at: %s" % SCHEMA_PATH)
	UICompilerScript.compile_schema(SCHEMA_PATH)
	assert(FileAccess.file_exists(GENERATED_SCRIPT_PATH), "Generated file missing: %s" % GENERATED_SCRIPT_PATH)
	SystemLogger.log_info("  ✓ Successfully compiled to: %s" % GENERATED_SCRIPT_PATH)

	# 2. Instantiate View
	SystemLogger.log_info("\n[STEP 2] Instantiating GenRosterDocket headlessly...")
	var script_res = ResourceLoader.load(GENERATED_SCRIPT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert(script_res != null, "Failed to load generated script resource: %s" % GENERATED_SCRIPT_PATH)

	var view: Control = script_res.new() as Control
	assert(view != null, "Failed to instantiate GenRosterDocket instance")
	root.add_child(view)

	var header_title: Label = view.find_child("crew_header_title", true, false) as Label
	var header_sub: Label = view.find_child("crew_header_subtitle", true, false) as Label
	var cards_box: VBoxContainer = view.find_child("operative_cards", true, false) as VBoxContainer

	assert(header_title != null, "crew_header_title missing in GenRosterDocket hierarchy!")
	assert(header_sub != null, "crew_header_subtitle missing in hierarchy!")
	assert(cards_box != null, "operative_cards container missing in hierarchy!")
	SystemLogger.log_info("  ✓ GenRosterDocket instantiated and all control nodes resolved.")

	# 3. Test Snapshot Data Binding
	SystemLogger.log_info("\n[STEP 3] Testing bind_data() snapshot binding...")
	view.bind_data({
		"enterprise_title": "THE PEAKY BLINDERS",
		"home_district_name": "Small Heath",
		"crew_members": [
			{
				"resident_id": 101,
				"name": "Thomas Shelby",
				"summary_line": "Bookmaker"
			}
		]
	})

	assert(header_title.text == "THE PEAKY BLINDERS", "Title mismatch! Got: %s" % header_title.text)
	assert(header_sub.text == "SMALL HEATH", "Subtitle mismatch! Got: %s" % header_sub.text)
	assert(cards_box.get_child_count() > 0, "Operative cards failed to generate list items!")
	SystemLogger.log_info("  ✓ Roster snapshot bound cleanly.")

	# 4. Test Snapshot Reset Behavior (Pipeline Rule #9)
	SystemLogger.log_info("\n[STEP 4] Testing snapshot reset behavior on empty payload...")
	view.bind_data({})
	assert(header_title.text == "--- UNNAMED ---", "Header title failed to reset! Got: %s" % header_title.text)
	assert(header_sub.text == "", "Header subtitle failed to reset! Got: %s" % header_sub.text)
	
	# Empty payload uses queue_free(), so we must exclude doomed nodes from the count
	var active_card_count := 0
	for child in cards_box.get_children():
		if not child.is_queued_for_deletion():
			active_card_count += 1
			
	assert(active_card_count == 0, "Operative cards failed to clear on empty snapshot!")
	SystemLogger.log_info("  ✓ Empty snapshot reset all fields and lists cleanly.")

	# 5. Test Inscription Capability (First-Class Section)
	SystemLogger.log_info("\n[STEP 5] Testing inscribe_entry() for field notes...")
	var insc_container: VBoxContainer = null
	if "_value_labels" in view and view._value_labels.has("__inscriptions__"):
		insc_container = view._value_labels["__inscriptions__"] as VBoxContainer
	assert(insc_container != null, "Missing '__inscriptions__' container in GenRosterDocket!")
	
	view.inscribe_entry({
		"author": "Field Intel",
		"text": "Operative spotted on active duty."
	})
	
	assert(insc_container.get_child_count() == 1, "Failed to mount inscribed entry!")
	SystemLogger.log_info("  ✓ Successfully inscribed entry into roster container.")

	# Teardown
	root.remove_child(view)
	_deep_free_node(view)

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL ROSTER DOCKET PIPELINE TESTS PASSED")
	SystemLogger.log_info("=======================================================\n")
	quit(0)

func _deep_free_node(node: Node) -> void:
	for child in node.get_children():
		_deep_free_node(child)
	node.free()