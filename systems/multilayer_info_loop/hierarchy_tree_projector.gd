# res://systems/multilayer_info_loop/hierarchy_tree_projector.gd
class_name HierarchyTreeProjector
extends RefCounted

const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")
const ManagerAIResolverScript = preload("res://systems/economy/manager_ai_resolver.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")

const INDIVIDUAL_DRILLDOWN_MIN_INTEL := 60.0
const DEFAULT_STALE_DAYS := 28

## Resolves stale_decay_threshold_days from fog_of_war config
static func _get_stale_threshold_days() -> int:
	if ScenarioManifestManagerScript.has_module("fog_of_war"):
		var fow: Dictionary = ScenarioManifestManagerScript.load_module("fog_of_war")
		return int(fow.get("general", {}).get("stale_decay_threshold_days", DEFAULT_STALE_DAYS))
	return DEFAULT_STALE_DAYS

## Builds a normalized hierarchy node dictionary
static func _make_node(
	node_id: String,
	parent_id: String,
	depth: int,
	node_type: String,
	entity_scope: String,
	entity_id: String,
	label_text: String,
	sublabel_text: String = "",
	badge_token: String = "",
	detail_route: String = "",
	drillable: bool = true,
	metrics: Dictionary = {},
	feedback_digests: Array[String] = []
) -> Dictionary:
	return {
		"node_id": node_id,
		"parent_id": parent_id,
		"depth": depth,
		"node_type": node_type, # "KNOWN" | "STALE" | "TBC_BRIDGE" | "TBC_LEAF"
		"entity_scope": entity_scope,
		"entity_id": entity_id,
		"label_text": label_text,
		"sublabel_text": sublabel_text,
		"badge_token": badge_token,
		"detail_route": detail_route,
		"drillable": drillable,
		"metrics": metrics,
		"feedback_digests": feedback_digests,
		"children": []
	}

