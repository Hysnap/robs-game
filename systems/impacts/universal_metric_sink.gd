# res://systems/impacts/universal_metric_sink.gd
class_name UniversalMetricSink
extends RefCounted

const CONDITION_EVALUATOR = preload("res://systems/condition_evaluator.gd")

var metric_id: String = ""
var target_scope: String = "SPATIAL" # "SPATIAL", "ACTOR", "GLOBAL"
var routing_mode: String = "DIRECT"  # "DIRECT", "ACTOR_FALLBACK", "MULTI_CONTAINER", "INVENTORY_LANE", "GLOBAL_SCALAR"
var state_container: String = "districts"
var state_field: String = ""

# Numeric Bounds & Baseline Tuning
var min_floor: float = 0.0
var max_ceiling: float = 1.0
var default_baseline: float = 0.0
var allow_negative: bool = false

# Ambient Heartbeat Configuration
var ambient_mode: String = "NONE" # "NONE", "COOLING_TO_FLOOR", "DRIFT_TO_CEILING", "TOWARDS_BASELINE", "RESET_TO_ZERO", "CONDITIONAL_CREEP"
var ambient_rate: float = 0.0
var ambient_max: float = 1.0
var gate_field: String = ""
var gate_threshold: float = 0.0
var gate_operator: String = "<"

func _init(profile: Dictionary) -> void:
	metric_id = str(profile.get("metric_id", ""))
	target_scope = str(profile.get("target_scope", "SPATIAL"))
	
	# Container & Field Targeting
	state_container = str(profile.get("state_container", "districts" if target_scope == "SPATIAL" else "operations"))
	state_field = str(profile.get("state_field", metric_id.to_lower()))
	routing_mode = str(profile.get("routing_mode", "DIRECT"))

	# Tuning Parameters
	var tuning: Dictionary = profile.get("tuning", {})
	min_floor = float(tuning.get("minimum_floor", profile.get("min_value", 0.0)))
	max_ceiling = float(tuning.get("maximum_ceiling", profile.get("max_value", 1.0)))
	default_baseline = float(tuning.get("default_baseline", tuning.get("default_baseline_sentiment", tuning.get("default_baseline_reputation", min_floor))))
	allow_negative = bool(tuning.get("allow_negative_balance", tuning.get("allow_negative_stock", false)))

	# Detect Ambient Mode
	if tuning.has("passive_cooling_per_week"):
		ambient_mode = "COOLING_TO_FLOOR"
		ambient_rate = float(tuning["passive_cooling_per_week"])
	elif tuning.has("ambient_decay_step"):
		ambient_mode = "COOLING_TO_FLOOR"
		ambient_rate = float(tuning["ambient_decay_step"])
	elif tuning.has("passive_recovery_per_tick"):
		ambient_mode = "DRIFT_TO_CEILING"
		ambient_rate = float(tuning["passive_recovery_per_tick"])
	elif tuning.has("passive_drift_per_tick") or tuning.has("passive_decay_rate_per_tick"):
		ambient_mode = "TOWARDS_BASELINE"
		ambient_rate = float(tuning.get("passive_drift_per_tick", tuning.get("passive_decay_rate_per_tick", 0.0)))
	elif tuning.has("ambient_reset_to_zero") and bool(tuning["ambient_reset_to_zero"]):
		ambient_mode = "RESET_TO_ZERO"
	elif tuning.has("loyalty_skim_threshold"):
		ambient_mode = "CONDITIONAL_CREEP"
		gate_field = str(tuning.get("loyalty_field", "loyalty"))
		gate_threshold = float(tuning.get("loyalty_skim_threshold", 0.60))
		gate_operator = str(tuning.get("loyalty_operator", "<"))
		ambient_rate = float(tuning.get("ambient_skim_increment", 0.01))
		ambient_max = float(tuning.get("max_ambient_skim", 1.0))
	elif profile.has("ambient_mode"):
		ambient_mode = str(profile["ambient_mode"])
		ambient_rate = float(tuning.get("ambient_rate", 0.0))

## 1. IDENTITY CONTRACT
func get_metric_key() -> String:
	return metric_id

func get_target_scope() -> String:
	return target_scope

## 2. ACTION IMPULSE (Delta Application)
func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0:
		return

	match routing_mode:
		"INVENTORY_LANE":
			_apply_inventory(world_state, target_id, delta)
		"MULTI_CONTAINER":
			_apply_multi_container(world_state, target_id, delta)
		"GLOBAL_SCALAR":
			_apply_global_scalar(world_state, delta)
		"ACTOR_FALLBACK":
			_apply_actor_fallback(world_state, target_id, delta)
		_:
			_apply_direct(world_state, target_id, delta)

## 3. AMBIENT HEARTBEAT CONTRACT
func process_ambient(world_state: Dictionary) -> void:
	match ambient_mode:
		"COOLING_TO_FLOOR":
			_ambient_cooling(world_state)
		"DRIFT_TO_CEILING":
			_ambient_drift_ceiling(world_state)
		"TOWARDS_BASELINE":
			_ambient_towards_baseline(world_state)
		"RESET_TO_ZERO":
			_ambient_reset(world_state)
		"CONDITIONAL_CREEP":
			_ambient_conditional_creep(world_state)
		_:
			pass

# --- INTERNAL DELTA HANDLERS ---

