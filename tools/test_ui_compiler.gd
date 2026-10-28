# res://tools/test_ui_compiler.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")
const RetroThemeScript = preload("res://scenes/ui/shell_host/retro_theme.gd")

const SCHEMAS_VIEW_DIR := "res://data_modules/core/ui_schemas/views/"
const GENERATED_DIR := "res://generated/ui/"

func _init() -> void:
	print("\n=======================================================")
	print("   DYNAMIC UI COMPILER & CONTRACT TEST SUITE")
	print("=======================================================")

	# 1. Discover all screen schemas under views/
	var dir := DirAccess.open(SCHEMAS_VIEW_DIR)
	assert(dir != null, "Missing views schema directory: %s" % SCHEMAS_VIEW_DIR)

	var schema_files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			schema_files.append(SCHEMAS_VIEW_DIR.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	print("[DISCOVERY] Found %d screen schema definition(s) in %s" % [schema_files.size(), SCHEMAS_VIEW_DIR])
	assert(schema_files.size() >= 5, "Expected at least 5 view schemas (docket, nav, cashbook, diary, planner)")

	# 2. Audit contracts
	print("\n[TEST 1] Auditing schema syntaxes and contracts...")
	for s_path in schema_files:
		_audit_schema_file(s_path)
	print("  ✓ All view schemas passed structural contract validation.")

	# 3. Compile
	print("\n[TEST 2] Executing Headless Compilation Pass...")
	UICompilerScript.compile_all()

	# 4. Test dynamic instantiation & binding
	print("\n[TEST 3] Testing Dynamic Instantiation & bind_data() Across All Components...")
	for s_path in schema_files:
		_test_compiled_component(s_path)
	print("  ✓ All compiled UI classes instantiated, bound, and verified cleanly.")

	# 5. Test OuterShell & Slot Mounting
	print("\n[TEST 4] Testing OuterShell Scene & View Mounting...")
	test_outer_shell_mounting()
	print("  ✓ OuterShell instantiated, mounted with wrapper, and verified across all slots.")

	print("\n=======================================================")
	print("   ALL DYNAMIC UI TESTS PASSED CLEANLY")
	print("=======================================================\n")
	quit(0)

func _audit_schema_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Could not open: %s" % path)
	var schema = JSON.parse_string(f.get_as_text())
	f.close()

	assert(schema is Dictionary, "Schema root must be a JSON object: %s" % path)
	assert(schema.has("_meta"), "Missing '_meta' block in: %s" % path)
	assert(schema.has("sections"), "Missing 'sections' array in: %s" % path)
	assert(schema["sections"] is Array, "'sections' must be an Array in: %s" % path)

func _test_compiled_component(schema_path: String) -> void:
	var gen_name := "gen_" + schema_path.get_file().replace(".json", ".gd")
	var gen_path := GENERATED_DIR.path_join(gen_name)
	assert(FileAccess.file_exists(gen_path), "Generated file missing: %s" % gen_path)

	var script_res = load(gen_path)
	assert(script_res != null, "Script failed to parse/compile: %s" % gen_path)

	var instance = script_res.new()
	assert(instance is Control, "Generated class must extend Control")

	# Test mock binding
	var mock_data := {
		"population": 1250,
		"unemployment_rate": 0.125,
		"disposable_income": 45.50,
		"actual_police_heat": 0.35,
		"liquid_cash": 250.00
	}
	if instance.has_method("bind_data"):
		instance.bind_data(mock_data)

	instance.free()

func test_outer_shell_mounting() -> void:
	var shell_scene: PackedScene = load("res://scenes/ui/shell_host/outer_shell.tscn")
	assert(shell_scene != null, "outer_shell.tscn failed to load from shell_host!")

	var shell = shell_scene.instantiate()
	root.add_child(shell)

	# Mount default Filofax wrapper so generic slots are available
	var filo_spread_scene: PackedScene = load("res://scenes/ui/shells/filofax/filofax_spread.tscn")
	assert(filo_spread_scene != null, "filofax_spread.tscn failed to load!")
	shell.set_spread_wrapper(filo_spread_scene.instantiate())

	var dummy_nav = Control.new()
	var dummy_content = Control.new()
	var dummy_action = Control.new()

	shell.mount_view("NAV", dummy_nav)
	shell.mount_view("CONTENT", dummy_content)
	shell.mount_view("ACTION", dummy_action)

	assert(shell.get_slot("NAV") != null and shell.get_slot("NAV").get_child_count() == 1, "NAV slot failed mount")
	assert(shell.get_slot("CONTENT") != null and shell.get_slot("CONTENT").get_child_count() == 1, "CONTENT slot failed mount")
	assert(shell.get_slot("ACTION") != null and shell.get_slot("ACTION").get_child_count() == 1, "ACTION slot failed mount")

	root.remove_child(shell)
	shell.free()