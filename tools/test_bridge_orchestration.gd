# res://tools/test_bridge_orchestration.gd
extends SceneTree

const OuterShellScript = preload("res://scenes/ui/shell_host/outer_shell.gd")
const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")
const StaggeredCardStackScript = preload("res://scenes/ui/components/staggered_card_stack.gd")

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

	# 2. MOUNT PRESENTATION LAYER (SHELL, VIEWHOST, SPREAD WRAPPER)
	SystemLogger.log_info("\n[STEP 2] Assembling presentation layer (OuterShell, ViewHost, StaggeredCardStack)...")
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

	var card_stack := StaggeredCardStackScript.new()
	root.add_child(card_stack)

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

	# 3. TEST DIRECTIVE STAGING, REORDERING & DISPATCH THROUGH VIEWHOST
	SystemLogger.log_info("\n[STEP 3] Testing directive staging & reordering in ViewHost...")
	var directive_1: Dictionary = {
		"verb": "BUY",
		"initiator_id": "STAFF_BILLY",
		"counterparty_id": "",
		"target_item": "BEER_STRONG_LAGER",
		"amount": 5.0,
		"target_node_id": "DIST_ASTON_01",
		"target_scope": "DISTRICT"
	}
	var directive_2: Dictionary = {
		"verb": "SELL",
		"initiator_id": "PLAYER",
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
	SystemLogger.log_info("  ✓ Staging buffer and priority reordering verified (SELL prioritized ahead of BUY).")

	# Trigger shift commitment signal
	var test_signal_fired := {"fired": false, "code": ""}
	host.action_requested.connect(func(action_code: String, _payload: Dictionary):
		test_signal_fired["fired"] = true
		test_signal_fired["code"] = action_code
	)

	var btn_execute: Button = null
	if "_value_labels" in planner and planner._value_labels.has("btn_execute_shift"):
		btn_execute = planner._value_labels["btn_execute_shift"] as Button
	elif planner.find_child("btn_execute_shift", true, false) != null:
		btn_execute = planner.find_child("btn_execute_shift", true, false) as Button
	assert(btn_execute != null, "btn_execute_shift missing in compiled planner!")
	btn_execute.pressed.emit()

	assert(test_signal_fired["fired"], "Action requested failed to emit from ViewHost!")
	assert(test_signal_fired["code"] == "COMMIT_SHIFT", "Expected 'COMMIT_SHIFT' action code!")
	SystemLogger.log_info("  ✓ Shift execution triggered cleanly via 'COMMIT_SHIFT' button.")

	# 4. EXECUTE TURN & INSCRIBE ORDERS INTO DIARY
	SystemLogger.log_info("\n[STEP 4] Executing turn: inscribe orders into Diary & run SimController...")
	var active_orders: Array = [directive_2] # Process the SELL directive
	for cmd in active_orders:
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
	var turn_report: Dictionary = SimControllerScript.process_turn_cycle(world_state, active_orders)
	var event_triggers: Array = turn_report.get("executed_events", [])
	assert(event_triggers.size() >= 1, "Expected at least 1 resolution trigger from SimController!")

	# Verify state mutation: Cash credited and stock decremented
	assert(world_state["finances"]["liquid_cash"] == 135.0, "Liquid cash failed to credit from sale!")
	assert(world_state["inventory_registry"]["BEER_STRONG_LAGER"]["STOCK"] == 10.0, "Inventory stock failed to decrement!")
	SystemLogger.log_info("  ✓ SimController execution succeeded: £135.00 vault cash, 10 units stock remaining.")

	# 5. TRANSLATE EVENT TRIGGERS INTO MODULAR CARD STACK
	SystemLogger.log_info("\n[STEP 5] Translating pure telemetry triggers to desk cards...")
	var cards: Array = FeedbackTranslatorScript.triggers_to_slip_cards(event_triggers)
	card_stack.push_cards(cards)
	assert(card_stack.get_card_count() >= 1, "CardStack failed to accept translated cards!")
	SystemLogger.log_info("  ✓ Translated outcome card landed on desktop stack (%d cards queued)." % card_stack.get_card_count())

	# 6. TEST PHYSICAL TRIAGE: 📌 FILE RECEIPT TO FINANCE
	SystemLogger.log_info("\n[STEP 6] Testing Triage Action: 📌 File Receipt to FINANCE...")
	var initial_evidence: float = float(world_state["operations"]["police_evidence_weight"])

	var triage_recorded := {"filed": false}
	card_stack.top_card_action.connect(func(action_id: String, payload: Dictionary):
		if action_id == "FILE":
			triage_recorded["filed"] = true
			var dest: String = str(payload.get("destination", "FINANCE"))
			host.inscribe_entry_to_domain(dest, {
				"tick": payload.get("tick", 1),
				"author": payload.get("slip_profile", "REPORT"),
				"text": payload.get("display_text", "")
			})
			var risk: float = float(payload.get("evidence_weight", 0.08))
			world_state["operations"]["police_evidence_weight"] += risk
	)

	card_stack.pop_top_card("FILE")
	assert(triage_recorded["filed"], "Top card action failed to fire on pop_top_card('FILE')!")

	var cashbook_container: VBoxContainer = null
	if "_value_labels" in cashbook and cashbook._value_labels.has("__inscriptions__"):
		cashbook_container = cashbook._value_labels["__inscriptions__"] as VBoxContainer
	elif "_inscribed_entries_container" in cashbook:
		cashbook_container = cashbook._inscribed_entries_container
	assert(cashbook_container != null and cashbook_container.get_child_count() >= 1, "Cashbook failed to inscribe filed receipt!")
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