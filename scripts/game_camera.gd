extends Camera2D
## Câmera que segue o jogador, olha um pouco na direção do mouse e treme
## com Game.shake(). Fica presa nos limites da fase.

var target: Node2D
var _shake := 0.0
var _look := Vector2.ZERO


func _ready() -> void:
	add_to_group("camera")
	zoom = Vector2(1.25, 1.25)
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	position_smoothing_speed = 9.0


func setup(follow: Node2D, bounds: Rect2) -> void:
	target = follow
	var view := get_viewport_rect().size / zoom
	var r := bounds
	# fase menor que a tela: centraliza
	if r.size.x < view.x:
		r = r.grow_individual((view.x - r.size.x) * 0.5, 0, (view.x - r.size.x) * 0.5, 0)
	if r.size.y < view.y:
		r = r.grow_individual(0, (view.y - r.size.y) * 0.5, 0, (view.y - r.size.y) * 0.5)
	limit_left = int(r.position.x)
	limit_top = int(r.position.y)
	limit_right = int(r.end.x)
	limit_bottom = int(r.end.y)
	global_position = follow.global_position + Vector2(0, -48)
	reset_smoothing()


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if is_instance_valid(target):
		var want := (get_global_mouse_position() - target.global_position).limit_length(320.0) * 0.2
		_look = _look.lerp(want, minf(1.0, 6.0 * delta))
		global_position = target.global_position + Vector2(0, -48) + _look


func _process(delta: float) -> void:
	# a tremida decai em tempo real (não fica "presa" no hitstop / câmera lenta)
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_shake = maxf(0.0, _shake - 45.0 * real_dt)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
