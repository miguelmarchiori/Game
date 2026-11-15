extends CharacterBody2D

var health := 75
var speed := 90.0
var attack_range := 300.0
var attack_cooldown := 0.0
var player: Node2D
var visual: Polygon2D

func _ready() -> void:
	visual = Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-13,-40), Vector2(13,-40), Vector2(15,-7), Vector2(-15,-7)])
	visual.color = Color("#a94e4e")
	add_child(visual)
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([Vector2(-9,-56), Vector2(9,-56), Vector2(10,-40), Vector2(-10,-40)])
	head.color = Color("#c18c70")
	add_child(head)
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	var distance := global_position.distance_to(player.global_position)
	if distance < attack_range:
		var direction := signf(player.global_position.x - global_position.x)
		velocity.x = direction * speed
		visual.scale.x = direction
		attack_cooldown -= delta
		if distance < 48.0 and attack_cooldown <= 0.0:
			player.take_damage(12)
			attack_cooldown = 1.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	move_and_slide()

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()
