extends CharacterBody2D
## INIMIGO — variantes no mesmo script (escolha em `kind`):
##   GUNNER  (atirador):    mira com LASER e atira (pistola)
##   SHOTGUN (escopeteiro): mira mais devagar, rajada de 5 projéteis de curto alcance
##   BRUTE   (brutamontes): grandão com taco, corre até você e golpeia (mais vida, aguenta mais)
##   DUMMY   (boneco):      saco de pancada que nunca morre — mostra o dano
## Reações: atordoado (hitstun), derrubado/lançado (dá para fazer combo no ar), batida na
## parede, e um inimigo arremessado derruba os outros no caminho. Larga a arma ao morrer.
## A origem do nó fica nos PÉS.

signal killed(enemy: Node)

const Fx := preload("res://scripts/fx.gd")
const Rig := preload("res://scripts/rig.gd")
const Weapons := preload("res://scripts/weapons.gd")
const ITEM := preload("res://scripts/weapon_item.gd")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

enum Kind { GUNNER, SHOTGUN, BRUTE, DUMMY }
enum State { PATROL, REACT, CHASE, AIM, WINDUP, STRIKE, RECOVER, HITSTUN, DOWN, GETUP, DEAD }

## Ajuste fino de cada tipo.
const STATS := {
	Kind.GUNNER: {
		"hp": 60, "walk": 60.0, "chase": 120.0, "vision": 520.0, "react": 0.35,
		"aim": 0.6, "cooldown": 0.9, "pellets": 1, "spread": 0.0, "dmg": 16,
		"bullet_speed": 900.0, "bullet_life": 1.2, "range": 480.0, "weapon": "pistola",
		"scale": 1.0, "kb_scale": 1.0, "eye": Color("#ffd23f"), "top": Color("#4f86c6"),
	},
	Kind.SHOTGUN: {
		"hp": 75, "walk": 50.0, "chase": 110.0, "vision": 440.0, "react": 0.4,
		"aim": 0.8, "cooldown": 1.3, "pellets": 5, "spread": 0.42, "dmg": 10,
		"bullet_speed": 820.0, "bullet_life": 0.45, "range": 320.0, "weapon": "escopeta",
		"scale": 1.0, "kb_scale": 0.9, "eye": Color("#ff8c3a"), "top": Color("#8aa63f"),
	},
	Kind.BRUTE: {
		"hp": 150, "walk": 70.0, "chase": 230.0, "vision": 480.0, "react": 0.3,
		"windup": 0.42, "cooldown": 0.7, "reach": 66.0, "dmg": 28, "weapon": "taco",
		"scale": 1.2, "kb_scale": 0.55, "eye": Color("#ff3b3b"), "top": Color("#b5553a"),
	},
	Kind.DUMMY: {
		"hp": 9999, "scale": 1.0, "kb_scale": 0.0, "eye": Color.WHITE, "top": Color("#c8a46e"),
	},
}

@export var kind: Kind = Kind.GUNNER
@export var facing := -1
@export var patrols := true

var state: State = State.PATROL
var hp := 60
var max_hp := 60
var _st: Dictionary
var _style: Dictionary
var _t := 0.0
var _stun := 0.3
var _player: Node2D
var _last_seen := Vector2.ZERO
var _aware := false
var _sees_player := false
var _vision_timer := 0.0
var _turn_pause := 0.0
var _aim_point := Vector2.ZERO
var _laser_end := Vector2.ZERO
var _muzzle_flash := 0.0
var _hurt_flash := 0.0
var _bar_t := 0.0
var _anim := 0.0
var _lie_rot := 0.0
var _lying := false
var _resting := false
var _bowl_ids := {}
var _wobble := 0.0
var _wobble_v := 0.0
var _dummy_regen := 0.0
var _pose := {}


