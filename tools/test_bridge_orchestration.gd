# res://tools/test_bridge_orchestration.gd
extends SceneTree

const OuterShellScript = preload("res://scenes/ui/shell_host/outer_shell.gd")
const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const StaggeredCardStackScript = preload("res://scenes/ui/components/staggered_card_stack.gd")

const SimControllerScript = preload("res://systems/sim_controller.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const CommodityManagerScript = preload("res://systems/commodity_manager.gd")
const FilofaxManagerScript = preload("res://systems/filofax_manager.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")

func _init() -> void:
	print("\n=======================================================")
	print("   HEADLESS BRIDGE TEST: TURN COMMIT, INBOX & LEDGERS")
	print("=======================================================")

	# 1. MOUNT ENGINE SUBSYSTEMS & REGISTRIES
	print("\n[STEP 1] Booting simulation switchboards & commodity catalogs...")
	VerbRouterScript.initialize()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")
	var commodities = CommodityManagerScript.load_hierarchical_commodities("res://data_modules/core/commodities/")
	
	var world_state = {
		"metadata": {"current_week_tick": 1, "current_day_tick": 1, "time_horizon": "day"},
		"finances": {"liquid_cash": 100.0},
		"operations": {"police_evidence_weight": 0.05, "fatigue": 0.0},
		"commodity_registry": commodities,
		"pending_orders": {},
		"inventory_registry": {
			"BEER_STRONG_LAGER": {"STOCK": 20.0, "PREPPED": 0.0}
		},
		"counterparties": {
			"MARKET_CONSUMERS_ASTON": {"cash": 100.0, "inventory": {"BEER_STRONG_LAGER": {"STOCK": 0.0}}}
		},
		"districts": {
			"DIST_ASTON_01": {
				"display_name": "Aston Central",
				"actual_police_heat": 0.10,
				"zone_health_index": 80.0
			}
		}
	}
	var filofax_cache = FilofaxManagerScript.init_cache(world_state)
	print("  ✓ Engine initialized. World cash: £%.2f | District heat: %.2f" % [world_state["finances"]["liquid_cash"], world_state["districts"]["DIST_ASTON_01"]["actual_police_heat"]])

	# 2. MOUNT PRESENTATION LAYER (SHELL, VIEWHOST, STAGGERED STACK)
	print("\n[STEP 2] Assembling presentation layer (OuterShell, ViewHost, StaggeredCardStack)...")
	var shell_scene: PackedScene = load("res://scenes/ui/shell_host/outer_shell.tscn")
	assert(shell_scene != null, "outer_shell.tscn failed to load!")
	var shell = shell_scene.instantiate()
	root.add_child(shell)

	var host = ViewHostScript.new()
	host.shell_node = shell
	shell.add_child(host)

	var card_stack = StaggeredCardStackScript.new()
	root.add_child(card_stack)

	# Mount compiled views into ViewHost
	var nav_bar = load("res://generated/ui/gen_navigation_bar.gd").new()
	host.set_navigation_component(nav_bar)

	var docket = load("res://generated/ui/gen_district_docket.gd").new()
	var cashbook = load("res://generated/ui/gen_cashbook_ledger.gd").new()
	var diary = load("res://generated/ui/gen_diary_log.gd").new()
	var planner = load("res://generated/ui/gen_action_planner.gd").new()

	host.register_view("DOSSIER", docket)
	host.register_view("FINANCE", cashbook)
	host.register_view("DIARY", diary)

	# Mount Action Planner into ACTION slot
	shell.mount_view("ACTION", planner)
	host.switch_to_domain("DIARY")
	print("  ✓ Navigation, Docket, Cashbook, Diary, and Action Planner mounted cleanly.")

	# 3. TEST DIRECTIVE STAGING & DISPATCH THROUGH PLANNER
	print("\n[STEP 3] Simulating player staging an order in Action Planner...")
	var test_directive = {
		"verb": "SELL",
		"initiator_id": "PLAYER",
		"counterparty_id": "MARKET_CONSUMERS_ASTON",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"target_node_id": "DIST_ASTON_01",
		"config": {"unit_price": 3.50, "exposure_modifier": 1.0}
	}
	
	# The controller populates the planner's ItemList widget
	var staged_queue: Array = [test_directive]
	var queue_widget: ItemList = planner._value_labels["queue_list"]
	assert(queue_widget != null, "Missing queue_list widget in compiled planner!")
	queue_widget.add_item("#1: SELL BEER_STRONG_LAGER (Qty: 10)")

	# Dictionary container ensures closure mutates by reference
	var test_state := {"commit_emitted": false}
	planner.turn_commit_requested.connect(func():
		test_state["commit_emitted"] = true
	)

	# Click the compiled commit button
	var commit_btn: Button = planner._value_labels["btn_commit"]
	commit_btn.pressed.emit()

	assert(test_state["commit_emitted"], "turn_commit_requested signal failed to emit on button press!")
	print("  ✓ turn_commit_requested emitted cleanly from compiled action planner.")

	# 4. EXECUTE TURN & INSCRIBE CARBON-COPY ORDERS INTO DIARY
	print("\n[STEP 4] Bridge processes turn: inscribe orders into Diary & run SimController...")
	for cmd in staged_queue:
		host.inscribe_entry_to_domain("DIARY", {
			"tick": world_state["metadata"]["current_week_tick"],
			"author": "Order Dispatch",
			"text": "DISPATCH: %s %s (Qty: %.0f)" % [cmd.get("verb", ""), cmd.get("target_item", ""), float(cmd.get("amount", 1))]
		})

	assert(diary._inscribed_entries_container.get_child_count() == 1, "Diary failed to inscribe dispatched order!")
	print("  ✓ Dispatched order inscribed on Diary ruled lines.")

	# Execute simulation cycle (returns pure event triggers, no slips)
	var event_triggers: Array = SimControllerScript.process_turn_cycle(world_state, staged_queue)
	assert(event_triggers.size() == 1, "Expected 1 resolution trigger from turn cycle")
	
	# Verify backend state mutation
	assert(world_state["finances"]["liquid_cash"] == 135.0, "Liquid cash failed to credit from sale!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 10.0, "Inventory stock failed to decrement!")
	print("  ✓ SimController execution succeeded: £135.00 vault cash, 10 units stock remaining.")

	# 5. TRANSLATE EVENT TRIGGERS INTO MODULAR CARD STACK
	print("\n[STEP 5] Translating pure telemetry triggers to desk cards via schema...")
	var schema_path := "res://data_modules/core/ui_schemas/catalogs/triage_slip_profiles.json"
	var s_file := FileAccess.open(schema_path, FileAccess.READ)
	var profiles_schema: Dictionary = JSON.parse_string(s_file.get_as_text())
	s_file.close()

	var cards: Array = FeedbackTranslatorScript.triggers_to_slip_cards(event_triggers, profiles_schema)
	card_stack.push_cards(cards)
	assert(card_stack.get_card_count() == 1, "CardStack failed to accept translated cards!")
	print("  ✓ Translated outcome card landed on desktop stack.")

	# 6. TEST PHYSICAL TRIAGE: 📌 FILE RECEIPT TO FINANCE
	print("\n[STEP 6] Testing Triage Action: 📌 File Receipt to FINANCE...")
	var initial_evidence: float = world_state["operations"]["police_evidence_weight"]

	card_stack.top_card_action.connect(func(action_id, payload):
		if str(action_id) == "FILE":
			var dest: String = payload.get("destination", "DIARY")
			host.inscribe_entry_to_domain(dest, {
				"tick": payload.get("tick", 1),
				"author": payload.get("slip_profile", "REPORT"),
				"text": payload.get("display_text", "")
			})
			var risk: float = float(payload.get("evidence_weight", 0.0))
			world_state["operations"]["police_evidence_weight"] += risk
	)

	card_stack.pop_top_card("FILE")

	assert(cashbook._inscribed_entries_container.get_child_count() == 1, "Cashbook failed to inscribe filed receipt!")
	assert(is_equal_approx(world_state["operations"]["police_evidence_weight"], initial_evidence + 0.08), "Evidence weight did not increment on file!")
	print("  ✓ Card filed into Cashbook ledger; police evidence increased to: %.2f" % world_state["operations"]["police_evidence_weight"])

	# 7. TEST VIEW SWITCHING & PERCEPTION SYNC
	print("\n[STEP 7] Testing ViewHost domain switching & perceived cache synchronization...")
	FilofaxManagerScript.refresh_cache_instant(world_state, filofax_cache)

	host.switch_to_domain("FINANCE")
	host.update_active_view_data({
		"reported_cash": filofax_cache["finances"]["reported_cash"],
		"total_filed_expenses": 35.00
	})
	assert(cashbook._value_labels["liquid_cash"].text == "£135.00", "Cashbook failed to format synced cash!")
	print("  ✓ Switched to FINANCE view. Inked liquid cash bound: £135.00.")

	# Clean teardown
	root.remove_child(shell)
	root.remove_child(card_stack)
	shell.free()
	card_stack.free()

	print("\n=======================================================")
	print("   ALL BRIDGE ORCHESTRATION TESTS PASSED CLEANLY")
	print("=======================================================\n")
	quit(0)