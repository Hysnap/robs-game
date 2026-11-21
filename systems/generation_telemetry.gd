# res://systems/generation_telemetry.gd
class_name GenerationTelemetry
extends RefCounted

const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")
const TELEMETRY_PATH := "user://gen_telemetry.json"

const ORDERED_STAGES: Array[String] = [
	"STREETS",
	"DISTRICTS",
	"SOCIETY_PREMISES",
	"SOCIETY_CITIZENS",
	"SOCIETY_DUNBAR",
	"ROSTER",
	"SAVE"
]

## Loads [generation_pacing] baseline weights and alpha from business_rules.cfg
static func load_baseline_config() -> Dictionary:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(MANIFEST_MANAGER.BUSINESS_RULES_PATH)
	assert(err == OK, "FATAL: [GenerationTelemetry] Could not load business_rules.cfg.")
	assert(cfg.has_section("generation_pacing"), "FATAL: [GenerationTelemetry] Missing [generation_pacing] in business_rules.cfg.")

	var alpha: float = clampf(float(cfg.get_value("generation_pacing", "ema_alpha", 0.35)), 0.01, 1.0)
	var raw_weights: Dictionary = {}
	for stage_id in ORDERED_STAGES:
		var key := "weight_" + stage_id.to_lower()
		assert(cfg.has_section_key("generation_pacing", key), "FATAL: [GenerationTelemetry] Missing key '%s' in [generation_pacing]." % key)
		raw_weights[stage_id] = maxf(0.001, float(cfg.get_value("generation_pacing", key)))

	return {
		"ema_alpha": alpha,
		"weights": _normalize_weights(raw_weights)
	}

## Loads persisted EMA stage weights from user://gen_telemetry.json, or seeds from business_rules.cfg
static func load_active_weights() -> Dictionary:
	var baseline: Dictionary = load_baseline_config()
	var active: Dictionary = baseline["weights"].duplicate()

	if not FileAccess.file_exists(TELEMETRY_PATH):
		return active

	var file := FileAccess.open(TELEMETRY_PATH, FileAccess.READ)
	if file == null:
		return active

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return active

	var stored_weights = parsed.get("weights", null)
	if not (stored_weights is Dictionary):
		return active

	for stage_id in ORDERED_STAGES:
		if stored_weights.has(stage_id):
			var val: float = float(stored_weights[stage_id])
			if val > 0.0:
				active[stage_id] = val

	return _normalize_weights(active)

## Builds cumulative { stage_id: { "start": float, "end": float } } ranges spanning [0.0, 100.0]
static func compute_stage_ranges(weights: Dictionary = {}) -> Dictionary:
	var w_map: Dictionary = weights if not weights.is_empty() else load_active_weights()
	var norm: Dictionary = _normalize_weights(w_map)
	var ranges: Dictionary = {}
	var cursor: float = 0.0

	for i in range(ORDERED_STAGES.size()):
		var stage_id: String = ORDERED_STAGES[i]
		var span: float = float(norm[stage_id]) * 100.0
		var end_pct: float = 100.0 if i == ORDERED_STAGES.size() - 1 else minf(100.0, cursor + span)
		ranges[stage_id] = {
			"start": cursor,
			"end": end_pct
		}
		cursor = end_pct

	return ranges

## Maps a stage-local fraction [0.0..1.0] onto its calibrated global progress percentage [0.0..100.0]
static func map_stage_progress(ranges: Dictionary, stage_id: String, local_fraction: float) -> float:
	if not ranges.has(stage_id):
		return clampf(local_fraction * 100.0, 0.0, 100.0)
	var bounds: Dictionary = ranges[stage_id]
	var s: float = float(bounds["start"])
	var e: float = float(bounds["end"])
	return lerpf(s, e, clampf(local_fraction, 0.0, 1.0))

## Updates stored EMA stage shares from measured wall-clock milliseconds and writes user://gen_telemetry.json
static func record_run_durations(stage_durations_ms: Dictionary) -> Dictionary:
	var baseline: Dictionary = load_baseline_config()
	var alpha: float = float(baseline["ema_alpha"])
	var prev_weights: Dictionary = load_active_weights()

	var sample_count: int = 0
	if FileAccess.file_exists(TELEMETRY_PATH):
		var read_f := FileAccess.open(TELEMETRY_PATH, FileAccess.READ)
		if read_f != null:
			var existing = JSON.parse_string(read_f.get_as_text())
			read_f.close()
			if existing is Dictionary:
				sample_count = int(existing.get("sample_count", 0))

	# Convert wall-clock stage durations into normalized shares for this run
	var run_clamped_ms: Dictionary = {}
	var total_ms: float = 0.0
	for stage_id in ORDERED_STAGES:
		var raw_ms: float = maxf(1.0, float(stage_durations_ms.get(stage_id, 1.0)))
		run_clamped_ms[stage_id] = raw_ms
		total_ms += raw_ms

	var updated_raw: Dictionary = {}
	for stage_id in ORDERED_STAGES:
		var observed_share: float = float(run_clamped_ms[stage_id]) / total_ms
		var prior_share: float = float(prev_weights[stage_id])
		updated_raw[stage_id] = ((1.0 - alpha) * prior_share) + (alpha * observed_share)

	var normalized: Dictionary = _normalize_weights(updated_raw)
	sample_count += 1

	var payload: Dictionary = {
		"version": 1,
		"ema_alpha": alpha,
		"sample_count": sample_count,
		"last_total_ms": int(round(total_ms)),
		"last_durations_ms": run_clamped_ms,
		"weights": normalized
	}

	var write_f := FileAccess.open(TELEMETRY_PATH, FileAccess.WRITE)
	if write_f != null:
		write_f.store_string(JSON.stringify(payload, "\t"))
		write_f.close()

	return normalized

static func _normalize_weights(raw: Dictionary) -> Dictionary:
	var sum_w: float = 0.0
	for stage_id in ORDERED_STAGES:
		sum_w += maxf(0.0001, float(raw.get(stage_id, 0.01)))
	var out: Dictionary = {}
	for stage_id in ORDERED_STAGES:
		out[stage_id] = maxf(0.0001, float(raw.get(stage_id, 0.01))) / sum_w
	return out