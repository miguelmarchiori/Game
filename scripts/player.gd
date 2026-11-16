extends CharacterBody2D
## JOGADOR — começa de MÃOS LIVRES.
##
## Movimento / parkour
##   corrida que acelera até "sprint" · pulo com coyote/buffer · deslizar e pular na parede
##   DASH (Shift, 8 direções, 1 no ar) · DESLIZE (S correndo — passa por vãos baixos,
##   acelera em rampas, pulo no deslize = pulo longo) · AGACHAR (S parado)
##   VAULT automático em obstáculos baixos · AGARRAR BORDA e subir
## Combate
##   clique: soco, soco, chute (combo) · mira pra cima: gancho · no ar: voadora (na direção do mouse)
##   no ar de novo: soco aéreo · deslizando: rasteira · logo após o dash: soco investida
##   F: chute frontal (empurra longe) · armas: E pega, clique usa, botão direito arremessa
## A origem do nó fica nos PÉS.

signal died
signal hit_landed(damage: int)
signal damaged(amount: int)

const Fx := preload("res://scripts/fx.gd")
const Rig := preload("res://scripts/rig.gd")
const Weapons := preload("res://scripts/weapons.gd")
const ITEM := preload("res://scripts/weapon_item.gd")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

const STYLE := {
	"skin": Color("#e8b48f"), "hair": Color("#2b1d14"),
	"top": Color("#ff7b29"), "top_dark": Color("#c25a17"),
	"legs": Color("#34435a"), "legs_dark": Color("#252f3f"),
	"shoes": Color("#ececec"), "fist": Color("#f4f1ea"),
	"head_r": 7.0, "torso_w": 8.0, "limb_w": 6.0, "hood": true,
}
const STYLE_HURT := {
	"skin": Color.WHITE, "hair": Color.WHITE, "top": Color.WHITE, "top_dark": Color(0.9, 0.9, 0.9),
	"legs": Color.WHITE, "legs_dark": Color(0.9, 0.9, 0.9), "shoes": Color.WHITE, "fist": Color.WHITE,
	"head_r": 7.0, "torso_w": 8.0, "limb_w": 6.0, "hood": true,
}

## Golpes desarmados. hit = janela (s) em que o golpe acerta. kb = empurrão (x para frente).
const MOVES := {
	"jab":       {"dmg": 9,  "dur": 0.2,  "hit": [0.04, 0.11], "reach": 46.0, "h": 34.0, "kb": Vector2(170, -30),  "stun": 0.3,  "lunge": 150.0, "sfx": "punch"},
	"cross":     {"dmg": 12, "dur": 0.22, "hit": [0.05, 0.12], "reach": 50.0, "h": 34.0, "kb": Vector2(230, -40),  "stun": 0.32, "lunge": 180.0, "sfx": "punch"},
	"kick":      {"dmg": 20, "dur": 0.36, "hit": [0.09, 0.19], "reach": 60.0, "h": 46.0, "kb": Vector2(560, -220), "stun": 0.5,  "lunge": 200.0, "sfx": "kick", "down": true},
	"upper":     {"dmg": 16, "dur": 0.32, "hit": [0.05, 0.15], "reach": 44.0, "h": 56.0, "kb": Vector2(110, -720), "stun": 0.5,  "lunge": 60.0,  "sfx": "kick", "launch": true, "up": true},
	"flykick":   {"dmg": 20, "dur": 0.34, "hit": [0.03, 0.26], "reach": 52.0, "h": 40.0, "kb": Vector2(520, -200), "stun": 0.5,  "lunge": 560.0, "sfx": "kick", "down": true, "aimed": true},
	"airjab":    {"dmg": 10, "dur": 0.22, "hit": [0.04, 0.12], "reach": 48.0, "h": 40.0, "kb": Vector2(150, -260), "stun": 0.4,  "lunge": 60.0,  "sfx": "punch", "air": true},
	"pushkick":  {"dmg": 14, "dur": 0.38, "hit": [0.1, 0.2],   "reach": 62.0, "h": 40.0, "kb": Vector2(860, -230), "stun": 0.5,  "lunge": 80.0,  "sfx": "kick", "down": true},
	"dashpunch": {"dmg": 26, "dur": 0.3,  "hit": [0.0, 0.14],  "reach": 58.0, "h": 42.0, "kb": Vector2(720, -250), "stun": 0.6,  "lunge": 0.0,   "sfx": "kick", "down": true, "keep": true},
	"sweep":     {"dmg": 12, "dur": 0.3,  "hit": [0.0, 0.24],  "reach": 50.0, "h": 26.0, "kb": Vector2(220, -420), "stun": 0.6,  "lunge": 0.0,   "sfx": "kick", "launch": true, "low": true},
}

@export_group("Corrida")
@export var run_speed := 300.0
@export var sprint_speed := 410.0
@export var sprint_delay := 0.45          ## segurando a direção no chão por esse tempo vira sprint
@export var ground_accel := 2600.0
@export var air_accel := 1800.0
@export var ground_friction := 2900.0
@export_group("Pulo")
@export var jump_velocity := 640.0
@export var gravity_up := 1750.0
@export var gravity_down := 2600.0
@export var max_fall_speed := 1000.0
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12
@export_group("Parede")
@export var wall_slide_speed := 140.0
@export var wall_jump_push := 380.0
@export var wall_jump_velocity := 600.0
@export var wall_jump_lock := 0.14
@export_group("Dash")
@export var dash_speed := 950.0
@export var dash_time := 0.15
@export var dash_cooldown := 0.3
@export var dash_exit_speed := 460.0
@export_group("Deslize")
@export var slide_min_speed := 170.0      ## velocidade mínima para deslizar (senão agacha)
@export var slide_start_min := 470.0
@export var slide_max := 780.0
@export var slide_friction := 520.0
@export var slide_slope_accel := 1500.0   ## aceleração ladeira abaixo
@export var slide_min_time := 0.22
@export_group("Vida")
@export var max_health := 100
@export var regen_delay := 3.0
@export var regen_rate := 30.0

enum State { NORMAL, CROUCH, SLIDE, DASH, MANTLE, ATTACK, DEAD }

