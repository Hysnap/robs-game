# res://systems/directive_composer_controller.gd
class_name DirectiveComposerController
extends RefCounted

const TargetDomainRegistryScript = preload("res://systems/target_domain_registry.gd")
const VerbRouterScript = preload("res://systems/verb_router.gd")
const IntelManagerScript = preload("res://systems/multilayer_info_loop/intel_manager.gd")

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

## Resolves active crew operatives from canonical world_state["residents"] via IntelManager
static func get_crew_actors(world_state: Dictionary) -> Array[Dictionary]:
	return IntelManagerScript.get_crew_residents(world_state)

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

## Filters player-known locations from IntelManager by the active verb's allowed_scopes
static func build_locations_cache(verb_token: String, active_district_id: String, world_state: Dictionary) -> Array[Dictionary]:
	var allowed_scopes := get_allowed_scopes(verb_token)
	var known_locations: Array[Dictionary] = IntelManagerScript.get_known_locations(active_district_id, world_state)
	if allowed_scopes.is_empty():
		return known_locations

	var filtered: Array[Dictionary] = []
	for loc in known_locations:
		var loc_type: String = str(loc.get("type", ""))
		if allowed_scopes.has(loc_type):
			filtered.append(loc)
	return filtered

## Delegates establishment contact resolution through IntelManager's Fog-of-War filter
static func resolve_contacts_for_location(location_meta: Dictionary, world_state: Dictionary = {}) -> Array[Dictionary]:
	return IntelManagerScript.resolve_known_contacts_for_location(location_meta, world_state)

## Calculates total order estimate using IntelManager's perceived unit cost
static func calculate_estimate_with_intel(
	qty: float,
	target_meta: Dictionary,
	location_meta: Dictionary,
	world_state: Dictionary
) -> Dictionary:
	var safe_qty: float = maxf(0.0, qty)
	var base_cost: float = float(target_meta.get("unit_cost", target_meta.get("base_cost", 0.0)))
	var item_id: String = str(target_meta.get("id", ""))

	if safe_qty <= 0.0 or base_cost <= 0.0 or item_id.is_empty():
		return {
			"estimated_total": 0.0,
			"perceived_unit_cost": 0.0,
			"is_exact": true,
			"confidence_token": "UI_ESTIMATE_VERIFIED"
		}

	var unit_est: Dictionary = IntelManagerScript.estimate_perceived_unit_cost(item_id, base_cost, location_meta, world_state)
	var perceived_unit_cost: float = float(unit_est.get("perceived_unit_cost", base_cost))
	var is_exact: bool = bool(unit_est.get("is_exact", true))

	return {
		"estimated_total": safe_qty * perceived_unit_cost,
		"perceived_unit_cost": perceived_unit_cost,
		"is_exact": is_exact,
		"confidence_token": "UI_ESTIMATE_VERIFIED" if is_exact else "UI_ESTIMATE_SPECULATIVE"
	}

## Helper: preserves native int IDs while normalizing numeric strings or keeping non-numeric tokens
static func _normalize_entity_id(raw_val: Variant) -> Variant:
	if raw_val == null:
		return ""
	if raw_val is int:
		return raw_val
	var s_val: String = str(raw_val).strip_edges()
	if s_val.is_valid_int():
		return int(s_val)
	return s_val

## Validates and constructs normalized directive packet based on verb's configured form_layout
static func build_and_validate_directive(form_data: Dictionary) -> Dictionary:
	var verb: String = str(form_data.get("verb", "")).strip_edges().to_upper()
	if verb.is_empty():
		push_error("[DirectiveComposerController REJECTED] Verb cannot be empty.")
		return {}

	var layout := get_form_layout(verb)
	var initiator_val: Variant = _normalize_entity_id(form_data.get("initiator_id", "PLAYER"))
	if initiator_val is String and str(initiator_val).is_empty():
		initiator_val = "PLAYER"

	var assigned_val: Variant = _normalize_entity_id(form_data.get("assigned_to", initiator_val))
	if assigned_val is String and str(assigned_val).is_empty():
		assigned_val = initiator_val

	var directive: Dictionary = {
		"verb": verb,
		"initiator_id": initiator_val,
		"assigned_to": assigned_val,
		"config": {
			"unit_cost": float(form_data.get("unit_cost", 0.0)),
			"exposure_modifier": float(form_data.get("exposure_modifier", 1.0))
		}
	}

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

	# 3. Settlement Rail & Postal Delivery Section (Optional)
	var rail_cfg: Dictionary = layout.get("rail_section", {})
	if not rail_cfg.is_empty():
		var rail_field: String = str(rail_cfg.get("mapped_field", "rail_code"))
		var rail_val: String = str(form_data.get("rail_code", form_data.get("settlement_rail", ""))).strip_edges().to_upper()
		if bool(rail_cfg.get("required", false)) and rail_val.is_empty():
			push_error("[DirectiveComposerController REJECTED] Settlement rail is required for verb '%s'." % verb)
			return {}
		if not rail_val.is_empty():
			directive["settlement_rail"] = rail_val
			if not rail_field.is_empty():
				directive[rail_field] = rail_val
		var default_item: String = str(rail_cfg.get("default_item_id", "")).strip_edges()
		if not default_item.is_empty() and not directive.has("item_id"):
			directive["item_id"] = default_item
		var postal_val: String = str(form_data.get("postal_class", "")).strip_edges().to_upper()
		if not postal_val.is_empty():
			directive["postal_class"] = postal_val

	# 4. Location Section
	var loc_cfg: Dictionary = layout.get("location_section", {})
	var loc_field: String = str(loc_cfg.get("mapped_field", "target_node_id"))
	var loc_id: Variant = _normalize_entity_id(form_data.get("target_node_id", ""))
	var loc_empty: bool = (loc_id is int and loc_id <= 0) or (loc_id is String and str(loc_id).is_empty())
	var loc_name: String = str(form_data.get("target_node_name", str(loc_id))).strip_edges()
	if bool(loc_cfg.get("required", false)) and loc_empty:
		push_error("[DirectiveComposerController REJECTED] Target location is required for verb '%s'." % verb)
		return {}
	if not loc_empty:
		directive["target_node_id"] = loc_id
		directive["target_node_name"] = loc_name
		if not loc_field.is_empty():
			directive[loc_field] = loc_id
	directive["target_scope"] = str(form_data.get("target_scope", "DISTRICT"))

	# 5. Contact Section
	var contact_cfg: Dictionary = layout.get("contact_section", {})
	var contact_field: String = str(contact_cfg.get("mapped_field", "counterparty_id"))
	var raw_contact: Variant = form_data.get("counterparty_id", form_data.get("target_resident_id", ""))
	var contact_id: Variant = _normalize_entity_id(raw_contact)
	var contact_empty: bool = (contact_id is int and contact_id <= 0) or (contact_id is String and str(contact_id).is_empty())
	if bool(contact_cfg.get("required", false)) and contact_empty:
		push_error("[DirectiveComposerController REJECTED] Contact/Counterparty is required for verb '%s'." % verb)
		return {}
	if not contact_empty:
		directive["counterparty_id"] = contact_id
		if not contact_field.is_empty():
			directive[contact_field] = contact_id

	# Optional Trade Supplier Key Parity
	if form_data.has("supplier_id"):
		var sup_id: Variant = _normalize_entity_id(form_data["supplier_id"])
		var sup_empty: bool = (sup_id is int and sup_id <= 0) or (sup_id is String and str(sup_id).is_empty())
		if not sup_empty:
			directive["supplier_id"] = sup_id
	elif not contact_empty and not directive.has("supplier_id"):
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