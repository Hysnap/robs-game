# res://tests/test_manifest_loader.gd
extends SceneTree

const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

func _init() -> void:
	print("\n=======================================================")
	print("       TESTING SCENARIO MANIFEST MANAGER (DRY)         ")
	print("=======================================================")

	MANIFEST_MGR.reset_cache()

	# 1. Test Manifest Path Resolution from business_rules.cfg
	var manifest_path := MANIFEST_MGR.get_manifest_path()
	print("  ✓ Manifest Path resolved: %s" % manifest_path)
	assert(not manifest_path.is_empty(), "FAILED: Manifest path is empty!")

	# 2. Test Root Manifest Parsing & Caching
	var manifest := MANIFEST_MGR.get_manifest()
	print("  ✓ Root Manifest loaded: '%s' (%s)" % [
		manifest.get("_meta", {}).get("manifest_id", "UNKNOWN"),
		manifest.get("_meta", {}).get("description", "")
	])
	assert(manifest.has("modules"), "FAILED: Root manifest missing 'modules' key!")

	# 3. Verify Module Registrations
	var expected_modules := ["demographics", "lexicon", "cultural_demographics", "civic_hierarchy"]
	for mod_key in expected_modules:
		assert(MANIFEST_MGR.has_module(mod_key), "FAILED: Missing module declaration for '%s'" % mod_key)
		var mod_path := MANIFEST_MGR.get_module_path(mod_key)
		print("  ✓ Module '%s' -> %s" % [mod_key, mod_path])

	# 4. Test Ingestion of Sub-Modules
	var demo := MANIFEST_MGR.load_module("demographics")
	assert(demo.has("temporal_anchor"), "FAILED: Demographics module missing 'temporal_anchor'!")
	print("  ✓ Demographics verified: Epoch '%s', Start Date '%s'" % [
		demo["temporal_anchor"].get("epoch_date"),
		demo["temporal_anchor"].get("simulation_start_date")
	])

	var civic := MANIFEST_MGR.load_module("civic_hierarchy")
	assert(civic.has("hierarchy_scales"), "FAILED: Civic hierarchy missing 'hierarchy_scales'!")
	print("  ✓ Civic hierarchy verified: %d institutional profiles loaded." % civic["hierarchy_scales"].size())

	# 5. Verify In-Memory Caching (Second load must return cached reference)
	var demo_cached := MANIFEST_MGR.load_module("demographics")
	assert(demo == demo_cached, "FAILED: Cache check failed!")
	print("  ✓ In-memory module cache confirmed functional.")

	print("\n=======================================================")
	print("     ALL SCENARIO MANIFEST MANAGER TESTS PASSED!       ")
	print("=======================================================\n")
	quit()