func _ready() -> void:
	add_to_group("enemies")
	_st = STATS[kind]
	max_hp = int(_st["hp"])
	hp = max_hp
	floor_snap_length = 10.0
	floor_max_angle = deg_to_rad(50.0)
	var top: Color = _st["top"]
	_style = {
		"skin": Color("#c9a080"), "mask": Color("#2b3038"), "eye": _st["eye"],
		"top": top, "top_dark": top.darkened(0.3), "legs": Color("#3a4656"), "legs_dark": Color("#2c3542"),
		"shoes": Color("#15181c"), "fist": Color("#2b3038"), "head_r": 7.0,
		"torso_w": 10.0 if kind == Kind.BRUTE else 8.0, "limb_w": 7.5 if kind == Kind.BRUTE else 6.0,
	}
	if kind == Kind.BRUTE:
		var cs: CollisionShape2D = $CollisionShape2D
		var cap := CapsuleShape2D.new()
		cap.radius = 14.0
		cap.height = 56.0
		cs.shape = cap
		cs.position = Vector2(0, -28)
	_pose = _pose_idle()


func is_alive() -> bool:
	return state != State.DEAD


func center() -> Vector2:
	return global_position + Vector2(0, -26.0 * float(_st["scale"]))


# ------------------------------------------------------------- loop ---

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_physics_dead(delta)
		return
	_t += delta
	_muzzle_flash = maxf(0.0, _muzzle_flash - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_bar_t = maxf(0.0, _bar_t - delta)

	if kind == Kind.DUMMY:
		_physics_dummy(delta)
		return

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_vision_timer -= delta
	if _vision_timer <= 0.0:
		_vision_timer = 0.06
		_sees_player = Game.ai_enabled and _can_see_player()
	if _sees_player:
		_last_seen = _player_center()

	var thinking := state in [State.PATROL, State.REACT, State.CHASE, State.AIM, State.WINDUP]
	if not Game.ai_enabled and thinking:
		if state != State.PATROL:
			_set_state(State.PATROL)
		_brake(delta)
	else:
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
				if _t >= 0.16:
					_set_state(State.RECOVER)
			State.RECOVER:
				_brake(delta)
				if _t >= float(_st["cooldown"]):
					_decide()
			State.HITSTUN:
				velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
				if _t >= _stun:
					_decide()
			State.DOWN:
				_physics_down(delta)
			State.GETUP:
				_brake(delta)
				_lie_rot = lerp_angle(_lie_rot, 0.0, minf(1.0, 14.0 * delta))
				if _t >= 0.32:
					_lie_rot = 0.0
					_decide()

	velocity.y = minf(velocity.y + 2200.0 * delta, 1000.0)
	var was_fast := absf(velocity.x)
	move_and_slide()
	if state == State.DOWN:
		_check_wall_splat(was_fast)
		_check_bowling()
	_anim += absf(velocity.x) * delta * 0.05
	Rig.blend(_pose, _target_pose(), 20.0, delta)
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
	return _player.center()


func _shoulder() -> Vector2:
	return global_position + Vector2(facing * 2.0, -34.0 * float(_st["scale"]))


func _muzzle() -> Vector2:
	return _shoulder() + (_aim_point - _shoulder()).normalized() * 28.0


# ------------------------------------------------------------- percepção ---

func _can_see_player() -> bool:
	if not _player_alive():
		return false
	var eye := global_position + Vector2(facing * 4.0, -40.0 * float(_st["scale"]))
	var to := _player_center() - eye
	var dist := to.length()
	if dist > float(_st["vision"]) or absf(to.y) > 360.0:
		return false
	if not _aware and signf(to.x) != float(facing) and dist > 90.0:
		return false
	var q := PhysicsRayQueryParameters2D.create(eye, _player_center(), Game.L_WORLD)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## Faz o inimigo perceber o jogador.
func alert(at: Vector2) -> void:
	if state != State.PATROL or kind == Kind.DUMMY or not Game.ai_enabled:
		return
	_last_seen = at
	_aware = true
	_set_state(State.REACT)
	Sfx.play("alert", -10.0)


func _decide() -> void:
	if not _player_alive() or not Game.ai_enabled or not _aware:
		_set_state(State.PATROL)
	elif kind == Kind.BRUTE:
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
	var from := global_position + Vector2(facing * 18.0, -4.0)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 40), Game.L_WORLD | Game.L_PLATFORM)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# ------------------------------------------------------------- IA ---

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
			if absf(p.x - global_position.x) < float(_st["reach"]) and absf(p.y - center().y) < 60.0:
				_face_toward(p)
				_set_state(State.WINDUP)
				Sfx.play("windup", -6.0)
				return
	elif _sees_player and _in_range():
		_start_aim()
		return
	var dx := _last_seen.x - global_position.x
	_face_toward(_last_seen)
	var speed := float(_st["chase"])
	if absf(dx) < 12.0 or _wall_ahead():
		speed = 0.0
	elif _ledge_ahead() and _last_seen.y < global_position.y + 20.0:
		speed = 0.0
	velocity.x = move_toward(velocity.x, facing * speed, 1600.0 * delta)


