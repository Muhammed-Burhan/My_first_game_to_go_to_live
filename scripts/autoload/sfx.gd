extends Node
## Procedural sound. No audio files: every effect is synthesized into an
## AudioStreamWAV, so the build has zero asset dependencies.
##
## Synthesis is split into steps so the loading screen can drive it and show
## honest progress. Call build_step(i) for i in 0..step_count()-1, or
## build_all() to do it in one blocking go (the sim and tests do that).
## When real recorded SFX arrive, swap any entry in _steps() for a loaded stream.

const RATE := 22050
const MUSIC_RATE := 11025
const POOL_SIZE := 16

var muted: bool = false
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur: String = ""
var _next_steal: int = 0
var _step_defs: Array = []
var _noise_salt: int = 0
var _last_play: Dictionary = {}


func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_a.volume_db = -60.0
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.volume_db = -60.0
	add_child(_music_b)
	muted = Save.is_muted()


## Sounds that fire many times a second, and the shortest gap each is allowed.
## Without this the archer volley alone is a continuous buzz.
const MIN_GAP_MS := {
	"arrow": 95, "hit": 70, "armor": 90, "coin": 80, "shoot": 70,
	"spear": 110, "naft": 120, "tower_hit": 90,
}


func play(sfx_name: String, volume_db: float = 0.0, pitch_var: float = 0.06) -> void:
	if muted or Game.sim_mode or not _streams.has(sfx_name):
		return
	var gap: int = MIN_GAP_MS.get(sfx_name, 0)
	if gap > 0:
		var now := Time.get_ticks_msec()
		if now - int(_last_play.get(sfx_name, -9999)) < gap:
			return
		_last_play[sfx_name] = now
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[_next_steal]
		_next_steal = (_next_steal + 1) % POOL_SIZE
	player.stream = _streams[sfx_name]
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	player.play()


## Same sound, pitched up a step per streak level: the combo ladder.
func play_pitched(sfx_name: String, semitones: float, volume_db: float = 0.0) -> void:
	if muted or Game.sim_mode or not _streams.has(sfx_name):
		return
	var player: AudioStreamPlayer = _players[_next_steal]
	for p in _players:
		if not p.playing:
			player = p
			break
	_next_steal = (_next_steal + 1) % POOL_SIZE
	player.stream = _streams[sfx_name]
	player.volume_db = volume_db
	player.pitch_scale = pow(2.0, semitones / 12.0)
	player.play()


## Cross-fade to "menu", "battle", or "" for silence.
func music(track: String) -> void:
	if Game.sim_mode:
		return
	if muted:
		track = ""
	if track == _music_cur:
		return
	var key := "music_" + track
	var from := _music_a if _music_a.playing else _music_b
	var to := _music_b if _music_a.playing else _music_a
	_music_cur = track
	if track != "" and _streams.has(key):
		to.stream = _streams[key]
		to.volume_db = -60.0
		to.play()
		var t1 := create_tween()
		t1.tween_property(to, "volume_db", -14.0, 1.1)
	if from.playing:
		var t2 := create_tween()
		t2.tween_property(from, "volume_db", -60.0, 0.9)
		t2.tween_callback(from.stop)


func set_muted(m: bool) -> void:
	muted = m
	Save.set_muted(m)
	if m:
		var was := _music_cur
		_music_cur = ""
		for p in [_music_a, _music_b]:
			p.stop()
		set_meta("resume_track", was)
	else:
		music(str(get_meta("resume_track", "menu")))


# ------------------------------------------------------------------ build steps

func step_count() -> int:
	if _step_defs.is_empty():
		_step_defs = _steps()
	return _step_defs.size()


## Runs one synthesis step and returns the label to show on the loading bar.
func build_step(i: int) -> String:
	if _step_defs.is_empty():
		_step_defs = _steps()
	if i < 0 or i >= _step_defs.size():
		return ""
	var d: Array = _step_defs[i]
	var fn: Callable = d[1]
	fn.call()
	return str(d[0])


func build_all() -> void:
	for i in range(step_count()):
		build_step(i)


