extends Area2D

@export var speed := 900.0
var direction := Vector2.RIGHT
var damage := 25
var lifetime := 1.5

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-5,-2), Vector2(5,-2), Vector2(5,2), Vector2(-5,2)])
	visual.color = Color("#f5d58a")
	visual.rotation = direction.angle()
	add_child(visual)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
