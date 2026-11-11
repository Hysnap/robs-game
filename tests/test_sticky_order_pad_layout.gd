# res://tests/test_sticky_order_pad_layout.gd
extends SceneTree

const StickyOrderPadScene: PackedScene = preload("res://scenes/ui/components/sticky_order_pad.tscn")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const DirectiveComposerControllerScript = preload("res://systems/directive_composer_controller.gd")

var _frame_count: int = 0
var _pad: StickyOrderPad

func _init() -> void:
	print("\n--- [Test] Verifying StickyOrderPad Generic Slot Layout & Dynamic Adaptation ---")
	VerbRouterScript.initialize()

	var gs = ScenarioManifestManager.get_game_state()
	if gs != null and gs.has_method("initialize_fresh_state"):
		gs.initialize_fresh_state()

	_pad = StickyOrderPadScene.instantiate() as StickyOrderPad
	root.add_child(_pad)

func _process(_delta: float) -> bool:
	_frame_count += 1
	# Wait 2 frames for enter_tree and ready notifications to dispatch cleanly
	if _frame_count < 2:
		return false

	var passed: bool = true
	passed = passed and test_slot_hierarchy_and_skins(_pad)
	passed = passed and test_layout_adaptation_buy(_pad)
	passed = passed and test_layout_adaptation_scout(_pad)

	_pad.queue_free()

	if passed:
		print("--- [Test] STICKY ORDER PAD GENERIC SLOTS FULLY VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] STICKY ORDER PAD VERIFICATION FAILED ---\n")
		quit(1)

	return true

func test_slot_hierarchy_and_skins(pad: StickyOrderPad) -> bool:
	if pad.slot_action == null or pad.slot_target == null or pad.slot_scalar == null or pad.slot_actor == null or pad.slot_location == null or pad.slot_telemetry == null:
		printerr("FAIL: Generic slot binding failure:")
		printerr("  slot_action:    ", pad.slot_action)
		printerr("  slot_target:    ", pad.slot_target)
		printerr("  slot_scalar:    ", pad.slot_scalar)
		printerr("  slot_actor:     ", pad.slot_actor)
		printerr("  slot_location:  ", pad.slot_location)
		printerr("  slot_telemetry: ", pad.slot_telemetry)
		return false

	print("PASS: Generic slot hierarchy (Slot_Action, Slot_Target, Slot_Scalar, etc.) bound and intact.")
	return true

func test_layout_adaptation_buy(pad: StickyOrderPad) -> bool:
	pad._apply_form_layout_for_verb("BUY")

	var slot_target: CanvasItem = pad.slot_target
	var slot_telemetry: CanvasItem = pad.slot_telemetry
	var spin_amount: SpinBox = pad.spin_amount

	if not slot_target.visible:
		printerr("FAIL: Expected Slot_Target to be visible for BUY.")
		return false

	if not slot_telemetry.visible:
		printerr("FAIL: Expected Slot_Telemetry to be visible for BUY.")
		return false

	if spin_amount.max_value < 100.0:
		printerr("FAIL: Expected AmountSpin to permit large quantities for BUY, got max: ", spin_amount.max_value)
		return false

	print("PASS: BUY correctly configured commodity target, telemetry, and quantity bounds.")
	return true

func test_layout_adaptation_scout(pad: StickyOrderPad) -> bool:
	pad._apply_form_layout_for_verb("SCOUT")

	var slot_target: CanvasItem = pad.slot_target
	var slot_telemetry: CanvasItem = pad.slot_telemetry
	var spin_amount: SpinBox = pad.spin_amount

	if slot_target.visible:
		printerr("FAIL: Expected Slot_Target to be hidden for SCOUT.")
		return false

	if slot_telemetry.visible:
		printerr("FAIL: Expected Slot_Telemetry to be hidden for SCOUT.")
		return false

	if spin_amount.max_value != 8.0 or spin_amount.value != 2.0:
		printerr("FAIL: Expected AmountSpin to be clamped to 8.0 max and 2.0 default hours for SCOUT, got max: ", spin_amount.max_value, ", val: ", spin_amount.value)
		return false

	print("PASS: SCOUT correctly hid commodity target/telemetry and reconfigured scalar spinbox to patrol hours.")
	return true