extends Node
## AudioManager — процедурный звук (autoload «Audio»).
## В проекте нет аудио-ассетов: все семплы синтезируются в рантайме
## и кэшируются как AudioStreamWAV. Музыка собирается из слоёв,
## каждый слой включается по рангу стиля (главный аудио-хук игры).

signal music_layer_changed(layer_index: int)

const SR := 22050                      # частота дискретизации
const AMBIENT_SEC := 6.0
const LOOP_SEC := 4.0

var _cache: Dictionary = {}
var _players: Dictionary = {}          # pool AudioStreamPlayer для SFX
var _music_layers: Array[AudioStreamPlayer] = []
var _ambient: AudioStreamPlayer
var _current_music_layer: int = -1
var sfx_volume_db: float = -6.0
var music_volume_db: float = -14.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players[i] = p
	_ambient = AudioStreamPlayer.new()
	_ambient.volume_db = -22.0
	add_child(_ambient)
	Style.rank_changed.connect(_on_rank_changed)
	_build_all()


# ============================================================ СИНТЕЗ

func _make_stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampf(samples[i], -1.0, 1.0)
		var s16 := int(v * 32767.0)
		bytes.encode_s16(i * 2, s16)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _silence(sec: float) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	return out


func _env(i: int, n: int, attack: float, decay: float) -> float:
	var t := float(i) / float(n)
	var a := int(n * attack)
	if i < a and a > 0:
		return float(i) / float(a)
	return maxf(0.0, 1.0 - maxf(0.0, t - attack) / maxf(0.0001, decay))


## Резкий удар (кулак / выстрел / парирование).
func _noise_hit(sec: float, freq: float, drive: float) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20170314
	for i in n:
		var e := _env(i, n, 0.004, 0.9)
		phase += freq / SR
		var tone := sin(TAU * phase)
		var nz := rng.randf_range(-1.0, 1.0)
		out[i] = tanh((tone * 0.7 + nz * 0.55) * drive) * e
	return out


## Гул ламп / сердцебиение.
func _drone(sec: float, base: float, wobble: float) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var f := base + sin(TAU * 0.13 * t) * wobble
		phase += f / SR
		var e := _env(i, n, 0.15, 0.85)
		out[i] = (sin(TAU * phase) * 0.5 + sin(TAU * phase * 2.0) * 0.22 + sin(TAU * phase * 3.01) * 0.11) * e * 0.5
	return out


## Детский хор — одна нота, много голосов расстроены.
func _choir(sec: float, base: float, voices: int) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phases := PackedFloat32Array()
	var freqs := PackedFloat32Array()
	for v in voices:
		phases.append(0.0)
		freqs.append(base * (1.0 + rng.randf_range(-0.012, 0.012)))
	for i in n:
		var e := _env(i, n, 0.25, 0.7)
		var acc := 0.0
		for v in voices:
			phases[v] += freqs[v] / SR
			var s := sin(TAU * phases[v])
			s += 0.3 * sin(TAU * phases[v] * 2.0)
			s += 0.14 * sin(TAU * phases[v] * 3.0)
			acc += s
		out[i] = acc / float(voices) * e * 0.55
	return out


## Кик (breakcore-основа).
func _kick(sec: float) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var f := lerpf(140.0, 42.0, minf(1.0, t / 0.12))
		phase += f / SR
		var e := _env(i, n, 0.002, 0.98)
		out[i] = tanh(sin(TAU * phase) * 2.2) * e * 0.9
	return out


## Хэт / шумовой слой.
func _hat(sec: float, bright: float) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1403
	var lp := 0.0
	for i in n:
		var nz := rng.randf_range(-1.0, 1.0)
		lp += (nz - lp) * bright
		var e := _env(i, n, 0.001, 0.995)
		out[i] = lp * e * 0.5
	return out


## Бас-петля (слои 2+).
func _bass_loop(sec: float, root: float) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var steps := [0.0, 0.0, 7.0, 0.0, 3.0, 0.0, -2.0, 0.0]
	var step_len := sec / float(steps.size())
	var phase := 0.0
	for i in n:
		var si := int(float(i) / SR / step_len) % steps.size()
		var f := root * pow(2.0, steps[si] / 12.0)
		phase += f / SR
		var local := fmod(float(i) / SR, step_len) / step_len
		var e := maxf(0.0, 1.0 - local * 1.35)
		out[i] = tanh(sin(TAU * phase) * 1.7 + sin(TAU * phase * 2.0) * 0.4) * e * 0.55
	return out


## Брейкбит-ломаная петля (слой SSS+).
func _break_loop(sec: float) -> PackedFloat32Array:
	var n := int(SR * sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var kicks := _kick(0.22)
	var hats := _hat(0.06, 0.85)
	var pattern_k := [0.00, 0.38, 0.50, 0.88, 1.25, 1.62, 1.75, 2.13, 2.50, 2.63, 3.00, 3.38, 3.50, 3.88]
	var pattern_h := [0.25, 0.75, 1.25, 1.50, 2.25, 2.75, 3.25, 3.50]
	for i in n:
		out[i] = 0.0
	for pk in pattern_k:
		var start := int(pk / sec * float(n))
		for j in kicks.size():
			var idx := start + j
			if idx >= 0 and idx < n:
				out[idx] += kicks[j] * 0.85
	for ph in pattern_h:
		var start2 := int(ph / sec * float(n))
		for j2 in hats.size():
			var idx2 := start2 + j2
			if idx2 >= 0 and idx2 < n:
				out[idx2] += hats[j2] * 0.5
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gain_b: float) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var av := a[i] if i < a.size() else 0.0
		var bv := b[i] if i < b.size() else 0.0
		out[i] = av + bv * gain_b
	return out


