extends Area2D
## Porta de saída: trancada (vermelha) até todos os inimigos morrerem.
## Depois de aberta, encostar nela termina a fase.

signal reached

const Fx := preload("res://scripts/fx.gd")
const C_LOCKED := Color("#ff4060")
const C_OPEN := Color("#5affb0")

var locked := true
var _t := 0.0
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.L_PLAYER
	monitorable = false
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(36, 60)
	shape.shape = rs
	shape.position = Vector2(0, -30)
	add_child(shape)


func unlock() -> void:
	if not locked:
		return
	locked = false
	Sfx.play("door")
	Fx.ring(get_parent(), global_position + Vector2(0, -30), C_OPEN, 90.0)


func _physics_process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if locked or _done:
		return
	for b in get_overlapping_bodies():
		if b.is_in_group("player") and b.is_alive():
			_done = true
			reached.emit()
			return


func _draw() -> void:
	var c := C_LOCKED if locked else C_OPEN
	var glow := 0.25 + 0.15 * sin(_t * 4.0)
	draw_rect(Rect2(-22, -66, 44, 66), Color(c, 0.08 if locked else glow * 0.6))
	draw_rect(Rect2(-18, -62, 36, 62), Color("#0b0916"))
	draw_rect(Rect2(-18, -62, 36, 62), c, false, 2.0)
	if locked:
		for i in 4:
			var y := -52.0 + i * 14.0
			draw_line(Vector2(-14, y), Vector2(14, y), Color(c, 0.6), 2.0)
	else:
		var off := fmod(_t * 30.0, 14.0)
		for i in 4:
			var y := -10.0 - i * 14.0 - off
			if y > -60.0:
				draw_polyline(PackedVector2Array([Vector2(-8, y + 6), Vector2(0, y), Vector2(8, y + 6)]), Color(c, 0.8), 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-40, -76), "SAÍDA", HORIZONTAL_ALIGNMENT_CENTER, 80, 14, c)
