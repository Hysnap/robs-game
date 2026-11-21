# res://systems/audio/tactile_sfx.gd
class_name TactileSfx
extends RefCounted

const SFX_CONFIG_PATH := "res://resources/sound/tactile_sfx.json"

static var _initialized: bool = false
static var _streams: Dictionary = {} # cue_id -> AudioStream
static var _volumes: Dictionary = {} # cue_id -> float (dB)
static var _player: AudioStreamPlayer = null

## Plays a named tactile sound cue defined in res://data_modules/core/resouce/sound/tactile_sfx.json
static func play(cue_id: String, pitch_jitter: float = 0.04) -> void:
	if DisplayServer.get_name() == "headless":
		return

	_ensure_initialized()

	var key: String = cue_id.strip_edges().to_lower()
	if not _streams.has(key):
		push_warning("[TactileSfx] Unknown tactile cue requested: '%s'" % cue_id)
		return

	var player: AudioStreamPlayer = _get_or_create_player()
	if player == null:
		return

	player.stream = _streams[key]
	player.volume_db = float(_volumes.get(key, -6.0))
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	player.play()

static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true

	assert(FileAccess.file_exists(SFX_CONFIG_PATH), "FATAL: [TactileSfx] Missing config at: %s" % SFX_CONFIG_PATH)
	var cfg: Dictionary = ScenarioManifestManager.load_json_file(SFX_CONFIG_PATH)
	var meta: Dictionary = cfg.get("_meta", {})
	var sample_rate: int = int(meta.get("sample_rate", 22050))
	var cues: Dictionary = cfg.get("cues", {})
	assert(not cues.is_empty(), "FATAL: [TactileSfx] 'cues' dictionary is empty in %s" % SFX_CONFIG_PATH)

	for raw_id in cues.keys():
		var cue_key: String = str(raw_id).strip_edges().to_lower()
		var def: Dictionary = cues[raw_id]
		_volumes[cue_key] = float(def.get("volume_db", -6.0))

		var custom_path: String = str(def.get("stream_path", "")).strip_edges()
		if not custom_path.is_empty() and ResourceLoader.exists(custom_path):
			_streams[cue_key] = ResourceLoader.load(custom_path)
		else:
			_streams[cue_key] = _synthesize_cue(def, sample_rate)

static func _get_or_create_player() -> AudioStreamPlayer:
	if is_instance_valid(_player):
		return _player

	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var tree := main_loop as SceneTree
	if tree.root == null:
		return null

	_player = AudioStreamPlayer.new()
	_player.name = "TactileSfxPlayer"
	_player.bus = "Master"
	tree.root.add_child(_player)
	return _player

static func _synthesize_cue(def: Dictionary, sample_rate: int) -> AudioStreamWAV:
	var wave_type: String = str(def.get("wave_type", "MECHANICAL_CLICK")).to_upper()
	var f_start: float = float(def.get("freq_start", 1200.0))
	var f_end: float = float(def.get("freq_end", 350.0))
	var duration_ms: int = maxi(10, int(def.get("duration_ms", 60)))
	var noise_mix: float = clampf(float(def.get("noise_mix", 0.5)), 0.0, 1.0)

	var num_samples: int = maxi(1, int((float(duration_ms) / 1000.0) * float(sample_rate)))
	var pcm := PackedByteArray()
	pcm.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(wave_type.hash())

	var phase: float = 0.0
	var lp_noise: float = 0.0

	for i in range(num_samples):
		var t: float = float(i) / float(num_samples)
		var env: float = pow(1.0 - t, 2.2)
		if i < 48:
			env *= float(i) / 48.0

		var freq: float = lerpf(f_start, f_end, t)
		phase += (TAU * freq) / float(sample_rate)
		var tone: float = sin(phase)
		if wave_type == "METALLIC_SNAP":
			tone = (tone * 0.65) + (sin(phase * 2.73) * 0.35)
		elif wave_type == "MECHANICAL_CLICK":
			tone = signf(tone) * 0.6 + tone * 0.4

		var white: float = rng.randf_range(-1.0, 1.0)
		lp_noise = lerpf(lp_noise, white, 0.35 if wave_type == "PAPER_SLIDE" else 0.55)

		var sample_val: float = lerpf(tone, lp_noise, noise_mix) * env * 0.85
		var int_sample: int = clampi(int(round(sample_val * 32767.0)), -32768, 32767)
		pcm.encode_s16(i * 2, int_sample)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = pcm
	return wav