var state: State = State.NORMAL
var facing := 1
var health := 100.0
var weapon := ""              ## "" = mãos livres
var ammo := 0
var near_item: Node = null    ## arma ao alcance (lida pelo HUD e pela arma)
var input_lock := 0.2
var frozen := false
var use_aim_override := false ## usado pelos testes automáticos
var aim_override := Vector2.ZERO
var empty_warning := 0.0      ## >0: mostrar aviso "sem munição"

var _coyote := 0.0
var _jump_buffer := 0.0
var _wall_dir := 0
var _wall_lock := 0.0
var _sprint_t := 0.0
var _launched := false
var _air_dashes := 1
var _air_kick_used := false
var _dash_dir := Vector2.RIGHT
var _dash_left := 0.0
var _dash_cd := 0.0
var _post_dash := 0.0
var _invuln := 0.0
var _slide_t := 0.0
var _slide_dir := 1
var _sweep_t := 0.0
var _slide_hit_ids := {}
var _mantle_from := Vector2.ZERO
var _mantle_to := Vector2.ZERO
var _mantle_t := 0.0
var _mantle_dur := 0.15
var _mantle_keep := 0.0
var _move_name := ""
var _move := {}
var _move_t := 0.0
var _move_dir := Vector2.RIGHT
var _hit_ids := {}
var _combo_step := 0
var _combo_window := 0.0
var _queued_attack := false
var _fire_cd := 0.0
var _muzzle_t := 0.0
var _throw_t := 0.0
var _regen_wait := 0.0
var _hurt_t := 0.0
var _drop_timer := 0.0
var _on_oneway := false
var _was_on_floor := true
var _ghost_timer := 0.0
var _dust_timer := 0.0
var _run_phase := 0.0
var _anim_t := 0.0
var _squash := Vector2.ONE
var _body_rot := 0.0
var _dead_rot := 0.0
var _low := false
var _pose := {}
var _shape_node: CollisionShape2D
var _capsule: CapsuleShape2D


func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 10.0
	floor_max_angle = deg_to_rad(50.0)
	_shape_node = $CollisionShape2D
	_capsule = (_shape_node.shape as CapsuleShape2D).duplicate()
	_shape_node.shape = _capsule
	health = max_health
	_pose = _pose_idle()


# ------------------------------------------------------------- consultas ---

func is_alive() -> bool:
	return state != State.DEAD


func center() -> Vector2:
	return global_position + Vector2(0, -12 if _low else -24)


func aim_point() -> Vector2:
	return aim_override if use_aim_override else get_global_mouse_position()


func _aim_dir() -> Vector2:
	var d := aim_point() - _shoulder()
	return d.normalized() if d.length_squared() > 1.0 else Vector2(facing, 0)


func _shoulder() -> Vector2:
	return global_position + Vector2(facing * 2.0, -16.0 if _low else -34.0)


func speed_ratio() -> float:
	return clampf(absf(velocity.x) / sprint_speed, 0.0, 2.0)


# ------------------------------------------------------------- loop ---

func _physics_process(delta: float) -> void:
	_anim_t += delta
	if state == State.DEAD:
		_physics_dead(delta)
		return
	_tick(delta)

	var can := input_lock <= 0.0 and not frozen
	var ix := Input.get_axis("move_left", "move_right") if can else 0.0
	var down_held := can and Input.is_action_pressed("down")
	if can and Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	var on_floor := is_on_floor()
	if on_floor and velocity.y >= 0.0:
		_coyote = coyote_time
		_air_kick_used = false
		_air_dashes = 1
		_launched = false
	_wall_dir = 0 if on_floor else _detect_wall()
	_update_sprint(delta, ix, on_floor)
	_update_near_item()

	if can:
		_handle_actions(ix, on_floor)

	match state:
		State.NORMAL:
			_state_normal(delta, ix, on_floor)
		State.CROUCH:
			_state_crouch(delta, ix, down_held)
		State.SLIDE:
			_state_slide(delta, down_held)
		State.DASH:
			_state_dash(delta)
		State.MANTLE:
			_state_mantle(delta)
		State.ATTACK:
			_state_attack(delta)

	if state != State.MANTLE:
		move_and_slide()
	_after_move(delta)
	_update_pose(delta)
	queue_redraw()


