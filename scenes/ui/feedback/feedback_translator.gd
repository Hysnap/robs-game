# res://scenes/ui/feedback/feedback_translator.gd
class_name FeedbackTranslator
extends RefCounted

## Translates engine event triggers into physical card payloads using JSON config
static func triggers_to_slip_cards(event_triggers: Array, profiles_schema: Dictionary) -> Array:
	var cards: Array = []
	var profiles = profiles_schema.get("slip_profiles", {})

	for trigger in event_triggers:
		var verb: String = trigger.get("verb", "")
		var is_receipt: bool = (verb == "BUY" or verb == "SELL")
		
		var profile_key := "RECEIPT" if is_receipt else "FIELD_MEMO"
		var profile_conf: Dictionary = profiles.get(profile_key, {})

		# Presentation payload constructed strictly from configs
		var card := {
			"slip_profile": profile_key,
			"destination": profile_conf.get("default_filing_domain", "DIARY"),
			"evidence_weight": float(profile_conf.get("evidence_base_weight", 0.05)),
			"display_text": "[ %s ] %s %s" % [verb, trigger.get("target_item", ""), "SETTLED" if trigger.get("success", false) else "FAILED"],
			"tick": trigger.get("tick", 1)
		}
		cards.append(card)

	return cards