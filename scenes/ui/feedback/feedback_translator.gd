# res://scenes/ui/feedback/feedback_translator.gd
class_name FeedbackTranslator
extends RefCounted

const StationeryRegistryScript = preload("res://scenes/ui/feedback/stationery_registry.gd")

## Translates engine event triggers into physical card payloads using JSON config
static func triggers_to_slip_cards(event_triggers: Array) -> Array:
	StationeryRegistryScript.initialize()
	var cards: Array = []

	for trigger in event_triggers:
		var verb: String = trigger.get("verb", "")
		var binding: Dictionary = StationeryRegistryScript.get_verb_binding(verb)

		# Presentation payload constructed strictly from configs
		var card := {
			"stationery_profile": binding.get("default_definition", "STICKY_NOTE"),
            "destination": binding.get("default_filing_domain", "DIARY"),
            "display_text": "[ %s ] %s %s" % [
                verb,
                trigger.get("target_item", ""),
                "SETTLED" if trigger.get("success", false) else "FAILED"
            ],
            "tick": trigger.get("tick", trigger.get("day_offset", 1)),
            "week": trigger.get("week", 1),
            "author": trigger.get("author", "Runner Dispatch")
		}
		cards.append(card)

	return cards