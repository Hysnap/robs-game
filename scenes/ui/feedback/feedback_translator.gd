# res://scenes/ui/feedback/feedback_translator.gd
class_name FeedbackTranslator
extends RefCounted

const StationeryRegistryScript = preload("res://scenes/ui/feedback/stationery_registry.gd")

## Translates engine event triggers into physical card payloads using JSON config
static func triggers_to_slip_cards(event_triggers: Array) -> Array:
	StationeryRegistryScript.initialize()
	var default_def_id: String = StationeryRegistryScript.get_default_definition_id()
	var cards: Array = []

	for trigger in event_triggers:
		var verb: String = trigger.get("verb", "")
		var binding: Dictionary = StationeryRegistryScript.get_verb_binding(verb)
		var is_success: bool = trigger.get("success", false)

		# Prefer descriptive message if provided by SimController, else construct fallback
		var text: String = trigger.get("message", "")
		if text.is_empty():
			var item: String = str(trigger.get("target_item", ""))
			text = "[ %s ] %s %s" % [
				verb,
				item,
				"SETTLED" if is_success else "FAILED"
			]

		# Resolve operative author cleanly
		var author_name: String = str(trigger.get("author", ""))
		if author_name.is_empty():
			author_name = str(trigger.get("assigned_agent", trigger.get("staff_id", "Runner Dispatch")))

		# Presentation payload constructed strictly from configs
		var card := {
			"stationery_profile": binding.get("default_definition", default_def_id),
			"destination": binding.get("default_filing_domain", "DIARY"),
			"display_text": text,
			"tick": trigger.get("tick", trigger.get("day_offset", 1)),
			"week": trigger.get("week", 1),
			"success": is_success,
			"author": author_name,
			"target_node_id": trigger.get("target_node_id", ""),
			"staged_index": trigger.get("staged_index", 0)
		}
		cards.append(card)

	return cards