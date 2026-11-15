extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

var player: CharacterBody2D
var hud: CanvasLayer
var health_bar: ProgressBar
var ammo_label: Label
var status_label: Label
var arena_start := Vector2(150, 500)

func _ready() -> void:
	_build_arena()
	_spawn_player()
	_spawn_enemy(Vector2(850, 500))
	_build_hud()

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		health_bar.value = player.health
		ammo_label.text = "PISTOLA  %02d / %02d" % [player.ammo, player.magazine_size]

func _build_arena() -> void:
	_add_platform(Vector2(640, 660), Vector2(1280, 120), Color("#343b43"))
	_add_platform(Vector2(420, 485), Vector2(250, 24), Color("#4a5056"))
	_add_platform(Vector2(900, 390), Vector2(220, 24), Color("#4a5056"))
	_add_platform(Vector2(1120, 540), Vector2(180, 24), Color("#4a5056"))
	_add_platform(Vector2(20, 350), Vector2(40, 700), Color("#343b43"))
	_add_platform(Vector2(1260, 350), Vector2(40, 700), Color("#343b43"))
	var background := ColorRect.new()
	background.color = Color("#171d25")
	background.position = Vector2(0, 0)
	background.size = Vector2(1280, 540)
	background.z_index = -10
	add_child(background)
	move_child(background, 0)

func _add_platform(pos: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-size.x/2, -size.y/2), Vector2(size.x/2, -size.y/2), Vector2(size.x/2, size.y/2), Vector2(-size.x/2, size.y/2)])
	visual.color = color
	body.add_child(visual)
	add_child(body)

func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = arena_start
	add_child(player)
	player.died.connect(_on_player_died)

func _spawn_enemy(pos: Vector2) -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.position = pos
	add_child(enemy)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 20)
	panel.custom_minimum_size = Vector2(290, 92)
	hud.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "PLAYER"
	title.add_theme_color_override("font_color", Color("#e8e8e8"))
	box.add_child(title)
	health_bar = ProgressBar.new()
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.show_percentage = false
	box.add_child(health_bar)
	ammo_label = Label.new()
	ammo_label.text = "PISTOLA  12 / 12"
	box.add_child(ammo_label)
	status_label = Label.new()
	status_label.position = Vector2(24, 650)
	status_label.text = "WASD mover  |  ESPAÇO pular  |  SHIFT dash  |  MOUSE mirar/disparar  |  F corpo a corpo"
	hud.add_child(status_label)

func _on_player_died() -> void:
	get_tree().reload_current_scene()
