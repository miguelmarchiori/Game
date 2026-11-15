extends Area2D
## BALA — anda por raycast (não atravessa paredes, mesmo rápida).
## Mata o jogador com 1 acerto (exceto rolando). Se for CORTADA pela lâmina,
## é rebatida na direção do golpe, fica ciano e passa a matar inimigos.

const Fx := preload("res://scripts/fx.gd")
const C_BULLET := Color("#ffd25a")
const C_DEFLECT := Color("#5ae4ff")

var velocity := Vector2.ZERO
var lifetime := 2.0
var deflected := false
var _exclude: Array[RID] = []
var _trail := 0.0


func setup(pos: Vector2, dir: Vector2, speed: float, life: float, shooter: Node) -> void:
	position = pos
	velocity = dir.normalized() * speed
	lifetime = life
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
	var mask := Game.L_WORLD | (Game.L_ENEMY if deflected else Game.L_PLAYER)
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + motion, mask, _exclude)
	q.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit["collider"]
		var hit_pos: Vector2 = hit["position"]
		if c is Node and (c as Node).is_in_group("player"):
			if c.die(velocity.normalized()):
				queue_free()
				return
			_exclude.append((c as CollisionObject2D).get_rid())   # rolando: atravessa
		elif c is Node and (c as Node).is_in_group("enemies"):
			c.on_bullet(velocity.normalized())
			queue_free()
			return
		else:
			Fx.sparks(get_parent(), hit_pos, -velocity.normalized(), C_DEFLECT if deflected else C_BULLET, 5, 260.0)
			queue_free()
			return
	global_position += motion
	_trail = minf(_trail + motion.length(), 28.0)
	queue_redraw()


## Chamado pelo golpe do jogador.
func on_slashed(dir: Vector2, _by: Node) -> void:
	if deflected:
		return
	deflected = true
	velocity = dir.normalized() * maxf(velocity.length() * 1.4, 950.0)
	lifetime = 1.5
	_exclude.clear()
	_trail = 0.0
	Sfx.play("deflect", -2.0)
	Fx.sparks(get_parent(), global_position, dir, C_DEFLECT, 12, 480.0)
	Game.hitstop(0.05)
	Game.shake(5.0)


func _draw() -> void:
	var d := velocity.normalized()
	var c := C_DEFLECT if deflected else C_BULLET
	draw_line(-d * _trail, Vector2.ZERO, Color(c, 0.3), 7.0)
	draw_line(-d * _trail, Vector2.ZERO, c, 2.5)
	draw_circle(Vector2.ZERO, 2.5, Color.WHITE)
