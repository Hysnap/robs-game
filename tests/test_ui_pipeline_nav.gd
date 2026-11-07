# res://tests/test_ui_pipeline_nav.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")

const SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/navigation_bar.json"
const GENERATED_SCRIPT_PATH := "res://generated/ui/gen_navigation_bar.gd"

var _captured_actions: Array[Dictionary] = []

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   TEST: UI PIPELINE - NAVIGATION BAR COMPILATION & ACTIONS")
	SystemLogger.log_info("=======================================================")

	# 1. Compile single target schema
	SystemLogger.log_info("\n[STEP 1] Compiling navigation_bar.json schema...")
	assert(FileAccess.file_exists(SCHEMA_PATH), "Schema missing at: %s" % SCHEMA_PATH)
	UICompilerScript.compile_schema(SCHEMA_PATH)
	assert(FileAccess.file_exists(GENERATED_SCRIPT_PATH), "Generated file missing: %s" % GENERATED_SCRIPT_PATH)
	SystemLogger.log_info("  ✓ Successfully compiled to: %s" % GENERATED_SCRIPT_PATH)

	# 2. Instantiate View
	SystemLogger.log_info("\n[STEP 2] Instantiating GenNavBar headlessly...")
	var nav_script = load(GENERATED_SCRIPT_PATH)
	assert(nav_script != null, "Failed to load generated script resource: %s" % GENERATED_SCRIPT_PATH)

	var nav_view: Control = nav_script.new() as Control
	assert(nav_view != null, "Failed to instantiate GenNavBar instance")
	root.add_child(nav_view)

	assert(nav_view.has_signal("action_clicked"), "GenNavBar must declare 'action_clicked' signal!")
	nav_view.connect("action_clicked", _on_action_clicked)
	SystemLogger.log_info("  ✓ GenNavBar mounted and signal connected.")

	# 3. Test Button Actions
	SystemLogger.log_info("\n[STEP 3] Testing tab button clicks and action emission...")
	var expected_routes: Dictionary = {
		"diary": "DIARY",
		"dossier": "DOSSIER",
		"roster": "ROSTER",
		"finance": "FINANCE"
	}

	for btn_id in expected_routes.keys():
		_captured_actions.clear()
		var btn_node: Button = nav_view.find_child(btn_id, true, false) as Button
		assert(btn_node != null, "Expected tab button '%s' not found in GenNavBar hierarchy!" % btn_id)

		btn_node.emit_signal("pressed")

		assert(_captured_actions.size() == 1, "Clicking '%s' should emit exactly one action_clicked signal!" % btn_id)
		var event: Dictionary = _captured_actions[0]
		assert(event.get("code") == "NAV_ROUTE", "Expected action code 'NAV_ROUTE', got '%s'" % event.get("code"))
		var payload: Dictionary = event.get("payload", {})
		var expected_domain: String = expected_routes[btn_id]
		assert(payload.get("domain") == expected_domain, "Expected domain '%s', got '%s'" % [expected_domain, payload.get("domain")])
		SystemLogger.log_info("  ✓ Tab '%s' emitted NAV_ROUTE -> %s" % [btn_id, expected_domain])

	# 4. Verify Passive Data Contract
	SystemLogger.log_info("\n[STEP 4] Testing passive bind_data() contract...")
	assert(nav_view.has_method("bind_data"), "GenNavBar must implement bind_data()")
	nav_view.bind_data({})
	nav_view.bind_data({"active_domain": "DOSSIER"})
	SystemLogger.log_info("  ✓ bind_data executed safely without exceptions.")

	# Teardown
	root.remove_child(nav_view)
	for child in nav_view.get_children():
		child.free()
	nav_view.free()

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL NAVIGATION BAR PIPELINE TESTS PASSED")
	SystemLogger.log_info("=======================================================\n")
	quit(0)

func _on_action_clicked(action_code: String, payload: Dictionary) -> void:
	_captured_actions.append({
		"code": action_code,
		"payload": payload
	})