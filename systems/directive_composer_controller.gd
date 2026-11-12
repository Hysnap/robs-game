# res://systems/directive_composer_controller.gd
class_name DirectiveComposerController
extends RefCounted

const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const SocietyQueriesScript = preload("res://systems/society_queries.gd")
const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")
const OperationsControllerScript = preload("res://systems/operations_controller.gd")

## Returns all registered verbs from VerbRouter that are enabled for player composition
static func get_registered_verbs() -> Array[String]:
	var raw_verbs: Array[String] = VerbRouterScript.get_registered_verbs()
	var visible_verbs: Array[String] = []
	for verb_token in raw_verbs:
		if is_verb_user_creatable(verb_token):
			visible_verbs.append(verb_token)
	return visible_verbs

## Evaluates whether a verb is enabled for player order composition via its target_scope.json
static func is_verb_user_creatable(verb_token: String) -> bool:
	var scope_def: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition(verb_token)
	if scope_def.is_empty():
		return false

	# Exclude compiled recipe sub-verbs from the top-level composer dropdown
	if bool(scope_def.get("is_recipe_verb", false)):
		return false

	return bool(scope_def.get("visible_in_composer", true))

## Resolves raw targets for an active verb
static func resolve_targets_for_verb(verb_token: String, world_state: Dictionary) -> Array[Dictionary]:
	if verb_token.is_empty():
		return []
	return TargetDomainRegistryScript.resolve_targets(verb_token, world_state)

## Extracts unique category tokens from a list of targets
static func extract_target_categories(targets: Array[Dictionary]) -> Array[String]:
	var categories: Array[String] = []
	for item in targets:
		var cat: String = str(item.get("category", "")).strip_edges().to_upper()
		assert(!cat.is_empty(), "FATAL: [DirectiveComposerController] Target item '%s' has no category classification!" % str(item.get("id", "UNKNOWN")))
		if not categories.has(cat):
			categories.append(cat)
	categories.sort()
	return categories

## Filters targets by selected category ('ALL' returns all targets)
static func filter_targets_by_category(targets: Array[Dictionary], selected_category: String) -> Array[Dictionary]:
	var cat_upper := selected_category.strip_edges().to_upper()
	if cat_upper == "ALL" or cat_upper.is_empty():
		return targets

	var filtered: Array[Dictionary] = []
	for item in targets:
		var item_cat: String = str(item.get("category", "")).strip_edges().to_upper()
		if item_cat == cat_upper:
			filtered.append(item)
	return filtered

## Resolves allowed location scopes from target_scope.json
static func get_allowed_scopes(verb_token: String) -> Array[String]:
	if verb_token.is_empty():
		return []
	return TargetDomainRegistryScript.get_allowed_scopes(verb_token)

## Resolves dynamic UI form layout from verb's target_scope.json via TargetDomainRegistry. Fails loud if missing.
static func get_form_layout(verb_token: String) -> Dictionary:
	var clean_verb := verb_token.strip_edges().to_upper()
	assert(!clean_verb.is_empty(), "FATAL: [DirectiveComposerController] Verb token cannot be empty when requesting form layout.")

	var scope_def: Dictionary = TargetDomainRegistryScript.get_verb_scope_definition(clean_verb)
	assert(!scope_def.is_empty(), "FATAL: [DirectiveComposerController] Missing target_scope definition for verb '%s'." % clean_verb)

	var layout: Variant = scope_def.get("form_layout", null)
	assert(layout is Dictionary and not layout.is_empty(), "FATAL: [DirectiveComposerController] Verb '%s' scope file missing 'form_layout' dictionary." % clean_verb)

	return layout

