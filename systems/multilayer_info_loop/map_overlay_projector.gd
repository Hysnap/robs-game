# res://systems/multilayer_info_loop/map_overlay_projector.gd
class_name MapOverlayProjector
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const OrgMandateManagerScript = preload("res://systems/economy/org_mandate_manager.gd")
const ManagerAIResolverScript = preload("res://systems/economy/manager_ai_resolver.gd")

const MODULE_NAME := "map_overlays"

static var _profiles_cache: Dictionary = {}

## Clears cached overlay definitions (for test isolation or manifest reload)
static func reset_cache() -> void:
	_profiles_cache.clear()

## Loads map_overlay_profiles.json from the active scenario manifest
static func get_config() -> Dictionary:
	if not _profiles_cache.is_empty():
		return _profiles_cache
	assert(ScenarioManifestManagerScript.has_module(MODULE_NAME),
		"FATAL: [MapOverlayProjector] '%s' module not registered in active society manifest." % MODULE_NAME)
	var parsed: Dictionary = ScenarioManifestManagerScript.load_module(MODULE_NAME)
	assert(parsed.has("overlays") and parsed["overlays"] is Array,
		"FATAL: [MapOverlayProjector] '%s' module missing 'overlays' array." % MODULE_NAME)
	assert(parsed.has("visual_states") and parsed["visual_states"] is Dictionary,
		"FATAL: [MapOverlayProjector] '%s' module missing 'visual_states' dictionary." % MODULE_NAME)
	_profiles_cache = parsed
	return _profiles_cache

## Returns ordered list of overlay descriptors [{ id, label_token, mode }] for UI selector buttons
static func get_available_overlays() -> Array[Dictionary]:
	var cfg: Dictionary = get_config()
	var result: Array[Dictionary] = []
	for item in cfg.get("overlays", []):
		if item is Dictionary and not str(item.get("id", "")).is_empty():
			result.append({
				"id": str(item["id"]),
				"label_token": str(item.get("label_token", "UI_OVERLAY_NONE")),
				"mode": str(item.get("mode", "NONE"))
			})
	return result

## Resolves a single overlay profile dictionary by ID (asserts if unknown)
static func get_overlay_profile(overlay_id: String) -> Dictionary:
	var cfg: Dictionary = get_config()
	var target_id: String = overlay_id.strip_edges().to_upper()
	if target_id.is_empty():
		target_id = str(cfg.get("default_overlay_id", "NONE")).to_upper()

	for item in cfg.get("overlays", []):
		if item is Dictionary and str(item.get("id", "")).to_upper() == target_id:
			return item

	assert(false, "FATAL: [MapOverlayProjector] Unknown overlay_id '%s'." % overlay_id)
	return {}

## Projects perceived district views + active org mandates into normalized render states and legend entries
static func project_city_overlay(
	overlay_id: String,
	perceived_district_views: Dictionary,
	world_state: Dictionary = {}
) -> Dictionary:
	var cfg: Dictionary = get_config()
	var profile: Dictionary = get_overlay_profile(overlay_id)
	var resolved_id: String = str(profile.get("id", "NONE"))
	var mode: String = str(profile.get("mode", "NONE")).to_upper()
	var visual_states: Dictionary = cfg.get("visual_states", {})

	var district_overlays: Dictionary = {}
	var has_any_stale: bool = false
	var has_any_unexplored: bool = false
	var has_any_overlap: bool = false

	var sorted_ids: Array = perceived_district_views.keys()
	sorted_ids.sort()

	for d_key in sorted_ids:
		var district_id: String = str(d_key)
		var view = perceived_district_views[d_key]
		if not (view is Dictionary):
			continue

		var projected: Dictionary = _project_single_district(
			district_id,
			view,
			profile,
			visual_states,
			cfg,
			world_state
		)
		district_overlays[district_id] = projected

		var st: String = str(projected.get("state", ""))
		if st == "UNEXPLORED" or st == "MASKED_TIER":
			has_any_unexplored = true
		elif st == "STALE":
			has_any_stale = true
		if str(projected.get("pattern_mode", "")) == "CONFLICT_STRIPE":
			has_any_overlap = true

	var legend_entries: Array[Dictionary] = _build_legend_entries(
		profile,
		visual_states,
		has_any_stale,
		has_any_unexplored,
		has_any_overlap
	)

	return {
		"overlay_id": resolved_id,
		"label_token": str(profile.get("label_token", "UI_OVERLAY_NONE")),
		"mode": mode,
		"districts": district_overlays,
		"legend": legend_entries
	}

