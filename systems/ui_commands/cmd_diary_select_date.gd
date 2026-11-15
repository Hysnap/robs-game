# res://systems/ui_commands/cmd_diary_select_date.gd
extends RefCounted

const _CmdOpenDiary = preload("res://systems/ui_commands/cmd_open_diary.gd")

## Refreshes the active Diary Log view for a selected date or month offset without switching domains
static func execute(payload: Dictionary, view_host: ViewHost, context_refs: Dictionary = {}) -> void:
	var merged: Dictionary = payload.duplicate()
	merged["keep_domain"] = true
	_CmdOpenDiary.execute(merged, view_host, context_refs)