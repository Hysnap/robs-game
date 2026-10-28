# res://tools/test_modular_stack_contract.gd
extends SceneTree

const StaggeredStackScript = preload("res://scenes/ui/components/staggered_card_stack.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")
const StationeryRegistryScript = preload("res://scenes/ui/feedback/stationery_registry.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   TESTING PURE EVENT TRIGGERS & UNIVERSAL STACK MODULE")
	print("=======================================================")

	# 1. Initialize Stationery & Stack Rules Manifest
	StationeryRegistryScript.initialize()
	var stack_rules: Dictionary = StationeryRegistryScript.get_stack_rules()
	print("[STEP 1] Loaded stationery registry and stack rules.")

	# 2. Simulate Turn Progression (SimController returns a report Dictionary)
	var world_state := {
		"metadata": {"current_day_tick": 1, "current_week_tick": 1, "time_horizon": "day"}
	}
	var test_directives := [
		{"verb": "SELL", "target_item": "BEER", "amount": 10.0}
	]

	var turn_report: Dictionary = SimControllerScript.process_turn_cycle(world_state, test_directives)
	var triggers: Array = turn_report.get("executed_events", [])
	assert(not triggers.is_empty(), "SimController failed to emit executed events in report")
	assert(not triggers[0].has("display_text"), "LEAK: SimController is generating presentation text!")
	assert(not triggers[0].has("palette_bg"), "LEAK: SimController is generating UI styling!")
	print("  ✓ SimController returned pure telemetry triggers in report (zero presentation leaks).")

	# 3. Translate Triggers to Card Payloads via StationeryRegistry (1 argument)
	var cards: Array = FeedbackTranslatorScript.triggers_to_slip_cards(triggers)
	assert(cards.size() == 1, "Translator failed to map triggers to cards")
	assert(cards[0].has("stationery_profile"), "Missing stationery_profile in card payload")
	assert(cards[0]["destination"] == "FINANCE", "Failed to resolve filing domain from registry bindings")
	print("  ✓ Triggers translated into configured card payloads via StationeryRegistry.")

	# 4. Mount Universal StaggeredCardStack Module
	var stack = StaggeredStackScript.new()
	stack.configure_from_schema({"stack_rules": stack_rules})
	root.add_child(stack)

	# 5. Use Dictionary container to ensure lambda captures by reference
	var tracker := {
		"action": "",
		"payload": {},
		"count_received": -1
	}

	stack.top_card_action.connect(func(act, payload):
		tracker["action"] = str(act)
		tracker["payload"] = payload
	)

	stack.stack_count_changed.connect(func(c: int):
		tracker["count_received"] = c
	)

	# 6. Test Ingestion & Count Signal
	stack.push_cards(cards)
	assert(stack.get_card_count() == 1, "Stack failed to ingest cards")
	assert(stack.visible == true, "Stack should be visible when holding cards")
	assert(tracker["count_received"] == 1, "FAILED: stack_count_changed did not fire on push_cards!")
	print("  ✓ Cards pushed: count signal and visibility verified.")

	# 7. Test Triage & Pop Signal
	stack.pop_top_card("FILE")
	assert(tracker["action"] == "FILE", "Top card action failed to fire")
	assert(tracker["payload"]["destination"] == "FINANCE", "Triaged card payload corrupted")
	assert(stack.is_empty(), "Stack should be empty after triage")
	assert(tracker["count_received"] == 0, "FAILED: stack_count_changed did not fire on pop_top_card!")
	print("  ✓ Universal StaggeredCardStack triaged top card cleanly.")

	# Clean teardown
	root.remove_child(stack)
	stack.free()

	print("\n=======================================================")
	print("   ALL EVENT TRIGGER & STACK CONTRACTS VERIFIED")
	print("=======================================================\n")
	quit(0)