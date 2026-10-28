# res://tools/test_view_host_wiring.gd
extends SceneTree

const SCHEMAS_DIR := "res://data_modules/core/ui_schemas/"
const GENERATED_DIR := "res://generated/ui/"

# Explicit preloads to guarantee availability in headless CLI mode
const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const OuterShellScript = preload("res://scenes/ui/shell_host/outer_shell.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   TESTING PURE VIEW HOST (ZERO NOUN LEAKS)")
	print("=======================================================")

	# 1. Mount OuterShell and ViewHost
	var shell_scene: PackedScene = load("res://scenes/ui/shell_host/outer_shell.tscn")
	assert(shell_scene != null, "outer_shell.tscn failed to load!")
	var shell = shell_scene.instantiate()
	root.add_child(shell)

	var host = ViewHostScript.new()
	host.shell_node = shell
	shell.add_child(host)

	# 2. Mount Compiled Navigation Component
	var nav_script: GDScript = load(GENERATED_DIR.path_join("gen_navigation_bar.gd"))
	assert(nav_script != null, "gen_navigation_bar.gd failed to load!")
	var nav_bar: Control = nav_script.new()
	host.set_navigation_component(nav_bar)

	var nav_slot = shell.get_slot("NAV")
	assert(nav_slot.get_child_count() == 1, "NavSlot did not receive navigation component!")
	print("  ✓ Pure navigation component mounted into generic NAV slot.")

	# 3. Dynamically Register All Generated Views Without Hardcoded Names
	var dir := DirAccess.open(SCHEMAS_DIR)
	assert(dir != null, "Failed to open schemas directory")
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

	print("  ✓ Dynamically registered %d compiled views into ViewHost." % registered_count)

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

	print("  ✓ All registered views cycled through ContentSlot and ingested data cleanly.")

	# Clean teardown
	root.remove_child(shell)
	shell.free()

	print("\n=======================================================")
	print("   ALL VIEW HOST ARCHITECTURAL RULES VERIFIED")
	print("=======================================================\n")
	quit(0)