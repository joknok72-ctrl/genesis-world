extends Node
## AudioBus — صوت إجرائي (Procedural) يُولَّد داخل المحرك بلا ملفات خارجية.
## الصوت 50% من الانغماس: ريح، ماء، حفيف، نبضة الكون، رنّة الولادة، ناقوس الموت...

const RATE := 22050

var _streams: Dictionary = {}
var _ambient_player: AudioStreamPlayer
var _ambient_target := 0.0
var _cosmos_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _wind_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_all()
	_ambient_player = _mk_player(true)
	_cosmos_player = _mk_player(true)
	_wind_player = _mk_player(true)
	for i in 6:
		_sfx_players.append(_mk_player(false))
	apply_volumes()

func _mk_player(loop_bus: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	add_child(p)
	return p

func apply_volumes() -> void:
	var m := linear_to_db(clampf(Settings.music_volume, 0.0001, 1.0))
	_ambient_player.volume_db = m
	_cosmos_player.volume_db = m
	_wind_player.volume_db = m - 6.0
	var s := linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0))
	for p in _sfx_players:
		p.volume_db = s

## ---------- تشغيل ----------
func play_cosmos() -> void:
	_start_loop(_cosmos_player, "cosmos")
	_ambient_player.stop()
	_wind_player.stop()

func play_earth_ambient() -> void:
	_cosmos_player.stop()
	_start_loop(_ambient_player, "nature")
	_start_loop(_wind_player, "wind")

func set_night(night: bool) -> void:
	if not _ambient_player.playing:
		return
	var want := "night" if night else "nature"
	if _ambient_player.get_meta("key", "") != want:
		_start_loop(_ambient_player, want)

func sfx(key: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not _streams.has(key):
		return
	var p := _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_players.size()
	p.stream = _streams[key]
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0)) + vol_db
	p.play()

func _start_loop(p: AudioStreamPlayer, key: String) -> void:
	if not _streams.has(key):
		return
	p.stream = _streams[key]
	p.set_meta("key", key)
	p.play()

## ---------- توليد الأصوات ----------
func _build_all() -> void:
	_streams["cosmos"] = _gen(8.0, true, _cosmos_fn)
	_streams["nature"] = _gen(6.0, true, _nature_fn)
	_streams["night"] = _gen(6.0, true, _night_fn)
	_streams["wind"] = _gen(5.0, true, _wind_fn)
	_streams["tap"] = _gen(0.08, false, _tap_fn)
	_streams["birth"] = _gen(1.2, false, _birth_fn)
	_streams["death"] = _gen(1.8, false, _death_fn)
	_streams["discover"] = _gen(0.9, false, _discover_fn)
	_streams["bang"] = _gen(3.0, false, _bang_fn)
	_streams["thunder"] = _gen(2.5, false, _thunder_fn)
	_streams["rain"] = _gen(4.0, true, _rain_fn)
	_streams["fire"] = _gen(3.0, true, _fire_fn)

func _gen(seconds: float, loop: bool, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var noise_state := 12345
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		noise_state = (noise_state * 1103515245 + 12345) & 0x7fffffff
		var noise := float(noise_state) / 0x7fffffff * 2.0 - 1.0
		var v: float = fn.call(t, seconds, noise, lp)
		lp = lp + (noise - lp) * 0.02
		if loop:
			# تلاشي ناعم عند نقاط التكرار لتفادي "الطقطقة"
			var edge := minf(t, seconds - t)
			v *= clampf(edge / 0.15, 0.0, 1.0)
		var s := int(clampf(v, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav

func _cosmos_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var a := sin(TAU * 55.0 * t) * 0.25
	var b := sin(TAU * 82.4 * t + sin(t * 0.7) * 2.0) * 0.18
	var c := sin(TAU * 110.0 * t) * 0.08 * (0.5 + 0.5 * sin(t * 0.31))
	var shimmer := sin(TAU * 1320.0 * t) * 0.02 * maxf(0.0, sin(t * 1.3))
	return (a + b + c + shimmer) * (0.7 + 0.3 * sin(TAU * t / dur))

func _nature_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var breeze := lp * 0.6 * (0.6 + 0.4 * sin(t * 0.9))
	var bird := 0.0
	var ph := fmod(t, 2.3)
	if ph < 0.18:
		bird = sin(TAU * (2200.0 + 600.0 * sin(ph * 40.0)) * t) * 0.09 * sin(ph / 0.18 * PI)
	var ph2 := fmod(t + 1.1, 3.7)
	if ph2 < 0.12:
		bird += sin(TAU * 3100.0 * t) * 0.06 * sin(ph2 / 0.12 * PI)
	return breeze + bird

func _night_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var breeze := lp * 0.35
	var cricket := 0.0
	var ph := fmod(t * 14.0, 1.0)
	if ph < 0.5:
		cricket = sin(TAU * 4200.0 * t) * 0.05 * sin(ph * PI * 2.0)
	var owl := 0.0
	var ph2 := fmod(t, 6.0)
	if ph2 < 0.5:
		owl = sin(TAU * 380.0 * t) * 0.08 * sin(ph2 / 0.5 * PI)
	return breeze + cricket + owl

func _wind_fn(t: float, dur: float, noise: float, lp: float) -> float:
	return lp * (0.8 + 0.6 * sin(t * 0.5) * sin(t * 0.21)) * 0.9

func _rain_fn(t: float, dur: float, noise: float, lp: float) -> float:
	return noise * 0.25 + lp * 0.3

func _fire_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var crackle := noise if absf(noise) > 0.985 else 0.0
	return lp * 0.5 + crackle * 0.6

func _tap_fn(t: float, dur: float, noise: float, lp: float) -> float:
	return sin(TAU * 900.0 * t) * exp(-t * 60.0) * 0.6

func _birth_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var env := exp(-t * 2.5)
	return (sin(TAU * 523.25 * t) + 0.6 * sin(TAU * 659.25 * t) + 0.4 * sin(TAU * 783.99 * t)) * env * 0.3

func _death_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var env := exp(-t * 1.6)
	return (sin(TAU * 196.0 * t) + 0.5 * sin(TAU * 146.8 * t) + 0.2 * sin(TAU * 98.0 * t)) * env * 0.35

func _discover_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var f := 660.0 + 660.0 * clampf(t * 3.0, 0.0, 1.0)
	return sin(TAU * f * t) * exp(-t * 3.0) * 0.4

func _bang_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var boom := sin(TAU * (40.0 + 200.0 * exp(-t * 6.0)) * t) * exp(-t * 1.2)
	var rumble := lp * exp(-t * 0.9) * 1.5
	return (boom * 0.7 + rumble) * 0.9

func _thunder_fn(t: float, dur: float, noise: float, lp: float) -> float:
	var crack := noise * exp(-t * 12.0) * 0.8
	var rumble := lp * exp(-t * 1.1) * 2.0 * (0.7 + 0.3 * sin(t * 9.0))
	return crack + rumble
