extends Camera2D
## Câmera: segue o jogador, olha um pouco para o mouse e para onde ele corre,
## afasta levemente em alta velocidade e treme com Game.shake().

const BASE_ZOOM := 1.5

var target: Node2D
var _shake := 0.0
var _look := Vector2.ZERO
var _zoom := BASE_ZOOM


func _init() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _ready() -> void:
	add_to_group("camera")
	zoom = Vector2(BASE_ZOOM, BASE_ZOOM)
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0


func setup(follow: Node2D, bounds: Rect2) -> void:
	target = follow
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)
	snap_to_target()


func snap_to_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position + Vector2(0, -48)
	reset_smoothing()
	reset_physics_interpolation()


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var to_mouse := (get_global_mouse_position() - target.global_position).limit_length(320.0) * 0.18
	var vel: Vector2 = target.get("velocity") if target.get("velocity") != null else Vector2.ZERO
	var ahead := Vector2(clampf(vel.x * 0.18, -110.0, 110.0), 0)
	_look = _look.lerp(to_mouse + ahead, minf(1.0, 5.0 * delta))
	global_position = target.global_position + Vector2(0, -48) + _look
	var speed := absf(vel.x) / 420.0
	_zoom = lerpf(_zoom, BASE_ZOOM - clampf(speed - 0.6, 0.0, 1.0) * 0.15, minf(1.0, 2.0 * delta))
	zoom = Vector2(_zoom, _zoom)


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_shake = maxf(0.0, _shake - 45.0 * real_dt)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
