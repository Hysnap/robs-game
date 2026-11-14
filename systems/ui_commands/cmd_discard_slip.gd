# res://systems/ui_commands/cmd_discard_slip.gd
extends RefCounted

## Handles discarding a feedback slip from the desk inbox stack
static func execute(payload: Dictionary, _view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	SystemLogger.log_info("[CmdDiscardSlip] Discarded slip: %s" % str(payload.get("display_text", "")))