# res://systems/ui_commands/cmd_contact_detail.gd
extends RefCounted

const CmdOperativeDetailScript = preload("res://systems/ui_commands/cmd_operative_detail.gd")

## Resolves a known contact's resident_id to their home establishment and opens their residential docket
static func execute(payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	CmdOperativeDetailScript.execute(payload, view_host, context_refs)