func _start_aim() -> void:
	_set_state(State.AIM)
	_aim_point = _player_center()
	_face_toward(_aim_point)


func _aim(delta: float) -> void:
	_brake(delta)
	var aim_time := float(_st["aim"])
	if _t < aim_time * 0.7:   # nos últimos 30% a mira TRAVA (hora de desviar!)
		if _sees_player:
			_aim_point = _aim_point.lerp(_player_center(), 1.0 - exp(-14.0 * delta))
		elif _t > 0.15:
			_set_state(State.CHASE)
			return
	_face_toward(_aim_point)
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
		b.setup(muzzle, base.rotated(a), float(_st["bullet_speed"]), float(_st["bullet_life"]), self, "enemy", int(_st["dmg"]))
		get_parent().add_child(b)
	_muzzle_flash = 0.06
	Sfx.play("shotgun" if n > 1 else "shot", -4.0)
	Fx.sparks(get_parent(), muzzle, base, Color("#ffd27a"), 5, 280.0)


func _strike() -> void:
	Sfx.play("swing", -2.0)
	if not _player_alive():
		return
	var p := _player_center()
	var dx := p.x - global_position.x
	var in_front := signf(dx) == float(facing) or absf(dx) < 16.0
	if in_front and absf(dx) < float(_st["reach"]) + 14.0 and absf(p.y - center().y) < 64.0:
		if _player.take_damage(int(_st["dmg"]), Vector2(facing, -0.5)):
			_player.velocity += Vector2(facing * 420.0, -220.0)
			Sfx.play("bat", -2.0)
			Game.hitstop(0.06)


# ------------------------------------------------------------- dano ---

