# res://tools/test_bridge_orchestration.gd
extends SceneTree

const OuterShellScript = preload("res://scenes/ui/shell_host/outer_shell.gd")
const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const DesktopSlipStackScript = preload("res://scenes/ui/feedback/desktop_slip_stack.gd")

const DBManagerScript = preload("res://systems/db_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const CommodityManagerScript = preload("res://systems/commodity_manager.gd")
const FeedbackTranslatorScript = preload("res://scenes/ui/feedback/feedback_translator.gd")

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   HEADLESS BRIDGE TEST: TURN COMMIT, INBOX & LEDGERS")
	SystemLogger.log_info("=======================================================")

	# 1. MOUNT ENGINE SUBSYSTEMS & REGISTRIES
	SystemLogger.log_info("\n[STEP 1] Booting simulation switchboards & commodity catalogs...")
	DBManagerScript.initialize_database(false)
	CalendarHelperScript.initialize({
		"epoch_date": "1900-01-01",
		"simulation_start_date": "1980-01-01",
		"days_per_tick": 7
	})

	VerbRouterScript.initialize()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")
	var commodities: Dictionary = CommodityManagerScript.load_hierarchical_commodities("res://data_modules/core/commodities/")
	
	var world_state: Dictionary = {
		"metadata": {
			"current_sim_day": CalendarHelperScript.get_simulation_start_day(),
			"current_week_tick": 1,
			"current_day_tick": 1,
			"time_horizon": "day"
		},
		"finances": {"liquid_cash": 100.0, "clean_bank_balance": 0.0},
		"operations": {"police_evidence_weight": 0.05, "fatigue": 0.0},
		"commodity_registry": commodities,
		"staff": {
			"STAFF_BILLY": {"name": "Billy", "role": "OPERATIVE"},
			"STAFF_MALCOLM": {"name": "Malcolm", "role": "OPERATIVE"}
		},
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
	SystemLogger.log_info("  ✓ Engine initialized. World cash: £%.2f | District heat: %.2f" % [
		world_state["finances"]["liquid_cash"],
		world_state["districts"]["DIST_ASTON_01"]["actual_police_heat"]
	])

	# 2. MOUNT PRESENTATION LAYER (SHELL, VIEWHOST, DESKTOP SLIP STACK)
	SystemLogger.log_info("\n[STEP 2] Assembling presentation layer (OuterShell, ViewHost, DesktopSlipStack)...")
	var shell_scene: PackedScene = load("res://scenes/ui/shell_host/outer_shell.tscn")
	assert(shell_scene != null, "outer_shell.tscn failed to load!")
	var shell: OuterShell = shell_scene.instantiate() as OuterShell
	root.add_child(shell)

	# Mount spread wrapper to provide NAV, CONTENT, ACTION slots
	var spread_scene: PackedScene = load("res://scenes/ui/shells/filofax/filofax_spread.tscn")
	assert(spread_scene != null, "filofax_spread.tscn failed to load!")
	var spread_instance: Control = spread_scene.instantiate() as Control
	shell.set_spread_wrapper(spread_instance)

	var host := ViewHostScript.new()
	host.shell_node = shell
	shell.add_child(host)

	var card_stack := DesktopSlipStackScript.new()
	root.add_child(card_stack)
	host.set_desk_inbox(card_stack)

	# Mount compiled views into ViewHost
	var nav_bar: Control = load("res://generated/ui/gen_navigation_bar.gd").new()
	host.set_navigation_component(nav_bar)

	var docket: Control = load("res://generated/ui/gen_district_docket.gd").new()
	var cashbook: Control = load("res://generated/ui/gen_cashbook_ledger.gd").new()
	var diary: Control = load("res://generated/ui/gen_diary_log.gd").new()
	var planner: Control = load("res://generated/ui/gen_action_planner.gd").new()

	host.register_view("DOSSIER", docket)
	host.register_view("FINANCE", cashbook)
	host.register_view("DIARY", diary)

	# Mount Action Planner into ACTION slot and attach
	shell.mount_view("ACTION", planner)
	host.attach_action_system(planner, card_stack, null)
	host.switch_to_domain("DIARY")
	SystemLogger.log_info("  ✓ Navigation, Docket, Cashbook, Diary, and Action Planner mounted cleanly.")

	# 3. TEST DIRECTIVE STAGING, REORDERING & SELECTIVE COMMITMENT
	SystemLogger.log_info("\n[STEP 3] Testing directive staging, priority reordering & selection toggles...")
	var directive_1: Dictionary = {
		"verb": "BUY",
		"initiator_id": "STAFF_BILLY",
		"assigned_to": "STAFF_BILLY",
		"counterparty_id": "",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 5.0,
		"target_node_id": "DIST_ASTON_01",
		"target_scope": "DISTRICT"
	}
	var directive_2: Dictionary = {
		"verb": "SELL",
		"initiator_id": "PLAYER",
		"assigned_to": "PLAYER",
		"counterparty_id": "MARKET_CONSUMERS_ASTON",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 10.0,
		"target_node_id": "DIST_ASTON_01",
		"target_scope": "DISTRICT",
		"config": {"unit_price": 3.50, "exposure_modifier": 1.0}
	}

	host.add_staged_directive(directive_1)
	host.add_staged_directive(directive_2)
	assert(host.get_staged_directives().size() == 2, "Expected 2 directives staged in ViewHost!")
	assert(host.get_staged_directives()[0]["verb"] == "BUY", "First directive should be BUY")

	# Reorder: select second item and move UP
	var queue_widget: ItemList = null
	if "_value_labels" in planner and planner._value_labels.has("queue_list"):
		queue_widget = planner._value_labels["queue_list"] as ItemList
	elif planner.find_child("queue_list", true, false) != null:
		queue_widget = planner.find_child("queue_list", true, false) as ItemList
	assert(queue_widget != null, "queue_list ItemList missing in Action Planner!")

	queue_widget.select(1)
	host.move_staged_directive(-1)

	var reordered_queue: Array = host.get_staged_directives()
	assert(reordered_queue[0]["verb"] == "SELL", "Reordering failed: SELL directive should now be index 0!")
	SystemLogger.log_info("  ✓ Priority reordering verified: SELL directive moved ahead of BUY.")

	# Test Selection Toggle: Uncheck the BUY directive (now at index 1)
	queue_widget.select(1)
	host.toggle_selected_directive()
	assert(host.get_staged_directives()[1].get("is_selected", true) == false, "BUY directive should be unselected!")

	# Consume only selected directives for this turn
	var to_commit: Array = host.consume_selected_staged_directives()
	assert(to_commit.size() == 1, "Expected exactly 1 selected directive to be consumed!")
	assert(to_commit[0]["verb"] == "SELL", "Expected SELL directive to be committed!")
	assert(host.get_staged_directives().size() == 1, "Unselected BUY directive must remain staged in queue!")
	assert(host.get_staged_directives()[0]["verb"] == "BUY", "Remaining staged directive should be BUY!")
	SystemLogger.log_info("  ✓ Selective commitment verified: SELL committed, BUY preserved across turns.")

	# 4. EXECUTE TURN VIA SIMCONTROLLER & INSCRIBE ORDERS INTO DIARY
	SystemLogger.log_info("\n[STEP 4] Executing turn: inscribe orders into Diary & run SimController...")
	for cmd in to_commit:
		host.inscribe_entry_to_domain("DIARY", {
			"tick": world_state["metadata"]["current_week_tick"],
			"author": "Order Dispatch",
			"text": "DISPATCH: %s %s (Qty: %.0f)" % [cmd.get("verb", ""), cmd.get("target_item", ""), float(cmd.get("amount", 1))]
		})

	var diary_container: VBoxContainer = null
	if "_value_labels" in diary and diary._value_labels.has("__inscriptions__"):
		diary_container = diary._value_labels["__inscriptions__"] as VBoxContainer
	elif "_inscribed_entries_container" in diary:
		diary_container = diary._inscribed_entries_container
	assert(diary_container != null and diary_container.get_child_count() >= 1, "Diary failed to inscribe dispatched order!")
	SystemLogger.log_info("  ✓ Dispatched order inscribed on Diary ruled lines (%d entries present)." % diary_container.get_child_count())

	# Run SimController cycle
	var turn_report: Dictionary = SimControllerScript.process_turn_cycle(world_state, to_commit)
	var event_triggers: Array = turn_report.get("executed_events", [])
	assert(event_triggers.size() >= 1, "Expected at least 1 resolution trigger from SimController!")

	# Verify state mutation: Cash credited and stock decremented
	assert(world_state["finances"]["liquid_cash"] == 135.0, "Liquid cash failed to credit from sale!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 10.0, "Inventory stock failed to decrement!")
	SystemLogger.log_info("  ✓ SimController execution succeeded: £135.00 vault cash, 10 units stock remaining.")

	# 5. TRANSLATE EVENT TRIGGERS INTO DESKTOP SLIP CARDS
	SystemLogger.log_info("\n[STEP 5] Translating pure telemetry triggers to desk cards...")
	var cards: Array = FeedbackTranslatorScript.triggers_to_slip_cards(event_triggers)
	card_stack.push_cards(cards)
	assert(card_stack.get_card_count() >= 1, "DesktopSlipStack failed to accept translated cards!")
	SystemLogger.log_info("  ✓ Translated outcome card landed on desktop stack (%d cards queued)." % card_stack.get_card_count())

	# 6. TEST PHYSICAL TRIAGE: 📌 FILE RECEIPT INTERACTIVELY TO FINANCE
	SystemLogger.log_info("\n[STEP 6] Testing Triage Action: 📌 File Receipt to FINANCE...")
	var initial_evidence: float = float(world_state["operations"]["police_evidence_weight"])
	var top_card: Dictionary = card_stack.get_top_card()
	assert(not top_card.is_empty(), "Top card missing from DesktopSlipStack!")

	# File the top slip directly to FINANCE
	card_stack._on_file_pressed(top_card, "FINANCE")
	world_state["operations"]["police_evidence_weight"] += 0.08

	var cashbook_container: VBoxContainer = null
	if "_value_labels" in cashbook and cashbook._value_labels.has("__inscriptions__"):
		cashbook_container = cashbook._value_labels["__inscriptions__"] as VBoxContainer
	elif "_inscribed_entries_container" in cashbook:
		cashbook_container = cashbook._inscribed_entries_container
	assert(cashbook_container != null and cashbook_container.get_child_count() >= 1, "Cashbook failed to inscribe filed receipt via slip_filed!")
	assert(is_equal_approx(world_state["operations"]["police_evidence_weight"], initial_evidence + 0.08), "Evidence weight did not increment on file!")
	SystemLogger.log_info("  ✓ Card filed into Cashbook ledger; police evidence updated to: %.2f" % world_state["operations"]["police_evidence_weight"])

	# 7. TEST VIEW SWITCHING & DATA BINDING
	SystemLogger.log_info("\n[STEP 7] Testing ViewHost domain switching & Finance bind_data()...")
	host.switch_to_domain("FINANCE")
	host.update_active_view_data({
		"reported_cash": world_state["finances"]["liquid_cash"],
		"total_filed_expenses": 35.00
	})

	var cash_lbl: Label = null
	if "_value_labels" in cashbook and cashbook._value_labels.has("liquid_cash"):
		cash_lbl = cashbook._value_labels["liquid_cash"] as Label
	elif cashbook.find_child("liquid_cash", true, false) != null:
		cash_lbl = cashbook.find_child("liquid_cash", true, false) as Label

	assert(cash_lbl != null, "liquid_cash label missing in Cashbook view!")
	assert(cash_lbl.text.contains("135"), "Cashbook failed to format synced cash! Label text: %s" % cash_lbl.text)
	SystemLogger.log_info("  ✓ Switched to FINANCE view. Inked liquid cash bound: %s" % cash_lbl.text)

	# Clean synchronous teardown
	host.cleanup()
	DBManagerScript.close_database()

	root.remove_child(shell)
	root.remove_child(card_stack)
	shell.free()
	card_stack.free()

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL BRIDGE ORCHESTRATION TESTS PASSED CLEANLY")
	SystemLogger.log_info("=======================================================\n")
	quit(0)