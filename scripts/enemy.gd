extends CharacterBody2D
## INIMIGO — três variantes no mesmo script (escolha em `kind`):
##   GUNNER  (atirador):  mira com LASER por um instante e dispara 1 bala
##   SHOTGUN (escopeta):  mira mais devagar, 5 projéteis de curto alcance
##   BRUTE   (brutamontes): corre até você, ergue o cano (aviso) e golpeia
## Patrulha até VER o jogador (linha de visão + cone na frente). Morre com 1 golpe
## ou com a própria bala rebatida. A origem do nó fica nos PÉS.

signal killed(enemy: Node)

const Fx := preload("res://scripts/fx.gd")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

enum Kind { GUNNER, SHOTGUN, BRUTE }
enum State { PATROL, REACT, CHASE, AIM, WINDUP, STRIKE, RECOVER, DEAD }

## Ajuste fino de cada tipo de inimigo.
const STATS := {
	Kind.GUNNER: {
		"walk": 60.0, "chase": 120.0, "vision": 500.0, "react": 0.3,
		"aim": 0.55, "cooldown": 0.85, "pellets": 1, "spread": 0.0,
		"bullet_speed": 700.0, "bullet_life": 2.0, "range": 480.0,
		"color": Color("#c4485e"), "visor": Color("#ffd25a"),
	},
	Kind.SHOTGUN: {
		"walk": 50.0, "chase": 110.0, "vision": 420.0, "react": 0.35,
		"aim": 0.8, "cooldown": 1.3, "pellets": 5, "spread": 0.42,
		"bullet_speed": 640.0, "bullet_life": 0.6, "range": 340.0,
		"color": Color("#b0503a"), "visor": Color("#ff8a3d"),
	},
	Kind.BRUTE: {
		"walk": 70.0, "chase": 250.0, "vision": 480.0, "react": 0.25,
		"windup": 0.36, "cooldown": 0.6, "reach": 62.0,
		"color": Color("#8e3a6b"), "visor": Color("#ff4060"),
	},
}

@export var kind: Kind = Kind.GUNNER
@export var facing := -1
@export var patrols := true

var state: State = State.PATROL
var _st: Dictionary
var _t := 0.0
var _player: Node2D
var _last_seen := Vector2.ZERO
var _sees_player := false
var _vision_timer := 0.0
var _turn_pause := 0.0
var _aim_point := Vector2.ZERO
var _laser_end := Vector2.ZERO
var _muzzle_flash := 0.0
var _anim := 0.0
var _dead_rot := 0.0
var _resting := false


func _ready() -> void:
	add_to_group("enemies")
	_st = STATS[kind]
	floor_snap_length = 8.0


func is_alive() -> bool:
	return state != State.DEAD


# ------------------------------------------------------------- loop ---

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_physics_dead(delta)
		return
	_t += delta
	_muzzle_flash = maxf(0.0, _muzzle_flash - delta)
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_vision_timer -= delta
	if _vision_timer <= 0.0:
		_vision_timer = 0.06
		_sees_player = _can_see_player()
	if _sees_player:
		_last_seen = _player_center()

	match state:
		State.PATROL:
			_patrol(delta)
		State.REACT:
			_brake(delta)
			_face_toward(_last_seen)
			if _t >= float(_st["react"]):
				_decide()
		State.CHASE:
			_chase(delta)
		State.AIM:
			_aim(delta)
		State.WINDUP:
			_brake(delta)
			if _t >= float(_st["windup"]):
				_set_state(State.STRIKE)
				_strike()
		State.STRIKE:
			_brake(delta)
			if _t >= 0.14:
				_set_state(State.RECOVER)
		State.RECOVER:
			_brake(delta)
			if _t >= float(_st["cooldown"]):
				_decide()

	velocity.y = minf(velocity.y + 2200.0 * delta, 1000.0)
	move_and_slide()
	_anim += absf(velocity.x) * delta * 0.05
	queue_redraw()


func _set_state(s: State) -> void:
	state = s
	_t = 0.0


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)


func _face_toward(p: Vector2) -> void:
	var dx := p.x - global_position.x
	if absf(dx) > 4.0:
		facing = 1 if dx > 0.0 else -1


func _player_alive() -> bool:
	return is_instance_valid(_player) and _player.is_alive()


func _player_center() -> Vector2:
	return _player.global_position + Vector2(0, -24)


func _eye() -> Vector2:
	return global_position + Vector2(facing * 4.0, -40.0)


func _shoulder() -> Vector2:
	return global_position + Vector2(0, -30)


func _muzzle() -> Vector2:
	return _shoulder() + (_aim_point - _shoulder()).normalized() * 22.0


# ------------------------------------------------------------- percepção ---