# ============================================================ СБОРКА БАНКА

func _build_all() -> void:
	_cache["hit_light"]   = _make_stream(_noise_hit(0.12, 210.0, 2.4))
	_cache["hit_heavy"]   = _make_stream(_noise_hit(0.28, 90.0, 3.6))
	_cache["parry"]       = _make_stream(_mix(_noise_hit(0.30, 1250.0, 3.0), _choir(0.45, 880.0, 3), 0.35))
	_cache["shoot"]       = _make_stream(_noise_hit(0.16, 420.0, 3.2))
	_cache["shotgun"]     = _make_stream(_mix(_noise_hit(0.42, 70.0, 4.2), _kick(0.2), 0.6))
	_cache["saw"]         = _make_stream(_noise_hit(0.55, 340.0, 2.0))
	_cache["dash"]        = _make_stream(_noise_hit(0.18, 620.0, 1.4))
	_cache["jump"]        = _make_stream(_noise_hit(0.10, 300.0, 1.1))
	_cache["land"]        = _make_stream(_noise_hit(0.14, 120.0, 2.0))
	_cache["slam"]        = _make_stream(_mix(_noise_hit(0.5, 55.0, 4.5), _kick(0.3), 0.8))
	_cache["hurt"]        = _make_stream(_mix(_noise_hit(0.35, 160.0, 2.6), _choir(0.5, 220.0, 5), 0.5))
	_cache["heal"]        = _make_stream(_choir(0.55, 660.0, 4))
	_cache["coin"]        = _make_stream(_mix(_noise_hit(0.34, 2100.0, 2.2), _choir(0.3, 1760.0, 2), 0.4))
	_cache["enemy_die"]   = _make_stream(_mix(_noise_hit(0.4, 130.0, 3.4), _choir(0.6, 150.0, 6), 0.55))
	_cache["rank_up"]     = _make_stream(_choir(1.1, 523.25, 8))
	_cache["ui"]          = _make_stream(_noise_hit(0.06, 900.0, 1.2))
	_cache["chalk"]       = _make_stream(_hat(0.7, 0.12))            # скрип мела — «голос» Веры
	_cache["ambient_white"] = _make_stream(_drone(AMBIENT_SEC, 58.0, 3.0), true)
	_cache["ambient_rust"]  = _make_stream(_mix(_drone(AMBIENT_SEC, 41.0, 9.0), _choir(AMBIENT_SEC, 82.0, 3), 0.35), true)

	# музыкальные слои по рангу стиля
	var mus0 := _drone(LOOP_SEC, 49.0, 1.5)
	var mus1 := _mix(mus0, _bass_loop(LOOP_SEC, 49.0), 0.75)
	var mus2 := _mix(mus1, _break_loop(LOOP_SEC), 0.55)
	var mus3 := _mix(mus2, _choir(LOOP_SEC, 392.0, 7), 0.6)
	_cache["music_0"] = _make_stream(mus0, true)
	_cache["music_1"] = _make_stream(mus1, true)
	_cache["music_2"] = _make_stream(mus2, true)
	_cache["music_3"] = _make_stream(mus3, true)

	for i in 4:
		var p := AudioStreamPlayer.new()
		p.stream = _cache["music_%d" % i]
		p.volume_db = music_volume_db - 60.0
		p.bus = "Master"
		add_child(p)
		_music_layers.append(p)


# ============================================================ ВОСПРОИЗВЕДЕНИЕ

func play(sfx_id: String, volume_offset_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _cache.has(sfx_id):
		return
	var p: AudioStreamPlayer = _free_player()
	if p == null:
		return
	p.stream = _cache[sfx_id]
	p.volume_db = sfx_volume_db + volume_offset_db
	p.pitch_scale = pitch
	p.play()


func _free_player() -> AudioStreamPlayer:
	for i in _players.size():
		var p: AudioStreamPlayer = _players[i]
		if not p.playing:
			return p
	return _players[0]


## Слои музыки: 0 — вне боя, 1 — ранг B, 2 — ранг S, 3 — ранг SSS/ULR.
func _on_rank_changed(_old: String, new_rank: String) -> void:
	var idx := 0
	var v := Style.rank_value(new_rank)
	if v >= Style.rank_value("SSS"):
		idx = 3
	elif v >= Style.rank_value("S"):
		idx = 2
	elif v >= Style.rank_value("B"):
		idx = 1
	set_music_layer(idx)
	if v >= Style.rank_value("S"):
		play("rank_up", -10.0)


func set_music_layer(idx: int) -> void:
	if idx == _current_music_layer:
		return
	_current_music_layer = idx
	music_layer_changed.emit(idx)
	for i in _music_layers.size():
		var p := _music_layers[i]
		if i == idx:
			if not p.playing:
				p.play()
			p.volume_db = music_volume_db
		else:
			p.volume_db = music_volume_db - 60.0


func set_ambient(layer: String) -> void:
	var key := "ambient_rust" if layer == "rust" else "ambient_white"
	if not _cache.has(key):
		return
	_ambient.stream = _cache[key]
	_ambient.volume_db = -20.0
	if not _ambient.playing:
		_ambient.play()


func stop_all() -> void:
	for i in _players.size():
		_players[i].stop()
	for p in _music_layers:
		p.stop()
	_ambient.stop()
	_current_music_layer = -1


func has_sfx(sfx_id: String) -> bool:
	return _cache.has(sfx_id)