static func _project_single_district(
	district_id: String,
	view: Dictionary,
	profile: Dictionary,
	visual_states: Dictionary,
	cfg: Dictionary,
	world_state: Dictionary
) -> Dictionary:
	var mode: String = str(profile.get("mode", "NONE")).to_upper()
	if mode == "NONE":
		return {
			"district_id": district_id,
			"overlay_id": str(profile.get("id", "NONE")),
			"active": false,
			"state": "NONE",
			"fill_color": Color(1.0, 1.0, 1.0, 0.0),
			"fill_alpha": 0.0,
			"pattern_mode": "NONE",
			"value_token": "",
			"badge_text": ""
		}

	var is_known: bool = bool(view.get("is_known", false))
	var intel_score: float = float(view.get("intel_score", 0.0))
	var intel_status: String = str(view.get("intel_status_token", view.get("intel_status", "INTEL_STATUS_UNEXPLORED")))
	var is_stale: bool = (intel_status == "INTEL_STATUS_STALE")

	# Mode 1: Intelligence Coverage & Freshness (works even on unexplored districts)
	if mode == "INTEL_STATUS":
		var status_colors: Dictionary = profile.get("status_colors", {})
		var hex: String = str(status_colors.get(intel_status, visual_states.get("UNEXPLORED", {}).get("fill_color", "#2b303a")))
		var base_col := Color.html(hex)
		var state_name := "UNEXPLORED" if not is_known else ("STALE" if is_stale else "VERIFIED")
		var pattern := "FOG_HATCH" if not is_known else ("STALE_STRIPE" if is_stale else "NONE")
		var alpha := 0.58 if not is_known else (0.44 if is_stale else clampf(0.32 + (intel_score / 100.0) * 0.30, 0.32, 0.62))
		var age_days: int = int(view.get("intel_age_days", -1))
		var badge := ""
		if is_known:
			badge = "%d%%" % int(round(intel_score))
			if age_days > 0:
				badge += " (%dd)" % age_days
		return {
			"district_id": district_id,
			"overlay_id": str(profile.get("id", "INTEL_COVERAGE")),
			"active": true,
			"state": state_name,
			"fill_color": base_col,
			"fill_alpha": alpha,
			"pattern_mode": pattern,
			"value_token": intel_status,
			"badge_text": badge
		}

	# Mode 2: Organizational Mandate Jurisdiction & Turf Overlaps
	if mode == "ORG_MANDATE_COVERAGE":
		return _project_org_jurisdiction(district_id, profile, visual_states, cfg, world_state)

	# Mode 3: Perceived Telemetry Bucket Choropleth / Heatmap (strictly gated by Fog-of-War & Intel Score)
	var min_score: float = float(profile.get("min_intel_score", 20.0))
	if not is_known:
		var unexp_cfg: Dictionary = visual_states.get("UNEXPLORED", {})
		return {
			"district_id": district_id,
			"overlay_id": str(profile.get("id", "")),
			"active": true,
			"state": "UNEXPLORED",
			"fill_color": Color.html(str(unexp_cfg.get("fill_color", "#2b303a"))),
			"fill_alpha": float(unexp_cfg.get("fill_alpha", 0.58)),
			"pattern_mode": str(unexp_cfg.get("pattern_mode", "FOG_HATCH")),
			"value_token": "INTEL_STATUS_UNEXPLORED",
			"badge_text": ""
		}

	var source_field: String = str(profile.get("source_field", ""))
	var raw_token: String = str(view.get(source_field, "UI_INTEL_MASKED_BLANK"))
	if intel_score < min_score or raw_token.is_empty() or raw_token == "UI_INTEL_MASKED_BLANK":
		var masked_cfg: Dictionary = visual_states.get("MASKED_TIER", {})
		return {
			"district_id": district_id,
			"overlay_id": str(profile.get("id", "")),
			"active": true,
			"state": "MASKED_TIER",
			"fill_color": Color.html(str(masked_cfg.get("fill_color", "#4b5563"))),
			"fill_alpha": float(masked_cfg.get("fill_alpha", 0.45)),
			"pattern_mode": str(masked_cfg.get("pattern_mode", "FOG_HATCH")),
			"value_token": "UI_INTEL_MASKED_BLANK",
			"badge_text": ""
		}

	var bucket_colors: Dictionary = profile.get("bucket_colors", {})
	var bucket_hex: String = str(bucket_colors.get(raw_token, profile.get("default_color", "#64748b")))
	var color := Color.html(bucket_hex)

	if is_stale:
		var stale_cfg: Dictionary = visual_states.get("STALE_MODIFIER", {})
		var desat: float = clampf(float(stale_cfg.get("desaturate_ratio", 0.45)), 0.0, 1.0)
		var luma: float = color.get_luminance()
		color = color.lerp(Color(luma, luma, luma, color.a), desat)
		var age_d: int = int(view.get("intel_age_days", -1))
		return {
			"district_id": district_id,
			"overlay_id": str(profile.get("id", "")),
			"active": true,
			"state": "STALE",
			"fill_color": color,
			"fill_alpha": float(stale_cfg.get("fill_alpha", 0.42)),
			"pattern_mode": str(stale_cfg.get("pattern_mode", "STALE_STRIPE")),
			"value_token": raw_token,
			"badge_text": "%dd" % age_d if age_d > 0 else ""
		}

	var verified_cfg: Dictionary = visual_states.get("VERIFIED_MODIFIER", {})
	return {
		"district_id": district_id,
		"overlay_id": str(profile.get("id", "")),
		"active": true,
		"state": "VERIFIED",
		"fill_color": color,
		"fill_alpha": float(verified_cfg.get("fill_alpha", 0.52)),
		"pattern_mode": str(verified_cfg.get("pattern_mode", "NONE")),
		"value_token": raw_token,
		"badge_text": ""
	}

