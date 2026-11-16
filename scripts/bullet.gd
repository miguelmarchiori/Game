extends Area2D
## PROJÉTIL — anda por raycast (não atravessa paredes, mesmo rápido).
## team "enemy": machuca o jogador · team "player": machuca inimigos.
## Taco e espada REBATEM projéteis inimigos (viram do jogador, com dano dobrado).

const Fx := preload("res://scripts/fx.gd")
const C_ENEMY := Color("#ffcf5a")
const C_PLAYER := Color("#ffffff")
const C_DEFLECT := Color("#3fd6c6")

var velocity := Vector2.ZERO
var lifetime := 2.0
var team := "enemy"
var damage := 18
var knock := 200.0
var deflected := false
var _exclude: Array[RID] = []
var _trail := 0.0
var _from: Node


func setup(pos: Vector2, dir: Vector2, speed: float, life: float, shooter: Node, team_name := "enemy", dmg := 18, kb := 200.0) -> void:
	position = pos
	velocity = dir.normalized() * speed
	lifetime = life
	team = team_name
	damage = dmg
	knock = kb
	_from = shooter
	if shooter is CollisionObject2D:
		_exclude.append((shooter as CollisionObject2D).get_rid())


func _ready() -> void:
	collision_layer = Game.L_BULLET
	collision_mask = 0
	monitoring = false
	z_index = 5


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var motion := velocity * delta
	var mask := Game.L_WORLD | (Game.L_PLAYER if team == "enemy" else Game.L_ENEMY)
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + motion, mask, _exclude)
	q.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit["collider"]
		var hit_pos: Vector2 = hit["position"]
		var dir := velocity.normalized()
		if c is Node and (c as Node).is_in_group("player"):
			if c.take_damage(damage, dir):
				queue_free()
				return
			_exclude.append((c as CollisionObject2D).get_rid())   # dash: atravessa
		elif c is Node and (c as Node).is_in_group("enemies"):
			c.take_hit({"dmg": damage, "kb": dir * knock + Vector2(0, -60), "stun": 0.25, "from": _from, "bullet": true})
			if is_instance_valid(_from) and _from.has_method("register_hit"):
				_from.register_hit(damage)
			queue_free()
			return
		else:
			Fx.sparks(get_parent(), hit_pos, -dir, _color(), 5, 260.0)
			queue_free()
			return
	global_position += motion
	_trail = minf(_trail + motion.length(), 30.0)
	queue_redraw()


## Rebatida por taco/espada.
func on_deflect(dir: Vector2, by: Node) -> void:
	if team != "enemy":
		return
	team = "player"
	deflected = true
	damage *= 2
	_from = by
	velocity = dir.normalized() * maxf(velocity.length() * 1.3, 1100.0)
	lifetime = 1.5
	_exclude.clear()
	_trail = 0.0
	Sfx.play("deflect", -2.0)
	Fx.sparks(get_parent(), global_position, dir, C_DEFLECT, 12, 480.0)
	Game.hitstop(0.05)
	Game.shake(5.0)


func _color() -> Color:
	if deflected:
		return C_DEFLECT
	return C_ENEMY if team == "enemy" else C_PLAYER


func _draw() -> void:
	var d := velocity.normalized()
	var c := _color()
	draw_line(-d * _trail, Vector2.ZERO, Color(c, 0.3), 6.0)
	draw_line(-d * _trail, Vector2.ZERO, c, 2.0)
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
