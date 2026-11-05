# res://tools/commodity_access_auditor.gd
class_name CommodityAccessAuditor
extends RefCounted

## Developer diagnostic tool: Audits whether an item is available at a venue and returns
## the exact authorization trail and authoring JSON file.
static func audit_commodity_availability(
	commodity_id: String, 
	venue_data: Dictionary, 
	world_state: Dictionary, 
	check_off_book: bool = false
) -> Dictionary:
	var registry: Dictionary = world_state.get("commodity_registry", {})
	if not registry.has(commodity_id):
		return {
			"commodity_id": commodity_id,
			"venue_archetype": str(venue_data.get("archetype", "")),
			"is_available": false,
			"access_tier": "NONE",
			"matched_role": "",
			"authorizing_file": "",
			"permitted_containers": [],
			"debug_override_active": false,
			"audit_trace": "Commodity '%s' does not exist in commodity_registry." % commodity_id
		}

	var item: Dictionary = registry[commodity_id]
	var debug_rules: Dictionary = world_state.get("debug_rules", {})
	var is_debug_override: bool = bool(debug_rules.get("all_items_in_all_stores", false))

	# 1. Check Debug Bypass
	if is_debug_override:
		return {
			"commodity_id": commodity_id,
			"venue_archetype": str(venue_data.get("archetype", "")),
			"is_available": true,
			"access_tier": "DEBUG_BYPASS",
			"matched_role": "ALL",
			"authorizing_file": "DEBUG_RULE:all_items_in_all_stores",
			"permitted_containers": ["*"],
			"debug_override_active": true,
			"audit_trace": "Bypassed standard RBAC gates via world_state['debug_rules']['all_items_in_all_stores']."
		}

	# 2. Extract Venue Role Tokens
	var venue_roles: Array[String] = []
	var primary_arch: String = str(venue_data.get("archetype", "")).to_upper()
	if not primary_arch.is_empty():
		venue_roles.append(primary_arch)

	for group in venue_data.get("taxonomic_groups", []):
		var g_token: String = str(group).to_upper()
		if not g_token.is_empty() and not venue_roles.has(g_token):
			venue_roles.append(g_token)

	for cat in venue_data.get("trade_categories", []):
		var cat_token: String = str(cat).to_upper()
		if not cat_token.is_empty() and not venue_roles.has(cat_token):
			venue_roles.append(cat_token)

	var rules: Dictionary = item.get("stocking_rules", {})
	var auth_file: String = str(rules.get("_auth_origin", item.get("source_path", "UNKNOWN_FILE")))

	# Backward compatibility: check category or sub_category against venue_roles
	var item_cat: String = str(item.get("category", "")).to_upper()
	var item_subcat: String = str(item.get("sub_category", "")).to_upper()
	var legacy_match: bool = false
	var matched_legacy_role: String = ""
	for r in venue_roles:
		if r == item_cat or r == item_subcat:
			legacy_match = true
			matched_legacy_role = r
			break

	# 3. Check Open Access
	var open_rules = rules.get("openly_stocked_in", null)
	var open_match: Dictionary = _evaluate_role_match(open_rules, venue_roles)
	if open_match.get("matched", false):
		return {
			"commodity_id": commodity_id,
			"venue_archetype": primary_arch,
			"is_available": true,
			"access_tier": "OPEN",
			"matched_role": open_match.get("role", ""),
			"authorizing_file": auth_file,
			"permitted_containers": open_match.get("containers", []),
			"debug_override_active": false,
			"audit_trace": "Granted open retail access via role '%s' declared in '%s'." % [open_match.get("role", ""), auth_file]
		}

	# Check legacy category fallback if no explicit stocking rules exist
	if rules.is_empty() and legacy_match:
		return {
			"commodity_id": commodity_id,
			"venue_archetype": primary_arch,
			"is_available": true,
			"access_tier": "OPEN",
			"matched_role": matched_legacy_role,
			"authorizing_file": str(item.get("source_path", "LEGACY_CATEGORY_MATCH")),
			"permitted_containers": [],
			"debug_override_active": false,
			"audit_trace": "Granted open access via legacy category match '%s'." % matched_legacy_role
		}

	# 4. Check Off-Book Access (if requested)
	if check_off_book:
		var possible_rules = rules.get("possibly_stocked_in", null)
		var off_book_match: Dictionary = _evaluate_role_match(possible_rules, venue_roles)
		if off_book_match.get("matched", false):
			return {
				"commodity_id": commodity_id,
				"venue_archetype": primary_arch,
				"is_available": true,
				"access_tier": "OFF_BOOK",
				"matched_role": off_book_match.get("role", ""),
				"authorizing_file": auth_file,
				"permitted_containers": off_book_match.get("containers", []),
				"debug_override_active": false,
				"audit_trace": "Granted off-book access via role '%s' declared in '%s'." % [off_book_match.get("role", ""), auth_file]
			}

	# 5. Denied
	return {
		"commodity_id": commodity_id,
		"venue_archetype": primary_arch,
		"is_available": false,
		"access_tier": "NONE",
		"matched_role": "",
		"authorizing_file": auth_file,
		"permitted_containers": [],
		"debug_override_active": false,
		"audit_trace": "Denied: Venue roles %s do not match permissions in '%s'." % [str(venue_roles), auth_file]
	}

static func _evaluate_role_match(rule_definition, venue_roles: Array[String]) -> Dictionary:
	if rule_definition is Dictionary:
		for role in venue_roles:
			if rule_definition.has(role):
				var containers: Array = []
				var val = rule_definition[role]
				if val is Array:
					containers = val
				return {"matched": true, "role": role, "containers": containers}
	elif rule_definition is Array:
		for role in venue_roles:
			if rule_definition.has(role):
				return {"matched": true, "role": role, "containers": []}
	return {"matched": false, "role": "", "containers": []}