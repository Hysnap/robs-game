# res://tests/test_ui_pipeline_diary.gd
extends SceneTree

const UICompilerScript = preload("res://tools/ui_compiler/ui_compiler.gd")
const DBManagerScript = preload("res://systems/db_manager.gd")
const ObligationLedgerScript = preload("res://systems/economy/obligation_ledger.gd")
const DiaryAgendaBuilderScript = preload("res://systems/economy/diary_agenda_builder.gd")
const CalendarNavigatorScript = preload("res://scenes/ui/components/calendar_navigator.gd")

const SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/diary_log.json"
const GENERATED_SCRIPT_PATH := "res://generated/ui/core/gen_diary_log.gd"
const POCKETBOOK_SCHEMA_PATH := "res://data_modules/core/ui_schemas/views/pocketbooks/diary_log.json"
const POCKETBOOK_GENERATED_PATH := "res://generated/ui/core/pocketbooks/gen_diary_log.gd"

func _init() -> void:
	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   TEST: UI PIPELINE - DIARY LOG COMPILATION & BINDING")
	SystemLogger.log_info("=======================================================")

	# 1. Compile target schemas (core + pocketbooks)
	SystemLogger.log_info("\n[STEP 1] Compiling diary_log.json schemas...")
	assert(FileAccess.file_exists(SCHEMA_PATH), "Schema missing at: %s" % SCHEMA_PATH)
	UICompilerScript.compile_schema(SCHEMA_PATH)
	assert(FileAccess.file_exists(GENERATED_SCRIPT_PATH), "Generated file missing: %s" % GENERATED_SCRIPT_PATH)

	assert(FileAccess.file_exists(POCKETBOOK_SCHEMA_PATH), "Pocketbook schema missing at: %s" % POCKETBOOK_SCHEMA_PATH)
	UICompilerScript.compile_schema(POCKETBOOK_SCHEMA_PATH)
	assert(FileAccess.file_exists(POCKETBOOK_GENERATED_PATH), "Generated pocketbook file missing: %s" % POCKETBOOK_GENERATED_PATH)
	SystemLogger.log_info("  ✓ Successfully compiled core and pocketbook diary views.")

	# 2. Instantiate View
	SystemLogger.log_info("\n[STEP 2] Instantiating GenDiaryLog headlessly...")
	var diary_script = load(GENERATED_SCRIPT_PATH)
	assert(diary_script != null, "Failed to load generated script resource: %s" % GENERATED_SCRIPT_PATH)

	var diary_view: Control = diary_script.new() as Control
	assert(diary_view != null, "Failed to instantiate GenDiaryLog instance")
	assert(diary_view.has_signal("action_clicked"), "GenDiaryLog missing action_clicked signal!")
	root.add_child(diary_view)

	var week_lbl: Label = diary_view.find_child("current_week_value", true, false) as Label
	var orders_lbl: Label = diary_view.find_child("dispatched_count_value", true, false) as Label
	var cal_nav: CalendarNavigatorScript = diary_view.find_child("calendar_nav", true, false) as CalendarNavigatorScript
	assert(week_lbl != null, "current_week_value label missing in GenDiaryLog hierarchy!")
	assert(orders_lbl != null, "dispatched_count_value label missing in GenDiaryLog hierarchy!")
	assert(cal_nav != null, "calendar_nav CalendarNavigator widget missing in GenDiaryLog hierarchy!")
	SystemLogger.log_info("  ✓ GenDiaryLog instantiated and metric + CalendarNavigator nodes resolved.")

	# 3. Test Full Snapshot Binding
	SystemLogger.log_info("\n[STEP 3] Testing bind_data() metric formatting...")
	diary_view.bind_data({
		"current_week_tick": 4,
		"total_dispatched_orders": 18
	})

	assert(week_lbl.text.contains("4"), "Expected current week formatted with 4, got: %s" % week_lbl.text)
	assert(orders_lbl.text.contains("18"), "Expected dispatched orders formatted with 18, got: %s" % orders_lbl.text)
	SystemLogger.log_info("  ✓ Metric snapshot bound cleanly: Week %s | Orders %s" % [week_lbl.text, orders_lbl.text])

	# 4. Test Snapshot Reset Behavior (Pipeline Rule #9)
	SystemLogger.log_info("\n[STEP 4] Testing snapshot reset behavior on empty payload...")
	diary_view.bind_data({})
	var masked_text: String = tr("UI_INTEL_MASKED_BLANK")
	assert(week_lbl.text == masked_text, "Current week failed to reset on empty snapshot! Got: %s" % week_lbl.text)
	assert(orders_lbl.text == masked_text, "Dispatched orders failed to reset on empty snapshot! Got: %s" % orders_lbl.text)
	SystemLogger.log_info("  ✓ Omitted fields reset to placeholder (%s) cleanly." % masked_text)

	# 5. Test Inscription Capability (First-Class Section)
	SystemLogger.log_info("\n[STEP 5] Testing inscribe_entry() for operational logs...")
	assert(diary_view.has_method("inscribe_entry"), "GenDiaryLog must implement inscribe_entry()")

	var insc_container: VBoxContainer = null
	if "_value_labels" in diary_view and diary_view._value_labels.has("__inscriptions__"):
		insc_container = diary_view._value_labels["__inscriptions__"] as VBoxContainer
	assert(insc_container != null, "Missing '__inscriptions__' container in GenDiaryLog!")
	assert(insc_container.get_child_count() == 0, "Inscriptions container should initially be empty")

	diary_view.inscribe_entry({
		"tick": 28,
		"author": "Runner Dispatch",
		"text": "OPERATIONAL DISPATCH: 5x CIGARETTES_UNFILTERED to The Rusty Anchor"
	})

	assert(insc_container.get_child_count() == 1, "Failed to mount inscribed memo label in container!")
	var entry_node: Control = insc_container.get_child(0) as Control
	assert(entry_node != null, "Inscribed entry node is null!")
	SystemLogger.log_info("  ✓ Successfully inscribed memo into diary container.")

	# 6. Test CalendarNavigator + DiaryAgendaBuilder + SocietyQueries End-to-End
	SystemLogger.log_info("\n[STEP 6] Testing CalendarNavigator agenda binding and action signals...")
	assert(DBManagerScript.initialize_database(true, ":memory:"), "Failed to initialize in-memory SQLite DB for calendar test!")
	var start_day: int = CalendarHelper.get_simulation_start_day()

	var pub_event_id: int = ObligationLedgerScript.create_calendar_event({
		"event_type": "CIVIC_FAIR",
		"title_token": "UI_EVENT_CIVIC_FAIR",
		"location_id": "DIST_CENTRAL",
		"visibility_scope": "PUBLIC",
		"start_day": start_day + 2,
		"end_day": start_day + 2,
		"created_day": start_day
	})
	var hidden_priv_id: int = ObligationLedgerScript.create_calendar_event({
		"event_type": "CLANDESTINE_DROP",
		"title_token": "UI_EVENT_HIDDEN_DROP",
		"location_id": "DIST_DOCKS",
		"visibility_scope": "PRIVATE",
		"start_day": start_day + 2,
		"end_day": start_day + 2,
		"created_day": start_day
	})
	var crew_priv_id: int = ObligationLedgerScript.create_calendar_event({
		"event_type": "CREW_SUMMONS",
		"title_token": "UI_EVENT_CREW_SUMMONS",
		"location_id": "DIST_CENTRAL",
		"visibility_scope": "PRIVATE",
		"start_day": start_day + 2,
		"end_day": start_day + 2,
		"created_day": start_day
	})
	assert(pub_event_id > 0 and hidden_priv_id > 0 and crew_priv_id > 0, "Failed to insert test calendar_events!")

	ObligationLedgerScript.create_obligation({
		"obligation_type": "EVENT_ATTENDANCE",
		"debtor": "RESIDENT:RES_CREW_1",
		"creditor": "ORG:LOCAL_GUILD",
		"principal": 0.0,
		"created_day": start_day,
		"due_day": start_day + 2,
		"linked_event_id": crew_priv_id
	})

	var mock_ws := {
		"residents": {
			"RES_CREW_1": {"resident_id": "RES_CREW_1", "is_crew": true}
		},
		"districts": {
			"DIST_CENTRAL": {"name": "Central Ward"}
		}
	}

	var cal_payload := DiaryAgendaBuilderScript.build_calendar_payload(mock_ws, start_day, {"sim_day": start_day + 2})
	assert(cal_payload["selected_sim_day"] == start_day + 2, "Expected selected_sim_day to match requested sim_day!")

	var agenda_items: Array = cal_payload["selected_day_items"]
	assert(agenda_items.size() == 2, "Expected 2 visible items (public + crew-linked private), got %d" % agenda_items.size())
	for item in agenda_items:
		assert(int(item["event_id"]) != hidden_priv_id, "Fog-of-War leak: unlinked PRIVATE event appeared in crew agenda!")
		assert(bool(item["can_attend"]) == true, "Expected eligible future event to have can_attend == true")

	var emitted_signals: Array[Dictionary] = []
	diary_view.action_clicked.connect(func(code: String, payload: Dictionary):
		emitted_signals.append({"code": code, "payload": payload})
	)

	diary_view.bind_data({
		"current_week_tick": 1,
		"total_dispatched_orders": 0,
		"calendar_payload": cal_payload
	})

	# Verify day cell button emits diary_select_date
	var target_day_btn: Button = cal_nav.find_child("day_btn_%d" % (start_day + 4), true, false) as Button
	assert(target_day_btn != null, "Expected day button for start_day + 4 in CalendarNavigator!")
	target_day_btn.pressed.emit()
	assert(emitted_signals.size() == 1, "Expected 1 emitted signal from day button press")
	assert(emitted_signals[0]["code"] == "diary_select_date", "Expected diary_select_date, got: %s" % emitted_signals[0]["code"])
	assert(int(emitted_signals[0]["payload"].get("sim_day", -1)) == start_day + 4, "Payload sim_day mismatch!")

	# Verify ATTEND button emits open_order_composer pre-targeted to ATTEND_EVENT
	var attend_btn: Button = cal_nav.find_child("attend_btn_%d" % pub_event_id, true, false) as Button
	assert(attend_btn != null, "Expected attend_btn_%d in CalendarNavigator agenda!" % pub_event_id)
	attend_btn.pressed.emit()
	assert(emitted_signals.size() == 2, "Expected 2 emitted signals after attend button press")
	assert(emitted_signals[1]["code"] == "open_order_composer", "Expected open_order_composer, got: %s" % emitted_signals[1]["code"])
	assert(emitted_signals[1]["payload"].get("verb", "") == "ATTEND_EVENT", "Expected verb ATTEND_EVENT!")
	assert(int(emitted_signals[1]["payload"].get("event_id", 0)) == pub_event_id, "Expected event_id %d in composer payload!" % pub_event_id)

	DBManagerScript.close_database()
	SystemLogger.log_info("  ✓ CalendarNavigator bound agenda, enforced private-event FoW, and emitted selection + ATTEND_EVENT signals.")

	# Teardown
	root.remove_child(diary_view)
	_deep_free_node(diary_view)

	SystemLogger.log_info("\n=======================================================")
	SystemLogger.log_info("   ALL DIARY LOG PIPELINE TESTS PASSED")
	SystemLogger.log_info("=======================================================\n")
	quit(0)

func _deep_free_node(node: Node) -> void:
	for child in node.get_children():
		_deep_free_node(child)
	node.free()