func _tick(delta: float) -> void:
	input_lock = maxf(0.0, input_lock - delta)
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_post_dash = maxf(0.0, _post_dash - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_combo_window = maxf(0.0, _combo_window - delta)
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_muzzle_t = maxf(0.0, _muzzle_t - delta)
	_throw_t = maxf(0.0, _throw_t - delta)
	_hurt_t = maxf(0.0, _hurt_t - delta)
	empty_warning = maxf(0.0, empty_warning - delta)
	if _combo_window <= 0.0:
		_combo_step = 0
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			set_collision_mask_value(5, true)
	# regeneração de vida
	if _regen_wait > 0.0:
		_regen_wait -= delta
	elif health < max_health:
		health = minf(max_health, health + regen_rate * delta)


func _detect_wall() -> int:
	if test_move(global_transform, Vector2(-3, 0)):
		return -1
	if test_move(global_transform, Vector2(3, 0)):
		return 1
	return 0


func _apply_gravity(delta: float, scale := 1.0) -> void:
	var g := gravity_down
	if velocity.y < 0.0 and (Input.is_action_pressed("jump") or _launched):
		g = gravity_up
	velocity.y = minf(velocity.y + g * scale * delta, max_fall_speed)


func _update_sprint(delta: float, ix: float, on_floor: bool) -> void:
	var same_dir := absf(ix) > 0.1 and signf(ix) == signf(velocity.x) and absf(velocity.x) > run_speed * 0.85
	if same_dir and (on_floor or _sprint_t > 0.0):
		_sprint_t += delta if on_floor else 0.0
	elif absf(ix) < 0.1 or signf(ix) != signf(velocity.x):
		_sprint_t = 0.0


# ------------------------------------------------------------- comandos ---

func _handle_actions(ix: float, on_floor: bool) -> void:
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and state in [State.NORMAL, State.CROUCH, State.SLIDE, State.ATTACK]:
		if on_floor or _air_dashes > 0:
			_start_dash(ix, on_floor)
			return
	if Input.is_action_just_pressed("interact"):
		_try_pickup()
	if Input.is_action_just_pressed("throw") and weapon != "" and state != State.MANTLE:
		_throw_weapon()
	if Input.is_action_just_pressed("kick") and state in [State.NORMAL, State.CROUCH]:
		_stand_if_possible()
		if state == State.NORMAL:
			_start_move("pushkick")
			return

	if weapon != "" and Weapons.is_gun(weapon):
		var d: Dictionary = Weapons.DATA[weapon]
		var wants: bool = Input.is_action_pressed("attack") if d["auto"] else Input.is_action_just_pressed("attack")
		if wants and _fire_cd <= 0.0 and state in [State.NORMAL, State.CROUCH, State.SLIDE]:
			_fire()
	elif Input.is_action_just_pressed("attack"):
		if state == State.ATTACK:
			if _move_t > float(_move["dur"]) * 0.35:
				_queued_attack = true
		elif state in [State.NORMAL, State.CROUCH, State.SLIDE, State.DASH]:
			_start_attack(on_floor)

	if Input.is_action_just_pressed("down"):
		if on_floor and state == State.NORMAL:
			if _on_oneway and absf(ix) < 0.1 and absf(velocity.x) < 80.0:
				_drop_through()
			elif absf(velocity.x) >= slide_min_speed:
				_start_slide()
			else:
				state = State.CROUCH
				_set_low(true)
		elif not on_floor and state == State.NORMAL:
			velocity.y = maxf(velocity.y, 760.0)   # mergulho rápido


# ------------------------------------------------------------- estados ---

func _horizontal(delta: float, ix: float, on_floor: bool, top_override := -1.0) -> void:
	var top := sprint_speed if _sprint_t >= sprint_delay else run_speed
	if top_override > 0.0:
		top = top_override
	var accel := ground_accel if on_floor else air_accel
	if _wall_lock > 0.0:
		accel *= 0.2
	if absf(ix) > 0.1:
		if signf(ix) == signf(velocity.x) and absf(velocity.x) > top:
			# acima do limite (veio de dash/deslize/rampa): perde velocidade aos poucos
			velocity.x = move_toward(velocity.x, ix * top, (650.0 if on_floor else 90.0) * delta)
		else:
			velocity.x = move_toward(velocity.x, ix * top, accel * delta)
	elif on_floor:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, air_accel * 0.2 * delta)


func _update_facing(ix: float) -> void:
	if weapon != "" and Weapons.is_gun(weapon):
		facing = 1 if aim_point().x >= global_position.x else -1
	elif absf(ix) > 0.1:
		facing = 1 if ix > 0.0 else -1


func _state_normal(delta: float, ix: float, on_floor: bool) -> void:
	_horizontal(delta, ix, on_floor)
	_update_facing(ix)
	_apply_gravity(delta)

	# deslizar na parede
	var sliding := not on_floor and _wall_dir != 0 and velocity.y > 0.0 and int(signf(ix)) == _wall_dir
	if sliding:
		velocity.y = minf(velocity.y, wall_slide_speed)
		facing = -_wall_dir
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.07
			Fx.dust(get_parent(), global_position + Vector2(_wall_dir * 10.0, -30.0), 1)

	# agarrar borda (no ar, empurrando contra a parede) / vault (correndo contra obstáculo baixo)
	if not on_floor and _wall_dir != 0 and int(signf(ix)) == _wall_dir and velocity.y > -260.0:
		var ledge := _find_ledge(_wall_dir, 84.0)
		if ledge.is_finite():
			_start_mantle(ledge, false)
			return
	elif on_floor and absf(ix) > 0.1 and absf(velocity.x) > 160.0 and test_move(global_transform, Vector2(signf(ix) * 6.0, 0)):
		var low := _find_ledge(int(signf(ix)), 40.0)
		if low.is_finite():
			_start_mantle(low, true)
			return

	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			_jump()
		elif _wall_dir != 0:
			_wall_jump()


func _jump() -> void:
	velocity.y = -jump_velocity
	_jump_buffer = 0.0
	_coyote = 0.0
	_squash = Vector2(0.78, 1.22)
	Sfx.play("jump", -10.0)
	Fx.dust(get_parent(), global_position, 5)


func _wall_jump() -> void:
	velocity = Vector2(-_wall_dir * wall_jump_push, -wall_jump_velocity)
	facing = -_wall_dir
	_wall_lock = wall_jump_lock
	_jump_buffer = 0.0
	_air_dashes = 1
	_air_kick_used = false
	_squash = Vector2(0.8, 1.2)
	Sfx.play("jump", -10.0, 1.15)
	Fx.dust(get_parent(), global_position + Vector2(_wall_dir * 10.0, -20.0), 5)


func _drop_through() -> void:
	set_collision_mask_value(5, false)
	_drop_timer = 0.22
	position.y += 2.0


func _state_crouch(delta: float, ix: float, down_held: bool) -> void:
	velocity.x = move_toward(velocity.x, ix * 120.0, ground_accel * delta)
	_update_facing(ix)
	_apply_gravity(delta)
	var free := _can_stand()
	if _jump_buffer > 0.0 and _coyote > 0.0 and free:
		_set_low(false)
		state = State.NORMAL
		_jump()
	elif (not down_held or not is_on_floor()) and free:
		_set_low(false)
		state = State.NORMAL


# --- deslize ---

func _start_slide() -> void:
	state = State.SLIDE
	_slide_t = 0.0
	_sweep_t = 0.0
	_slide_dir = int(signf(velocity.x)) if absf(velocity.x) > 1.0 else facing
	facing = _slide_dir
	velocity.x = _slide_dir * clampf(absf(velocity.x) * 1.15, slide_start_min, slide_max)
	_slide_hit_ids.clear()
	_set_low(true)
	Sfx.play("slide", -4.0)
	Fx.dust(get_parent(), global_position, 6, Vector2(-_slide_dir, -0.3), 0.6)


