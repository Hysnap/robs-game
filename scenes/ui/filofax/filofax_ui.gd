# res://scenes/ui/filofax/filofax_ui.gd
extends PanelContainer
class_name FilofaxUI

@onready var week_label: Label = $VBox/Header/WeekLabel
@onready var cash_label: Label = $VBox/Header/CashLabel
@onready var district_container: VBoxContainer = $VBox/Spread/LeftPage/DistrictList
@onready var memo_container: VBoxContainer = $VBox/Spread/CenterSpike/MemoList

func update_display(cache: Dictionary) -> void:
	# 1. Update Header
	var tick = cache.get("metadata", {}).get("viewed_tick", 1)
	week_label.text = "WEEK %d [LEDGER DESK]" % tick
	
	var cash = cache.get("finances", {}).get("reported_cash", 0.0)
	cash_label.text = "VAULT CASH: £%.2f" % cash
	
	# 2. Render District Pages (Left Page)
	for child in district_container.get_children():
		child.queue_free()
		
	var districts: Dictionary = cache.get("districts", {})
	for dist_id in districts.keys():
		var data = districts[dist_id]
		var line = HBoxContainer.new()
		
		var name_lbl = Label.new()
		name_lbl.text = "%s: " % data["display_name"]
		line.add_child(name_lbl)
		
		var heat_lbl = Label.new()
		heat_lbl.text = "Heat %d%% | ZHI %d%%" % [
			int(data["inked_police_heat"] * 100), 
			int(data["inked_zone_health"])
		]
		
		# Visual cue: even with zero lag now, the UI is ready to color-code stale data later!
		if data["data_age_ticks"] > 2:
			heat_lbl.modulate = Color.DARK_ORANGE
		else:
			heat_lbl.modulate = Color.GREEN
			
		line.add_child(heat_lbl)
		district_container.add_child(line)