# res://systems/ui_commands/cmd_file_slip.gd
extends RefCounted

## Files a card slip into the appropriate ledger domain
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	var slip_data: Dictionary = payload.get("slip_data", payload)
	var dest: String = str(payload.get("destination", slip_data.get("destination", "DIARY")))
	if view_host != null:
		view_host.inscribe_entry_to_domain(dest, {
			"tick": slip_data.get("tick", 1),
			"text": slip_data.get("display_text", "")
		})
	SystemLogger.log_info("[CmdFileSlip] Filed slip to %s: %s" % [dest, slip_data.get("display_text", "")])