## 1. PLAYER ORG & PERSONNEL ROLL-UP TREE (Collated performance + aged-data & visibility gating)
static func project_player_org_tree(
	world_state: Dictionary,
	player_context: Dictionary,
	root_org_id: String = "ORG:CREW_ENTERPRISE"
) -> Dictionary:
	var current_day: int = CalendarHelperScript.get_current_sim_day(world_state)
	var stale_limit: int = _get_stale_threshold_days()
	var observers: Array = player_context.get("observers", [])

	var orgs: Dictionary = world_state.get("organizations", {})
	var residents: Dictionary = world_state.get("residents", {})
	var mandates: Dictionary = world_state.get("org_mandates", {})

	var root_org: Dictionary = orgs.get(root_org_id, {}) if orgs.get(root_org_id, null) is Dictionary else {}
	var root_name: String = str(root_org.get("display_name", world_state.get("operations", {}).get("enterprise_name", root_org_id)))

	# Collect active crew residents keyed by integer resident_id
	var crew_by_id: Dictionary = {}
	var unassigned_crew: Array[Dictionary] = []
	for r_key in residents.keys():
		var rec = residents[r_key]
		if not (rec is Dictionary) or not bool(rec.get("is_crew", true)):
			continue
		var r_id: int = int(rec.get("resident_id", 0))
		if r_id <= 0 or crew_by_id.has(r_id):
			continue
		crew_by_id[r_id] = rec

	# Collect active mandates belonging to root_org_id
	var active_mandates: Array[Dictionary] = []
	var manager_ids: Dictionary = {}
	var sub_org_ids: Dictionary = {}
	for m_key in mandates.keys():
		var m = mandates[m_key]
		if not (m is Dictionary) or not bool(m.get("is_active", true)):
			continue
		if str(m.get("org_id", "")) != root_org_id:
			continue
		active_mandates.append(m)
		var mgr_id: int = int(m.get("manager_resident_id", 0))
		if mgr_id > 0:
			manager_ids[mgr_id] = m
		var tgt_org: String = str(m.get("target_org_id", "")).strip_edges()
		if not tgt_org.is_empty():
			sub_org_ids[tgt_org] = m

	# Partition crew into manager cohorts vs. direct HQ operatives
	var subordinates_by_manager: Dictionary = {}
	for r_id in crew_by_id.keys():
		var rec: Dictionary = crew_by_id[r_id]
		var sup_id: int = int(rec.get("reports_to_resident_id", 0))
		if sup_id > 0 and manager_ids.has(sup_id):
			if not subordinates_by_manager.has(sup_id):
				subordinates_by_manager[sup_id] = []
			subordinates_by_manager[sup_id].append(rec)
		elif not manager_ids.has(r_id):
			unassigned_crew.append(rec)

	var root_node: Dictionary = _make_node(
		root_org_id,
		"",
		0,
		"KNOWN",
		"ORG",
		root_org_id,
		root_name,
		"",
		"INTEL_STATUS_VERIFIED",
		"ORG_NODE_SELECTED",
		true
	)

	# Build Manager / Mandate Branch Nodes
	var sorted_mgr_ids: Array = manager_ids.keys()
	sorted_mgr_ids.sort()
	for mgr_id in sorted_mgr_ids:
		var mandate: Dictionary = manager_ids[mgr_id]
		var mgr_rec: Dictionary = crew_by_id.get(mgr_id, residents.get(str(mgr_id), {}))
		var mgr_name: String = str(mgr_rec.get("name", "RESIDENT:%d" % mgr_id))
		var subs: Array = subordinates_by_manager.get(mgr_id, [])

		var intel_info: Dictionary = IntelManagerScript.get_collective_intel_status(
			world_state, observers, "RESIDENT", str(mgr_id)
		)
		var mgr_score: float = float(intel_info.get("score", 100.0 if crew_by_id.has(mgr_id) else 0.0))
		var mgr_age: int = int(intel_info.get("age_days", 0))
		var is_stale: bool = (mgr_score < INDIVIDUAL_DRILLDOWN_MIN_INTEL) or (mgr_age > stale_limit)

		var cohort_metrics: Dictionary = _aggregate_personnel_metrics(subs, mgr_rec, mandate)
		var digests: Array[String] = _build_manager_feedback_digests(world_state, mgr_rec, mandate, cohort_metrics, subs.size(), is_stale, mgr_age)

		var badge_tok: String = "UI_INTEL_STALE_REPORT" if is_stale else "INTEL_STATUS_VERIFIED"
		var sublabel: String = "%s • %d staff • Loyalty %.0f%%" % [
			str(mandate.get("title", "")),
			int(cohort_metrics.get("headcount", 0)),
			float(cohort_metrics.get("mean_loyalty", 1.0)) * 100.0
		]
		if is_stale and mgr_age > 0:
			sublabel += " • %dd" % mgr_age

		var mgr_node: Dictionary = _make_node(
			"MGR:%d" % mgr_id,
			root_org_id,
			1,
			"STALE" if is_stale else "KNOWN",
			"RESIDENT",
			str(mgr_id),
			mgr_name,
			sublabel,
			badge_tok,
			"OPERATIVE_DETAIL",
			not is_stale,
			cohort_metrics,
			digests
		)

		# Aged-data & visibility rule: individual subordinates only exposed when intel >= 60 AND fresh
		if not is_stale:
			for sub_rec in subs:
				var s_id: int = int(sub_rec.get("resident_id", 0))
				var s_name: String = str(sub_rec.get("name", str(s_id)))
				var s_fatigue: float = float(sub_rec.get("fatigue", 0.0))
				var s_loyalty: float = float(sub_rec.get("loyalty", 0.75))
				var s_node: Dictionary = _make_node(
					"RES:%d" % s_id,
					mgr_node["node_id"],
					2,
					"KNOWN",
					"RESIDENT",
					str(s_id),
					s_name,
					"Loyalty %.0f%% • Fatigue %.0f%%" % [s_loyalty * 100.0, s_fatigue * 100.0],
					"INTEL_STATUS_VERIFIED",
					"OPERATIVE_DETAIL",
					true,
					{"headcount": 1, "mean_loyalty": s_loyalty, "mean_fatigue": s_fatigue}
				)
				mgr_node["children"].append(s_node)
		elif not subs.is_empty():
			# Collapsed cohort bucket when aged or moderate intel prevents individual drill-down
			var tbc_cohort: Dictionary = _make_node(
				"COHORT_MASKED:%d" % mgr_id,
				mgr_node["node_id"],
				2,
				"TBC_LEAF",
				"COHORT",
				str(mgr_id),
				"UI_HIERARCHY_TBC_COHORT_BUCKET",
				"%d operatives (Stale / Limited Visibility)" % subs.size(),
				"UI_INTEL_STALE_REPORT",
				"",
				false,
				cohort_metrics
			)
			mgr_node["children"].append(tbc_cohort)

		root_node["children"].append(mgr_node)

	# Build ARMS_LENGTH Subsidiary Org Nodes
	var sorted_sub_orgs: Array = sub_org_ids.keys()
	sorted_sub_orgs.sort()
	for sub_org_id in sorted_sub_orgs:
		var mandate: Dictionary = sub_org_ids[sub_org_id]
		var sub_org: Dictionary = orgs.get(sub_org_id, {}) if orgs.get(sub_org_id, null) is Dictionary else {}
		var org_title: String = str(sub_org.get("display_name", sub_org_id))
		var intel_info: Dictionary = IntelManagerScript.get_collective_intel_status(world_state, observers, "ORG", sub_org_id)
		var org_score: float = float(intel_info.get("score", 50.0))
		var org_age: int = int(intel_info.get("age_days", 0))
		var is_stale: bool = (org_score < INDIVIDUAL_DRILLDOWN_MIN_INTEL) or (org_age > stale_limit)

		var org_metrics: Dictionary = {
			"headcount": int(sub_org.get("headcount", 0)),
			"mean_loyalty": float(sub_org.get("loyalty", 0.75)),
			"mean_fatigue": 0.0,
			"police_heat": float(sub_org.get("police_heat", 0.0)),
			"remittance_target": float(mandate.get("target_metrics", {}).get("remittance_target", 0.0))
		}
		var sub_node: Dictionary = _make_node(
			sub_org_id,
			root_org_id,
			1,
			"STALE" if is_stale else "KNOWN",
			"ORG",
			sub_org_id,
			org_title,
			"ARMS_LENGTH • Loyalty %.0f%% • Heat %.0f" % [float(org_metrics["mean_loyalty"]) * 100.0, float(org_metrics["police_heat"])],
			"UI_INTEL_STALE_REPORT" if is_stale else "INTEL_STATUS_VERIFIED",
			"ORG_NODE_SELECTED",
			not is_stale,
			org_metrics
		)
		root_node["children"].append(sub_node)

	# Direct HQ Operatives (not assigned under a regional manager)
	unassigned_crew.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("resident_id", 0)) < int(b.get("resident_id", 0))
	)
	for hq_rec in unassigned_crew:
		var r_id: int = int(hq_rec.get("resident_id", 0))
		var hq_node: Dictionary = _make_node(
			"RES:%d" % r_id,
			root_org_id,
			1,
			"KNOWN",
			"RESIDENT",
			str(r_id),
			str(hq_rec.get("name", str(r_id))),
			"HQ • Loyalty %.0f%% • Fatigue %.0f%%" % [
				float(hq_rec.get("loyalty", 0.85)) * 100.0,
				float(hq_rec.get("fatigue", 0.0)) * 100.0
			],
			"INTEL_STATUS_VERIFIED",
			"OPERATIVE_DETAIL",
			true,
			{
				"headcount": 1,
				"mean_loyalty": float(hq_rec.get("loyalty", 0.85)),
				"mean_fatigue": float(hq_rec.get("fatigue", 0.0))
			}
		)
		root_node["children"].append(hq_node)

	# Roll up enterprise-wide totals onto root_node
	var all_crew_list: Array = crew_by_id.values()
	root_node["metrics"] = _aggregate_personnel_metrics(all_crew_list, {}, {})
	root_node["sublabel_text"] = "%d Total Operatives • %d Active Mandates • Day %d" % [
		all_crew_list.size(),
		active_mandates.size(),
		current_day
	]
	return root_node

