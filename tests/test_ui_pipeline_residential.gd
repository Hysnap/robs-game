# res://tests/test_ui_pipeline_residential.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")

const SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/residential_docket.json"
const GENERATED_SCRIPT_PATH := "res://generated/ui/gen_residential_docket.gd"

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   TEST: UI PIPELINE - RESIDENTIAL DOCKET COMPILATION & BINDING")
	SystemLogger.log_info("=======================================================")

	# 1. Compile target schema
	SystemLogger.log_info("\n[STEP 1] Compiling residential_docket.json schema...")
	assert(FileAccess.file_exists(SCHEMA_PATH), "Schema missing at: %s" % SCHEMA_PATH)
	UICompilerScript.compile_schema(SCHEMA_PATH)
	assert(FileAccess.file_exists(GENERATED_SCRIPT_PATH), "Generated file missing: %s" % GENERATED_SCRIPT_PATH)
	SystemLogger.log_info("  ✓ Successfully compiled to: %s" % GENERATED_SCRIPT_PATH)

	# 2. Instantiate View
	SystemLogger.log_info("\n[STEP 2] Instantiating GenResidentialDocket headlessly...")
	var script_res = load(GENERATED_SCRIPT_PATH)
	assert(script_res != null, "Failed to load generated script resource: %s" % GENERATED_SCRIPT_PATH)

	var view: Control = script_res.new() as Control
	assert(view != null, "Failed to instantiate GenResidentialDocket instance")
	root.add_child(view)

	var back_btn: Button = view.find_child("btn_back", true, false) as Button
	var header_title: Label = view.find_child("tenancy_header_title", true, false) as Label
	var header_sub: Label = view.find_child("tenancy_header_subtitle", true, false) as Label
	var door_lbl: Label = view.find_child("door_num_value", true, false) as Label
	var ward_lbl: Label = view.find_child("ward_value", true, false) as Label
	var pub_lbl: Label = view.find_child("local_pub_value", true, false) as Label
	var occupants_list: ItemList = view.find_child("occupants_list", true, false) as ItemList

	assert(back_btn != null, "btn_back missing in GenResidentialDocket hierarchy!")
	assert(header_title != null, "tenancy_header_title label missing in hierarchy!")
	assert(header_sub != null, "tenancy_header_subtitle label missing in hierarchy!")
	assert(door_lbl != null, "door_num_value label missing in hierarchy!")
	assert(ward_lbl != null, "ward_value label missing in hierarchy!")
	assert(pub_lbl != null, "local_pub_value label missing in hierarchy!")
	assert(occupants_list != null, "occupants_list missing in hierarchy!")
	SystemLogger.log_info("  ✓ GenResidentialDocket instantiated and all control nodes resolved.")

	# 3. Test Signal Routing on Back Button
	SystemLogger.log_info("\n[STEP 3] Testing route_requested signal dispatch on back button...")
	var signal_received := false
	var received_domain := ""
	var received_page := ""
	view.route_requested.connect(func(domain: String, page: String):
		signal_received = true
		received_domain = domain
		received_page = page
	)
	back_btn.pressed.emit()
	assert(signal_received, "Failed to receive route_requested signal when back button pressed!")
	assert(received_domain == "DOSSIER", "Expected domain 'DOSSIER', got: %s" % received_domain)
	assert(received_page == "", "Expected empty target page, got: %s" % received_page)
	SystemLogger.log_info("  ✓ Back button route signal emitted cleanly ('DOSSIER').")

	# 4. Test Snapshot Data Binding
	SystemLogger.log_info("\n[STEP 4] Testing bind_data() snapshot binding...")
	view.bind_data({
		"name": "14 Crown Terrace",
		"residence_type": "Terraced Tenement",
		"unit_door_number": "14B",
		"district_name": "Aston Central",
		"local_pub_name": "The Black Dog",
		"residents_summary": [
			"Arthur Shelby (Head, 38) - Metal Finisher",
			"Ada Thorne (Sister, 32) - Clerk"
		]
	})

	assert(header_title.text == "14 CROWN TERRACE", "Title mismatch! Got: %s" % header_title.text)
	assert(header_sub.text == "TERRACED TENEMENT", "Subtitle mismatch! Got: %s" % header_sub.text)
	assert(door_lbl.text == "14B", "Door number mismatch! Got: %s" % door_lbl.text)
	assert(ward_lbl.text == "Aston Central", "Ward mismatch! Got: %s" % ward_lbl.text)
	assert(pub_lbl.text == "The Black Dog", "Local pub mismatch! Got: %s" % pub_lbl.text)
	assert(occupants_list.item_count == 2, "Expected 2 list items, got: %d" % occupants_list.item_count)
	SystemLogger.log_info("  ✓ Household census snapshot bound cleanly.")

	# 5. Test Snapshot Reset Behavior (Pipeline Rule #9)
	SystemLogger.log_info("\n[STEP 5] Testing snapshot reset behavior on empty payload...")
	view.bind_data({})
	var masked_text: String = tr("UI_INTEL_MASKED_BLANK")
	assert(header_title.text == "--- UNNAMED ---", "Header title failed to reset! Got: %s" % header_title.text)
	assert(header_sub.text == "", "Header subtitle failed to reset! Got: %s" % header_sub.text)
	assert(door_lbl.text == masked_text, "Door number failed to reset! Got: %s" % door_lbl.text)
	assert(ward_lbl.text == masked_text, "Ward failed to reset! Got: %s" % ward_lbl.text)
	assert(pub_lbl.text == masked_text, "Local pub failed to reset! Got: %s" % pub_lbl.text)
	assert(occupants_list.item_count == 0, "Occupants list failed to clear on empty snapshot!")
	SystemLogger.log_info("  ✓ Empty snapshot reset all fields and list items cleanly.")

	# Teardown
	root.remove_child(view)
	_deep_free_node(view)

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL RESIDENTIAL DOCKET PIPELINE TESTS PASSED")
	SystemLogger.log_info("=======================================================\n")
	quit(0)

func _deep_free_node(node: Node) -> void:
	for child in node.get_children():
		_deep_free_node(child)
	node.free()