func _can_see_player() -> bool:
	if not _player_alive():
		return false
	var eye := _eye()
	var to := _player_center() - eye
	var dist := to.length()
	if dist > float(_st["vision"]) or absf(to.y) > 360.0:
		return false
	# patrulhando: só enxerga na frente (ou muito perto)
	if state == State.PATROL and signf(to.x) != float(facing) and dist > 90.0:
		return false
	var q := PhysicsRayQueryParameters2D.create(eye, _player_center(), Game.L_WORLD)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## Faz o inimigo perceber o jogador (visto, ou um aliado morreu perto).
func alert(at: Vector2) -> void:
	if state != State.PATROL:
		return
	_last_seen = at
	_set_state(State.REACT)
	Sfx.play("alert", -8.0)


func _decide() -> void:
	if not _player_alive():
		_set_state(State.PATROL)
		return
	if kind == Kind.BRUTE:
		_set_state(State.CHASE)
	elif _sees_player and _in_range():
		_start_aim()
	else:
		_set_state(State.CHASE)


func _in_range() -> bool:
	return global_position.distance_to(_player_center()) <= float(_st.get("range", 0.0))


func _wall_ahead() -> bool:
	return test_move(global_transform, Vector2(facing * 4.0, 0))


func _ledge_ahead() -> bool:
	var from := global_position + Vector2(facing * 16.0, -4.0)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 28), Game.L_WORLD | Game.L_PLATFORM)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# ------------------------------------------------------------- estados ---

func _patrol(delta: float) -> void:
	if _sees_player:
		alert(_last_seen)
		return
	if not patrols or not is_on_floor():
		_brake(delta)
		return
	if _turn_pause > 0.0:
		_turn_pause -= delta
		velocity.x = 0.0
		if _turn_pause <= 0.0:
			facing = -facing
		return
	if _wall_ahead() or _ledge_ahead():
		_turn_pause = 0.8
		velocity.x = 0.0
		return
	velocity.x = facing * float(_st["walk"])


func _chase(delta: float) -> void:
	if not _player_alive():
		_set_state(State.PATROL)
		return
	if kind == Kind.BRUTE:
		if _sees_player:
			var p := _player_center()
			if absf(p.x - global_position.x) < float(_st["reach"]) and absf(p.y - (global_position.y - 24.0)) < 56.0:
				_face_toward(p)
				_set_state(State.WINDUP)
				Sfx.play("windup", -4.0)
				return
	elif _sees_player and _in_range():
		_start_aim()
		return

	var dx := _last_seen.x - global_position.x
	_face_toward(_last_seen)
	var speed := float(_st["chase"])
	if absf(dx) < 12.0:
		speed = 0.0
	elif _wall_ahead():
		speed = 0.0
	elif _ledge_ahead() and _last_seen.y < global_position.y + 20.0:
		speed = 0.0   # não pula da borda se o jogador não está abaixo
	velocity.x = move_toward(velocity.x, facing * speed, 1600.0 * delta)


func _start_aim() -> void:
	_set_state(State.AIM)
	_aim_point = _player_center()
	_face_toward(_aim_point)


