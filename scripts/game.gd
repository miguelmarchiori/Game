extends Node
## Autoload "Game" — controla o TEMPO do jogo (câmera lenta + hitstop),
## tremida de câmera, camadas de física e estatísticas da sessão.
##
## Tudo que mexe em Engine.time_scale passa por aqui, para a câmera lenta
## e o "congelamento" de impacto (hitstop) não brigarem entre si.

signal slowmo_toggled(active: bool)

# --- Camadas de física (bits) — iguais às de Projeto > Config. > Nomes de camadas ---
const L_WORLD := 1      # camada 1: paredes/chão
const L_PLAYER := 2     # camada 2: jogador
const L_ENEMY := 4      # camada 3: inimigos
const L_BULLET := 8     # camada 4: balas (Area2D, para o golpe poder rebatê-las)
const L_PLATFORM := 16  # camada 5: plataformas finas (atravessáveis por baixo)
const TILE := 32

# --- Câmera lenta (bateria "FOCO") ---
const SLOWMO_SCALE := 0.3            ## velocidade do mundo durante a câmera lenta
const SLOWMO_DRAIN := 0.3            ## bateria gasta por segundo REAL (~3,3 s de uso)
const SLOWMO_RECHARGE := 0.2         ## bateria recarregada por segundo real
const SLOWMO_RECHARGE_DELAY := 0.6   ## espera antes de começar a recarregar
const SLOWMO_MIN_START := 0.1        ## bateria mínima para ativar
const SLOWMO_FADE := 8.0             ## rapidez da transição normal <-> lento
const HITSTOP_SCALE := 0.03

var battery := 1.0
var slowmo_active := false
var slowmo_amount := 0.0          ## 0..1 suavizado (usado por efeitos visuais)
var gameplay_active := false      ## main.gd liga durante a fase, desliga em menus/morte
var god_mode := false             ## debug (F1)
var deaths := 0
var best_times := {}              ## índice da fase -> melhor tempo (s)

var _need_release := false
var _recharge_wait := 0.0
var _hitstop_left := 0.0
var _last_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	# delta de _process já vem multiplicado pelo time_scale; aqui precisamos do tempo REAL.
	var now := Time.get_ticks_usec()
	var real_dt := minf(float(now - _last_usec) / 1000000.0, 0.1)
	_last_usec = now
	if get_tree().paused:
		return
	_update_slowmo(real_dt)
	_hitstop_left = maxf(0.0, _hitstop_left - real_dt)
	var scale := lerpf(1.0, SLOWMO_SCALE, slowmo_amount)
	if _hitstop_left > 0.0:
		scale = HITSTOP_SCALE
	Engine.time_scale = scale
	# o som fica mais grave na câmera lenta (mas não "trava" no hitstop)
	AudioServer.playback_speed_scale = lerpf(1.0, 0.65, slowmo_amount)


func _update_slowmo(real_dt: float) -> void:
	var wants := gameplay_active and Input.is_action_pressed("slowmo")
	if not wants:
		_need_release = false
	if wants and not slowmo_active and not _need_release and battery >= SLOWMO_MIN_START:
		_set_slowmo(true)
	elif slowmo_active and (not wants or battery <= 0.0):
		if battery <= 0.0:
			_need_release = true
		_set_slowmo(false)

	if slowmo_active:
		battery = maxf(0.0, battery - SLOWMO_DRAIN * real_dt)
	elif _recharge_wait > 0.0:
		_recharge_wait -= real_dt
	else:
		battery = minf(1.0, battery + SLOWMO_RECHARGE * real_dt)
	slowmo_amount = move_toward(slowmo_amount, 1.0 if slowmo_active else 0.0, SLOWMO_FADE * real_dt)


func _set_slowmo(on: bool) -> void:
	slowmo_active = on
	if not on:
		_recharge_wait = SLOWMO_RECHARGE_DELAY
	Sfx.play("slowmo_in" if on else "slowmo_out", -6.0)
	slowmo_toggled.emit(on)


## Congela o jogo por alguns instantes (sensação de impacto).
func hitstop(duration: float) -> void:
	_hitstop_left = maxf(_hitstop_left, duration)


## Treme a câmera ativa.
func shake(amount: float) -> void:
	get_tree().call_group("camera", "add_shake", amount)


## Chamado pelo main.gd a cada início/reinício de fase.
func reset_for_level() -> void:
	battery = 1.0
	slowmo_active = false
	slowmo_amount = 0.0
	_need_release = false
	_recharge_wait = 0.0
	_hitstop_left = 0.0
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
