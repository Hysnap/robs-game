# res://tools/test_view_host_wiring.gd
extends SceneTree

const SCHEMAS_VIEW_DIR := "res://data_modules/core/ui_schemas/views/"
const GENERATED_DIR := "res://generated/ui/"

# Explicit preloads to guarantee availability in headless CLI mode
const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const OuterShellScript = preload("res://scenes/ui/shell_host/outer_shell.gd")
const ActionQueuePresenterScript = preload("res://scenes/ui/components/action_queue_presenter.gd")

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   TESTING PURE VIEW HOST (ZERO NOUN LEAKS)")
	SystemLogger.log_info("=======================================================")

	# 1. Mount OuterShell and ViewHost
	var shell_scene: PackedScene = load("res://scenes/ui/shell_host/outer_shell.tscn")
	assert(shell_scene != null, "outer_shell.tscn failed to load!")
	var shell = shell_scene.instantiate()
	root.add_child(shell)

	# Mount default Filofax wrapper so generic slots (NAV, CONTENT, ACTION) are available
	var filo_spread_scene: PackedScene = load("res://scenes/ui/shells/filofax/filofax_spread.tscn")
	assert(filo_spread_scene != null, "filofax_spread.tscn failed to load!")
	shell.set_spread_wrapper(filo_spread_scene.instantiate())

	var host = ViewHostScript.new()
	host.shell_node = shell
	shell.add_child(host)

	# 2. Mount Compiled Navigation Component
	var nav_script: GDScript = load(GENERATED_DIR.path_join("gen_navigation_bar.gd"))
	assert(nav_script != null, "gen_navigation_bar.gd failed to load!")
	var nav_bar: Control = nav_script.new()
	host.set_navigation_component(nav_bar)

	var nav_slot = shell.get_slot("NAV")
	assert(nav_slot != null and nav_slot.get_child_count() == 1, "NavSlot did not receive navigation component!")
	SystemLogger.log_info("  ✓ Pure navigation component mounted into generic NAV slot.")

	# 3. Dynamically Register All Generated Views Without Hardcoded Names
	var dir := DirAccess.open(SCHEMAS_VIEW_DIR)
	assert(dir != null, "Failed to open schemas directory: %s" % SCHEMAS_VIEW_DIR)
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var registered_count := 0

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json") and not file_name.contains("nav"):
			var gen_name := "gen_" + file_name.replace(".json", ".gd")
			var gen_script: GDScript = load(GENERATED_DIR.path_join(gen_name))
			if gen_script:
				var domain_key := file_name.replace(".json", "").to_upper()
				host.register_view(domain_key, gen_script.new())
				registered_count += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	SystemLogger.log_info("  ✓ Dynamically registered %d compiled views into ViewHost." % registered_count)

	# 4. Test Switching Domains and Ingesting Data Payloads (Agnostic Contract)
	for domain_key in host._views.keys():
		host.switch_to_domain(domain_key)
		var content_slot = shell.get_slot("CONTENT")
		var expected_view = host._views[domain_key]
		
		# Assert that the expected view is physically present inside content_slot
		assert(content_slot.get_children().has(expected_view), "Failed to mount view for: " + domain_key)

		# Feed a generic mock payload without knowing the view's specific schema
		host.update_active_view_data({"test_field": 100})

		# If view supports lined notes, verify inscribe_entry_to_domain contract
		host.inscribe_entry_to_domain(domain_key, {
			"tick": 1,
			"author": "Dispatcher",
			"text": "Automated verified note."
		})

	SystemLogger.log_info("  ✓ All registered views cycled through ContentSlot and ingested data cleanly.")

	# 5. Test Agnostic Signal Forwarding
	var signal_capture := {"action": "", "target_route": "", "filter_key": null}
	host.action_requested.connect(func(code: String, _payload: Dictionary): signal_capture["action"] = code)
	host.item_selected.connect(func(route: String, key: Variant):
		signal_capture["target_route"] = route
		signal_capture["filter_key"] = key
	)

	# Create a dummy control to test standard auto-wiring
	var test_dummy := Control.new()
	test_dummy.add_user_signal("action_clicked", [{"name": "action_code", "type": TYPE_STRING}])
	test_dummy.add_user_signal("item_selected", [{"name": "target_route", "type": TYPE_STRING}, {"name": "filter_key", "type": TYPE_INT}])
	host.register_view("DUMMY_TEST", test_dummy)

	test_dummy.emit_signal("action_clicked", "EXECUTE_TEST")
	assert(signal_capture["action"] == "EXECUTE_TEST", "FAIL: ViewHost failed to forward action_clicked to action_requested.")

	test_dummy.emit_signal("item_selected", "OPERATIVE_DETAIL", 42)
	assert(signal_capture["target_route"] == "OPERATIVE_DETAIL" and signal_capture["filter_key"] == 42, "FAIL: ViewHost failed to forward item_selected.")
	SystemLogger.log_info("  ✓ ViewHost purely relays action_clicked and item_selected outward.")

	# 6. Verify Reusable ActionQueuePresenter Component Headlessly
	var qp = ActionQueuePresenterScript.new()
	qp.add_directive({"verb": "BUY", "target_item": "BEER", "amount": 10})
	qp.add_directive({"verb": "SELL", "target_item": "CIGS", "amount": 5})
	assert(qp.size() == 2, "FAIL: ActionQueuePresenter failed to ingest directives.")

	# Reorder (move index 1 up to index 0)
	var new_idx = qp.move_directive(1, -1)
	assert(new_idx == 0, "FAIL: Move directive UP failed.")
	var lines = qp.get_display_lines()
	assert(lines[0].contains("SELL"), "FAIL: Top item should now be SELL.")

	# Toggle selection & consume
	qp.toggle_selection(1) # uncheck BUY
	var executable = qp.consume_selected_directives()
	assert(executable.size() == 1 and executable[0]["verb"] == "SELL", "FAIL: Executable directives extraction mismatch.")
	assert(qp.size() == 1 and qp.get_staged_directives()[0]["verb"] == "BUY", "FAIL: Unselected draft directive was not preserved.")
	SystemLogger.log_info("  ✓ Reusable ActionQueuePresenter passed all standalone queue mechanics.")

	# 7. Clean teardown: purge views and slots before removing root
	test_dummy.free()
	host.cleanup()
	nav_bar.free()
	root.remove_child
	shell.free()

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL VIEW HOST & QUEUE PRESENTER RULES VERIFIED")
	SystemLogger.log_info("=======================================================\n")
	quit(0)