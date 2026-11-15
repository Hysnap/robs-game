# res://systems/ui_commands/cmd_open_order_composer.gd
extends RefCounted

## Opens and initializes the StickyOrderPad order composer via ViewHost
static func execute(payload: Dictionary, view_host: ViewHost, _context_refs: Dictionary = {}) -> void:
	if view_host == null:
		return

	var order_pad = view_host.get_order_composer_node()
	if order_pad == null:
		SystemLogger.log_error("[CmdOpenOrderComposer] Cannot open order composer: ViewHost has no mounted order pad.")
		push_error("[CmdOpenOrderComposer] Cannot open order composer: ViewHost has no mounted order pad.")
		return

	if order_pad.has_method("open_for_context"):
		order_pad.open_for_context(payload)
	elif order_pad.has_method("open_for_district"):
		var target_dist: String = str(payload.get("target_district_id", payload.get("district_id", "")))
		if target_dist.is_empty():
			var gs = ScenarioManifestManager.get_game_state()
			if gs and "world_state" in gs:
				var ws: Dictionary = gs.world_state
				target_dist = str(ws.get("selected_district_id", ws.get("player_knowledge", {}).get("home_district_id", "")))
		if not target_dist.is_empty():
			order_pad.open_for_district(target_dist)
		else:
			order_pad.visible = true
			order_pad.move_to_front()
	else:
		order_pad.visible = true
		order_pad.move_to_front()