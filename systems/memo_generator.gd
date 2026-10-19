# res://systems/memo_generator.gd
class_name MemoGenerator extends RefCounted

## Converts shift execution facts into a natural language slip
static func generate_shift_feedback(staff: Dictionary, shift_report: Dictionary) -> String:
	var staff_name: String = staff.get("name", "Runner")
	var voice: String = staff.get("voice_profile", "STREET_RAW")
	var loyalty: float = staff.get("loyalty", 0.5) #
	
	var time_waited = shift_report.get("idle_ticks_waiting", 0)
	var missed_tasks: Array = shift_report.get("missed_tasks", [])
	var completed_late: bool = shift_report.get("overtime_worked", false)
	var fatigue_gain: float = shift_report.get("fatigue_added", 0.0)
	
	# If the day went completely smooth with zero friction
	if missed_tasks.is_empty() and not completed_late and time_waited == 0:
		return _generate_clean_memo(staff_name, voice)
		
	# Build narrative segments for a messy shift
	var narrative_parts: Array = []
	
	# 1. Opening / Time Delay Complaint
	if time_waited > 2:
		narrative_parts.append("Was kicking my heels waiting around for things to start like you said.")
	
	# 2. Missed task (e.g. Shop closed)
	for missed in missed_tasks:
		var reason = missed.get("reason", "")
		var task_name = missed.get("task_name", "the job")
		if reason == "OUTSIDE_HOURS" or reason == "SHOP_CLOSED":
			narrative_parts.append("Got round to %s but the shutters were down and place was locked up." % task_name)
		elif reason == "INSUFFICIENT_FUNDS":
			narrative_parts.append("Tried to sort %s but didn't have enough cash on me." % task_name)
		else:
			narrative_parts.append("Couldn't get %s sorted in time." % task_name)
			
	# 3. Late / Overtime Friction
	if completed_late:
		narrative_parts.append("Had to stay out half the night to get the rest over the line.")
		
	# 4. Sign-off based on Loyalty & Demeanor
	if loyalty > 0.8:
		narrative_parts.append("Got the rest sorted for you though, boss.")
	elif loyalty < 0.4:
		narrative_parts.append("Need paying extra if you're gonna have me running around like this.") #
	else:
		narrative_parts.append("Left what was done in the lockup.")
		
	return "%s: \"%s\"" % [staff_name.to_upper(), " ".join(narrative_parts)]

static func _generate_clean_memo(staff_name: String, _voice: String) -> String:
	var clean_phrases = [
		"All sorted as laid out. Stock checked and dropped.",
		"Everything ran on time today, boss.",
		"Done and dusted. No trouble on the rounds."
	]
	return "%s: \"%s\"" % [staff_name.to_upper(), clean_phrases.pick_random()]