func _state_slide(delta: float, down_held: bool) -> void:
	_slide_t += delta
	var on_floor := is_on_floor()
	if on_floor:
		var n := get_floor_normal()
		if absf(n.x) > 0.1:
			velocity.x += n.x * slide_slope_accel * delta     # rampa: acelera na descida, freia na subida
			velocity.x = clampf(velocity.x, -slide_max * 1.25, slide_max * 1.25)
		else:
			velocity.x = move_toward(velocity.x, 0.0, slide_friction * delta)
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.05
			Fx.dust(get_parent(), global_position + Vector2(_slide_dir * 10.0, 0), 1, Vector2(-_slide_dir, -0.5), 0.5)
	_apply_gravity(delta)
	if absf(velocity.x) > 1.0:
		_slide_dir = int(signf(velocity.x))
		facing = _slide_dir

	# rasteira (clique durante o deslize) ou deslize comum derrubando
	if _sweep_t > 0.0:
		_sweep_t -= delta
		_do_hits(MOVES["sweep"], Vector2(_slide_dir, 0), true)
	else:
		_slide_bump()

	if _jump_buffer > 0.0 and _coyote > 0.0 and _can_stand():
		# pulo longo: mantém a velocidade do deslize
		_set_low(false)
		state = State.NORMAL
		velocity.x *= 1.06
		_sprint_t = sprint_delay
		_jump()
		return
	var slow := absf(velocity.x) < 140.0
	var released := not down_held and _slide_t > slide_min_time
	if slow or released or (not on_floor and _slide_t > 0.15):
		if _can_stand():
			_set_low(false)
			state = State.NORMAL
			if absf(velocity.x) > run_speed:
				_sprint_t = sprint_delay
		elif on_floor:
			state = State.CROUCH


func _slide_bump() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(36, 22)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, global_position + Vector2(_slide_dir * 16.0, -11.0))
	q.collision_mask = Game.L_ENEMY
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 8):
		var e: Object = hit["collider"]
		if e == null or _slide_hit_ids.has(e.get_instance_id()) or not e.has_method("take_hit"):
			continue
		_slide_hit_ids[e.get_instance_id()] = true
		e.take_hit({"dmg": 8, "kb": Vector2(_slide_dir * 160.0, -380.0), "stun": 0.5, "launch": true, "from": self})
		_on_hit(8, (e as Node2D).global_position + Vector2(0, -20), "kick")


# --- dash ---

func _start_dash(ix: float, on_floor: bool) -> void:
	var vy := 0.0
	if Input.is_action_pressed("down"):
		vy += 1.0
	if Input.is_action_pressed("jump"):
		vy -= 1.0
	var d := Vector2(ix, vy)
	if on_floor and d.y > 0.0:
		d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector2(facing, 0)
	d = d.normalized()
	if state == State.SLIDE or state == State.CROUCH:
		if not _can_stand():
			return
		_set_low(false)
	state = State.DASH
	_dash_dir = d
	_dash_left = dash_time
	_dash_cd = dash_cooldown
	_invuln = dash_time + 0.04
	if not on_floor:
		_air_dashes -= 1
	if absf(d.x) > 0.1:
		facing = 1 if d.x > 0.0 else -1
	velocity = d * dash_speed
	_launched = false
	_squash = Vector2(1.25, 0.8)
	Sfx.play("dash", -3.0)
	Game.shake(2.0)
	Fx.dust(get_parent(), global_position + Vector2(0, -10), 5, -d, 0.5)


func _state_dash(delta: float) -> void:
	_dash_left -= delta
	velocity = _dash_dir * dash_speed
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.022
		Fx.ghost(get_parent(), global_position, _pose, facing)
	# pulo durante o dash no chão = pulo longo
	if _jump_buffer > 0.0 and _coyote > 0.0 and absf(_dash_dir.y) < 0.1:
		state = State.NORMAL
		velocity.x = _dash_dir.x * dash_exit_speed * 1.1
		_sprint_t = sprint_delay
		_post_dash = 0.15
		_jump()
		return
	if _dash_left <= 0.0:
		state = State.NORMAL
		velocity = _dash_dir * dash_exit_speed
		if _dash_dir.y < 0.0:
			velocity.y = _dash_dir.y * dash_exit_speed * 0.7
		if absf(_dash_dir.x) > 0.5:
			_sprint_t = sprint_delay
		_post_dash = 0.16


# --- borda / vault ---

