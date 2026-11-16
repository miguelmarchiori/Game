extends Node
## Autoload "Sfx" — efeitos sonoros PROVISÓRIOS sintetizados por código
## (assim o protótipo funciona sem nenhum arquivo de áudio).
##
## Para trocar por sons de verdade: coloque o arquivo em res://audio/ e, em
## _ready(), faça por exemplo:  _streams["slash"] = load("res://audio/corte.wav")
## O resto do jogo continua chamando Sfx.play("slash").

const RATE := 22050
const VOICES := 14

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


# ---------------------------------------------------------------- síntese ---

func _build_all() -> void:
	_streams["slash"] = _wav(_mix([_noise(0.15, 0.55, 2.5, 0.85, true), _tone(0.1, 1400.0, 500.0, 0.12, "saw", 2.0)]))
	_streams["deflect"] = _wav(_mix([_tone(0.4, 2300.0, 2250.0, 0.32, "sine", 3.0), _tone(0.3, 3450.0, 3400.0, 0.18, "sine", 4.0), _noise(0.03, 0.4, 1.0, 0.9, true)]))
	_streams["shot"] = _wav(_mix([_noise(0.22, 0.75, 4.0, 0.35, false), _tone(0.14, 170.0, 55.0, 0.5, "sine", 2.0)]))
	_streams["shotgun"] = _wav(_mix([_noise(0.38, 0.85, 3.0, 0.22, false), _tone(0.22, 130.0, 40.0, 0.6, "sine", 2.0)]))
	_streams["kill"] = _wav(_mix([_tone(0.24, 150.0, 38.0, 0.7, "square", 2.0), _noise(0.16, 0.5, 3.0, 0.3, false)]))
	_streams["player_death"] = _wav(_mix([_tone(0.7, 420.0, 55.0, 0.45, "saw", 1.4), _noise(0.25, 0.4, 3.0, 0.3, false)]))
	_streams["alert"] = _wav(_concat([_tone(0.05, 1320.0, 1320.0, 0.22, "square", 0.5), _silence(0.03), _tone(0.06, 1760.0, 1760.0, 0.22, "square", 0.5)]))
	_streams["roll"] = _wav(_noise(0.26, 0.35, 0.0, 0.12, false, true))
	_streams["jump"] = _wav(_tone(0.08, 240.0, 520.0, 0.18, "square", 1.5))
	_streams["land"] = _wav(_noise(0.07, 0.3, 3.0, 0.15, false))
	_streams["windup"] = _wav(_tone(0.32, 70.0, 110.0, 0.35, "saw", 0.6))
	_streams["swing"] = _wav(_noise(0.18, 0.5, 2.0, 0.25, false))
	_streams["door"] = _wav(_concat([_tone(0.1, 660.0, 660.0, 0.25, "square", 1.0), _tone(0.22, 990.0, 990.0, 0.25, "square", 1.5)]))
	_streams["clear"] = _wav(_concat([_tone(0.09, 523.0, 523.0, 0.22, "square", 1.0), _tone(0.09, 659.0, 659.0, 0.22, "square", 1.0), _tone(0.3, 784.0, 784.0, 0.22, "square", 2.0)]))
	_streams["slowmo_in"] = _wav(_tone(0.32, 700.0, 180.0, 0.25, "sine", 1.0))
	_streams["slowmo_out"] = _wav(_tone(0.22, 180.0, 700.0, 0.2, "sine", 1.0))
	_streams["ui"] = _wav(_tone(0.04, 880.0, 880.0, 0.2, "square", 1.0))
	# --- luta corpo a corpo / parkour / armas ---
	_streams["punch"] = _wav(_mix([_tone(0.08, 190.0, 85.0, 0.55, "sine", 2.0), _noise(0.06, 0.55, 3.0, 0.5, false)]))
	_streams["kick"] = _wav(_mix([_tone(0.13, 150.0, 55.0, 0.7, "sine", 2.0), _noise(0.1, 0.6, 3.0, 0.32, false)]))
	_streams["whoosh"] = _wav(_noise(0.13, 0.3, 0.0, 0.35, true, true))
	_streams["dash"] = _wav(_mix([_noise(0.2, 0.45, 0.0, 0.5, true, true), _tone(0.14, 260.0, 900.0, 0.1, "sine", 1.0)]))
	_streams["slide"] = _wav(_noise(0.38, 0.32, 0.0, 0.07, false, true))
	_streams["vault"] = _wav(_noise(0.09, 0.3, 2.0, 0.2, false))
	_streams["pickup"] = _wav(_concat([_tone(0.04, 620.0, 620.0, 0.18, "square", 1.0), _tone(0.06, 930.0, 930.0, 0.18, "square", 1.5)]))
	_streams["throw"] = _wav(_noise(0.16, 0.4, 0.0, 0.45, true, true))
	_streams["empty"] = _wav(_tone(0.03, 1300.0, 1300.0, 0.2, "square", 3.0))
	_streams["smg"] = _wav(_mix([_noise(0.09, 0.55, 4.0, 0.5, false), _tone(0.06, 230.0, 90.0, 0.4, "sine", 2.0)]))
	_streams["glass"] = _wav(_mix([_noise(0.28, 0.5, 3.0, 0.9, true), _tone(0.22, 3200.0, 3100.0, 0.14, "sine", 3.0), _tone(0.16, 4500.0, 4400.0, 0.1, "sine", 3.0)]))
	_streams["pad"] = _wav(_tone(0.26, 170.0, 760.0, 0.32, "square", 1.5))
	_streams["hurt"] = _wav(_tone(0.15, 320.0, 190.0, 0.28, "square", 1.5))
	_streams["bat"] = _wav(_mix([_tone(0.12, 420.0, 210.0, 0.45, "sine", 3.0), _noise(0.08, 0.6, 4.0, 0.55, false)]))
	_streams["splat"] = _wav(_mix([_tone(0.18, 110.0, 40.0, 0.8, "sine", 2.0), _noise(0.14, 0.7, 2.5, 0.25, false)]))


## Tom com glissando de f0 até f1. decay = expoente do envelope (0 = sem decaimento).
func _tone(dur: float, f0: float, f1: float, vol: float, wave: String, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var p := fmod(phase, 1.0)
		var s := 0.0
		match wave:
			"sine": s = sin(p * TAU)
			"square": s = 1.0 if p < 0.5 else -1.0
			"saw": s = p * 2.0 - 1.0
		var env := pow(1.0 - t, decay) * minf(1.0, i / 40.0)
		out[i] = s * vol * env
	return out


## Ruído. lp = filtro passa-baixa (0..1, menor = mais grave). hp = passa-alta. swell = envelope em "sino".
func _noise(dur: float, vol: float, decay: float, lp: float, hp := false, swell := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var x := randf_range(-1.0, 1.0)
		var prev := y
		y = lerpf(y, x, lp)
		var s := (y - prev) * 2.0 if hp else y
		var env := sin(t * PI) if swell else pow(1.0 - t, decay) * minf(1.0, i / 20.0)
		out[i] = s * vol * env
	return out


func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p: PackedFloat32Array in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p: PackedFloat32Array in parts:
		for i in p.size():
			out[i] += p[i]
	return out


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: PackedFloat32Array in parts:
		out.append_array(p)
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s
