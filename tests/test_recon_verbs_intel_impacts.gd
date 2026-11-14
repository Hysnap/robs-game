# res://tests/test_recon_verbs_intel_impacts.gd
extends SceneTree

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

func _init() -> void:
	print("\n--- [Test] Verifying End-to-End Recon & Social Verb INTEL_SCORE Impacts ---")

	ScenarioManifestManagerScript.reset_cache()
	IntelManagerScript.reset_cache()
	ImpactRouterScript.reset()
	ImpactRouterScript.autoload_sinks("res://data_modules/core/impacts/")
	VerbRouterScript.initialize()

	assert(ImpactRouterScript.has_sink("INTEL_SCORE"), "FAIL: INTEL_SCORE sink not mounted.")

	var passed: bool = true
	passed = passed and _test_all_four_verbs_end_to_end()

	if passed:
		print("--- [Test] ALL RECON & SOCIAL VERB INTEL IMPACTS VERIFIED ---\n")
		quit(0)
	else:
		printerr("--- [Test] RECON & SOCIAL VERB INTEL IMPACTS FAILED ---\n")
		quit(1)

func _test_all_four_verbs_end_to_end() -> bool:
	var ws: Dictionary = {
		"metadata": {"current_sim_day": 100},
		"knowledge_pools": {},
		"residents": {
			"op_01": {
				"name": "Mick Jenkins",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {"CASH": 100.0}
			},
			"res_contact_01": {
				"name": "Father O'Malley",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {}
			},
			"res_handler_01": {
				"name": "Handler Vance",
				"current_district_id": "DISTRICT_MARKET",
				"inventory": {}
			}
		},
		"establishments": {
			"estab_pub_01": {
				"name": "The Garrison Pub",
				"district_id": "DISTRICT_MARKET",
				"inventory": {"CASH": 250.0}
			}
		},
		"caches": {},
		"districts": {
			"DISTRICT_MARKET": {}
		}
	}

	# 1. SCOUT (District-level reconnaissance + secondary establishment sweep)
	var scout_res: Dictionary = SimControllerScript.execute_directive(ws, {
		"verb": "SCOUT",
		"assigned_to": "op_01",
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 2.0,
		"secondary_targets": [
			{"target_scope": "ESTABLISHMENT", "target_id": "estab_pub_01", "effort_ratio": 0.45}
		]
	})
	if not scout_res.get("success", false):
		printerr("FAIL [1/4]: SCOUT directive failed: ", scout_res.get("message"))
		return false

	var dist_score: float = IntelManagerScript.get_direct_score(ws, "RESIDENT", "op_01", "DISTRICT", "DISTRICT_MARKET")
	var swept_pub_score: float = IntelManagerScript.get_direct_score(ws, "RESIDENT", "op_01", "ESTABLISHMENT", "estab_pub_01")
	if dist_score <= 0.0 or swept_pub_score <= 0.0:
		printerr("FAIL [1/4]: SCOUT did not populate knowledge_pools (district=%.2f, pub=%.2f)." % [dist_score, swept_pub_score])
		return false
	print("  [PASS 1/4] SCOUT populated DISTRICT_MARKET=%.2f and swept estab_pub_01=%.2f." % [dist_score, swept_pub_score])

	# 2. INVESTIGATE (Focused establishment surveillance raises score above swept baseline)
	var inv_res: Dictionary = SimControllerScript.execute_directive(ws, {
		"verb": "INVESTIGATE",
		"assigned_to": "op_01",
		"target_entity_id": "estab_pub_01",
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 2.0
	})
	if not inv_res.get("success", false):
		printerr("FAIL [2/4]: INVESTIGATE directive failed: ", inv_res.get("message"))
		return false

	var post_inv_pub_score: float = IntelManagerScript.get_direct_score(ws, "RESIDENT", "op_01", "ESTABLISHMENT", "estab_pub_01")
	if post_inv_pub_score <= swept_pub_score:
		printerr("FAIL [2/4]: INVESTIGATE did not increase establishment score (before=%.2f, after=%.2f)." % [swept_pub_score, post_inv_pub_score])
		return false
	print("  [PASS 2/4] INVESTIGATE increased estab_pub_01 score from %.2f to %.2f." % [swept_pub_score, post_inv_pub_score])

	# 3. COMMUNICATE (Interpersonal probing builds dossier on target resident)
	var comm_res: Dictionary = SimControllerScript.execute_directive(ws, {
		"verb": "COMMUNICATE",
		"assigned_to": "op_01",
		"target_resident_id": "res_contact_01",
		"target_node_id": "DISTRICT_MARKET",
		"duration_ticks": 2.0
	})
	if not comm_res.get("success", false):
		printerr("FAIL [3/4]: COMMUNICATE directive failed: ", comm_res.get("message"))
		return false

	var contact_score: float = IntelManagerScript.get_direct_score(ws, "RESIDENT", "op_01", "RESIDENT", "res_contact_01")
	if contact_score <= 0.0:
		printerr("FAIL [3/4]: COMMUNICATE did not populate resident dossier score.")
		return false
	print("  [PASS 3/4] COMMUNICATE populated res_contact_01 dossier score=%.2f." % contact_score)

	# 4. INFORM (Compartmentalized transfer of establishment intel from op_01 to res_handler_01)
	var handler_before: float = IntelManagerScript.get_direct_score(ws, "RESIDENT", "res_handler_01", "ESTABLISHMENT", "estab_pub_01")
	assert(handler_before == 0.0, "FAIL: Handler should start with 0.0 score.")

	var inform_res: Dictionary = SimControllerScript.execute_directive(ws, {
		"verb": "INFORM",
		"assigned_to": "op_01",
		"target_resident_id": "res_handler_01",
		"target_node_id": "DISTRICT_MARKET",
		"subject_scope": "ESTABLISHMENT",
		"subject_id": "estab_pub_01",
		"duration_ticks": 1.0
	})
	if not inform_res.get("success", false):
		printerr("FAIL [4/4]: INFORM directive failed: ", inform_res.get("message"))
		return false

	var handler_after: float = IntelManagerScript.get_direct_score(ws, "RESIDENT", "res_handler_01", "ESTABLISHMENT", "estab_pub_01")
	if handler_after <= 0.0 or handler_after >= post_inv_pub_score:
		printerr("FAIL [4/4]: INFORM transfer out of bounds (handler=%.2f, source=%.2f)." % [handler_after, post_inv_pub_score])
		return false
	print("  [PASS 4/4] INFORM transferred estab_pub_01 intel to res_handler_01 (%.2f -> %.2f, source=%.2f)." % [handler_before, handler_after, post_inv_pub_score])

	return true