## Procura o topo de um obstáculo à frente (até max_h acima dos pés). Retorna INF se não houver.
func _find_ledge(dir: int, max_h: float) -> Vector2:
	var feet := global_position
	var x := feet.x + dir * 14.0
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(Vector2(x, feet.y - max_h - 4.0), Vector2(x, feet.y - 6.0), Game.L_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector2.INF
	var n: Vector2 = hit["normal"]
	if n.y > -0.7:
		return Vector2.INF
	var top: float = Vector2(hit["position"]).y
	var target := Vector2(feet.x + dir * 22.0, top - 0.5)
	if not _shape_free_at(target, false):
		return Vector2.INF
	return target


func _start_mantle(target: Vector2, vault: bool) -> void:
	state = State.MANTLE
	_mantle_from = global_position
	_mantle_to = target
	_mantle_t = 0.0
	var h := global_position.y - target.y
	_mantle_dur = 0.13 if vault else clampf(0.1 + h * 0.0016, 0.13, 0.24)
	_mantle_keep = velocity.x if vault else signf(target.x - global_position.x) * 140.0
	velocity = Vector2.ZERO
	facing = 1 if target.x > global_position.x else -1
	Sfx.play("vault", -6.0)


func _state_mantle(delta: float) -> void:
	_mantle_t += delta
	var k := clampf(_mantle_t / _mantle_dur, 0.0, 1.0)
	var up_k := 1.0 - pow(1.0 - minf(k * 1.5, 1.0), 2.0)
	var fw_k := smoothstep(0.25, 1.0, k)
	global_position = Vector2(lerpf(_mantle_from.x, _mantle_to.x, fw_k), lerpf(_mantle_from.y, _mantle_to.y, up_k))
	if k >= 1.0:
		state = State.NORMAL
		velocity = Vector2(_mantle_keep, 0)
		_coyote = coyote_time
		_squash = Vector2(1.15, 0.88)


# --- ataque ---

func _start_attack(on_floor: bool) -> void:
	if weapon != "":
		_stand_if_possible()
		if state == State.CROUCH:
			return
		_start_move("weapon")
		return
	if state == State.SLIDE:
		_sweep_t = 0.26
		_hit_ids.clear()
		Sfx.play("whoosh", -6.0)
		return
	if state == State.DASH or _post_dash > 0.0:
		_start_move("dashpunch")
		return
	if state == State.CROUCH:
		if not _can_stand():
			return
		_set_low(false)
		_start_move("upper")
		return
	if not on_floor:
		_start_move("airjab" if _air_kick_used else "flykick")
		return
	var aim := _aim_dir()
	if aim.y < -0.8:
		_start_move("upper")
		return
	var chain := ["jab", "cross", "kick"]
	_start_move(chain[_combo_step])
	_combo_step = (_combo_step + 1) % 3


func _start_move(move_name: String) -> void:
	_move_name = move_name
	if move_name == "weapon":
		var d: Dictionary = Weapons.DATA[weapon]
		var dur: float = d["dur"]
		_move = {"dmg": d["dmg"], "dur": dur, "hit": [dur * 0.28, dur * 0.62], "reach": d["alcance"], "h": 56.0,
			"kb": d["kb"], "stun": d["atordoa"], "lunge": 120.0, "sfx": d["som"], "down": d["derruba"],
			"deflect": d.get("rebate", false)}
	else:
		_move = MOVES[move_name]
	_move_t = 0.0
	_hit_ids.clear()
	_queued_attack = false
	state = State.ATTACK
	var aim := _aim_dir()
	facing = 1 if aim.x >= 0.0 else -1
	_move_dir = Vector2(facing, 0)
	var lunge: float = _move["lunge"]
	if _move.get("aimed", false):
		_move_dir = aim
		_air_kick_used = true
		var v := aim * lunge
		v.y = minf(v.y, 220.0) if aim.y > 0.0 else v.y
		velocity = v
	elif _move.get("up", false):
		_move_dir = Vector2(facing * 0.35, -1.0).normalized()
		velocity.x = facing * lunge
		if is_on_floor():
			velocity.y = -260.0
	elif _move.get("keep", false):
		velocity.x = facing * maxf(absf(velocity.x), 420.0)
	elif _move.get("air", false):
		velocity.x = velocity.x * 0.5 + facing * lunge
		velocity.y = minf(velocity.y, -60.0)    # "segura" no ar: dá para fazer combo aéreo
	else:
		velocity.x = facing * maxf(lunge, absf(velocity.x) * 0.4)
	_combo_window = float(_move["dur"]) + 0.38
	Sfx.play("whoosh", -7.0, 1.2 if float(_move["dur"]) < 0.25 else 0.9)
	if move_name == "weapon" and weapon in ["taco", "espada"]:
		Fx.slash(self, Vector2(0, -26), aim if weapon == "espada" else Vector2(facing, 0), float(_move["reach"]) * 0.85, Color(1, 0.95, 0.85))


func _state_attack(delta: float) -> void:
	_move_t += delta
	var hit: Array = _move["hit"]
	if _move_t >= float(hit[0]) and _move_t <= float(hit[1]):
		_do_hits(_move, _move_dir, _move.get("low", false))
	var on_floor := is_on_floor()
	if _move.get("aimed", false):
		_apply_gravity(delta, 0.45)
		if on_floor and _move_t > 0.08:
			_move_t = maxf(_move_t, float(_move["dur"]) - 0.06)
	elif not on_floor:
		_apply_gravity(delta, 0.4)
	else:
		_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, (1300.0 if on_floor else 300.0) * delta)
	# cancelar a recuperação com pulo
	if _move_t > float(hit[1]) and _jump_buffer > 0.0 and _coyote > 0.0:
		state = State.NORMAL
		_jump()
		return
	if _move_t >= float(_move["dur"]):
		state = State.NORMAL
		if _queued_attack:
			_queued_attack = false
			_start_attack(is_on_floor())


func _do_hits(m: Dictionary, dir: Vector2, low: bool) -> void:
	var reach: float = m["reach"]
	var shape := RectangleShape2D.new()
	shape.size = Vector2(reach, float(m["h"]))
	var origin := global_position + Vector2(0, -12 if low else -26)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(dir.angle(), origin + dir * (reach * 0.5 + 2.0))
	q.collision_mask = Game.L_ENEMY | (Game.L_BULLET if m.get("deflect", false) else 0)
	q.collide_with_areas = true
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var c: Object = hit["collider"]
		if c == null or _hit_ids.has(c.get_instance_id()):
			continue
		_hit_ids[c.get_instance_id()] = true
		if c.has_method("on_deflect"):
			c.on_deflect(_aim_dir(), self)
			continue
		if not c.has_method("take_hit"):
			continue
		var kb: Vector2 = m["kb"]
		var kbw := Vector2(kb.x * signf(dir.x if absf(dir.x) > 0.1 else facing), kb.y)
		if m.get("aimed", false):
			kbw = dir * kb.x + Vector2(0, kb.y * 0.5)
		c.take_hit({"dmg": int(m["dmg"]), "kb": kbw, "stun": float(m["stun"]), "down": m.get("down", false),
			"launch": m.get("launch", false), "from": self})
		var e2 := c as Node2D
		_on_hit(int(m["dmg"]), e2.global_position + Vector2(0, -26) if e2 else origin, String(m["sfx"]))
		if m.get("aimed", false):
			velocity = -dir * 220.0 + Vector2(0, -200)   # voadora: quica para trás
			_air_kick_used = false
		if _move_name == "weapon" and Weapons.DATA[weapon].get("quebra", false):
			Fx.shards(get_parent(), origin + dir * 30.0, dir, Weapons.C_GLASS, 14)
			weapon = ""
			ammo = 0
			Sfx.play("glass")


func _on_hit(dmg: int, at: Vector2, sfx: String) -> void:
	Game.hitstop(clampf(0.03 + dmg * 0.0018, 0.03, 0.09))
	Game.shake(2.5 + dmg * 0.15)
	Sfx.play(sfx, -2.0)
	Fx.impact(get_parent(), at, dmg >= 20)
	register_hit(dmg)


## Qualquer acerto do jogador (golpe, tiro, arremesso) passa aqui (contador de combo).
func register_hit(dmg: int) -> void:
	hit_landed.emit(dmg)


# --- armas ---

