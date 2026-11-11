# res://tests/test_all_verb_form_layouts.gd
extends SceneTree

const StickyOrderPadScene: PackedScene = preload("res://scenes/ui/components/sticky_order_pad.tscn")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const DirectiveComposerControllerScript = preload("res://systems/directive_composer_controller.gd")

var _frame_count: int = 0
var _pad: StickyOrderPad

func _init() -> void:
	print("\n--- [Test] Verifying All Verb UI Form Layouts & Composer Adaptation ---")
	VerbRouterScript.initialize()

	var gs = ScenarioManifestManager.get_game_state()
	if gs != null and gs.has_method("initialize_fresh_state"):
		gs.initialize_fresh_state()

	_pad = StickyOrderPadScene.instantiate() as StickyOrderPad
	root.add_child(_pad)

func _process(_delta: float) -> bool:
	_frame_count += 1
	if _frame_count < 2:
		return false

	var verbs: Array[String] = DirectiveComposerControllerScript.get_registered_verbs()
	if verbs.is_empty():
		printerr("FAIL: No verbs registered in DirectiveComposerController.")
		quit(1)
		return true

	var total_tested: int = 0
	var total_passed: int = 0
	var missing_configs: Array[String] = []

	for verb_token in verbs:
		var slug := verb_token.to_lower()
		var scope_path := "res://data_modules/core/verbs/".path_join(slug).path_join("target_scope.json")

		if not FileAccess.file_exists(scope_path):
			missing_configs.append(verb_token)
			continue

		total_tested += 1
		if _test_single_verb_layout(verb_token, _pad):
			total_passed += 1
			print("  [PASS] Verb '%s' form layout and view adaptation verified." % verb_token)
		else:
			printerr("  [FAIL] Verb '%s' form layout validation failed." % verb_token)

	_pad.queue_free()

	print("\n--- Summary: %d/%d configured verbs passed ---" % [total_passed, total_tested])
	if not missing_configs.is_empty():
		print("Pending target_scope.json configuration (%d verbs): %s" % [missing_configs.size(), str(missing_configs)])

	if total_passed == total_tested and total_tested > 0:
		print("--- [Test] ALL CONFIGURED VERB FORM LAYOUTS VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] VERB FORM LAYOUT VERIFICATION FAILED ---\n")
		quit(1)

	return true

func _test_single_verb_layout(verb_token: String, pad: StickyOrderPad) -> bool:
	var layout: Dictionary = DirectiveComposerControllerScript.get_form_layout(verb_token)
	if layout.is_empty():
		printerr("Empty layout returned for: ", verb_token)
		return false

	# 1. Structural schema assertions
	if not (layout.has("target_section") and layout.has("amount_section") and layout.has("location_section") and layout.has("contact_section")):
		printerr("Missing required section in layout for: ", verb_token)
		return false

	var target_cfg: Dictionary = layout["target_section"]
	var amount_cfg: Dictionary = layout["amount_section"]
	var loc_cfg: Dictionary = layout["location_section"]
	var contact_cfg: Dictionary = layout["contact_section"]

	var expect_target_vis: bool = bool(target_cfg.get("visible", true))
	var expect_amount_vis: bool = bool(amount_cfg.get("visible", true))
	var expect_loc_vis: bool = bool(loc_cfg.get("visible", true))
	var expect_contact_vis: bool = bool(contact_cfg.get("visible", false))

	# 2. View adaptation execution
	pad._apply_form_layout_for_verb(verb_token)

	# 3. View state assertions
	if pad.slot_target.visible != expect_target_vis:
		printerr("Mismatch on slot_target.visible for '%s'. Expected %s, got %s" % [verb_token, expect_target_vis, pad.slot_target.visible])
		return false

	if pad.slot_scalar.visible != expect_amount_vis:
		printerr("Mismatch on slot_scalar.visible for '%s'. Expected %s, got %s" % [verb_token, expect_amount_vis, pad.slot_scalar.visible])
		return false

	if pad.slot_location.visible != expect_loc_vis:
		printerr("Mismatch on slot_location.visible for '%s'. Expected %s, got %s" % [verb_token, expect_loc_vis, pad.slot_location.visible])
		return false

	if pad.opt_contact.visible != expect_contact_vis:
		printerr("Mismatch on opt_contact.visible for '%s'. Expected %s, got %s" % [verb_token, expect_contact_vis, pad.opt_contact.visible])
		return false

	if pad.slot_telemetry.visible != expect_target_vis:
		printerr("Mismatch on slot_telemetry.visible for '%s'. Expected %s, got %s" % [verb_token, expect_target_vis, pad.slot_telemetry.visible])
		return false

	# 4. Scalar bounds check if amount section is visible
	if expect_amount_vis:
		var min_val: float = float(amount_cfg.get("min_value", 1.0))
		var max_val: float = float(amount_cfg.get("max_value", 999.0))
		if pad.spin_amount.min_value != min_val or pad.spin_amount.max_value != max_val:
			printerr("SpinBox bounds mismatch for '%s'." % verb_token)
			return false

	return true