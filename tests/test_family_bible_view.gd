# res://tests/test_family_bible_view.gd
extends SceneTree

const TEST_SOCIETY_FACTORY = preload("res://tests/test_society_factory.gd")
const CREW_SCOUT_BOOTSTRAPPER = preload("res://systems/society/crew_scout_bootstrapper.gd")
const INTEL_MANAGER = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const SOCIETY_QUERIES = preload("res://systems/society_queries.gd")
const DB_MANAGER = preload("res://systems/db_manager.gd")

func _init() -> void:
	print("=== RUNNING FAMILY BIBLE & GENEALOGY VIEW TEST SUITE ===")

	# 1. Generate deterministic society + scout starting crew
	var world_state: Dictionary = TEST_SOCIETY_FACTORY.create_test_world(2, 2, "family-bible-test-seed")
	var home_district: String = str(world_state.get("operations", {}).get("home_district_id", ""))
	assert(not home_district.is_empty(), "FAIL: Empty home_district_id from TestSocietyFactory.")

	var scouted: bool = CREW_SCOUT_BOOTSTRAPPER.scout_and_bind_starting_crew(world_state, home_district)
	assert(scouted, "FAIL: CrewScoutBootstrapper failed to bind starting crew.")

	var current_sim_day: int = int(world_state.get("metadata", {}).get("current_sim_day", 29219))
	var intel_ctx: Dictionary = INTEL_MANAGER.build_player_intel_context(world_state)

	# 2. Query Family Bible payload
	var payload: Dictionary = SOCIETY_QUERIES.get_crew_family_bible(intel_ctx, current_sim_day)
	var lineages: Array = payload.get("crew_lineages", [])
	var vitals: Array = payload.get("vital_records", [])

	assert(str(payload.get("document_title", "")) == "UI_HDR_FAMILY_BIBLE", "FAIL: Unexpected document_title.")
	assert(lineages.size() >= 3, "FAIL: Expected at least the 3 starting crew operatives in crew_lineages, got %d." % lineages.size())
	assert(vitals.size() >= 3, "FAIL: Expected at least 3 vital records, got %d." % vitals.size())

	# Verify deceased relatives are non-navigable (resident_id == 0)
	for entry in lineages:
		if str(entry.get("summary_line", "")).contains("– d."):
			assert(int(entry.get("resident_id", -1)) == 0, "FAIL: Deceased relative must have resident_id == 0.")

	# 3. Verify compiled GenFamilyBible view instantiation, bind_data(), and snapshot reset
	var view_script = load("res://generated/ui/core/gen_family_bible.gd")
	assert(view_script != null, "FAIL: Could not load compiled res://generated/ui/core/gen_family_bible.gd.")

	var view_instance = view_script.new()
	view_instance.bind_data(payload)
	view_instance.bind_data({})
	view_instance.free()

	DB_MANAGER.close_database()

	print("PASS [All Tests]: Family Bible query (%d lineage rows, %d vital records) and GenFamilyBible binding verified." % [
		lineages.size(), vitals.size()
	])
	quit(0)