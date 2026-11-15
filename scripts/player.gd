extends CharacterBody2D
## JOGADOR
##  - corrida com aceleração, pulo com "coyote time" e buffer, altura variável
##  - deslizar e pular na parede (dá para escalar paredes)
##  - rolamento INVENCÍVEL (S / CTRL no chão)
##  - golpe de lâmina na direção do mouse: mata inimigos e REBATE balas
##  - morre com UM acerto, igual aos inimigos
## A origem do nó fica nos PÉS do personagem.

signal died

const Fx := preload("res://scripts/fx.gd")

const C_COAT := Color("#ece6d9")
const C_LEGS := Color("#8f86b3")
const C_SKIN := Color("#e2b89a")
const C_HAIR := Color("#15121f")
const C_SCARF := Color("#ff3d7f")
const C_BLADE := Color("#d6e2f0")
const C_DARK := Color("#1a1726")

@export_group("Movimento")
@export var run_speed := 340.0
@export var ground_accel := 3200.0
@export var air_accel := 2200.0
@export var ground_friction := 3600.0
@export var jump_velocity := 650.0
@export var gravity_up := 1800.0         ## gravidade subindo com o pulo pressionado
@export var gravity_down := 2700.0       ## gravidade caindo / pulo solto (pulo curto)
@export var max_fall_speed := 980.0
@export var coyote_time := 0.1           ## ainda pode pular logo após sair da borda
@export var jump_buffer_time := 0.12     ## aperta pulo um pouco antes de tocar o chão
@export_group("Parede")
@export var wall_slide_speed := 150.0
@export var wall_jump_push := 360.0
@export var wall_jump_velocity := 600.0
@export var wall_jump_lock := 0.14       ## tempo com controle aéreo reduzido após pular da parede
@export_group("Rolamento")
@export var roll_speed := 560.0
@export var roll_time := 0.32
@export var roll_cooldown := 0.12
@export_group("Golpe")
@export var attack_cooldown := 0.34
@export var attack_duration := 0.16
@export var attack_active := 0.1         ## janela em que o golpe acerta coisas
@export var attack_lunge := 480.0        ## impulso na direção do golpe
@export var attack_reach := 62.0
@export var attack_width := 66.0

enum State { NORMAL, ROLL, ATTACK, DEAD }

var state: State = State.NORMAL
var facing := 1
var input_lock := 0.2         ## ignora comandos logo após nascer (evita golpe acidental)
var frozen := false           ## true quando a fase termina
var use_aim_override := false ## usado pelos testes automáticos
var aim_override := Vector2.ZERO

var _coyote := 0.0
var _jump_buffer := 0.0
var _wall_dir := 0
var _wall_lock := 0.0
var _roll_left := 0.0
var _roll_dir := 1
var _roll_cd := 0.0
var _attack_cd := 0.0
var _attack_left := 0.0
var _attack_dir := Vector2.RIGHT
var _air_attack_used := false
var _hit_ids := {}
var _drop_timer := 0.0
var _on_oneway := false
var _was_on_floor := true
var _ghost_timer := 0.0
var _dust_timer := 0.0
var _run_phase := 0.0
var _squash := Vector2.ONE
var _dead_rot := 0.0
var _scarf := PackedVector2Array()
var _scarf_prev := PackedVector2Array()


func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 8.0
	for i in 7:
		var p := global_position + Vector2(-4.0 - i * 5.0, -44.0)
		_scarf.append(p)
		_scarf_prev.append(p)


# ------------------------------------------------------------- consultas ---

func is_alive() -> bool:
	return state != State.DEAD


func is_invulnerable() -> bool:
	return state == State.ROLL or Game.god_mode


func center() -> Vector2:
	return global_position + Vector2(0, -24)


func aim_point() -> Vector2:
	return aim_override if use_aim_override else get_global_mouse_position()


