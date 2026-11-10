# res://data_modules/core/impacts/inventory/sink_inventory.gd
class_name SinkInventory
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/inventory/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkInventory] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkInventory] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkInventory] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkInventory] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("allow_negative_stock"), "FATAL: [SinkInventory] Missing 'allow_negative_stock' in tuning.")
	assert(tuning.has("default_lane"), "FATAL: [SinkInventory] Missing 'default_lane' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "INVENTORY"

static func get_target_scope() -> String:
	return "ACTOR"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	var tuning: Dictionary = _get_tuning()
	var allow_negative: bool = bool(tuning["allow_negative_stock"])
	var default_lane: String = str(tuning["default_lane"])

	# Resolve item identifier and lane (e.g. "BEER_STRONG_LAGER" or "BEER_STRONG_LAGER:PREPPED")
	var item_id: String = target_id
	var lane: String = default_lane

	if target_id.contains(":"):
		var parts := target_id.split(":")
		item_id = parts[0]
		if parts.size() > 1 and not parts[1].is_empty():
			lane = parts[1]

	# Resolve master inventory registry container
	if not world_state.has("inventory"):
		world_state["inventory"] = {}
	var registry: Dictionary = world_state["inventory"]

	if not registry.has(item_id):
		registry[item_id] = {"STOCK": 0.0, "PREPPED": 0.0}

	var lanes: Dictionary = registry[item_id]
	var current_qty: float = float(lanes.get(lane, 0.0))
	var new_qty: float = current_qty + delta

	if not allow_negative:
		new_qty = maxf(0.0, new_qty)

	lanes[lane] = new_qty

## 3. AMBIENT HEARTBEAT CONTRACT
static func process_ambient(_world_state: Dictionary) -> void:
	# Passive deterioration or shelf-life decay is handled by perishable decay engines
	pass