## info: dmg, kb (Vector2), stun (s), down (derruba), launch (lança), from (quem bateu), bullet
func take_hit(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	var dmg := int(info.get("dmg", 10))
	var kb: Vector2 = info.get("kb", Vector2.ZERO)
	_hurt_flash = 0.1
	_bar_t = 2.5
	var col := Color.WHITE if dmg < 20 else (Color("#ffd23f") if dmg < 35 else Color("#ff6a3d"))
	Fx.number(get_parent(), center() + Vector2(0, -36), dmg, col)

	if kind == Kind.DUMMY:
		_wobble_v += signf(kb.x) * (2.0 + dmg * 0.25)
		hp = maxi(1, hp - dmg)
		_dummy_regen = 1.5
		Fx.shards(get_parent(), center(), kb.normalized() if kb != Vector2.ZERO else Vector2.UP, Color("#d9b77e"), 6)
		return

	hp -= dmg
	Fx.blood(get_parent(), center(), kb if kb != Vector2.ZERO else Vector2.UP, 4 + dmg / 4)
	var from: Variant = info.get("from")
	if from is Node2D and is_instance_valid(from):
		_last_seen = (from as Node2D).global_position + Vector2(0, -24)
	_aware = true
	if hp <= 0:
		die(kb)
		return

	var airborne := not is_on_floor() or state == State.DOWN
	var down: bool = info.get("down", false) or info.get("launch", false)
	if kind == Kind.BRUTE and dmg < 20:
		down = false                       # brutamontes só cai com golpe forte
	velocity = kb * float(_st["kb_scale"])
	if airborne and not info.get("bullet", false):
		velocity.y = minf(kb.y, -240.0)    # malabarismo: golpes no ar mantêm ele no alto
		down = true
	if down:
		_set_state(State.DOWN)
		_lying = false
		_resting = false
		_bowl_ids.clear()
	else:
		_set_state(State.HITSTUN)
		_stun = float(info.get("stun", 0.3)) * (0.5 if kind == Kind.BRUTE else 1.0)


func _physics_down(delta: float) -> void:
	var target_rot := PI * 0.5 * -facing
	_lie_rot = lerp_angle(_lie_rot, target_rot, minf(1.0, 9.0 * delta))
	if is_on_floor() and _t > 0.1:
		velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
		if not _lying and absf(velocity.x) < 30.0:
			_lying = true
			_t = 0.1
	if _lying and _t > 0.85:
		_set_state(State.GETUP)


func _check_wall_splat(speed_before: float) -> void:
	if speed_before > 420.0 and is_on_wall() and state == State.DOWN:
		var n := get_wall_normal()
		hp -= 8
		Fx.number(get_parent(), center() + Vector2(0, -36), 8, Color("#ff6a3d"))
		Fx.impact(get_parent(), center() - Vector2(n.x * 12.0, 0), true)
		Fx.blood(get_parent(), center(), -n, 10)
		Sfx.play("splat", -2.0)
		Game.shake(7.0)
		Game.hitstop(0.05)
		velocity.x = n.x * speed_before * 0.25
		if hp <= 0:
			die(n * 200.0)


func _check_bowling() -> void:
	if velocity.length() < 380.0:
		return
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, center())
	q.collision_mask = Game.L_ENEMY
	q.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 6):
		var e: Object = hit["collider"]
		if e == null or _bowl_ids.has(e.get_instance_id()) or not e.has_method("take_hit"):
			continue
		_bowl_ids[e.get_instance_id()] = true
		e.take_hit({"dmg": 10, "kb": velocity * 0.6 + Vector2(0, -200), "down": true, "from": self})
		Fx.impact(get_parent(), (center() + (e as Node2D).global_position) * 0.5 + Vector2(0, -20), true)
		Sfx.play("kick", -2.0)


func die(kb: Vector2) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_t = 0.0
	collision_layer = 0
	velocity = kb * 0.9 + Vector2(0, -200)
	Fx.blood(get_parent(), center(), kb if kb != Vector2.ZERO else Vector2.UP, 26)
	Sfx.play("kill", -2.0)
	_drop_weapon()
	killed.emit(self)


func _drop_weapon() -> void:
	var w: String = _st.get("weapon", "")
	if w == "":
		return
	var it := ITEM.new()
	it.kind = w
	if Weapons.is_gun(w):
		var full := int(Weapons.DATA[w]["municao"])
		it.ammo = randi_range(full / 2, full)
	it.position = center()
	it.pickup_delay = 0.3
	it.linear_velocity = Vector2(randf_range(-120, 120), -300)
	it.angular_velocity = randf_range(-12, 12)
	get_parent().add_child.call_deferred(it)


