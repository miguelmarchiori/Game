extends CharacterBody2D

signal died

const BulletScene := preload("res://scenes/bullet.tscn")
const SPEED := 240.0
const JUMP_VELOCITY := -390.0
const DASH_SPEED := 520.0
const DASH_TIME := 0.16
const MAX_HEALTH := 100

@export var magazine_size := 12
@export var fire_rate := 0.22
@export var bullet_damage := 25
@export var reload_time := 1.15

var health := MAX_HEALTH
var ammo := magazine_size
var facing := 1
var dash_timer := 0.0
var fire_timer := 0.0
var reload_timer := 0.0
var melee_cooldown := 0.0
var is_reloading := false
var aim_direction := Vector2.RIGHT
var body_visual: Polygon2D
var aim_pivot: Node2D
var gun_visual: Polygon2D
var camera: Camera2D

func _ready() -> void:
	add_to_group("player")
	_build_visuals()
	camera = Camera2D.new()
	camera.position = Vector2(0, -90)
	camera.zoom = Vector2(1.0, 1.0)
	add_child(camera)
	camera.make_current()

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_aim()
	_handle_movement(delta)
	_handle_combat()
	_update_visuals()
	move_and_slide()

func _update_timers(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	melee_cooldown = maxf(0.0, melee_cooldown - delta)
	if dash_timer > 0.0:
		dash_timer -= delta
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			ammo = magazine_size
			is_reloading = false

func _update_aim() -> void:
	var direction := get_global_mouse_position() - global_position
	if direction.length_squared() > 1.0:
		aim_direction = direction.normalized()
	facing = 1 if aim_direction.x >= 0.0 else -1
	if is_instance_valid(aim_pivot):
		aim_pivot.rotation = aim_direction.angle()

func _handle_movement(delta: float) -> void:
	if dash_timer > 0.0:
		velocity.x = float(facing) * DASH_SPEED
		velocity.y = 0.0
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	var input_x := Input.get_axis("move_left", "move_right")
	velocity.x = input_x * SPEED
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("dash"):
		dash_timer = DASH_TIME
		velocity = Vector2(float(facing) * DASH_SPEED, 0.0)

func _handle_combat() -> void:
	if Input.is_action_pressed("fire") and fire_timer <= 0.0 and not is_reloading:
		_shoot()
	if Input.is_action_just_pressed("melee") and melee_cooldown <= 0.0:
		_melee_attack()

func _shoot() -> void:
	if ammo <= 0:
		_start_reload()
		return
	var bullet := BulletScene.instantiate()
	bullet.global_position = global_position + aim_direction * 28.0 + Vector2(0, -22)
	bullet.direction = aim_direction
	bullet.damage = bullet_damage
	get_tree().current_scene.add_child(bullet)
	ammo -= 1
	fire_timer = fire_rate
	if ammo <= 0:
		_start_reload()

func _start_reload() -> void:
	if is_reloading or ammo == magazine_size:
		return
	is_reloading = true
	reload_timer = reload_time

func _melee_attack() -> void:
	melee_cooldown = 0.42
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(66, 42)
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + Vector2(float(facing) * 42.0, -22.0))
	query.collision_mask = 4
	for hit in space.intersect_shape(query, 8):
		var collider = hit.get("collider")
		if collider and collider.has_method("take_damage"):
			collider.take_damage(45)

func take_damage(amount: int) -> void:
	health = maxi(0, health - amount)
	if health <= 0:
		died.emit()

func _build_visuals() -> void:
	body_visual = Polygon2D.new()
	body_visual.polygon = PackedVector2Array([Vector2(-12,-44), Vector2(12,-44), Vector2(14,-8), Vector2(-14,-8)])
	body_visual.color = Color("#d4d0c8")
	add_child(body_visual)
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([Vector2(-9,-62), Vector2(9,-62), Vector2(10,-45), Vector2(-10,-45)])
	head.color = Color("#b98c72")
	add_child(head)
	aim_pivot = Node2D.new()
	aim_pivot.position = Vector2(0, -27)
	add_child(aim_pivot)
	gun_visual = Polygon2D.new()
	gun_visual.polygon = PackedVector2Array([Vector2(0,-4), Vector2(32,-4), Vector2(32,4), Vector2(0,4)])
	gun_visual.color = Color("#252a30")
	aim_pivot.add_child(gun_visual)

func _update_visuals() -> void:
	body_visual.scale.x = float(facing)
