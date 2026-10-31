# res://systems/operations_controller.gd
class_name OperationsController
extends RefCounted

const SimControllerScript = preload("res://systems/sim_controller.gd")
const StationeryRegistryScript = preload("res://scenes/ui/feedback/stationery_registry.gd")

## Executes staged directives through SimController, updates world state, and returns UI payloads
static func execute_staged_cycle(staged_orders: Array, view_host: ViewHost = null) -> Dictionary:
	var gs = ScenarioManifestManager.get_game_state()
	if gs == null or not "world_state" in gs:
		push_error("[OperationsController] GameState or world_state unmounted.")
		return {}

	if staged_orders.is_empty():
		print("[OperationsController] No directives staged for operational cycle.")
		return {}

	# 1. Run pure simulation cycle
	var report: Dictionary = SimControllerScript.process_turn_cycle(gs.world_state, staged_orders)

	# 2. Ingest outcome slips and format into stationery payloads
	StationeryRegistryScript.initialize()
	var events: Array = report.get("executed_events", [])
	var cards: Array = []

	for ev in events:
		var verb: String = ev.get("verb", "")
		var binding: Dictionary = StationeryRegistryScript.get_verb_binding(verb)
		var card_payload := {
			"stationery_profile": binding.get("default_definition", "STICKY_NOTE"),
			"destination": binding.get("default_filing_domain", "DIARY"),
			"display_text": ev.get("message", "Task settled."),
			"tick": ev.get("tick", 1),
			"week": ev.get("week", 1),
			"success": ev.get("success", false),
			"author": ev.get("author", "Runner Dispatch")
		}
		cards.append(card_payload)

	# 3. If a ViewHost is present, update the UI layers
	if view_host != null:
		view_host.clear_staged_directives()

		var current_date_str: String = report.get("calendar_date", "Shift Report")
		for memo in report.get("diary_memos", []):
			view_host.inscribe_entry_to_domain("DIARY", {
				"tick": report.get("week", 1),
				"text": "[%s] %s" % [current_date_str, memo]
			})

		if not cards.is_empty():
			view_host.push_feedback_slips(cards)

		# Refresh currently selected docket view
		var active_id: String = str(gs.world_state.get("selected_district_id", ""))
		if not active_id.is_empty() and gs.has_method("get_district_view"):
			var district_data: Dictionary = gs.get_district_view(active_id)
			view_host.update_active_view_data(district_data)

	# 4. Notify world of timeline step
	if gs.has_signal("turn_advanced"):
		gs.turn_advanced.emit(report.get("week", 1), report.get("day", 1))

	return report

## Files a card slip into the appropriate ledger domain
static func file_card_slip(card_payload: Dictionary, view_host: ViewHost = null) -> void:
	var dest: String = card_payload.get("destination", "DIARY")
	if view_host != null:
		view_host.inscribe_entry_to_domain(dest, {
			"tick": card_payload.get("tick", 1),
			"text": card_payload.get("display_text", "")
		})
	print("[OperationsController] Filed slip to %s: %s" % [dest, card_payload.get("display_text")])