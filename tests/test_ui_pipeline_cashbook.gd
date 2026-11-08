# res://tests/test_ui_pipeline_cashbook.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")

const SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/cashbook_ledger.json"
const GENERATED_SCRIPT_PATH := "res://generated/ui/gen_cashbook_ledger.gd"

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   TEST: UI PIPELINE - CASHBOOK LEDGER COMPILATION & BINDING")
	SystemLogger.log_info("=======================================================")

	# 1. Compile target schema
	SystemLogger.log_info("\n[STEP 1] Compiling cashbook_ledger.json schema...")
	assert(FileAccess.file_exists(SCHEMA_PATH), "Schema missing at: %s" % SCHEMA_PATH)
	UICompilerScript.compile_schema(SCHEMA_PATH)
	assert(FileAccess.file_exists(GENERATED_SCRIPT_PATH), "Generated file missing: %s" % GENERATED_SCRIPT_PATH)
	SystemLogger.log_info("  ✓ Successfully compiled to: %s" % GENERATED_SCRIPT_PATH)

	# 2. Instantiate View
	SystemLogger.log_info("\n[STEP 2] Instantiating GenCashbookLedger headlessly...")
	var ledger_script = load(GENERATED_SCRIPT_PATH)
	assert(ledger_script != null, "Failed to load generated script resource: %s" % GENERATED_SCRIPT_PATH)

	var ledger_view: Control = ledger_script.new() as Control
	assert(ledger_view != null, "Failed to instantiate GenCashbookLedger instance")
	root.add_child(ledger_view)

	var cash_lbl: Label = ledger_view.find_child("liquid_cash_value", true, false) as Label
	var expense_lbl: Label = ledger_view.find_child("filed_receipts_total_value", true, false) as Label
	assert(cash_lbl != null, "liquid_cash_value label missing in GenCashbookLedger hierarchy!")
	assert(expense_lbl != null, "filed_receipts_total_value label missing in GenCashbookLedger hierarchy!")
	SystemLogger.log_info("  ✓ GenCashbookLedger instantiated and metric nodes resolved.")

	# 3. Test Full Snapshot Binding & Currency Formatting
	SystemLogger.log_info("\n[STEP 3] Testing bind_data() currency formatting...")
	ledger_view.bind_data({
		"reported_cash": 250.75,
		"total_filed_expenses": 85.20
	})

	assert(cash_lbl.text.contains("250.75"), "Expected liquid cash formatted with 250.75, got: %s" % cash_lbl.text)
	assert(expense_lbl.text.contains("85.20"), "Expected filed receipts formatted with 85.20, got: %s" % expense_lbl.text)
	SystemLogger.log_info("  ✓ Currency snapshot bound cleanly: %s | %s" % [cash_lbl.text, expense_lbl.text])

	# 4. Test Snapshot Reset Behavior (Pipeline Rule #9)
	SystemLogger.log_info("\n[STEP 4] Testing snapshot reset behavior on empty payload...")
	ledger_view.bind_data({})
	var masked_text: String = tr("UI_INTEL_MASKED_BLANK")
	assert(cash_lbl.text == masked_text, "Liquid cash failed to reset on empty snapshot! Got: %s" % cash_lbl.text)
	assert(expense_lbl.text == masked_text, "Filed receipts failed to reset on empty snapshot! Got: %s" % expense_lbl.text)
	SystemLogger.log_info("  ✓ Omitted fields reset to placeholder (%s) cleanly." % masked_text)

	# 5. Test Inscription Capability
	SystemLogger.log_info("\n[STEP 5] Testing inscribe_entry() for filed slips...")
	assert(ledger_view.has_method("inscribe_entry"), "GenCashbookLedger must implement inscribe_entry()")

	var insc_container: VBoxContainer = null
	if "_value_labels" in ledger_view and ledger_view._value_labels.has("__inscriptions__"):
		insc_container = ledger_view._value_labels["__inscriptions__"] as VBoxContainer
	assert(insc_container != null, "Missing '__inscriptions__' container in GenCashbookLedger!")
	assert(insc_container.get_child_count() == 0, "Inscriptions container should initially be empty")

	ledger_view.inscribe_entry({
		"tick": 1,
		"author": "Aston Depot",
		"text": "PURCHASE: 10x BEER_STRONG_LAGER (£35.00)"
	})

	assert(insc_container.get_child_count() == 1, "Failed to mount inscribed entry label in container!")
	var entry_node: Control = insc_container.get_child(0) as Control
	assert(entry_node != null, "Inscribed entry node is null!")
	SystemLogger.log_info("  ✓ Successfully inscribed entry into ledger container.")

	# Teardown: Remove from tree and free the entire hierarchy cleanly
	root.remove_child(ledger_view)
	ledger_view.free()

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL CASHBOOK LEDGER PIPELINE TESTS PASSED")
	SystemLogger.log_info("=======================================================\n")
	quit(0)