func _physics_dead(delta: float) -> void:
	_t += delta
	velocity.y = minf(velocity.y + 2200.0 * delta, 1000.0)
	_lie_rot = lerp_angle(_lie_rot, PI * 0.5 * -facing, minf(1.0, 7.0 * delta))
	move_and_slide()
	if is_on_floor() and _t > 0.15:
		velocity.x = move_toward(velocity.x, 0.0, 1300.0 * delta)
		_resting = absf(velocity.x) < 4.0
	else:
		_resting = false
	Rig.blend(_pose, _pose_limp(), 10.0, delta)
	queue_redraw()
	if _resting and absf(angle_difference(_lie_rot, PI * 0.5 * -facing)) < 0.02:
		set_physics_process(false)


# ------------------------------------------------------------- boneco ---

func _physics_dummy(delta: float) -> void:
	_wobble_v += (-_wobble * 160.0 - _wobble_v * 7.0) * delta
	_wobble = clampf(_wobble + _wobble_v * delta, -0.9, 0.9)
	_dummy_regen -= delta
	if _dummy_regen <= 0.0:
		hp = max_hp
	velocity.x = 0.0
	velocity.y = minf(velocity.y + 2200.0 * delta, 1000.0)
	move_and_slide()
	queue_redraw()


## Plataforma de salto.
func launch(v: Vector2) -> void:
	if state == State.DEAD or kind == Kind.DUMMY:
		return
	velocity.y = v.y * 0.85
	if state != State.DOWN:
		_set_state(State.DOWN)
		_lying = false


# ------------------------------------------------------------- poses ---

func _pose_idle() -> Dictionary:
	return Rig.pose(Vector2(0, -21), Vector2(1, -36), Vector2(2, -46), Vector2(9, -24), Vector2(-5, -24), Vector2(6, 0), Vector2(-6, 0))


func _pose_limp() -> Dictionary:
	return Rig.pose(Vector2(0, -20), Vector2(1, -35), Vector2(2, -44), Vector2(10, -24), Vector2(-8, -22), Vector2(8, 0), Vector2(-6, -2))


func _target_pose() -> Dictionary:
	if state in [State.DOWN, State.GETUP]:
		return _pose_limp()
	if state == State.HITSTUN:
		return Rig.pose(Vector2(-1, -21), Vector2(-6, -35), Vector2(-9, -44), Vector2(2, -40), Vector2(-12, -36), Vector2(7, 0), Vector2(-6, 0))
	var p := _pose_idle()
	if absf(velocity.x) > 10.0 and is_on_floor():
		var ph := _anim
		p["foot_f"] = Vector2(sin(ph) * 9.0, -maxf(0.0, cos(ph)) * 6.0)
		p["foot_b"] = Vector2(-sin(ph) * 9.0, -maxf(0.0, -cos(ph)) * 6.0)
		p["chest"] = Vector2(3, -36)
		p["head"] = Vector2(5, -46)
	var chest: Vector2 = p["chest"]
	if kind == Kind.BRUTE:
		match state:
			State.WINDUP:
				p["hand_f"] = Vector2(-6, -50)
				p["chest"] = Vector2(-3, -36)
			State.STRIKE:
				p["hand_f"] = Vector2(26, -28)
				p["chest"] = Vector2(7, -35)
			_:
				p["hand_f"] = Vector2(10, -26)
		p["hand_b"] = Vector2(p["hand_f"]) + Vector2(-5, 3)
	elif state in [State.AIM, State.RECOVER, State.REACT]:
		var w := (_aim_point - _shoulder()).normalized()
		var al := Vector2(w.x * facing, w.y)
		p["hand_f"] = chest + Vector2(1, 1) + al * 17.0
		if kind == Kind.SHOTGUN:
			p["hand_b"] = chest + Vector2(1, 3) + al * 10.0
	return p


# ------------------------------------------------------------- desenho ---

