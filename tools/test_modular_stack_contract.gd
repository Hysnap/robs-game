# res://tools/test_modular_stack_contract.gd
extends SceneTree

const StaggeredStackScript = preload("res://scenes/ui/components/staggered_card_stack.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   TESTING PURE EVENT TRIGGERS & UNIVERSAL STACK MODULE")
	print("=======================================================")

	# 1. Load the Slip Profile Config
	var schema_path := "res://data_modules/core/ui_schemas/catalogs/triage_slip_profiles.json"
	assert(FileAccess.file_exists(schema_path), "Missing triage_slip_profiles.json")
	var file := FileAccess.open(schema_path, FileAccess.READ)
	var profiles_schema: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	print("[STEP 1] Loaded triage slip profiles schema from JSON.")

	# 2. Simulate Turn Progression (Must return pure event triggers, NO slips)
	var world_state := {
		"metadata": {"current_day_tick": 1, "current_week_tick": 1, "time_horizon": "day"}
	}
	var test_directives := [
		{"verb": "SELL", "target_item": "BEER", "amount": 10.0}
	]

	var triggers: Array = SimControllerScript.process_turn_cycle(world_state, test_directives)
	assert(triggers.size() == 1, "SimController failed to emit event trigger")
	assert(not triggers[0].has("display_text"), "LEAK: SimController is generating presentation text!")
	assert(not triggers[0].has("palette_bg"), "LEAK: SimController is generating UI styling!")
	print("  ✓ SimController returned pure telemetry triggers (zero presentation leaks).")

	# 3. Translate Triggers to Physical Card Payloads via Schema
	var cards: Array = FeedbackTranslatorScript.triggers_to_slip_cards(triggers, profiles_schema)
	assert(cards.size() == 1, "Translator failed to map triggers to cards")
	assert(cards[0]["slip_profile"] == "RECEIPT", "Failed to resolve slip profile from config")
	assert(cards[0]["destination"] == "FINANCE", "Failed to resolve filing domain from config")
	print("  ✓ Triggers translated into configured card payloads via JSON schema.")

	# 4. Mount Universal StaggeredCardStack Module
	var stack = StaggeredStackScript.new()
	stack.configure_from_schema(profiles_schema)
	root.add_child(stack)

	# 5. Use a Dictionary container to avoid GDScript lambda by-value capture isolation
	var capture := {
		"action": "",
		"payload": {}
	}
	stack.top_card_action.connect(func(act, payload):
		capture["action"] = str(act)
		capture["payload"] = payload
	)

	stack.push_cards(cards)
	assert(stack.get_card_count() == 1, "Stack failed to ingest cards")
	assert(stack.visible == true, "Stack should be visible when holding cards")

	# 6. Triage Card
	stack.pop_top_card("FILE")
	assert(capture["action"] == "FILE", "Top card action failed to fire")
	assert(capture["payload"]["destination"] == "FINANCE", "Triaged card payload corrupted")
	assert(stack.is_empty(), "Stack should be empty after triage")
	print("  ✓ Universal StaggeredCardStack triaged top card cleanly.")

	# Clean teardown
	root.remove_child(stack)
	stack.free()

	print("\n=======================================================")
	print("   ALL EVENT TRIGGER & STACK CONTRACTS VERIFIED")
	print("=======================================================\n")
	quit(0)