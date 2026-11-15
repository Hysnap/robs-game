# res://tests/test_bridge_orchestration.gd
extends SceneTree

const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const UIActionCommandScript = preload("res://scenes/ui/shell_host/ui_action_command.gd")
const OperationsControllerScript = preload("res://systems/operations_controller.gd")

func _init() -> void:
	print("\n--- [Test] Starting MVC Bridge Orchestration Validation ---")
	OperationsControllerScript.initialize_commands()
	var passed: bool = true
	
	passed = passed and test_route_request_dispatch()
	passed = passed and test_action_clicked_inbox_dispatch()
	
	if passed:
		print("--- [Test] ALL BRIDGE TESTS PASSED ---\n")
		quit(0)
	else:
		printerr("--- [Test] BRIDGE TESTS FAILED ---\n")
		quit(1)

func test_route_request_dispatch() -> bool:
	var view_host = ViewHostScript.new()
	
	var dummy_shell = OuterShell.new()
	var mock_content_slot = Control.new()
	mock_content_slot.name = "CONTENT"
	dummy_shell.add_child(mock_content_slot)
	
	view_host.shell_node = dummy_shell
	
	var dummy_view = Control.new()
	view_host.register_view("DIARY", dummy_view)
	
	# 1. Simulate UI intent via flat UIActionCommand DTO
	var cmd = UIActionCommandScript.new("open_diary", {})
	
	# 2. Fire across the boundary into dynamic cmd_open_diary.gd
	OperationsControllerScript.dispatch_ui_command(cmd, view_host, {})
	
	# 3. Assert the dynamic command brick orchestrated ViewHost
	var success: bool = (view_host.get_active_domain() == "DIARY")
	if success:
		print("PASS: OperationsController dynamically routed UIActionCommand ('open_diary').")
	else:
		printerr("FAIL: ViewHost active domain is '%s', expected 'DIARY'" % view_host.get_active_domain())
		
	view_host.free()
	dummy_view.free()
	dummy_shell.free()
	return success

func test_action_clicked_inbox_dispatch() -> bool:
	var view_host = ViewHostScript.new()
	
	# 1. Simulate slip discard UI intent
	var discard_cmd = UIActionCommandScript.new(
		"discard_slip",
		{"display_text": "Mock discarded slip"}
	)
	OperationsControllerScript.dispatch_ui_command(discard_cmd, view_host, {})

	# 2. Simulate slip file UI intent
	var file_cmd = UIActionCommandScript.new(
		"file_slip",
		{"destination": "DIARY", "tick": 1, "display_text": "Mock filed slip"}
	)
	OperationsControllerScript.dispatch_ui_command(file_cmd, view_host, {})
	
	print("PASS: OperationsController dynamically executed 'discard_slip' and 'file_slip' command bricks.")
	
	view_host.free()
	return true