func _fire() -> void:
	var d: Dictionary = Weapons.DATA[weapon]
	if ammo <= 0:
		Sfx.play("empty", -4.0)
		_fire_cd = 0.25
		empty_warning = 1.5
		return
	ammo -= 1
	_fire_cd = float(d["cadencia"])
	var dir := _aim_dir()
	var muzzle := _shoulder() + dir * (16.0 + float(d["len"]))
	var q := PhysicsRayQueryParameters2D.create(center(), muzzle, Game.L_WORLD)
	var block := get_world_2d().direct_space_state.intersect_ray(q)
	if not block.is_empty():
		muzzle = Vector2(block["position"]) - dir * 3.0
	var n := int(d["projeteis"])
	var spread := float(d["dispersao"])
	for i in n:
		var a := randf_range(-spread, spread) * 0.5
		if n > 1:
			a = lerpf(-spread * 0.5, spread * 0.5, float(i) / (n - 1)) + randf_range(-0.03, 0.03)
		var b := BULLET_SCENE.instantiate()
		b.setup(muzzle, dir.rotated(a), float(d["vel"]) * randf_range(0.92, 1.05), float(d["alcance"]), self, "player", int(d["dmg"]), float(d["kb"]))
		get_parent().add_child(b)
	var recoil := float(d["recuo"])
	if is_on_floor():
		velocity.x -= dir.x * recoil * 0.4
	else:
		velocity -= dir * recoil      # escopeta no ar = impulso!
		if dir.y > 0.5 and recoil > 200.0:
			_launched = true
	_muzzle_t = 0.05
	Sfx.play(String(d["som"]), -3.0)
	Game.shake(1.5 + recoil * 0.01)
	Fx.sparks(get_parent(), muzzle, dir, Color("#ffe3a3"), 4, 260.0)


func _throw_weapon() -> void:
	var dir := _aim_dir()
	var it := ITEM.new()
	it.kind = weapon
	it.ammo = ammo
	it.position = center() + dir * 18.0
	get_parent().add_child(it)
	it.throw(dir, 1000.0, self)
	weapon = ""
	ammo = 0
	_throw_t = 0.18
	Sfx.play("throw", -2.0)


func _try_pickup() -> void:
	if not is_instance_valid(near_item):
		return
	if weapon != "":
		_drop_weapon(Vector2(-facing * 120.0, -220.0))
	weapon = near_item.kind
	ammo = near_item.ammo
	near_item.queue_free()
	near_item = null
	Sfx.play("pickup", -4.0)


func _drop_weapon(vel: Vector2) -> void:
	if weapon == "":
		return
	var it := ITEM.new()
	it.kind = weapon
	it.ammo = ammo
	it.position = center()
	it.pickup_delay = 0.5
	get_parent().add_child(it)
	it.linear_velocity = vel
	it.angular_velocity = randf_range(-10.0, 10.0)
	weapon = ""
	ammo = 0


func _update_near_item() -> void:
	near_item = null
	var best := 62.0
	for it in get_tree().get_nodes_in_group("items"):
		if it.is_queued_for_deletion() or it.thrown or it.pickup_delay > 0.0:
			continue
		var dist := center().distance_to(it.global_position)
		if dist < best:
			best = dist
			near_item = it


# ------------------------------------------------------------- vida ---

## Retorna true se o dano foi aplicado (false durante o dash / morto / modo deus).
func take_damage(amount: int, dir: Vector2) -> bool:
	if state == State.DEAD or _invuln > 0.0:
		return false
	if Game.god_mode:
		_hurt_t = 0.08
		return true
	health -= amount
	_regen_wait = regen_delay
	_hurt_t = 0.14
	velocity += dir.normalized() * 140.0
	Fx.blood(get_parent(), center(), dir, 5 + amount / 3)
	Sfx.play("hurt", -3.0)
	Game.shake(4.0)
	damaged.emit(amount)
	if health <= 0.0:
		_die(dir)
	return true


func _die(dir: Vector2) -> void:
	health = 0.0
	if state == State.SLIDE or state == State.CROUCH:
		_set_low(false)
	state = State.DEAD
	_drop_weapon(Vector2(randf_range(-150, 150), -260))
	collision_layer = 0
	velocity = dir.normalized() * 380.0 + Vector2(0, -260)
	Fx.blood(get_parent(), center(), dir, 30)
	Sfx.play("player_death")
	Game.hitstop(0.1)
	Game.shake(12.0)
	died.emit()


func respawn(at: Vector2) -> void:
	state = State.NORMAL
	health = max_health
	_set_low(false)
	collision_layer = Game.L_PLAYER
	set_collision_mask_value(5, true)
	global_position = at
	velocity = Vector2.ZERO
	_dead_rot = 0.0
	_body_rot = 0.0
	input_lock = 0.2
	_invuln = 0.6
	_pose = _pose_idle()
	reset_physics_interpolation()


func _physics_dead(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity_down * delta, max_fall_speed)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	_dead_rot = lerp_angle(_dead_rot, -PI * 0.5, minf(1.0, 8.0 * delta))
	move_and_slide()
	Rig.blend(_pose, _pose_limp(), 10.0, delta)
	queue_redraw()


## Plataforma de salto.
func launch(v: Vector2) -> void:
	if state == State.DEAD:
		return
	if state in [State.SLIDE, State.CROUCH, State.DASH, State.ATTACK]:
		_set_low(false)
		state = State.NORMAL
	velocity.y = v.y
	_launched = true
	_air_dashes = 1
	_air_kick_used = false
	_coyote = 0.0
	_squash = Vector2(0.7, 1.3)


# ------------------------------------------------------------- colisão baixa ---

func _set_low(on: bool) -> void:
	if _low == on:
		return
	_low = on
	_capsule.height = 24.0 if on else 44.0
	_shape_node.position.y = -12.0 if on else -22.0


func _stand_if_possible() -> void:
	if (state == State.CROUCH or state == State.SLIDE) and _can_stand():
		_set_low(false)
		state = State.NORMAL


func _can_stand() -> bool:
	return _shape_free_at(global_position, true)