func _aim(delta: float) -> void:
	_brake(delta)
	var aim_time := float(_st["aim"])
	var tracking := _t < aim_time * 0.7   # nos últimos 30% a mira TRAVA (hora de reagir!)
	if tracking:
		if _sees_player:
			_aim_point = _aim_point.lerp(_player_center(), 1.0 - exp(-14.0 * delta))
		elif _t > 0.15:
			_set_state(State.CHASE)
			return
	_face_toward(_aim_point)
	# ponto final do laser (até bater numa parede)
	var dir := (_aim_point - _shoulder()).normalized()
	var far := _shoulder() + dir * 1400.0
	var q := PhysicsRayQueryParameters2D.create(_muzzle(), far, Game.L_WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	_laser_end = far if hit.is_empty() else Vector2(hit["position"])
	if _t >= aim_time:
		_fire()
		_set_state(State.RECOVER)


func _fire() -> void:
	var muzzle := _muzzle()
	var base := (_aim_point - _shoulder()).normalized()
	var n := int(_st["pellets"])
	var spread := float(_st["spread"])
	for i in n:
		var a := 0.0
		if n > 1:
			a = lerpf(-spread * 0.5, spread * 0.5, float(i) / (n - 1)) + randf_range(-0.04, 0.04)
		var b := BULLET_SCENE.instantiate()
		b.setup(muzzle, base.rotated(a), float(_st["bullet_speed"]), float(_st["bullet_life"]), self)
		get_parent().add_child(b)
	_muzzle_flash = 0.06
	Sfx.play("shotgun" if n > 1 else "shot", -2.0)
	Fx.sparks(get_parent(), muzzle, base, Color("#ffd25a"), 6, 300.0)


func _strike() -> void:
	Sfx.play("swing", -2.0)
	if not _player_alive():
		return
	var p := _player_center()
	var dx := p.x - global_position.x
	var in_front := signf(dx) == float(facing) or absf(dx) < 14.0
	if in_front and absf(dx) < float(_st["reach"]) + 12.0 and absf(p.y - (global_position.y - 24.0)) < 60.0:
		_player.die(Vector2(facing, -0.4))


# ------------------------------------------------------------- dano ---

func on_slashed(dir: Vector2, _by: Node) -> void:
	if state == State.DEAD:
		return
	Game.hitstop(0.07)
	Game.shake(9.0)
	die(dir)


## Atingido por bala rebatida.
func on_bullet(dir: Vector2) -> void:
	if state == State.DEAD:
		return
	Game.shake(6.0)
	die(dir)


func die(dir: Vector2) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_t = 0.0
	collision_layer = 0
	var d := dir.normalized()
	velocity = d * 520.0 + Vector2(0, -220)
	_dead_rot = 0.0
	Fx.blood(get_parent(), global_position + Vector2(0, -26), d, 34)
	Sfx.play("kill")
	killed.emit(self)


func _physics_dead(delta: float) -> void:
	_t += delta
	velocity.y = minf(velocity.y + 2200.0 * delta, 1000.0)
	_dead_rot = lerp_angle(_dead_rot, PI * 0.5 * -facing, minf(1.0, 7.0 * delta))
	move_and_slide()
	# só "descansa" depois de voar e cair de volta no chão
	if is_on_floor() and _t > 0.15:
		velocity.x = move_toward(velocity.x, 0.0, 1300.0 * delta)
		_resting = absf(velocity.x) < 4.0
	else:
		_resting = false
	queue_redraw()
	if _resting and absf(angle_difference(_dead_rot, PI * 0.5 * -facing)) < 0.02:
		set_physics_process(false)


# ------------------------------------------------------------- visual ---

func _draw() -> void:
	var f := float(facing)
	var big := 1.15 if kind == Kind.BRUTE else 1.0
	var col: Color = _st["color"]
	var visor: Color = _st["visor"]

	if state == State.DEAD:
		draw_set_transform(Vector2(0, -2), _dead_rot, Vector2(f * big, big))
		_draw_body(col.darkened(0.45), visor.darkened(0.7), Vector2(-4, 0), Vector2(5, 0))
		return

	# laser de mira (coordenadas sem espelhamento)
	if state == State.AIM:
		var locked := _t >= float(_st["aim"]) * 0.7
		var on := not locked or int(_t * 30.0) % 2 == 0
		if on:
			var a := 0.35 if not locked else 0.9
			draw_line(to_local(_muzzle()), to_local(_laser_end), Color(1.0, 0.15, 0.25, a), 1.5 if not locked else 2.5)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(f * big, big))
	var fa := Vector2(-4, 0)
	var fb := Vector2(5, 0)
	if absf(velocity.x) > 10.0:
		fa = Vector2(sin(_anim) * 8.0, -maxf(0.0, cos(_anim)) * 5.0)
		fb = Vector2(-sin(_anim) * 8.0, -maxf(0.0, -cos(_anim)) * 5.0)
	var body_col := col
	if state == State.WINDUP and int(_t * 20.0) % 2 == 0:
		body_col = Color.WHITE
	_draw_body(body_col, visor, fa, fb)

	# arma
	if kind == Kind.BRUTE:
		var sh := Vector2(2, -32)
		var end: Vector2
		match state:
			State.WINDUP:
				end = sh + Vector2(-14, -34)
			State.STRIKE:
				end = sh + Vector2(44, 6)
			_:
				end = sh + Vector2(16, 24)
		draw_line(sh, end, Color("#9aa3b5"), 5.0)
	else:
		var aiming := state in [State.AIM, State.RECOVER, State.REACT]
		var d := Vector2(0.5, 0.85).normalized()
		if aiming:
			var w := (_aim_point - _shoulder()).normalized()
			d = Vector2(w.x * f, w.y)
		var sh := Vector2(0, -30)
		var hand := sh + d * 14.0
		draw_line(sh, hand, body_col, 4.0)
		var gun_len := 20.0 if kind == Kind.SHOTGUN else 12.0
		draw_line(hand, hand + d * gun_len, Color("#2a2733"), 5.0 if kind == Kind.SHOTGUN else 4.0)
		if _muzzle_flash > 0.0:
			draw_circle(hand + d * (gun_len + 6.0), 7.0, Color("#fff1b0"))

	# aviso "!" quando percebe o jogador
	if state == State.REACT:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-6, -64 * big), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color.BLACK)
		draw_string(font, Vector2(-6, -64 * big), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#ffd25a"))


func _draw_body(col: Color, visor: Color, fa: Vector2, fb: Vector2) -> void:
	var hip := Vector2(0, -20)
	var leg := col.darkened(0.35)
	draw_line(hip, fa, leg, 5.0)
	draw_line(hip + Vector2(2, 0), fb, leg, 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-9, -18), Vector2(9, -18), Vector2(8, -40), Vector2(-8, -40)]), col)
	draw_line(Vector2(-9, -24), Vector2(9, -24), col.darkened(0.4), 2.0)
	draw_rect(Rect2(-7, -54, 15, 14), col.lightened(0.15))   # cabeça/capacete
	draw_rect(Rect2(1, -50, 8, 4), visor)                      # visor
