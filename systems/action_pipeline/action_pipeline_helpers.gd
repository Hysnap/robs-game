# res://systems/action_pipeline/action_pipeline_helpers.gd
class_name ActionPipelineHelpers
extends RefCounted

const ConditionEvaluatorScript = preload("res://systems/condition_evaluator.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")
const SocietyQueriesScript = preload("res://systems/society_queries.gd")

## Normalizes an entity ID Variant so integer IDs resolve as int keys while string slugs remain String
static func normalize_entity_key(raw_id: Variant) -> Variant:
	if raw_id is int:
		return raw_id
	var s_val: String = str(raw_id).strip_edges()
	if s_val.is_valid_int():
		return int(s_val)
	return s_val

## Resolves the primary actor ID responsible for the directive (int resident_id or String token)
static func resolve_actor_id(directive: Dictionary) -> Variant:
	var raw_actor: Variant = directive.get("assigned_to", directive.get("initiator_id", "PLAYER"))
	return normalize_entity_key(raw_actor)

## Dynamic symbol resolver for directive arguments and mathematical tokens
static func resolve_param_value(raw_val: Variant, directive: Dictionary, _world_state: Dictionary) -> Variant:
	if typeof(raw_val) != TYPE_STRING:
		return raw_val

	var s_val: String = str(raw_val).strip_edges()

	if s_val == "ORDER_ACTOR" or s_val == "INITIATOR":
		return resolve_actor_id(directive)
	if s_val == "TARGET_NODE" or s_val == "LOCATION":
		return normalize_entity_key(directive.get("target_node_id", ""))
	if s_val.begins_with("PARAM."):
		var key: String = s_val.substr(6)
		return directive.get(key, "")
	if s_val == "CALCULATED_TOTAL_COST":
		var qty: float = float(directive.get("amount", 1.0))
		var unit_cost: float = float(directive.get("unit_cost", 0.0))
		return qty * unit_cost

	return raw_val

## Hydrates an uncached SQLite resident or establishment into world_state by integer primary key if present in DB
static func _try_hydrate_sqlite_entity(world_state: Dictionary, entity_id: int) -> bool:
	if entity_id <= 0 or SocietyQueriesScript == null:
		return false

	var sim_day: int = int(world_state.get("metadata", {}).get("current_sim_day", 0))
	var res_profile: Dictionary = SocietyQueriesScript.get_resident_profile(entity_id, sim_day)
	if not res_profile.is_empty():
		if not world_state.has("residents") or not (world_state["residents"] is Dictionary):
			world_state["residents"] = {}
		world_state["residents"][entity_id] = {
			"id": entity_id,
			"resident_id": entity_id,
			"is_crew": false,
			"name": res_profile.get("full_name", ""),
			"age": int(res_profile.get("age", 0)),
			"gender_id": int(res_profile.get("gender_id", 0)),
			"household_id": int(res_profile.get("household_id", 0)),
			"establishment_id": int(res_profile.get("establishment_id", 0)),
			"home_establishment_id": int(res_profile.get("establishment_id", 0)),
			"current_district_id": str(res_profile.get("district_id", "")),
			"inventory": {
				"CASH": float(res_profile.get("cash_on_hand", 100.0))
			}
		}
		return true

	var estab_docket: Dictionary = SocietyQueriesScript.get_establishment_docket(entity_id, sim_day)
	if not estab_docket.is_empty() and int(estab_docket.get("establishment_id", 0)) == entity_id:
		if not world_state.has("establishments") or not (world_state["establishments"] is Dictionary):
			world_state["establishments"] = {}
		world_state["establishments"][entity_id] = {
			"establishment_id": entity_id,
			"name": str(estab_docket.get("name", "")),
			"district_id": str(estab_docket.get("district_id", "")),
			"inventory": {}
		}
		return true

	return false

## Explicitly checks physical commodity quantity (pure boolean gate)
static func evaluate_commodity_gate(world_state: Dictionary, entity_id: Variant, commodity_token: String, required_qty: float, op: String = ">=") -> bool:
	var clean_item: String = commodity_token.to_upper().strip_edges()
	var inv: Dictionary = get_entity_inventory(world_state, entity_id)

	if inv.is_empty() or not inv.has(clean_item):
		return false

	var held: float = float(inv[clean_item])
	return ConditionEvaluatorScript.evaluate(held, required_qty, op)