static func _project_org_jurisdiction(
	district_id: String,
	profile: Dictionary,
	visual_states: Dictionary,
	cfg: Dictionary,
	world_state: Dictionary
) -> Dictionary:
	var mandates: Dictionary = world_state.get("org_mandates", {})
	var residents: Dictionary = world_state.get("residents", {})
	var palette: Array = cfg.get("jurisdiction_palette", ["#2563eb"])

	var matching_mandates: Array[Dictionary] = []
	var sorted_m_keys: Array = mandates.keys()
	sorted_m_keys.sort()

	for m_key in sorted_m_keys:
		var m = mandates[m_key]
		if not (m is Dictionary) or not bool(m.get("is_active", true)):
			continue
		var scope_filter: Dictionary = m.get("scope_filter", {})
		if OrgMandateManagerScript.matches_scope(scope_filter, {"district_id": district_id}):
			matching_mandates.append(m)

	if matching_mandates.is_empty():
		return {
			"district_id": district_id,
			"overlay_id": str(profile.get("id", "ORG_JURISDICTION")),
			"active": true,
			"state": "UNASSIGNED",
			"fill_color": Color.html(str(profile.get("unassigned_color", "#64748b"))),
			"fill_alpha": float(profile.get("unassigned_alpha", 0.22)),
			"pattern_mode": "NONE",
			"value_token": "UI_OVERLAY_LEGEND_UNASSIGNED_TURF",
			"badge_text": ""
		}

	var primary: Dictionary = matching_mandates[0]
	var mgr_id: int = int(primary.get("manager_resident_id", 0))
	var color_idx: int = absi(mgr_id if mgr_id > 0 else int(primary.get("mandate_id", 0))) % maxi(1, palette.size())
	var base_color := Color.html(str(palette[color_idx]))

	if matching_mandates.size() == 1:
		var owner_label := _resolve_mandate_owner_short_name(primary, residents)
		return {
			"district_id": district_id,
			"overlay_id": str(profile.get("id", "ORG_JURISDICTION")),
			"active": true,
			"state": "ASSIGNED",
			"fill_color": base_color,
			"fill_alpha": 0.48,
			"pattern_mode": "NONE",
			"value_token": "UI_OVERLAY_LEGEND_ASSIGNED_TURF",
			"badge_text": owner_label
		}

	# Multiple mandates overlap in this district -> evaluate dyadic collision outcome
	var overlap_cfg: Dictionary = visual_states.get("OVERLAP_MODIFIER", {})
	var res_a: Dictionary = residents.get(int(matching_mandates[0].get("manager_resident_id", 0)), {})
	var res_b: Dictionary = residents.get(int(matching_mandates[1].get("manager_resident_id", 0)), {})
	var collision: Dictionary = ManagerAIResolverScript.resolve_dyadic_mandate_collision(
		res_a, matching_mandates[0], res_b, matching_mandates[1]
	)
	var outcome_tok: String = str(collision.get("outcome", "FRICTIONAL_OVERLAP"))
	return {
		"district_id": district_id,
		"overlay_id": str(profile.get("id", "ORG_JURISDICTION")),
		"active": true,
		"state": "OVERLAP",
		"fill_color": base_color,
		"fill_alpha": 0.56,
		"pattern_mode": str(overlap_cfg.get("pattern_mode", "CONFLICT_STRIPE")),
		"value_token": outcome_tok,
		"badge_text": "%dx" % matching_mandates.size()
	}

