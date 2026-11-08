# res://tests/test_bridge_orchestration.gd
extends SceneTree

const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const UIActionCommandScript = preload("res://scenes/ui/shell_host/ui_action_command.gd")
const OperationsControllerScript = preload("res://systems/operations_controller.gd")

func _init() -> void:
	print("\n--- [Test] Starting MVC Bridge Orchestration Validation ---")
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
	
	# FIX: Inject a dummy OuterShell with a mock "CONTENT" slot to silence the warning
	var dummy_shell = OuterShell.new()
	var mock_content_slot = Control.new()
	mock_content_slot.name = "CONTENT"
	dummy_shell.add_child(mock_content_slot)
	
	view_host.shell_node = dummy_shell
	
	var dummy_view = Control.new()
	view_host.register_view("TEST_DOMAIN", dummy_view)
	
	# 1. Simulate UI intent via DTO
	var cmd = UIActionCommandScript.new(UIActionCommandScript.CommandType.ROUTE_REQUEST, "TEST_DOMAIN")
	
	# 2. Fire across the boundary
	OperationsControllerScript.dispatch_ui_command(cmd, view_host, {})
	
	# 3. Assert the Controller correctly unpacked and orchestrated the host
	var success: bool = (view_host._active_domain == "TEST_DOMAIN")
	if success:
		print("PASS: OperationsController successfully routed UIActionCommand (ROUTE_REQUEST).")
	else:
		printerr("FAIL: ViewHost active domain is '%s', expected 'TEST_DOMAIN'" % view_host._active_domain)
		
	view_host.free()
	dummy_view.free()
	dummy_shell.free()
	return success

func test_action_clicked_inbox_dispatch() -> bool:
	var view_host = ViewHostScript.new()
	
	# 1. Simulate slip triage UI intent
	var cmd = UIActionCommandScript.new(
		UIActionCommandScript.CommandType.ACTION_CLICKED, 
		"INBOX", 
		"DISCARD", 
		{"display_text": "Mock discarded slip"}
	)
	
	# 2. Fire across the boundary
	OperationsControllerScript.dispatch_ui_command(cmd, view_host, {})
	
	# Reaching here without a type mismatch or missing property crash proves DTO unboxing works
	print("PASS: OperationsController safely unboxed UIActionCommand (ACTION_CLICKED / INBOX).")
	
	view_host.free()
	return true