func _steps() -> Array:
	return [
		["Fletching arrows", func():
			_streams["arrow"] = _wav(_mix([_sq(0.07, 1500.0, 600.0, 0.20, 38.0, 0.0, 0.3), _noise(0.022, 0.18, 95.0, 0.5)]))
			_streams["hit"] = _wav(_noise(0.03, 0.22, 80.0, 0.62))
			_streams["armor"] = _wav(_mix([_tone(0.08, 2200.0, 1800.0, "sine", 0.3, 45.0), _noise(0.03, 0.3, 90.0, 0.9)]))],
		["Boiling the oil", func():
			_streams["pot"] = _wav(_mix([_noise(0.30, 0.45, 12.0, 0.85), _tone(0.25, 200.0, 70.0, "sine", 0.5, 12.0)]))
			_streams["splash"] = _wav(_mix([_noise(0.40, 0.7, 9.0, 0.7), _tone(0.30, 120.0, 45.0, "sine", 0.6, 10.0), _noise(0.5, 0.25, 4.0, 0.2, 0.15)]))],
		["Winding the ballistas", func():
			_streams["bolt"] = _wav(_crush(_mix([_tone(0.30, 150.0, 50.0, "tri", 0.9, 12.0), _noise(0.05, 0.6, 50.0, 0.5), _sq(0.12, 900.0, 260.0, 0.28, 36.0)]), 32))
			_streams["whoosh"] = _wav(_mix([_noise(0.35, 0.4, 7.0, 0.55), _noise(0.2, 0.2, 14.0, 0.2, 0.06)]))],
		["Counting the treasury", func():
			_streams["coin"] = _wav(_mix([_tone(0.08, 1046.0, 1046.0, "sine", 0.35, 25.0), _tone(0.14, 1568.0, 1568.0, "sine", 0.35, 18.0, 0.06)]))
			_streams["combo"] = _wav(_mix([_tone(0.07, 880.0, 880.0, "tri", 0.3, 26.0), _tone(0.12, 1318.0, 1318.0, "sine", 0.3, 18.0, 0.05)]))
			_streams["star"] = _wav(_mix([_tone(0.10, 784.0, 1568.0, "sine", 0.35, 14.0), _tone(0.3, 2093.0, 2093.0, "sine", 0.22, 8.0, 0.08)]))],
		["Raising the scaffolds", func():
			_streams["build"] = _wav(_mix([_tone(0.14, 240.0, 160.0, "tri", 0.6, 22.0), _noise(0.05, 0.4, 60.0, 0.6)]))
			_streams["upgrade"] = _wav(_mix([_tone(0.10, 523.0, 523.0, "tri", 0.4, 20.0), _tone(0.10, 659.0, 659.0, "tri", 0.4, 20.0, 0.09), _tone(0.22, 784.0, 784.0, "tri", 0.45, 12.0, 0.18)]))
			_streams["sell"] = _wav(_mix([_tone(0.10, 659.0, 659.0, "tri", 0.35, 20.0), _tone(0.2, 440.0, 440.0, "tri", 0.35, 12.0, 0.1)]))],
		["Testing the horns", func():
			_streams["tap"] = _wav(_noise(0.02, 0.35, 60.0, 0.55))
			_streams["click"] = _wav(_mix([_tone(0.05, 1200.0, 800.0, "sine", 0.25, 55.0), _noise(0.02, 0.25, 80.0, 0.4)]))
			_streams["back"] = _wav(_mix([_tone(0.09, 700.0, 400.0, "tri", 0.28, 30.0)]))
			_streams["deny"] = _wav(_mix([_tone(0.12, 220.0, 200.0, "saw", 0.3, 20.0), _tone(0.16, 180.0, 160.0, "saw", 0.3, 18.0, 0.1)]))],
		["Tuning the daf", func():
			_streams["wave_start"] = _wav(_mix([_drum(0.0, 0.9), _drum(0.22, 0.6, true), _drum(0.42, 1.0)]))
			_streams["wave_clear"] = _wav(_mix([_tone(0.14, 587.0, 587.0, "saw", 0.35, 8.0, 0.0, 6.0), _tone(0.14, 659.0, 659.0, "saw", 0.35, 8.0, 0.14, 6.0), _tone(0.5, 880.0, 880.0, "saw", 0.4, 4.0, 0.28, 6.0), _drum(0.28, 0.9)]))
			_streams["countdown"] = _wav(_tone(0.12, 1046.0, 1046.0, "sine", 0.3, 22.0))],
		["Barring the gate", func():
			_streams["gate_hit"] = _wav(_mix([_tone(0.8, 75.0, 60.0, "saw", 0.8, 3.0, 0.0, 0.0, 9.0), _noise(0.55, 0.9, 6.0, 0.6), _tone(0.5, 55.0, 35.0, "sine", 0.9, 5.0)]))
			_streams["boss"] = _wav(_mix([_tone(1.2, 60.0, 50.0, "saw", 0.7, 2.0, 0.0, 0.0, 5.0), _drum(0.0, 1.0), _drum(0.5, 1.0), _drum(1.0, 1.0)]))],
		["Writing the ending", func():
			_streams["lose"] = _wav(_mix([_tone(1.1, 260.0, 70.0, "saw", 0.55, 2.5), _noise(0.9, 0.4, 5.0, 0.4), _drum(0.0, 1.0)]))
			_streams["win"] = _wav(_mix([_tone(0.16, 523.0, 523.0, "saw", 0.35, 8.0, 0.0, 5.0), _tone(0.16, 659.0, 659.0, "saw", 0.35, 8.0, 0.16, 5.0), _tone(0.16, 784.0, 784.0, "saw", 0.35, 8.0, 0.32, 5.0), _tone(0.9, 1046.0, 1046.0, "saw", 0.45, 2.5, 0.48, 6.0), _drum(0.48, 1.0), _drum(0.72, 0.7, true), _drum(0.96, 1.0)]))],
		["Packing the powder", func():
			# The big one: white-hot crack, noise collapsing to a rumble, sub thump.
			_streams["boom"] = _wav(_crush(_mix([
				_noise_sweep(0.9, 0.95, 4.0, 0.15, 0.96),
				_tone(0.55, 150.0, 34.0, "sine", 0.9, 5.5),
				_tone(0.25, 420.0, 60.0, "saw", 0.45, 14.0),
				_noise(0.06, 0.8, 40.0, 0.05),
			]), 24))
			_streams["tower_hit"] = _wav(_mix([
				_noise(0.12, 0.5, 26.0, 0.72), _tone(0.16, 210.0, 90.0, "tri", 0.5, 16.0)]))
			_streams["tower_down"] = _wav(_crush(_mix([
				_noise_sweep(1.1, 0.7, 3.2, 0.3, 0.95),
				_tone(0.8, 180.0, 42.0, "saw", 0.5, 4.0),
				_noise(0.3, 0.45, 9.0, 0.55, 0.25)]), 32))],
		["Loading the engines", func():
			_streams["stone"] = _wav(_mix([
				_tone(0.22, 90.0, 52.0, "tri", 0.7, 11.0), _noise(0.16, 0.4, 18.0, 0.8),
				_sq(0.09, 300.0, 140.0, 0.2, 26.0)]))
			_streams["naft"] = _wav(_mix([
				_noise_sweep(0.42, 0.5, 7.0, 0.72, 0.35), _tone(0.2, 620.0, 240.0, "saw", 0.18, 16.0)]))
			_streams["spear"] = _wav(_mix([
				_noise(0.07, 0.42, 44.0, 0.4), _sq(0.06, 520.0, 260.0, 0.22, 34.0)]))
			_streams["heal"] = _wav(_mix([
				_tone(0.3, 392.0, 784.0, "sine", 0.3, 7.0), _tone(0.2, 587.0, 880.0, "sine", 0.2, 9.0, 0.08)]))],
		["Sighting the repeater", func():
			# Contra's rifle: a fast square sweep with a noise transient on top.
			_streams["shoot"] = _wav(_crush(_mix([
				_sq(0.10, 1400.0, 260.0, 0.45, 30.0, 0.0, 0.25),
				_noise(0.035, 0.35, 70.0, 0.3)]), 16))
			_streams["overheat"] = _wav(_mix([
				_sq(0.3, 300.0, 120.0, 0.3, 8.0, 0.0, 0.12), _noise(0.25, 0.3, 10.0, 0.6)]))
			_streams["draft"] = _wav(_mix([
				_sq(0.07, 523.0, 523.0, 0.22, 22.0), _sq(0.07, 659.0, 659.0, 0.22, 22.0, 0.07),
				_sq(0.07, 784.0, 784.0, 0.22, 22.0, 0.14), _sq(0.22, 1046.0, 1046.0, 0.26, 10.0, 0.21)]))
			_streams["pick"] = _wav(_mix([
				_sq(0.1, 784.0, 784.0, 0.28, 16.0), _sq(0.1, 1046.0, 1046.0, 0.28, 16.0, 0.05),
				_sq(0.34, 1568.0, 1568.0, 0.3, 6.0, 0.1), _drum(0.0, 0.7)]))
			_streams["curse"] = _wav(_mix([
				_sq(0.25, 220.0, 110.0, 0.3, 8.0, 0.0, 0.18), _noise_sweep(0.5, 0.4, 5.0, 0.4, 0.9),
				_tone(0.4, 140.0, 70.0, "saw", 0.35, 5.0)]))],
		["Composing the night theme", func():
			_streams["music_menu"] = _music_loop(false)],
		["Composing the battle theme", func():
			_streams["music_battle"] = _music_loop(true)],
	]