# ------------------------------------------------------------- loop ---

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_physics_dead(delta)
		return
	_tick_timers(delta)

	var can_act := input_lock <= 0.0 and not frozen
	var input_x := 0.0
	if can_act:
		input_x = Input.get_axis("move_left", "move_right")
		if Input.is_action_just_pressed("jump"):
			_jump_buffer = jump_buffer_time
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = coyote_time
		_air_attack_used = false
	_wall_dir = 0 if on_floor else _detect_wall()

	if can_act and Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
		start_attack()
	elif can_act and Input.is_action_just_pressed("down"):
		_on_down_pressed(input_x, on_floor)

	match state:
		State.NORMAL:
			_state_normal(delta, input_x, on_floor)
		State.ROLL:
			_state_roll(delta)
		State.ATTACK:
			_state_attack(delta)

	move_and_slide()
	_after_move(delta)
	_update_scarf(delta)
	queue_redraw()


func _tick_timers(delta: float) -> void:
	input_lock = maxf(0.0, input_lock - delta)
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)
	_roll_cd = maxf(0.0, _roll_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			set_collision_mask_value(5, true)


func _detect_wall() -> int:
	if test_move(global_transform, Vector2(-3, 0)):
		return -1
	if test_move(global_transform, Vector2(3, 0)):
		return 1
	return 0


func _apply_gravity(delta: float, scale := 1.0) -> void:
	var g := gravity_down
	if velocity.y < 0.0 and Input.is_action_pressed("jump"):
		g = gravity_up
	velocity.y = minf(velocity.y + g * scale * delta, max_fall_speed)


# ------------------------------------------------------------- estados ---

func _state_normal(delta: float, input_x: float, on_floor: bool) -> void:
	var accel := ground_accel if on_floor else air_accel
	if _wall_lock > 0.0:
		accel *= 0.2
	if absf(input_x) > 0.1:
		velocity.x = move_toward(velocity.x, input_x * run_speed, accel * delta)
		facing = 1 if input_x > 0.0 else -1
	elif on_floor:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, air_accel * 0.35 * delta)

	_apply_gravity(delta)

	# deslizar na parede (segurando na direção dela)
	var sliding := not on_floor and _wall_dir != 0 and velocity.y > 0.0 and int(signf(input_x)) == _wall_dir
	if sliding:
		velocity.y = minf(velocity.y, wall_slide_speed)
		facing = -_wall_dir
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.08
			Fx.dust(get_parent(), global_position + Vector2(_wall_dir * 10.0, -30.0), 1)

	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			_jump()
		elif _wall_dir != 0:
			_wall_jump()


func _jump() -> void:
	velocity.y = -jump_velocity
	_jump_buffer = 0.0
	_coyote = 0.0
	_squash = Vector2(0.75, 1.25)
	Sfx.play("jump", -8.0)
	Fx.dust(get_parent(), global_position, 5)


func _wall_jump() -> void:
	velocity = Vector2(-_wall_dir * wall_jump_push, -wall_jump_velocity)
	facing = -_wall_dir
	_wall_lock = wall_jump_lock
	_jump_buffer = 0.0
	_squash = Vector2(0.8, 1.2)
	Sfx.play("jump", -8.0, 1.15)
	Fx.dust(get_parent(), global_position + Vector2(_wall_dir * 10.0, -20.0), 5)


func _on_down_pressed(input_x: float, on_floor: bool) -> void:
	if on_floor:
		if _on_oneway and absf(input_x) < 0.1:
			_drop_through()
		elif state != State.ROLL and _roll_cd <= 0.0:
			_start_roll(int(signf(input_x)) if absf(input_x) > 0.1 else facing)
	elif state == State.NORMAL:
		velocity.y = maxf(velocity.y, 720.0)  # mergulho rápido no ar


func _drop_through() -> void:
	set_collision_mask_value(5, false)
	_drop_timer = 0.22
	position.y += 2.0


func _start_roll(dir: int) -> void:
	state = State.ROLL
	_roll_left = roll_time
	_roll_dir = dir
	facing = dir
	velocity.x = dir * roll_speed
	_squash = Vector2(1.2, 0.8)
	Sfx.play("roll", -4.0)


