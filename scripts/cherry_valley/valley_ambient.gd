extends Node3D
## (Claude Code) Procedural ambient bed: river and wind are synthesised into
## looping AudioStreamWAV buffers at start-up, so the scene needs no external
## audio assets. Off by default; the player opts in with J.
##
## River: filtered low-frequency noise plus a few bubbling sine chirps.
## Wind: slow, gently swelling band of soft noise.

const SAMPLE_RATE: int = 22050
const LOOP_SECONDS: float = 6.0

var config: Dictionary
var players: Array[AudioStreamPlayer] = []
var enabled: bool = false
var sizes: Dictionary = {}

var _fade_target: float = 0.0


func build(cfg: Dictionary) -> void:
	config = cfg
	if not cfg.has("ambient"):
		return
	var spec: Dictionary = cfg.ambient
	var river: AudioStreamPlayer = _make_player("RiverBed", _river_stream(), float(spec.river_gain))
	var wind: AudioStreamPlayer = _make_player("WindBed", _wind_stream(), float(spec.wind_gain))
	players.append(river)
	players.append(wind)
	sizes["ambient_layers"] = players.size()
	set_enabled(bool(spec.get("default_on", false)), true)


func set_enabled(value: bool, immediate: bool = false) -> void:
	enabled = value
	_fade_target = float(config.ambient.volume_db) if value else -80.0
	for player: AudioStreamPlayer in players:
		if value:
			if not player.playing:
				player.play()
			player.volume_db = float(config.ambient.volume_db) if immediate else -60.0
		elif immediate:
			player.stop()
		elif not player.playing:
			player.volume_db = -80.0


func toggle() -> bool:
	set_enabled(not enabled)
	return enabled


func _process(delta: float) -> void:
	for player: AudioStreamPlayer in players:
		if not player.playing:
			continue
		player.volume_db = move_toward(player.volume_db, _fade_target, delta * 24.0)
		if player.volume_db <= -79.0 and _fade_target <= -79.0:
			player.stop()


func _make_player(node_name: String, stream: AudioStream, gain: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	return player


# ---------------------------------------------------------------- synthesis

func _river_stream() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * LOOP_SECONDS)
	var data: PackedByteArray = PackedByteArray()
	data.resize(length * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1103
	# Two cascaded one-pole low-passes give the noise a watery, non-hissy body.
	var low_a: float = 0.0
	var low_b: float = 0.0
	for i: int in range(length):
		var noise: float = rng.randf_range(-1.0, 1.0)
		low_a += (noise - low_a) * 0.08
		low_b += (low_a - low_b) * 0.32
		# Bubbles: short low sine bursts at irregular spacing.
		var t: float = float(i) / float(SAMPLE_RATE)
		var bubble: float = 0.0
		var burst_index: int = int(t * 2.3)
		var burst_phase: float = fmod(t * 2.3, 1.0)
		if burst_phase < 0.16:
			var envelope: float = sin(burst_phase / 0.16 * PI)
			bubble = sin(t * TAU * (420.0 + 70.0 * float(burst_index % 3))) * envelope * 0.05
		var sample: float = clampf(low_b * 1.9 + low_a * 0.35 + bubble, -1.0, 1.0)
		var idx: int = i * 2
		var value: int = int(clampf(sample, -1.0, 1.0) * 32000.0)
		data[idx] = value & 0xFF
		data[idx + 1] = (value >> 8) & 0xFF
	_smooth_loop(data, 0.6)
	return _to_wav(data)


func _wind_stream() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * LOOP_SECONDS)
	var data: PackedByteArray = PackedByteArray()
	data.resize(length * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2207
	var low: float = 0.0
	var very_low: float = 0.0
	for i: int in range(length):
		var t: float = float(i) / float(SAMPLE_RATE)
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.02
		very_low += (low - very_low) * 0.02
		# Slow swell, two full cycles per loop so the seam stays continuous.
		var swell: float = 0.65 + 0.35 * sin(t / LOOP_SECONDS * TAU * 2.0)
		var sample: float = clampf(very_low * 9.0 * swell, -1.0, 1.0)
		var idx: int = i * 2
		var value: int = int(sample * 32000.0)
		data[idx] = value & 0xFF
		data[idx + 1] = (value >> 8) & 0xFF
	_smooth_loop(data, 0.9)
	return _to_wav(data)


## Cross-fade the tail into the head so the WAV loops without a click.
func _smooth_loop(data: PackedByteArray, seconds: float) -> void:
	var frames: int = int(seconds * float(SAMPLE_RATE))
	var total: int = data.size() / 2
	frames = mini(frames, total / 3)
	if frames <= 1:
		return
	for i: int in range(frames):
		var w: float = float(i) / float(frames)
		w = w * w * (3.0 - 2.0 * w)
		var tail_index: int = total - frames + i
		var head: int = _read_sample(data, i)
		var tail: int = _read_sample(data, tail_index)
		_write_sample(data, tail_index, int(lerpf(float(tail), float(head), w)))


func _read_sample(data: PackedByteArray, index: int) -> int:
	var raw: int = data[index * 2] | (data[index * 2 + 1] << 8)
	if raw >= 32768:
		raw -= 65536
	return raw


func _write_sample(data: PackedByteArray, index: int, value: int) -> void:
	var clamped: int = clampi(value, -32768, 32767)
	data[index * 2] = clamped & 0xFF
	data[index * 2 + 1] = (clamped >> 8) & 0xFF


func _to_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(SAMPLE_RATE * LOOP_SECONDS)
	return stream