func _draw() -> void:
	var f := float(facing)
	var sc := float(_st["scale"])
	if kind == Kind.DUMMY:
		_draw_dummy()
		return

	# laser de mira (sem espelhamento)
	if state == State.AIM:
		var locked := _t >= float(_st["aim"]) * 0.7
		if not locked or int(_t * 30.0) % 2 == 0:
			draw_line(to_local(_muzzle()), to_local(_laser_end), Color(1.0, 0.2, 0.15, 0.9 if locked else 0.35), 2.5 if locked else 1.5)

	var m: Transform2D
	if absf(_lie_rot) > 0.01:
		m = Transform2D(_lie_rot, Vector2(f * sc, sc), 0.0, Vector2(0, -6)) * Transform2D(0.0, Vector2(0, 6))
	else:
		m = Transform2D(0.0, Vector2(f * sc, sc), 0.0, Vector2.ZERO)
	draw_set_transform_matrix(m)
	var style := _style
	if state == State.DEAD:
		style = _style.duplicate()
		for k in ["top", "top_dark", "legs", "legs_dark", "mask"]:
			style[k] = Color(style[k]).darkened(0.35)
		style["eye"] = Color("#3a3a3a")
	elif _hurt_flash > 0.0 or (state == State.WINDUP and int(_t * 20.0) % 2 == 0):
		style = _style.duplicate()
		for k in ["top", "top_dark", "legs", "legs_dark", "mask", "fist"]:
			style[k] = Color.WHITE
	Rig.draw_figure(self, _pose, style)

	# arma na mão
	if state != State.DEAD:
		var w: String = _st.get("weapon", "")
		var hand: Vector2 = m * Vector2(_pose["hand_f"])
		if Weapons.is_gun(w):
			var dir := Vector2(f, 0.35).normalized()
			if state in [State.AIM, State.RECOVER, State.REACT]:
				dir = (_aim_point - _shoulder()).normalized()
			Weapons.draw(self, w, hand, dir.angle(), -1.0 if dir.x < 0.0 else 1.0)
			if _muzzle_flash > 0.0:
				draw_circle(hand + dir * 26.0, 7.0, Color("#fff1c2"))
		elif w != "":
			var la := -1.9
			if state == State.WINDUP:
				la = -2.6
			elif state == State.STRIKE:
				la = 0.6
			Weapons.draw(self, w, hand, m.basis_xform(Vector2.from_angle(la)).angle(), f)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if state == State.REACT:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-6, -66 * sc), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color.BLACK)
		draw_string(font, Vector2(-6, -66 * sc), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#ffd23f"))
	_draw_hp_bar(-64.0 * sc)


func _draw_hp_bar(y: float) -> void:
	if _bar_t <= 0.0 or state == State.DEAD:
		return
	var a := clampf(_bar_t / 0.4, 0.0, 1.0)
	var w := 34.0
	draw_rect(Rect2(-w * 0.5 - 1, y - 1, w + 2, 6), Color(0, 0, 0, 0.6 * a))
	draw_rect(Rect2(-w * 0.5, y, w * clampf(float(hp) / max_hp, 0.0, 1.0), 4), Color(1.0, 0.35, 0.25, a))


func _draw_dummy() -> void:
	draw_rect(Rect2(-12, -4, 24, 4), Color("#4a4f55"))
	draw_set_transform(Vector2(0, -4), _wobble, Vector2.ONE)
	draw_rect(Rect2(-2.5, -40, 5, 40), Color("#7a5a3a"))
	var c := Color.WHITE if _hurt_flash > 0.0 else Color("#c8a46e")
	draw_rect(Rect2(-11, -62, 22, 34), c)
	draw_circle(Vector2(0, -62), 11.0, c)
	draw_circle(Vector2(0, -72), 8.0, c)
	draw_line(Vector2(-11, -50), Vector2(11, -50), Color(0.5, 0.35, 0.2, 0.6), 1.5)
	draw_line(Vector2(-11, -38), Vector2(11, -38), Color(0.5, 0.35, 0.2, 0.6), 1.5)
	draw_circle(Vector2(0, -46), 5.0, Color(0.85, 0.2, 0.2, 0.7))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
