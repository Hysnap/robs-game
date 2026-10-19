# res://systems/dialogue_resolver.gd
class_name DialogueResolver extends RefCounted

static func format_feedback(raw_result: Variant, staff: Dictionary, dialect: Dictionary, feedback_data: Dictionary) -> String:
	# 1. Unpack either an EngineResult or a Dictionary result cleanly
	var code: String = ""
	var verb: String = ""
	var context: Dictionary = {}
	
	if raw_result is EngineResult:
		code = raw_result.get_code_string()
		verb = raw_result.verb.to_upper()
		context = raw_result.context
	elif raw_result is Dictionary:
		code = raw_result.get("code", "SUCCESS" if raw_result.get("success", true) else "FAILED")
		verb = raw_result.get("verb", "").to_upper()
		context = raw_result.get("context", {})
		# Fallback: if context is empty, harvest top-level keys from the action result
		if context.is_empty():
			context = raw_result.duplicate()
	else:
		return "Invalid result payload passed to DialogueResolver."

	var templates: Array = []

	# 2. Action Colocated Override (Tier 1)
	if feedback_data.get("verbs", {}).has(verb):
		templates = feedback_data["verbs"][verb].get(code, [])

	# 3. Universal Shared Template (Tier 2)
	if templates.is_empty():
		templates = feedback_data.get("shared", {}).get(code, [])

	# 4. Engine Diagnostic Fallback (Tier 3)
	if templates.is_empty():
		return "%s: Completed %s with status [%s]" % [staff.get("name", "Staff"), verb, code]

	# 5. Token replacement ({amount}, {target_item}, {target_location}, etc.)
	var text: String = templates.pick_random()
	for k in context.keys():
		text = text.replace("{%s}" % k, str(context[k]))
	text = text.replace("{verb}", verb)

	# 6. Dialect slang replacements ({wedge}, {shut}, {done}, etc.)
	var replacements: Dictionary = dialect.get("replacements", {})
	for placeholder in replacements.keys():
		while text.contains(placeholder):
			var options: Array = replacements[placeholder]
			var chosen: String = options.pick_random() if not options.is_empty() else placeholder
			text = text.replace(placeholder, chosen)

	return "%s: \"%s\"" % [staff.get("name", "Staff").to_upper(), text]