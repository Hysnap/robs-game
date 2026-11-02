# res://data_modules/core/impacts/scrutiny/sink_regulatory_scrutiny.gd
class_name SinkRegulatoryScrutiny
extends ImpactSinkBase

const PROFILE_PATH := "res://data_modules/core/impacts/scrutiny/profile.json"

static var _tuning_cache: Dictionary = {}

## Loads tuning block dynamically from profile.json with hard assertion failure
static func _get_tuning() -> Dictionary:
	if not _tuning_cache.is_empty():
		return _tuning_cache

	assert(FileAccess.file_exists(PROFILE_PATH),
		"FATAL: [SinkRegulatoryScrutiny] profile.json not found at: %s" % PROFILE_PATH)

	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert(f != null, "FATAL: [SinkRegulatoryScrutiny] Failed to open: %s" % PROFILE_PATH)

	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "FATAL: [SinkRegulatoryScrutiny] Root must be a Dictionary in: %s" % PROFILE_PATH)
	assert(parsed.has("tuning"), "FATAL: [SinkRegulatoryScrutiny] Missing 'tuning' block in profile.json")

	var tuning: Dictionary = parsed["tuning"]
	assert(tuning.has("ambient_decay_step"), "FATAL: [SinkRegulatoryScrutiny] Missing 'ambient_decay_step' in tuning.")

	_tuning_cache = tuning
	return _tuning_cache

## 1. IDENTITY & CONTRACT
static func get_metric_key() -> String:
	return "REGULATORY_SCRUTINY"

static func get_target_scope() -> String:
	return "SPATIAL"

## 2. ACTION IMPULSE CONTRACT
static func apply_delta(world_state: Dictionary, target_id: String, delta: float) -> void:
	if delta == 0.0 or target_id.is_empty():
		return

	# Sinks scrutiny into the specific district where the workshop or retail node operates
	var districts: Dictionary = world_state.get("districts", {})
	if districts.has(target_id):
		var cur: float = float(districts[target_id].get("regulatory_scrutiny", 0.0))
		districts[target_id]["regulatory_scrutiny"] = clampf(cur + delta, 0.0, 1.0)
	else:
		# Fallback to general operations scrutiny only if target is explicitly "OPERATIONS" or unmapped
		if not world_state.has("operations"):
			world_state["operations"] = {}
		var cur_ops: float = float(world_state["operations"].get("regulatory_scrutiny", 0.0))
		world_state["operations"]["regulatory_scrutiny"] = clampf(cur_ops + delta, 0.0, 1.0)

## 3. AMBIENT DISSIPATION CONTRACT
static func process_ambient(world_state: Dictionary) -> void:
	var tuning: Dictionary = _get_tuning()
	var decay: float = float(tuning["ambient_decay_step"])

	var districts: Dictionary = world_state.get("districts", {})
	for dist_id in districts.keys():
		var cur: float = float(districts[dist_id].get("regulatory_scrutiny", 0.0))
		if cur > 0.0:
			districts[dist_id]["regulatory_scrutiny"] = maxf(0.0, cur - decay)

	if world_state.has("operations"):
		var cur_ops: float = float(world_state["operations"].get("regulatory_scrutiny", 0.0))
		if cur_ops > 0.0:
			world_state["operations"]["regulatory_scrutiny"] = maxf(0.0, cur_ops - decay)