static func _resolve_mandate_owner_short_name(mandate: Dictionary, residents: Dictionary) -> String:
	var target_org: String = str(mandate.get("target_org_id", "")).strip_edges()
	if not target_org.is_empty():
		return target_org.trim_prefix("ORG:")
	var mgr_id: int = int(mandate.get("manager_resident_id", 0))
	if mgr_id > 0 and residents.has(mgr_id) and residents[mgr_id] is Dictionary:
		var rec: Dictionary = residents[mgr_id]
		var full_name: String = str(rec.get("name", "")).strip_edges()
		if not full_name.is_empty():
			return full_name.split(" ")[0]
	return str(mandate.get("title", ""))

static func _build_legend_entries(
	profile: Dictionary,
	visual_states: Dictionary,
	has_any_stale: bool,
	has_any_unexplored: bool,
	has_any_overlap: bool
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for raw_item in profile.get("legend", []):
		if raw_item is Dictionary:
			entries.append({
				"color": Color.html(str(raw_item.get("color", "#64748b"))),
				"pattern_mode": str(raw_item.get("pattern_mode", "NONE")),
				"label_token": str(raw_item.get("label_token", ""))
			})

	var mode: String = str(profile.get("mode", "NONE")).to_upper()
	if mode == "PERCEIVED_BUCKET":
		if has_any_stale:
			var stale_cfg: Dictionary = visual_states.get("STALE_MODIFIER", {})
			entries.append({
				"color": Color.html("#94a3b8"),
				"pattern_mode": str(stale_cfg.get("pattern_mode", "STALE_STRIPE")),
				"label_token": str(stale_cfg.get("legend_token", "UI_OVERLAY_LEGEND_STALE_DATA"))
			})
		if has_any_unexplored:
			var unexp_cfg: Dictionary = visual_states.get("UNEXPLORED", {})
			entries.append({
				"color": Color.html(str(unexp_cfg.get("fill_color", "#2b303a"))),
				"pattern_mode": str(unexp_cfg.get("pattern_mode", "FOG_HATCH")),
				"label_token": str(unexp_cfg.get("legend_token", "UI_OVERLAY_LEGEND_UNEXPLORED"))
			})
	elif mode == "ORG_MANDATE_COVERAGE" and has_any_overlap:
		var ov_cfg: Dictionary = visual_states.get("OVERLAP_MODIFIER", {})
		var already_has_overlap := false
		for e in entries:
			if str(e.get("pattern_mode", "")) == "CONFLICT_STRIPE":
				already_has_overlap = true
				break
		if not already_has_overlap:
			entries.append({
				"color": Color.html("#d97706"),
				"pattern_mode": str(ov_cfg.get("pattern_mode", "CONFLICT_STRIPE")),
				"label_token": str(ov_cfg.get("legend_token", "UI_OVERLAY_LEGEND_TURF_OVERLAP"))
			})

	return entries