## Explicit Query: Entity State Attribute (Strictly record fields only, no inventory fallback)
static func get_entity_attribute(world_state: Dictionary, entity_id: Variant, attribute_key: String) -> float:
	var clean_attr: String = attribute_key.to_lower().strip_edges()
	var key: Variant = normalize_entity_key(entity_id)

	# 1. Residents (Operatives, Citizens, Contacts)
	var residents: Dictionary = world_state.get("residents", {})
	if not residents.has(key) and key is int:
		_try_hydrate_sqlite_entity(world_state, key)
		residents = world_state.get("residents", {})
	if residents.has(key):
		var res_record: Dictionary = residents[key]
		if res_record.has(clean_attr):
			return float(res_record[clean_attr])
		push_error("[ActionPipelineHelpers] FAIL_LOUD: Attribute '%s' does not exist on resident '%s'" % [clean_attr, str(key)])
		return -INF

	# 2. Player / Operations / Enterprise
	if str(key) in ["PLAYER", "", "HQ"]:
		var ops: Dictionary = world_state.get("operations", {})
		if ops.has(clean_attr):
			return float(ops[clean_attr])
		push_error("[ActionPipelineHelpers] FAIL_LOUD: Attribute '%s' does not exist in operations for '%s'" % [clean_attr, str(key)])
		return -INF

	# 3. Establishments (Venues, Businesses)
	var establishments: Dictionary = world_state.get("establishments", {})
	if establishments.has(key):
		var estab_record: Dictionary = establishments[key]
		if estab_record.has(clean_attr):
			return float(estab_record[clean_attr])
		push_error("[ActionPipelineHelpers] FAIL_LOUD: Attribute '%s' does not exist on establishment '%s'" % [clean_attr, str(key)])
		return -INF

	push_error("[ActionPipelineHelpers] FAIL_LOUD: Cannot query attribute '%s' on unknown entity '%s'" % [clean_attr, str(key)])
	return -INF

## Resolves an entity's physical inventory dictionary directly from canonical tables
static func get_entity_inventory(world_state: Dictionary, entity_id: Variant) -> Dictionary:
	var key: Variant = normalize_entity_key(entity_id)

	# 1. Residents (Every person: Player, operative, vendor, contact)
	var residents: Dictionary = world_state.get("residents", {})
	if not residents.has(key) and key is int:
		_try_hydrate_sqlite_entity(world_state, key)
		residents = world_state.get("residents", {})
	if residents.has(key):
		var r = residents[key]
		if not r.has("inventory"):
			r["inventory"] = {}
		return r["inventory"]

	# 2. Establishments (Every physical premise: HQ, shop, depot, vault)
	var establishments: Dictionary = world_state.get("establishments", {})
	if establishments.has(key):
		var e = establishments[key]
		if not e.has("inventory"):
			e["inventory"] = {}
		return e["inventory"]

	# 3. Field Caches (Any dead-drop or physical stash container)
	var caches: Dictionary = world_state.get("caches", {})
	if caches.has(key):
		var c = caches[key]
		if not c.has("inventory"):
			c["inventory"] = {}
		return c["inventory"]

	# Fail loud immediately — no guessing, no crawling
	push_error("[ActionPipelineHelpers] FAIL_LOUD: Entity '%s' not found in canonical entity pools." % str(key))
	return {}

## Safely mutates item inventory quantities across any actor, venue, or vault
static func mutate_inventory_pool(world_state: Dictionary, entity_id: Variant, item_id: String, delta: float) -> void:
	var clean_item: String = item_id.to_upper().strip_edges()
	var inv: Dictionary = get_entity_inventory(world_state, entity_id)
	
	var current_qty: float = float(inv.get(clean_item, 0.0))
	var new_qty: float = max(0.0, current_qty + delta)
	if new_qty > 0.0:
		inv[clean_item] = new_qty
	else:
		inv.erase(clean_item)

## Ingests an authored JSON impact profile and routes the delta to UniversalMetricSink
static func load_and_dispatch_profile(world_state: Dictionary, target_id: String, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json_str: String = file.get_as_text()
	var parsed = JSON.parse_string(json_str)
	if parsed is Dictionary:
		var metric: String = str(parsed.get("metric_key", parsed.get("metric", ""))).to_upper()
		var delta_val: float = float(parsed.get("delta", parsed.get("factor", 0.0)))
		if not metric.is_empty():
			ImpactRouterScript.dispatch_delta(world_state, target_id, metric, delta_val)