func _apply_direct(world_state: Dictionary, target_id: String, delta: float) -> void:
	var container = world_state.get(state_container, {})
	if container is Dictionary and container.has(target_id):
		var entity: Dictionary = container[target_id]
		var cur: float = float(entity.get(state_field, default_baseline))
		var updated: float = cur + delta
		entity[state_field] = updated if allow_negative else clampf(updated, min_floor, max_ceiling)
	elif state_container == "operations":
		if not world_state.has("operations"):
			world_state["operations"] = {}
		var ops: Dictionary = world_state["operations"]
		var cur: float = float(ops.get(state_field, default_baseline))
		var updated: float = cur + delta
		ops[state_field] = updated if allow_negative else clampf(updated, min_floor, max_ceiling)

func _apply_actor_fallback(world_state: Dictionary, target_id: String, delta: float) -> void:
	var staff: Dictionary = world_state.get("staff", {})
	if not target_id.is_empty() and target_id != "PLAYER" and staff.has(target_id):
		var member: Dictionary = staff[target_id]
		var cur: float = float(member.get(state_field, default_baseline))
		var updated: float = cur + delta
		member[state_field] = updated if allow_negative else clampf(updated, min_floor, max_ceiling)
		return

	# Fallback to player operations pool
	if not world_state.has("operations"):
		world_state["operations"] = {}
	var ops: Dictionary = world_state["operations"]
	var cur: float = float(ops.get(state_field, default_baseline))
	var updated: float = cur + delta
	ops[state_field] = updated if allow_negative else clampf(updated, min_floor, max_ceiling)

func _apply_multi_container(world_state: Dictionary, target_id: String, delta: float) -> void:
	var cur: float = 0.0
	var updated: float = 0.0

	# Checks counterparties, staff, organizations, establishments, districts, or standings
	for c_name in ["counterparties", "npcs", "staff", "organizations", "establishments", "districts", "standings"]:
		var tbl = world_state.get(c_name, null)
		if tbl is Dictionary and tbl.has(target_id):
			var ent: Dictionary = tbl[target_id]
			cur = float(ent.get(state_field, default_baseline))
			updated = cur + delta
			ent[state_field] = updated if allow_negative else clampf(updated, min_floor, max_ceiling)
			return

	# If cash/finances fallback
	if state_field == "cash" or state_field == "liquid_cash":
		var fin: Dictionary = world_state.get("finances", {})
		cur = float(fin.get("liquid_cash", 0.0))
		updated = cur + delta
		fin["liquid_cash"] = updated if allow_negative else maxf(0.0, updated)

func _apply_inventory(world_state: Dictionary, target_id: String, delta: float) -> void:
	var item_id: String = target_id
	var lane: String = "STOCK"
	if target_id.contains(":"):
		var parts := target_id.split(":")
		item_id = parts[0]
		if parts.size() > 1 and not parts[1].is_empty():
			lane = parts[1]

	var inv_reg: Dictionary = world_state.get("inventory", {})
	if not inv_reg.has(item_id):
		inv_reg[item_id] = {"STOCK": 0.0, "PREPPED": 0.0}

	var lanes: Dictionary = inv_reg[item_id]
	var cur: float = float(lanes.get(lane, 0.0))
	var updated: float = cur + delta
	lanes[lane] = updated if allow_negative else maxf(0.0, updated)

func _apply_global_scalar(world_state: Dictionary, delta: float) -> void:
	var container = world_state.get(state_container, {})
	if container is Dictionary:
		var cur: float = float(container.get(state_field, default_baseline))
		var updated: float = cur + delta
		container[state_field] = updated if allow_negative else clampf(updated, min_floor, max_ceiling)

# --- INTERNAL AMBIENT HANDLERS ---

func _ambient_cooling(world_state: Dictionary) -> void:
	var tbl = world_state.get(state_container, null)
	if tbl is Dictionary:
		for k in tbl.keys():
			var ent = tbl[k]
			if ent is Dictionary and ent.has(state_field):
				ent[state_field] = maxf(min_floor, float(ent[state_field]) - ambient_rate)
	if world_state.has("operations") and world_state["operations"].has(state_field):
		var ops: Dictionary = world_state["operations"]
		ops[state_field] = maxf(min_floor, float(ops[state_field]) - ambient_rate)

func _ambient_drift_ceiling(world_state: Dictionary) -> void:
	var tbl = world_state.get(state_container, null)
	if tbl is Dictionary:
		for k in tbl.keys():
			var ent = tbl[k]
			if ent is Dictionary and ent.has(state_field):
				ent[state_field] = minf(max_ceiling, float(ent[state_field]) + ambient_rate)

func _ambient_towards_baseline(world_state: Dictionary) -> void:
	var tbl = world_state.get(state_container, null)
	if tbl is Dictionary:
		for k in tbl.keys():
			var ent = tbl[k]
			if ent is Dictionary and ent.has(state_field):
				var cur: float = float(ent[state_field])
				if cur > default_baseline:
					ent[state_field] = maxf(default_baseline, cur - ambient_rate)
				elif cur < default_baseline:
					ent[state_field] = minf(default_baseline, cur + ambient_rate)

func _ambient_reset(world_state: Dictionary) -> void:
	if world_state.has("operations") and world_state["operations"].has(state_field):
		world_state["operations"][state_field] = 0.0
	var staff: Dictionary = world_state.get("staff", {})
	for s_id in staff.keys():
		if staff[s_id] is Dictionary and staff[s_id].has(state_field):
			staff[s_id][state_field] = 0.0

func _ambient_conditional_creep(world_state: Dictionary) -> void:
	var staff: Dictionary = world_state.get("staff", {})
	for s_id in staff.keys():
		var member = staff[s_id]
		if member is Dictionary:
			var gate_val: float = float(member.get(gate_field, 1.0))
			if CONDITION_EVALUATOR.evaluate(gate_val, gate_threshold, gate_operator):
				var cur: float = float(member.get(state_field, 0.0))
				member[state_field] = clampf(cur + ambient_rate, min_floor, ambient_max)