## Builds normalized location list based on player knowledge and active district
static func build_locations_cache(verb_token: String, active_district_id: String, world_state: Dictionary) -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	var allowed_scopes := get_allowed_scopes(verb_token)

	# A. Districts Known to Player (if allowed by verb)
	if allowed_scopes.is_empty() or allowed_scopes.has("DISTRICT"):
		var known_districts: Array = world_state.get("player_knowledge", {}).get("known_districts", []).duplicate()
		if not active_district_id.is_empty() and not known_districts.has(active_district_id):
			known_districts.append(active_district_id)

		var districts_map: Dictionary = world_state.get("districts", {})

		for dist_id in known_districts:
			var s_id := str(dist_id)
			var d_name := ""

			# 1. Resolve authentic name from world_state in memory
			if districts_map.has(s_id) and districts_map[s_id] is Dictionary:
				d_name = str(districts_map[s_id].get("display_name", ""))

			# 2. Fall back to SQLite v_district_census via get_district_census
			if d_name.is_empty() and SocietyQueriesScript != null:
				var census: Dictionary = SocietyQueriesScript.get_district_census(s_id)
				d_name = str(census.get("district_name", ""))

			# 3. Clean token fallback (strip internal prefix)
			if d_name.is_empty():
				d_name = s_id.trim_prefix("DISTRICT_").capitalize().replace("_", " ")

			locations.append({
				"id": s_id,
				"type": "DISTRICT",
				"category": "DISTRICT",
				"sector": "DISTRICT",
				"display": d_name
			})

	# B. Establishments in active district (if allowed by verb)
	if (allowed_scopes.is_empty() or allowed_scopes.has("ESTABLISHMENT")) and not active_district_id.is_empty():
		var estabs: Array = SocietyQueriesScript.get_district_establishments(active_district_id)
		for e in estabs:
			var e_id: Variant = e.get("establishment_id", "")
			var e_name: String = str(e.get("name", "Unnamed Venue"))
			var cat_code: String = str(e.get("category_code", ""))

			var is_residential: bool = (cat_code == "RESIDENTIAL_UNIT" or cat_code.begins_with("RESIDENTIAL"))
			var sector: String = "RESIDENTIAL" if is_residential else "WORKPLACE"

			locations.append({
				"id": str(e_id),
				"type": "ESTABLISHMENT",
				"category": cat_code,
				"sector": sector,
				"display": e_name
			})

	return locations

## Queries establishment dockets through the Fog-of-War intel filter and extracts known contacts
static func resolve_contacts_for_location(location_meta: Dictionary, world_state: Dictionary = {}) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	if not location_meta is Dictionary or location_meta.get("type") != "ESTABLISHMENT":
		return contacts

	var estab_id: int = int(location_meta.get("id", 0))
	if estab_id <= 0:
		return contacts

	var sim_day: int = int(world_state.get("metadata", {}).get("current_sim_day", 0))
	var intel_ctx: Dictionary = OperationsControllerScript._build_player_intel_context(world_state)
	var docket: Dictionary = SocietyQueriesScript.get_establishment_docket(estab_id, sim_day, intel_ctx)
	
	for emp in docket.get("employees", []):
		if bool(emp.get("is_masked", false)):
			continue
		var res_id: int = int(emp.get("resident_id", 0))
		var emp_name: String = str(emp.get("full_name", ""))
		var emp_role: String = str(emp.get("role_title", ""))
		if res_id > 0 and not emp_name.is_empty():
			contacts.append({
				"id": str(res_id),
				"name": emp_name,
				"role": emp_role,
				"type": "EMPLOYEE"
			})

	for res in docket.get("residents", []):
		if bool(res.get("is_masked", false)):
			continue
		var res_id: int = int(res.get("resident_id", 0))
		var res_name: String = str(res.get("full_name", ""))
		if res_id > 0 and not res_name.is_empty():
			contacts.append({
				"id": str(res_id),
				"name": res_name,
				"role": "OCCUPANT",
				"type": "RESIDENTIAL"
			})

	return contacts

## Calculates cost estimate incorporating player knowledge and perception fuzzing
static func calculate_estimate_with_intel(
	qty: float, 
	target_meta: Dictionary, 
	location_meta: Dictionary, 
	world_state: Dictionary
) -> Dictionary:
	var safe_qty: float = maxf(0.0, qty)
	var base_cost: float = float(target_meta.get("unit_cost", target_meta.get("base_cost", 0.0)))
	var item_id: String = str(target_meta.get("id", ""))
	var venue_id: String = str(location_meta.get("id", ""))

	if safe_qty <= 0.0 or base_cost <= 0.0 or item_id.is_empty():
		return {
			"estimated_total": 0.0,
			"perceived_unit_cost": 0.0,
			"is_exact": true,
			"confidence_token": "UI_ESTIMATE_VERIFIED"
		}

	var known_prices: Dictionary = world_state.get("player_knowledge", {}).get("transacted_prices", {})
	var venue_prices: Dictionary = known_prices.get(venue_id, {})
	var has_prior_history: bool = venue_prices.has(item_id)

	var perceived_unit_cost: float = base_cost
	var is_exact: bool = true

	if has_prior_history:
		perceived_unit_cost = float(venue_prices[item_id])
		is_exact = true
	else:
		var is_home: bool = bool(location_meta.get("is_home_turf", false))
		var fuzzed_cost: float = ConditionEvaluatorScript.calculate_fuzzed_ratio(base_cost, is_home, -0.25, 0.25, 0.10, 0.05)
		perceived_unit_cost = snappedf(fuzzed_cost, 0.05)
		is_exact = false

	var total: float = safe_qty * perceived_unit_cost
	return {
		"estimated_total": total,
		"perceived_unit_cost": perceived_unit_cost,
		"is_exact": is_exact,
		"confidence_token": "UI_ESTIMATE_VERIFIED" if is_exact else "UI_ESTIMATE_SPECULATIVE"
	}