func _state_roll(delta: float) -> void:
	_roll_left -= delta
	var k := clampf(_roll_left / roll_time, 0.0, 1.0)
	velocity.x = _roll_dir * roll_speed * (0.55 + 0.45 * k)
	_apply_gravity(delta)
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.035
		Fx.ghost(get_parent(), global_position, true)
	# pulo cancela o rolamento
	if _jump_buffer > 0.0 and _coyote > 0.0:
		state = State.NORMAL
		_roll_cd = roll_cooldown
		_jump()
		return
	if _roll_left <= 0.0:
		state = State.NORMAL
		_roll_cd = roll_cooldown


## Golpe na direção do mouse. Público para os testes poderem chamar.
func start_attack() -> void:
	_attack_dir = (aim_point() - center()).normalized()
	if _attack_dir == Vector2.ZERO:
		_attack_dir = Vector2(facing, 0)
	state = State.ATTACK
	_attack_left = attack_duration
	_attack_cd = attack_cooldown
	_hit_ids.clear()
	facing = 1 if _attack_dir.x >= 0.0 else -1

	var lunge := _attack_dir * attack_lunge
	if is_on_floor():
		lunge.y = minf(lunge.y, 0.0)          # no chão não "afunda"
	elif _air_attack_used:
		lunge.y = maxf(lunge.y, velocity.y)   # só 1 impulso para cima por pulo
	else:
		_air_attack_used = true
	velocity = lunge

	Fx.slash(self, Vector2(0, -24), _attack_dir)
	Sfx.play("slash")
	_check_slash_hits()


func _state_attack(delta: float) -> void:
	_attack_left -= delta
	if attack_duration - _attack_left <= attack_active:
		_check_slash_hits()
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	velocity.y = minf(velocity.y + gravity_down * 0.5 * delta, max_fall_speed)
	if _attack_left <= 0.0:
		state = State.NORMAL


func _check_slash_hits() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(attack_reach * 1.4, attack_width)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(_attack_dir.angle(), center() + _attack_dir * attack_reach * 0.6)
	q.collision_mask = Game.L_ENEMY | Game.L_BULLET
	q.collide_with_areas = true
	q.collide_with_bodies = true
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var c: Object = hit["collider"]
		if c == null:
			continue
		var id := c.get_instance_id()
		if _hit_ids.has(id):
			continue
		_hit_ids[id] = true
		if c.has_method("on_slashed"):
			c.on_slashed(_attack_dir, self)


func _after_move(delta: float) -> void:
	_on_oneway = false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < -0.7:
			var c := col.get_collider()
			if c is Node and (c as Node).is_in_group("oneway"):
				_on_oneway = true
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		_squash = Vector2(1.25, 0.78)
		Sfx.play("land", -10.0)
		Fx.dust(get_parent(), global_position, 4)
	_was_on_floor = now_floor
	_run_phase += absf(velocity.x) * delta * 0.045
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, 12.0 * delta))


# ------------------------------------------------------------- morte ---

## Retorna true se morreu (false se estava invencível / já morto).
func die(from_dir: Vector2) -> bool:
	if state == State.DEAD or is_invulnerable():
		return false
	state = State.DEAD
	var d := from_dir.normalized()
	velocity = d * 380.0 + Vector2(0, -260)
	set_collision_mask_value(5, true)
	Fx.blood(get_parent(), center(), d, 44)
	Sfx.play("player_death")
	Game.hitstop(0.12)
	Game.shake(14.0)
	died.emit()
	return true


func _physics_dead(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity_down * delta, max_fall_speed)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	_dead_rot = lerp_angle(_dead_rot, -PI * 0.5 * facing, minf(1.0, 8.0 * delta))
	move_and_slide()
	_update_scarf(delta)
	queue_redraw()


# ------------------------------------------------------------- visual ---