func _shape_free_at(feet: Vector2, standing: bool) -> bool:
	var cap := CapsuleShape2D.new()
	cap.radius = 9.0
	cap.height = 42.0 if standing else 22.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cap
	q.transform = Transform2D(0.0, feet + Vector2(0, -cap.height * 0.5 - 1.5))
	q.collision_mask = Game.L_WORLD
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _after_move(delta: float) -> void:
	_on_oneway = false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < -0.7:
			var c := col.get_collider()
			if c is Node and (c as Node).is_in_group("oneway"):
				_on_oneway = true
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor and state != State.MANTLE:
		_squash = Vector2(1.22, 0.8)
		Sfx.play("land", -12.0)
		Fx.dust(get_parent(), global_position, 4)
	_was_on_floor = now_floor
	_run_phase += absf(velocity.x) * delta * 0.05
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, 12.0 * delta))
	# poeira do sprint
	if now_floor and state == State.NORMAL and absf(velocity.x) > run_speed + 30.0:
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.09
			Fx.dust(get_parent(), global_position, 1, Vector2(-signf(velocity.x), -0.4), 0.4)


# ------------------------------------------------------------- poses ---

func _pose_idle() -> Dictionary:
	var b := sin(_anim_t * 3.0) * 0.8
	return Rig.pose(Vector2(0, -21 + b * 0.3), Vector2(2, -36 + b), Vector2(4, -46 + b),
		Vector2(11, -38 + b), Vector2(6, -35 + b), Vector2(7, 0), Vector2(-6, 0))


func _pose_limp() -> Dictionary:
	return Rig.pose(Vector2(0, -20), Vector2(1, -35), Vector2(2, -44), Vector2(10, -24), Vector2(-8, -22), Vector2(8, 0), Vector2(-6, -2))


func _pose_run() -> Dictionary:
	var ph := _run_phase
	var s := clampf(absf(velocity.x) / sprint_speed, 0.0, 1.2)
	var lean := 2.0 + 6.0 * s
	var amp := 9.0 + 6.0 * s
	var bob := absf(sin(ph)) * -2.0
	return Rig.pose(Vector2(0, -21 + bob), Vector2(lean, -36 + bob), Vector2(lean + 3.0, -45 + bob),
		Vector2(lean - sin(ph) * amp, -27 - maxf(0.0, -sin(ph)) * 5.0),
		Vector2(lean + sin(ph) * amp, -27 - maxf(0.0, sin(ph)) * 5.0),
		Vector2(sin(ph) * (11.0 + 4.0 * s), -maxf(0.0, cos(ph)) * (7.0 + 3.0 * s)),
		Vector2(-sin(ph) * (11.0 + 4.0 * s), -maxf(0.0, -cos(ph)) * (7.0 + 3.0 * s)))


func _target_pose() -> Dictionary:
	match state:
		State.SLIDE:
			var ff := Vector2(25, -5) if _sweep_t > 0.0 else Vector2(19, -3)
			return Rig.pose(Vector2(-2, -9), Vector2(-11, -17), Vector2(-14, -25), Vector2(5, -15), Vector2(-19, -2), ff, Vector2(4, -2))
		State.CROUCH:
			var w := sin(_run_phase) * 5.0 if absf(velocity.x) > 10.0 else 0.0
			return Rig.pose(Vector2(0, -13), Vector2(4, -25), Vector2(7, -34), Vector2(13, -28), Vector2(8, -24), Vector2(8 + w, 0), Vector2(-7 - w, 0))
		State.DASH:
			return Rig.pose(Vector2(-2, -20), Vector2(9, -31), Vector2(15, -36), Vector2(22, -31), Vector2(14, -27), Vector2(-12, -10), Vector2(-7, -16))
		State.MANTLE:
			return Rig.pose(Vector2(0, -24), Vector2(5, -40), Vector2(9, -47), Vector2(13, -52), Vector2(9, -50), Vector2(7, -12), Vector2(-3, -18))
		State.ATTACK:
			return _attack_pose()
	var p: Dictionary
	if not is_on_floor():
		if _wall_dir != 0 and velocity.y > 0.0:
			p = Rig.pose(Vector2(0, -21), Vector2(-1, -36), Vector2(1, -46), Vector2(9, -40), Vector2(-11, -42), Vector2(-5, -3), Vector2(-9, -14))
		elif velocity.y < 0.0:
			p = Rig.pose(Vector2(0, -22), Vector2(2, -37), Vector2(4, -47), Vector2(10, -46), Vector2(-7, -42), Vector2(7, -9), Vector2(-5, -4))
		else:
			p = Rig.pose(Vector2(0, -21), Vector2(1, -36), Vector2(3, -46), Vector2(13, -36), Vector2(-11, -36), Vector2(6, -3), Vector2(-7, -7))
	elif absf(velocity.x) > 30.0:
		p = _pose_run()
	else:
		p = _pose_idle()
	_apply_arm_overrides(p)
	return p


## Braços segurando arma / arremessando.
func _apply_arm_overrides(p: Dictionary) -> void:
	var chest: Vector2 = p["chest"]
	if _throw_t > 0.0:
		var a := _aim_dir()
		p["hand_f"] = chest + Vector2(a.x * facing, a.y) * 20.0
	elif weapon != "" and Weapons.is_gun(weapon):
		var a2 := _aim_dir()
		var al := Vector2(a2.x * facing, a2.y)
		p["hand_f"] = chest + Vector2(1, 1) + al * 17.0
		if weapon != "pistola":
			p["hand_b"] = chest + Vector2(1, 3) + al * 10.0
	elif weapon != "":
		p["hand_f"] = chest + Vector2(7, 9)
		p["hand_b"] = chest + Vector2(3, 7)