## Validates and constructs normalized directive packet based on verb's configured form_layout
static func build_and_validate_directive(form_data: Dictionary) -> Dictionary:
	var verb: String = str(form_data.get("verb", "")).strip_edges().to_upper()
	if verb.is_empty():
		push_error("[DirectiveComposerController REJECTED] Verb cannot be empty.")
		return {}

	var layout := get_form_layout(verb)
	var directive: Dictionary = {
		"verb": verb,
		"initiator_id": str(form_data.get("initiator_id", "PLAYER")).strip_edges(),
		"assigned_to": str(form_data.get("assigned_to", "Player")).strip_edges(),
		"config": {
			"unit_cost": float(form_data.get("unit_cost", 0.0)),
			"exposure_modifier": float(form_data.get("exposure_modifier", 1.0))
		}
	}
	if directive["initiator_id"].is_empty():
		directive["initiator_id"] = "PLAYER"

	# 1. Target Section (Item / Entity)
	var target_cfg: Dictionary = layout.get("target_section", {})
	var target_field: String = str(target_cfg.get("mapped_field", "item_id"))
	var target_val: String = str(form_data.get("target_item", form_data.get("item_id", ""))).strip_edges()
	if bool(target_cfg.get("required", false)) and target_val.is_empty():
		push_error("[DirectiveComposerController REJECTED] Target is required for verb '%s'." % verb)
		return {}
	if not target_val.is_empty():
		directive["target_item"] = target_val
		if not target_field.is_empty():
			directive[target_field] = target_val

	# 2. Amount / Duration Section
	var amount_cfg: Dictionary = layout.get("amount_section", {})
	var amount_field: String = str(amount_cfg.get("mapped_field", "amount"))
	var raw_amount: float = float(form_data.get("amount", amount_cfg.get("default_value", 1.0)))
	if bool(amount_cfg.get("required", false)) and raw_amount <= 0.0:
		push_error("[DirectiveComposerController REJECTED] Amount/Duration must be > 0.0 for verb '%s'." % verb)
		return {}
	directive["amount"] = raw_amount
	if not amount_field.is_empty():
		directive[amount_field] = raw_amount

	# 3. Location Section
	var loc_cfg: Dictionary = layout.get("location_section", {})
	var loc_field: String = str(loc_cfg.get("mapped_field", "target_node_id"))
	var loc_id: String = str(form_data.get("target_node_id", "")).strip_edges()
	var loc_name: String = str(form_data.get("target_node_name", loc_id)).strip_edges()
	if bool(loc_cfg.get("required", false)) and loc_id.is_empty():
		push_error("[DirectiveComposerController REJECTED] Target location is required for verb '%s'." % verb)
		return {}
	if not loc_id.is_empty():
		directive["target_node_id"] = loc_id
		directive["target_node_name"] = loc_name
		if not loc_field.is_empty():
			directive[loc_field] = loc_id
	directive["target_scope"] = str(form_data.get("target_scope", "DISTRICT"))

	# 4. Contact Section
	var contact_cfg: Dictionary = layout.get("contact_section", {})
	var contact_field: String = str(contact_cfg.get("mapped_field", "counterparty_id"))
	var contact_id: String = str(form_data.get("counterparty_id", form_data.get("target_resident_id", ""))).strip_edges()
	if bool(contact_cfg.get("required", false)) and contact_id.is_empty():
		push_error("[DirectiveComposerController REJECTED] Contact/Counterparty is required for verb '%s'." % verb)
		return {}
	if not contact_id.is_empty():
		directive["counterparty_id"] = contact_id
		if not contact_field.is_empty():
			directive[contact_field] = contact_id

	# Optional Trade Supplier Key Parity
	if form_data.has("supplier_id") and not str(form_data["supplier_id"]).is_empty():
		directive["supplier_id"] = str(form_data["supplier_id"]).strip_edges()
	elif not contact_id.is_empty() and not directive.has("supplier_id"):
		directive["supplier_id"] = contact_id

	return directive

## Filters cached locations by sector/type
static func filter_locations(cached_locations: Array[Dictionary], filter_type: String) -> Array[Dictionary]:
	var f_upper := filter_type.strip_edges().to_upper()
	if f_upper == "ALL" or f_upper.is_empty():
		return cached_locations

	var filtered: Array[Dictionary] = []
	for loc in cached_locations:
		if f_upper == "DISTRICT" and loc.get("type") == "DISTRICT":
			filtered.append(loc)
		elif loc.get("type") == "ESTABLISHMENT" and loc.get("sector") == f_upper:
			filtered.append(loc)
	return filtered