# res://tools/test_ui_preview.gd
extends Control

@onready var shell: OuterShell = $OuterShell
var host: ViewHost

func _ready() -> void:
	# 1. Attach the ViewHost presenter
	host = preload("res://scenes/ui/shell_host/view_host.gd").new()
	host.shell_node = shell
	add_child(host)

	# 2. Mount Compiled Navigation Component
	var nav_class = load("res://generated/ui/gen_navigation_bar.gd")
	if nav_class:
		host.set_navigation_component(nav_class.new())

	# 3. Mount Compiled Views
	var docket_class = load("res://generated/ui/gen_district_docket.gd")
	if docket_class:
		host.register_view("DOSSIER", docket_class.new())

	var cashbook_class = load("res://generated/ui/gen_cashbook_ledger.gd")
	if cashbook_class:
		host.register_view("FINANCE", cashbook_class.new())

	var diary_class = load("res://generated/ui/gen_diary_log.gd")
	if diary_class:
		host.register_view("DIARY", diary_class.new())

	# 4. Default to Dossier view and supply sample data
	host.switch_to_domain("DOSSIER")
	host.update_active_view_data({
		"active_population": 8420,
		"total_households": 2150,
		"formally_employed_count": 5200,
		"street_informal_count": 940,
		"avg_disposable_income": 94.50,
		"zone_health_index": 76.2,
		"actual_police_heat": 0.38,
		"unemployment_rate": 0.14
	})

	# 5. Listen to tab clicks to feed sample data dynamically
	host.route_changed.connect(func(domain_key: String):
		match domain_key:
			"FINANCE":
				host.update_active_view_data({
					"reported_cash": 1250.75,
					"total_filed_expenses": 340.20
				})
			"DIARY":
				host.update_active_view_data({
					"current_week_tick": 12,
					"total_dispatched_orders": 6
				})
	)
