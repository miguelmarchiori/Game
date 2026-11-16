extends Area2D
## PLATAFORMA DE SALTO — lança para cima quem pisar (jogador, inimigos e armas).

const POWER := 1400.0

var _cooldown := {}
var _press := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.L_PLAYER | Game.L_ENEMY | Game.L_ITEM
	monitorable = false
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(30, 10)
	shape.shape = rs
	shape.position = Vector2(0, -7)
	add_child(shape)


func _physics_process(delta: float) -> void:
	_press = maxf(0.0, _press - delta * 5.0)
	var now := Time.get_ticks_msec()
	for b in get_overlapping_bodies():
		var id := b.get_instance_id()
		if _cooldown.get(id, 0) > now:
			continue
		if b.has_method("launch"):
			b.launch(Vector2(0, -POWER))
			_cooldown[id] = now + 300
			_press = 1.0
			Sfx.play("pad", -4.0)
	queue_redraw()


func _draw() -> void:
	var top := -10.0 + _press * 6.0
	draw_rect(Rect2(-16, -4, 32, 4), Color("#2b2f35"))
	var pts := PackedVector2Array()
	for i in 7:
		pts.append(Vector2(-10 + i * 20.0 / 6.0, -4 + (top + 4) * float(i) / 6.0 + (3.0 if i % 2 == 0 else -3.0)))
	draw_polyline(pts, Color("#8d949c"), 2.0)
	draw_rect(Rect2(-16, top - 4, 32, 5), Color("#ffb21e"))
	for i in 4:
		draw_line(Vector2(-14 + i * 9, top - 4), Vector2(-10 + i * 9, top + 1), Color("#1e2226"), 2.0)
