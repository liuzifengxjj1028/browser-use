extends Node
## Procedurally generated placeholder audio. No external sound assets are used
## in the prototype (PRD §13); every cue is synthesized at startup.

const RATE := 22050

var sounds: Dictionary = {}

func _ready() -> void:
	sounds["step"] = _wav(_noise_burst(0.07, 0.25, 6.0))
	sounds["step_enemy"] = _wav(_thud(0.18, 66.0, 0.8))
	sounds["heartbeat"] = _wav(_thud(0.22, 52.0, 0.9))
	sounds["throw_hit"] = _wav(_noise_burst(0.14, 0.9, 22.0))
	sounds["pickup"] = _wav(_blip(0.09, 660.0, 0.35))
	sounds["monitor_on"] = _wav(_blip(0.28, 520.0, 0.4))
	sounds["monitor_bad"] = _wav(_buzz(0.4, 96.0, 0.5))
	sounds["elevator"] = _wav(_chime())
	sounds["sting"] = _wav(_sting())
	sounds["door"] = _wav(_noise_burst(0.22, 0.5, 10.0))
	sounds["whistle_low"] = _wav(_blip(0.5, 210.0, 0.3))
	sounds["hum"] = _wav(_hum(), true)
	sounds["static"] = _wav(_noise_burst(0.8, 0.35, 2.0))

func stream(name: String) -> AudioStreamWAV:
	return sounds.get(name)

func play_at(name: String, pos: Vector3, parent: Node, vol_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name) or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds[name]
	p.volume_db = vol_db
	p.pitch_scale = clampf(pitch * randf_range(0.96, 1.04), 0.1, 3.0)
	p.max_distance = 40.0
	p.unit_size = 6.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

func play_ui(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sounds[name]
	p.volume_db = vol_db
	p.pitch_scale = clampf(pitch, 0.1, 3.0)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

# --- generators: each returns PackedFloat32Array of samples in [-1, 1] ---

func _env(i: int, n: int, attack := 0.02) -> float:
	var t := float(i) / float(n)
	var a := clampf(t / maxf(attack, 0.001), 0.0, 1.0)
	var r := 1.0 - t
	return a * r * r

func _noise_burst(dur: float, tone: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var s := randf_range(-1.0, 1.0)
		lp += tone * (s - lp)
		out[i] = lp * _env(i, n) * exp(-decay * float(i) / RATE)
	return out

func _thud(dur: float, freq: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := freq * (1.0 + 0.6 * exp(-t * 30.0))
		out[i] = amp * sin(TAU * f * t) * _env(i, n, 0.005)
	return out

func _blip(dur: float, freq: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = amp * sin(TAU * freq * t) * (0.7 + 0.3 * sin(TAU * freq * 2.01 * t)) * _env(i, n)
	return out

func _buzz(dur: float, freq: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var square := 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
		out[i] = amp * square * (0.6 + 0.4 * randf()) * _env(i, n)
	return out

func _chime() -> PackedFloat32Array:
	var n := int(0.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.3 * sin(TAU * 784.0 * t) + 0.3 * sin(TAU * 988.0 * maxf(t - 0.25, 0.0))
		out[i] = v * _env(i, n, 0.01)
	return out

func _sting() -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.35 * sin(TAU * 220.0 * t) + 0.35 * sin(TAU * 233.0 * t) + 0.2 * sin(TAU * 466.0 * t)
		out[i] = v * _env(i, n, 0.01)
	return out

func _hum() -> PackedFloat32Array:
	var n := int(1.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = 0.10 * sin(TAU * 60.0 * t) + 0.05 * sin(TAU * 120.0 * t) + 0.02 * randf_range(-1, 1)
	return out

func _wav(samples: PackedFloat32Array, looped := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w
