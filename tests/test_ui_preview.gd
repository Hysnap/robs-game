# res://tools/test_ui_preview.gd
extends Control

const DistrictPerceptionFilterScript = preload("res://systems/multilayer_info_loop/district_perception_filter.gd")
const ViewHostScript = preload("res://scenes/ui/shell_host/view_host.gd")

@onready var shell: OuterShell = $OuterShell
var host: ViewHost

func _ready() -> void:
	# 1. Mount default Filofax wrapper so generic slots (NAV, CONTENT, ACTION) are initialized
	var filo_spread_scene: PackedScene = load("res://scenes/ui/shells/filofax/filofax_spread.tscn")
	assert(filo_spread_scene != null, "filofax_spread.tscn failed to load!")
	shell.set_spread_wrapper(filo_spread_scene.instantiate())

	# 2. Attach the ViewHost presenter
	host = ViewHostScript.new()
	host.shell_node = shell
	add_child(host)

	# 3. Mount Compiled Navigation Component
	var nav_class = load("res://generated/ui/gen_navigation_bar.gd")
	if nav_class:
		host.set_navigation_component(nav_class.new())

	# 4. Mount Compiled Views
	var docket_class = load("res://generated/ui/gen_district_docket.gd")
	if docket_class:
		host.register_view("DOSSIER", docket_class.new())

	var cashbook_class = load("res://generated/ui/gen_cashbook_ledger.gd")
	if cashbook_class:
		host.register_view("FINANCE", cashbook_class.new())

	var diary_class = load("res://generated/ui/gen_diary_log.gd")
	if diary_class:
		host.register_view("DIARY", diary_class.new())

	# 5. Assemble realistic raw district state telemetry
	var raw_district_state: Dictionary = {
		"district_id": "DIST_EAST_DOCKS",
		"district_name": "East Docks Catchment",
		"jurisdiction_name": "Greater Municipal Harbor",
		"is_public_landmark": false,
		"active_population": 4850,
		"total_households": 1240,
		"occupied_households": 1110,
		"disposable_income": 42.50,
		"employment_rate": 0.86,
		"unemployment_rate": 0.14,
		"actual_police_heat": 0.32,
		"zone_health_index": 54.0,
		"establishments_summary": [
			{
				"establishment_id": 1,
				"name": "St. Jude's Parish Church",
				"category_title": "Place of Worship",
				"worker_count": 2
			},
			{
				"establishment_id": 2,
				"name": "Anchor Iron Foundry",
				"category_title": "Industrial Works",
				"worker_count": 84
			},
			{
				"establishment_id": 3,
				"name": "Harbor Freight Clearing",
				"category_title": "Logistics Depot",
				"worker_count": 26
			}
		]
	}

	var player_context: Dictionary = {
		"home_district_id": "DIST_EAST_DOCKS",
		"intel_scores": {
			"DISTRICT:DIST_EAST_DOCKS": 85.0,
			"ESTABLISHMENT:1": 70.0,
			"ESTABLISHMENT:2": 70.0,
			"ESTABLISHMENT:3": 70.0
		},
		"current_sim_day": 12
	}

	# Run through the perception filter model to generate perceived tokens & entity records
	var perceived_payload: Dictionary = DistrictPerceptionFilterScript.filter_district_view(raw_district_state, player_context)

	# 6. Default to Dossier view and supply perceived data
	host.switch_to_domain("DOSSIER")
	host.update_active_view_data(perceived_payload)

	# 7. Listen to tab clicks to feed sample domain data dynamically
	host.route_changed.connect(func(domain_key: String) -> void:
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