# ------------------------------------------------------------------ synthesis

func _wav(samples: PackedFloat32Array, rate: int = RATE, loop: bool = false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


## Ramps the last few milliseconds to zero so a sample never ends on a step.
func _fade(arr: PackedFloat32Array, ms: float = 6.0) -> PackedFloat32Array:
	var n := arr.size()
	var k := mini(int(RATE * ms / 1000.0), n)
	for i in range(k):
		arr[n - 1 - i] *= float(i) / float(k)
	var a := mini(int(RATE * 0.0015), n)
	for i in range(a):
		arr[i] *= float(i) / float(a)
	return arr


func _osc(phase: float, kind: String) -> float:
	var t := fmod(phase, 1.0)
	match kind:
		"sine":
			return sin(t * TAU)
		"tri":
			return 4.0 * absf(t - 0.5) - 1.0
		"saw":
			return 2.0 * t - 1.0
		"square":
			return 1.0 if t < 0.5 else -1.0
	return sin(t * TAU)


## Frequency sweep f0->f1 with sharp attack and exponential decay.
func _tone(dur: float, f0: float, f1: float, kind: String, amp: float, decay: float,
		delay: float = 0.0, vibrato: float = 0.0, tremolo: float = 0.0) -> PackedFloat32Array:
	var n := int((dur + delay) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var start := int(delay * RATE)
	var phase := 0.0
	for i in range(start, n):
		var t := float(i - start) / RATE
		var u := t / dur
		var f := f0 * pow(f1 / f0, u)
		if vibrato > 0.0:
			f *= 1.0 + 0.012 * sin(t * TAU * vibrato)
		phase += f / RATE
		var env := minf(1.0, t * 260.0) * exp(-decay * t) * (1.0 - u * 0.15)
		if tremolo > 0.0:
			env *= 0.7 + 0.3 * sin(t * TAU * tremolo)
		out[i] = _osc(phase, kind) * env * amp
	return _fade(out)


## A square-wave pitch sweep: the NES gun. Short, loud, unmistakable.
func _sq(dur: float, f0: float, f1: float, amp: float, decay: float, delay: float = 0.0,
		duty: float = 0.5) -> PackedFloat32Array:
	var n := int((dur + delay) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var start := int(delay * RATE)
	var phase := 0.0
	for i in range(start, n):
		var t := float(i - start) / RATE
		var u := t / dur
		var f := f0 * pow(f1 / f0, u)
		phase += f / RATE
		var env := minf(1.0, t * 500.0) * exp(-decay * t)
		out[i] = (1.0 if fmod(phase, 1.0) < duty else -1.0) * env * amp
	return _fade(out)


## Noise whose filter closes over time: the NES noise channel stepping its period
## down. This is what makes an explosion read as an explosion rather than a hiss.
func _noise_sweep(dur: float, amp: float, decay: float, lp0: float, lp1: float,
		delay: float = 0.0) -> PackedFloat32Array:
	var n := int((dur + delay) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var start := int(delay * RATE)
	var y := 0.0
	var rng := RandomNumberGenerator.new()
	_noise_salt += 1
	rng.seed = 4242 + _noise_salt * 104729
	for i in range(start, n):
		var t := float(i - start) / RATE
		var u := clampf(t / dur, 0.0, 1.0)
		var lp := lerpf(lp0, lp1, u)
		var x := rng.randf_range(-1.0, 1.0)
		y += (x - y) * (1.0 - lp * 0.985)
		out[i] = y * exp(-decay * t) * amp
	return _fade(out)


## Quantise to a handful of levels. Cheap 8-bit grit.
func _crush(arr: PackedFloat32Array, levels: int) -> PackedFloat32Array:
	var step := 2.0 / float(levels)
	for i in range(arr.size()):
		arr[i] = round(arr[i] / step) * step
	return arr


## Filtered noise burst. lp = one-pole low-pass amount (0 = raw, 1 = very dark).
func _noise(dur: float, amp: float, decay: float, lp: float, delay: float = 0.0) -> PackedFloat32Array:
	var n := int((dur + delay) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var start := int(delay * RATE)
	var y := 0.0
	var rng := RandomNumberGenerator.new()
	_noise_salt += 1
	rng.seed = 1258 + _noise_salt * 7919
	for i in range(start, n):
		var t := float(i - start) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		y += (x - y) * (1.0 - lp * 0.97)
		out[i] = y * exp(-decay * t) * amp
	return _fade(out)


## Daf-style hit: low "dum" or high "tek".
func _drum(delay: float, amp: float, tek: bool = false) -> PackedFloat32Array:
	if tek:
		return _mix([_noise(0.12, amp * 0.5, 30.0, 0.35, delay), _tone(0.08, 900.0, 500.0, "sine", amp * 0.3, 40.0, delay)])
	return _mix([_tone(0.28, 110.0, 48.0, "sine", amp * 0.9, 11.0, delay), _noise(0.10, amp * 0.35, 40.0, 0.6, delay)])


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var arr: PackedFloat32Array = p
		for i in range(arr.size()):
			out[i] += arr[i]
	return out


## Two takes of the same chip track: a calmer one for menus and prep, a faster
## and louder one for the wave itself. See scripts/util/chiptune.gd.
func _music_loop(battle: bool) -> AudioStreamWAV:
	return _wav(Chiptune.build(battle), MUSIC_RATE, true)