func _attack_pose() -> Dictionary:
	var dur: float = _move["dur"]
	var hit: Array = _move["hit"]
	var h0 := float(hit[0]) / dur
	var h1 := float(hit[1]) / dur
	var k := clampf(_move_t / dur, 0.0, 1.0)
	var e := 0.0
	if k < h0:
		e = smoothstep(0.0, maxf(h0, 0.001), k)
	elif k <= h1:
		e = 1.0
	else:
		e = 1.0 - smoothstep(h1, 1.0, k)
	if h0 <= 0.0 and k < h1:
		e = 1.0
	var g := _pose_idle()
	var x: Dictionary
	match _move_name:
		"jab":
			x = Rig.pose(Vector2(1, -21), Vector2(5, -36), Vector2(7, -46), Vector2(29, -37), Vector2(7, -35), Vector2(9, 0), Vector2(-6, 0))
		"cross":
			x = Rig.pose(Vector2(1, -21), Vector2(7, -35), Vector2(9, -45), Vector2(6, -40), Vector2(29, -36), Vector2(10, 0), Vector2(-8, 0))
		"kick":
			x = Rig.pose(Vector2(-1, -23), Vector2(-6, -37), Vector2(-8, -46), Vector2(6, -40), Vector2(-10, -36), Vector2(31, -32), Vector2(-3, 0))
		"pushkick":
			x = Rig.pose(Vector2(-2, -22), Vector2(-7, -36), Vector2(-9, -45), Vector2(4, -38), Vector2(-8, -36), Vector2(31, -20), Vector2(-4, 0))
		"upper":
			g = Rig.pose(Vector2(0, -16), Vector2(4, -29), Vector2(6, -38), Vector2(10, -22), Vector2(6, -26), Vector2(8, 0), Vector2(-7, 0))
			x = Rig.pose(Vector2(0, -23), Vector2(4, -40), Vector2(6, -50), Vector2(12, -63), Vector2(4, -34), Vector2(6, -2), Vector2(-6, 0))
		"flykick":
			return Rig.pose(Vector2(0, -22), Vector2(-6, -34), Vector2(-8, -43), Vector2(-4, -40), Vector2(-12, -32), Vector2(27, -17), Vector2(-5, -12))
		"airjab":
			g = Rig.pose(Vector2(0, -22), Vector2(2, -37), Vector2(4, -47), Vector2(10, -40), Vector2(5, -36), Vector2(6, -8), Vector2(-6, -5))
			x = Rig.pose(Vector2(0, -22), Vector2(5, -37), Vector2(8, -46), Vector2(30, -38), Vector2(5, -36), Vector2(8, -6), Vector2(-7, -8))
		"dashpunch":
			x = Rig.pose(Vector2(-2, -20), Vector2(10, -32), Vector2(15, -38), Vector2(34, -33), Vector2(6, -30), Vector2(12, -2), Vector2(-14, -4))
		"weapon":
			return _weapon_swing_pose(k, h0, h1)
		_:
			x = g
	var out := {}
	for key in Rig.KEYS:
		out[key] = Vector2(g[key]).lerp(x[key], e)
	return out


func _weapon_swing_pose(k: float, h0: float, h1: float) -> Dictionary:
	var p := _pose_idle()
	var rest := Vector2(9, -28)
	var back := Vector2(-4, -48)
	var front := Vector2(25, -26)
	if weapon == "faca":
		back = Vector2(6, -32)
		front = Vector2(31, -34)
	var hand: Vector2
	if k < h0:
		hand = rest.lerp(back, smoothstep(0.0, h0, k))
	elif k < h1:
		hand = back.lerp(front, smoothstep(h0, h1, k))
	else:
		hand = front.lerp(rest, smoothstep(h1, 1.0, k))
	p["hand_f"] = hand
	p["hand_b"] = hand + Vector2(-5, 3)
	var lean := 5.0 if k > h0 and k < h1 + 0.2 else 0.0
	p["chest"] = Vector2(p["chest"]) + Vector2(lean, 0)
	p["head"] = Vector2(p["head"]) + Vector2(lean, 0)
	return p


## Ângulo da arma branca (referencial do personagem olhando para a direita).
func _weapon_local_angle() -> float:
	var rest := -1.9 if weapon in ["taco", "espada", "garrafa"] else -0.5
	if state != State.ATTACK or _move_name != "weapon":
		return rest
	var dur: float = _move["dur"]
	var hit: Array = _move["hit"]
	var k := _move_t / dur
	var h0 := float(hit[0]) / dur
	var h1 := float(hit[1]) / dur
	if weapon == "faca":
		return 0.0 if k > h0 * 0.5 and k < 1.0 else rest
	if k < h0:
		return lerpf(rest, -2.5, smoothstep(0.0, h0, k))
	elif k < h1:
		return lerpf(-2.5, 0.7, smoothstep(h0, h1, k))
	return lerpf(0.7, rest, smoothstep(h1, 1.0, k))


func _update_pose(delta: float) -> void:
	var target := _target_pose()
	var rate := 22.0
	if state == State.ATTACK or state == State.DASH:
		rate = 42.0
	elif state == State.SLIDE or state == State.MANTLE:
		rate = 30.0
	Rig.blend(_pose, target, rate, delta)
	# inclinação do corpo na voadora
	var want_rot := 0.0
	if state == State.ATTACK and _move_name == "flykick":
		var kick_vec := Vector2(27.0 * facing, 5.0)
		want_rot = clampf(kick_vec.angle_to(_move_dir), -1.3, 1.3)
	_body_rot = lerp_angle(_body_rot, want_rot, minf(1.0, 25.0 * delta))


# ------------------------------------------------------------- desenho ---

func _draw() -> void:
	var f := float(facing)
	var m: Transform2D
	if state == State.DEAD:
		m = Transform2D(_dead_rot, Vector2(f, 1), 0.0, Vector2(0, -6)) * Transform2D(0.0, Vector2(0, 6))
	elif absf(_body_rot) > 0.01:
		m = Transform2D(_body_rot, Vector2(f, 1), 0.0, Vector2(0, -22)) * Transform2D(0.0, Vector2(0, 22))
	else:
		m = Transform2D(0.0, Vector2(f * _squash.x, _squash.y), 0.0, Vector2.ZERO)
	draw_set_transform_matrix(m)
	Rig.draw_figure(self, _pose, STYLE_HURT if _hurt_t > 0.0 else STYLE)
	if weapon == "" or state == State.DEAD:
		return
	var hand: Vector2 = m * Vector2(_pose["hand_f"])
	if Weapons.is_gun(weapon):
		var a := _aim_dir()
		Weapons.draw(self, weapon, hand, a.angle(), -1.0 if a.x < 0.0 else 1.0)
		if _muzzle_t > 0.0:
			var tip := hand + a * (float(Weapons.DATA[weapon]["len"]) + 6.0)
			draw_circle(tip, 7.0, Color("#fff1c2"))
			draw_circle(tip, 4.0, Color.WHITE)
	else:
		var wv := m.basis_xform(Vector2.from_angle(_weapon_local_angle()))
		Weapons.draw(self, weapon, hand, wv.angle(), f)