## 2. EXTERNAL / RIVAL ORG TREE WITH TBC_BRIDGE CONTRACTION & SINGLE TBC_LEAF COLLAPSING
## Handles disjoint top + bottom intel by contracting contiguous unknown middle tiers into a single TBC_BRIDGE node.
static func project_external_org_tree(
	world_state: Dictionary,
	player_context: Dictionary,
	org_id: String,
	hierarchy_records: Array[Dictionary]
) -> Dictionary:
	var observers: Array = player_context.get("observers", [])
	var stale_limit: int = _get_stale_threshold_days()

	var org_intel: Dictionary = IntelManagerScript.get_collective_intel_status(world_state, observers, "ORG", org_id)
	var org_score: float = float(org_intel.get("score", 0.0))
	var org_known: bool = IntelManagerScript.is_entity_known(org_score, "ORG")
	var org_name: String = str(world_state.get("organizations", {}).get(org_id, {}).get("display_name", org_id if org_known else "UI_INTEL_UNKNOWN"))

	var root_node: Dictionary = _make_node(
		org_id,
		"",
		0,
		"KNOWN" if org_known else "TBC_LEAF",
		"ORG",
		org_id,
		org_name,
		"",
		"INTEL_STATUS_VERIFIED" if org_known else "INTEL_STATUS_UNEXPLORED",
		"ORG_NODE_SELECTED" if org_known else "",
		org_known
	)

	# Index raw hierarchy records by record_id and parent_record_id
	# Expected record shape: { "id": String, "parent_id": String, "scope": "RESIDENT"|"ESTABLISHMENT"|"ORG", "entity_id": String, "name": String, "role": String }
	var by_id: Dictionary = {}
	var children_map: Dictionary = {}
	var top_ids: Array[String] = []

	for rec in hierarchy_records:
		var rec_id: String = str(rec.get("id", "")).strip_edges()
		if rec_id.is_empty():
			continue
		var p_id: String = str(rec.get("parent_id", "")).strip_edges()
		var scope: String = str(rec.get("scope", "RESIDENT")).to_upper()
		var ent_id: String = str(rec.get("entity_id", rec_id)).strip_edges()

		var intel: Dictionary = IntelManagerScript.get_collective_intel_status(world_state, observers, scope, ent_id)
		var score: float = float(intel.get("score", 0.0))
		var age: int = int(intel.get("age_days", -1))
		var known: bool = IntelManagerScript.is_entity_known(score, scope)

		var enriched: Dictionary = rec.duplicate(true)
		enriched["_known"] = known
		enriched["_score"] = score
		enriched["_age"] = age
		enriched["_stale"] = known and ((score < 40.0) or (age > stale_limit))
		by_id[rec_id] = enriched

		if p_id.is_empty() or p_id == org_id:
			top_ids.append(rec_id)
		else:
			if not children_map.has(p_id):
				children_map[p_id] = []
			children_map[p_id].append(rec_id)

	var projected_top: Array[Dictionary] = _project_graph_level(
		top_ids,
		org_id,
		1,
		by_id,
		children_map,
		false
	)
	root_node["children"] = projected_top
	return root_node