func _update_scarf(delta: float) -> void:
	var anchor := global_position + Vector2(-4.0 * facing, -46.0)
	if state == State.ROLL:
		anchor = global_position + Vector2(0, -16)
	elif state == State.DEAD:
		anchor = global_position + Vector2(-20.0 * facing, -8.0)
	_scarf[0] = anchor
	var force := Vector2(-facing * 500.0 - velocity.x * 0.6, 420.0) * delta * delta
	for i in range(1, _scarf.size()):
		var p := _scarf[i]
		var v := (p - _scarf_prev[i]) * 0.88
		_scarf_prev[i] = p
		_scarf[i] = p + v + force
	for _iter in 2:
		for i in range(1, _scarf.size()):
			var d := _scarf[i] - _scarf[i - 1]
			if d.length() > 5.0:
				_scarf[i] = _scarf[i - 1] + d.normalized() * 5.0


func _draw() -> void:
	# cachecol (pontos em coordenadas globais)
	for i in range(_scarf.size() - 1):
		var w := lerpf(5.0, 1.5, float(i) / _scarf.size())
		draw_line(to_local(_scarf[i]), to_local(_scarf[i + 1]), C_SCARF, w)

	var f := float(facing)
	if state == State.DEAD:
		draw_set_transform(Vector2(0, -2), _dead_rot, Vector2(f, 1))
		_draw_body(Vector2(-4, 0), Vector2(6, 0))
		return

	if state == State.ROLL:
		var spin := (1.0 - _roll_left / roll_time) * TAU * 1.2 * _roll_dir
		draw_circle(Vector2(0, -14), 13.0, C_COAT)
		draw_circle(Vector2(0, -14) + Vector2.from_angle(spin + PI) * 7.0, 5.5, C_SKIN)
		draw_line(Vector2(0, -14), Vector2(0, -14) + Vector2.from_angle(spin) * 13.0, C_DARK, 3.0)
		return

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(f * _squash.x, _squash.y))
	var fa: Vector2
	var fb: Vector2
	if is_on_floor() and absf(velocity.x) > 20.0:
		var s := sin(_run_phase)
		var c := cos(_run_phase)
		fa = Vector2(s * 10.0, -maxf(0.0, c) * 6.0)
		fb = Vector2(-s * 10.0, -maxf(0.0, -c) * 6.0)
	elif is_on_floor():
		fa = Vector2(-4, 0)
		fb = Vector2(5, 0)
	else:
		fa = Vector2(-6, -6)
		fb = Vector2(7, -10)
	_draw_body(fa, fb)

	# braço + lâmina
	if state == State.ATTACK:
		var d := Vector2(_attack_dir.x * f, _attack_dir.y)
		var sh := Vector2(2, -33)
		var hand := sh + d * 14.0
		draw_line(sh, hand, C_COAT, 4.0)
		draw_line(hand, hand + d * 40.0, C_BLADE, 3.0)
	else:
		var hand := Vector2(8, -23)
		draw_line(Vector2(3, -33), hand, C_COAT, 4.0)
		draw_line(hand, hand + Vector2(-4, 4), C_DARK, 4.0)        # cabo
		draw_line(hand + Vector2(-4, 4), hand + Vector2(-30, 16), C_BLADE, 2.5)  # lâmina para trás


func _draw_body(foot_a: Vector2, foot_b: Vector2) -> void:
	var hip := Vector2(0, -20)
	draw_line(hip, foot_a, C_LEGS, 4.5)
	draw_line(hip + Vector2(2, 0), foot_b, C_LEGS, 4.5)
	var sway := clampf(-velocity.x * 0.02, -6.0, 6.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -36), Vector2(-7, -18), Vector2(-12 + sway, -12), Vector2(-2, -18)]), C_COAT.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([Vector2(-7, -18), Vector2(8, -18), Vector2(6, -38), Vector2(-6, -38)]), C_COAT)
	draw_line(Vector2(-7, -23), Vector2(7, -23), C_DARK, 2.0)
	draw_circle(Vector2(1, -45), 7.0, C_SKIN)
	draw_colored_polygon(PackedVector2Array([Vector2(-7, -45), Vector2(-6, -52), Vector2(2, -54), Vector2(8, -50), Vector2(8, -47), Vector2(2, -49), Vector2(-3, -43)]), C_HAIR)
	draw_line(Vector2(-6, -47), Vector2(8, -47), C_SCARF, 2.5)