## Recursively projects a graph level:
## - Known nodes emit directly and recurse normally.
## - Contiguous unknown middle nodes with known descendants contract into ONE single TBC_BRIDGE node.
## - Unknown siblings with NO known descendants collapse into ONE single TBC_LEAF node per level.
static func _project_graph_level(
	candidate_ids: Array,
	parent_node_id: String,
	depth: int,
	by_id: Dictionary,
	children_map: Dictionary,
	inside_unknown_bridge: bool
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var unknown_leaf_count: int = 0
	var bridged_known_descendants: Array[Dictionary] = []

	for raw_id in candidate_ids:
		var rec_id: String = str(raw_id)
		if not by_id.has(rec_id):
			continue
		var rec: Dictionary = by_id[rec_id]
		var child_ids: Array = children_map.get(rec_id, [])

		if bool(rec.get("_known", false)):
			var is_stale: bool = bool(rec.get("_stale", false))
			var scope: String = str(rec.get("scope", "RESIDENT")).to_upper()
			var ent_id: String = str(rec.get("entity_id", rec_id))
			var route: String = "ESTABLISHMENT_DOCKET" if scope == "ESTABLISHMENT" else ("ORG_NODE_SELECTED" if scope == "ORG" else "OPERATIVE_DETAIL")
			var node: Dictionary = _make_node(
				"%s:%s" % [scope, ent_id],
				parent_node_id,
				depth,
				"STALE" if is_stale else "KNOWN",
				scope,
				ent_id,
				str(rec.get("name", ent_id)),
				str(rec.get("role", "")),
				"UI_INTEL_STALE_REPORT" if is_stale else "INTEL_STATUS_VERIFIED",
				route,
				true
			)
			node["children"] = _project_graph_level(child_ids, node["node_id"], depth + 1, by_id, children_map, false)
			if inside_unknown_bridge:
				bridged_known_descendants.append(node)
			else:
				result.append(node)
		else:
			# Unknown node: check if ANY descendant beneath it is known
			var sub_projected: Array[Dictionary] = _project_graph_level(
				child_ids,
				parent_node_id,
				depth if inside_unknown_bridge else depth + 1,
				by_id,
				children_map,
				true
			)
			if sub_projected.is_empty():
				unknown_leaf_count += 1
			else:
				bridged_known_descendants.append_array(sub_projected)

	# If we are already inside a contiguous unknown middle chain, pass known descendants upward to be wrapped once
	if inside_unknown_bridge:
		return bridged_known_descendants

	# Wrap all known descendants reachable through unknown middle tiers in ONE single TBC_BRIDGE intermediary node
	if not bridged_known_descendants.is_empty():
		var bridge_id: String = "TBC_BRIDGE:%s:%d" % [parent_node_id, depth]
		var bridge_node: Dictionary = _make_node(
			bridge_id,
			parent_node_id,
			depth,
			"TBC_BRIDGE",
			"UNKNOWN",
			"",
			"UI_HIERARCHY_TBC_INTERMEDIARY",
			"UI_HIERARCHY_TBC_BRIDGE_SUB",
			"INTEL_STATUS_UNEXPLORED",
			"",
			true
		)
		for desc in bridged_known_descendants:
			desc["parent_id"] = bridge_id
			desc["depth"] = depth + 1
		bridge_node["children"] = bridged_known_descendants
		result.append(bridge_node)

	# Collapse all unknown leaf siblings at this level into ONE single generic TBC_LEAF node (never 1 per missing actor)
	if unknown_leaf_count > 0:
		var leaf_node: Dictionary = _make_node(
			"TBC_LEAF:%s:%d" % [parent_node_id, depth],
			parent_node_id,
			depth,
			"TBC_LEAF",
			"UNKNOWN",
			"",
			"UI_HIERARCHY_TBC_GENERIC",
			"",
			"INTEL_STATUS_UNEXPLORED",
			"",
			false
		)
		result.append(leaf_node)

	return result

static func _aggregate_personnel_metrics(subordinates: Array, manager_rec: Dictionary, mandate: Dictionary) -> Dictionary:
	var count: int = subordinates.size()
	var total_loyalty: float = 0.0
	var total_fatigue: float = 0.0
	for s in subordinates:
		if s is Dictionary:
			total_loyalty += float(s.get("loyalty", 0.75))
			total_fatigue += float(s.get("fatigue", 0.0))

	var mean_loyalty: float = (total_loyalty / float(count)) if count > 0 else float(manager_rec.get("loyalty", 0.85))
	var mean_fatigue: float = (total_fatigue / float(count)) if count > 0 else float(manager_rec.get("fatigue", 0.0))
	var target_metrics: Dictionary = mandate.get("target_metrics", {}) if mandate.get("target_metrics", null) is Dictionary else {}

	return {
		"headcount": count,
		"mean_loyalty": mean_loyalty,
		"mean_fatigue": mean_fatigue,
		"heat_ceiling": float(mandate.get("heat_ceiling", 0.65)),
		"remittance_target": float(target_metrics.get("remittance_target", 0.0)),
		"operating_float": float(target_metrics.get("operating_float", 0.0))
	}

static func _build_manager_feedback_digests(
	world_state: Dictionary,
	mgr_rec: Dictionary,
	mandate: Dictionary,
	cohort_metrics: Dictionary,
	sub_count: int,
	is_stale: bool,
	age_days: int
) -> Array[String]:
	var digests: Array[String] = []
	if mgr_rec.is_empty():
		return digests

	var span_eval: Dictionary = ManagerAIResolverScript.evaluate_span_of_control(mgr_rec, sub_count)
	if int(span_eval.get("overload_count", 0)) > 0:
		digests.append("UI_FEEDBACK_SPAN_OVERLOAD")

	var kpis: Dictionary = {
		"current_heat": float(mandate.get("current_heat", 0.0)),
		"target_attainment": float(mandate.get("target_attainment", 1.0)),
		"subordinate_escalations": 1 if float(cohort_metrics.get("mean_fatigue", 0.0)) > 0.75 else 0
	}
	var report_eval: Dictionary = ManagerAIResolverScript.evaluate_reporting_and_escalation(
		world_state, mgr_rec, mandate, kpis
	)
	var rep_tok: String = str(report_eval.get("report_token", ""))
	if not rep_tok.is_empty():
		digests.append(rep_tok)

	if is_stale and age_days > 0:
		digests.append("UI_INTEL_STALE_REPORT")

	return digests