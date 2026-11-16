extends Node2D
## PLAYGROUND — um único cenário para testar movimento e luta.
## Teclas 1-0 e "-" criam inimigos/armas NA MIRA. Veja a barra no rodapé (TAB) e a ajuda (H).

const MAP := preload("res://scripts/playground.gd")
const LevelScript := preload("res://scripts/level.gd")
const CameraScript := preload("res://scripts/game_camera.gd")
const HudScript := preload("res://scripts/hud.gd")
const ITEM := preload("res://scripts/weapon_item.gd")
const Fx := preload("res://scripts/fx.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

const ENEMY_KINDS := {"g": 0, "s": 1, "b": 2, "d": 3}   # = Enemy.Kind
const SPAWNS := [
	{"tecla": "1", "key": KEY_1, "nome": "Atirador", "inimigo": "g"},
	{"tecla": "2", "key": KEY_2, "nome": "Escopeteiro", "inimigo": "s"},
	{"tecla": "3", "key": KEY_3, "nome": "Brutamontes", "inimigo": "b"},
	{"tecla": "4", "key": KEY_4, "nome": "Boneco", "inimigo": "d"},
	{"tecla": "5", "key": KEY_5, "nome": "Pistola", "arma": "pistola"},
	{"tecla": "6", "key": KEY_6, "nome": "Escopeta", "arma": "escopeta"},
	{"tecla": "7", "key": KEY_7, "nome": "Submetralhadora", "arma": "metralhadora"},
	{"tecla": "8", "key": KEY_8, "nome": "Taco", "arma": "taco"},
	{"tecla": "9", "key": KEY_9, "nome": "Faca", "arma": "faca"},
	{"tecla": "0", "key": KEY_0, "nome": "Espada", "arma": "espada"},
	{"tecla": "-", "key": KEY_MINUS, "nome": "Garrafa", "arma": "garrafa"},
]
const MAX_ENEMIES := 40
const MAX_ITEMS := 60
const RESPAWN_DELAY := 1.6

var world: Node2D
var level: Node2D
var player: CharacterBody2D
var camera: Camera2D
var hud: CanvasLayer

var combo := 0
var combo_damage := 0
var combo_t := 0.0
var combo_pop := 0.0
var best_combo := 0
var kills := 0
var hurt_flash := 0.0
var show_spawn := true
var show_help := true
var _help_auto := 14.0
var _respawn_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	build_world()


## (Re)cria o playground do zero.
func build_world() -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	Game.reset_time()
	Game.gameplay_active = true
	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	level = LevelScript.new()
	level.name = "Level"
	world.add_child(level)
	level.build(MAP.DATA, MAP.ITEM_CHARS)
	for s: Dictionary in level.enemy_spawns:
		var guard := spawn_enemy(s["kind"], s["pos"], s["facing"])
		if guard:
			guard.patrols = false   # os do mapa ficam de guarda na zona deles
	for s: Dictionary in level.item_spawns:
		spawn_item(s["kind"], s["pos"])

	player = PLAYER_SCENE.instantiate()
	player.position = level.player_spawn
	world.add_child(player)
	player.died.connect(_on_player_died)
	player.hit_landed.connect(_on_hit_landed)
	player.damaged.connect(func(_a: int) -> void: hurt_flash = 1.0)

	camera = CameraScript.new()
	world.add_child(camera)
	camera.make_current()
	camera.setup(player, Rect2(Vector2.ZERO, level.pixel_size()))
	combo = 0
	_respawn_t = 0.0


func alive_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return e.is_alive())


func spawn_enemy(key: String, pos: Vector2, facing := -1) -> Node:
	if alive_enemies().size() >= MAX_ENEMIES:
		hud.message("Limite de %d inimigos — X limpa" % MAX_ENEMIES)
		return null
	var e := ENEMY_SCENE.instantiate()
	e.kind = ENEMY_KINDS[key]
	e.facing = facing
	e.position = pos
	if key == "d":
		e.patrols = false
	world.add_child(e)
	e.killed.connect(_on_enemy_killed)
	return e


func spawn_item(kind: String, pos: Vector2) -> Node:
	var items := get_tree().get_nodes_in_group("items")
	if items.size() >= MAX_ITEMS:
		items[0].queue_free()
	var it := ITEM.new()
	it.kind = kind
	it.position = pos
	world.add_child(it)
	return it


## Cria o que a entrada de SPAWNS pede, na posição do mouse.
func spawn_at_cursor(entry: Dictionary, at := Vector2.INF) -> Node:
	var p := at if at.is_finite() else world.get_global_mouse_position()
	var is_enemy := entry.has("inimigo")
	var spot := _free_spot(p, is_enemy)
	if not spot.is_finite():
		hud.message("Lugar bloqueado — mire num espaço livre")
		return null
	var n: Node
	if is_enemy:
		var face := 1 if player.global_position.x > spot.x else -1
		n = spawn_enemy(entry["inimigo"], spot, face)
		Fx.ring(world, spot + Vector2(0, -26), Color("#e0574a"), 50.0)
	else:
		n = spawn_item(entry["arma"], spot)
		Fx.ring(world, spot, Color("#ff8a2b"), 30.0)
	if n:
		Sfx.play("ui", -8.0)
	return n


## Procura um ponto livre (sem parede) perto de p, subindo se precisar.
func _free_spot(p: Vector2, tall: bool) -> Vector2:
	var size: Vector2 = level.pixel_size()
	p = p.clamp(Vector2(40, 60), size - Vector2(40, 40))
	if tall:
		p.y += 24.0   # para inimigos, p = pés (corpo fica centrado na mira)
	for i in 12:
		var ok := _point_free(p + Vector2(0, -4))
		if tall:
			ok = ok and _point_free(p + Vector2(0, -24)) and _point_free(p + Vector2(0, -46))
		if ok:
			return p
		p.y -= 32.0
	return Vector2.INF


func _point_free(p: Vector2) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = Game.L_WORLD
	return world.get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for b in get_tree().get_nodes_in_group("blood"):
		b.queue_free()


func clear_items() -> void:
	for it in get_tree().get_nodes_in_group("items"):
		it.queue_free()


func respawn_player() -> void:
	_respawn_t = 0.0
	player.respawn(level.player_spawn)
	camera.snap_to_target()


# ------------------------------------------------------------- eventos ---

func _on_hit_landed(dmg: int) -> void:
	combo += 1
	combo_damage = combo_damage + dmg if combo > 1 else dmg
	combo_t = 1.8
	combo_pop = 1.0
	best_combo = maxi(best_combo, combo)


func _on_enemy_killed(enemy: Node) -> void:
	kills += 1
	for other in alive_enemies():
		if other != enemy and other.global_position.distance_to(enemy.global_position) < 320.0:
			other.alert(player.center())


func _on_player_died() -> void:
	_respawn_t = RESPAWN_DELAY
	hurt_flash = 1.0


# ------------------------------------------------------------- loop / entrada ---

func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	if get_tree().paused:
		return
	combo_t = maxf(0.0, combo_t - real_dt)
	if combo_t <= 0.0:
		combo = 0
	combo_pop = maxf(0.0, combo_pop - real_dt * 6.0)
	hurt_flash = maxf(0.0, hurt_flash - real_dt * 2.5)
	if _respawn_t > 0.0:
		_respawn_t -= real_dt
		if _respawn_t <= 0.0:
			respawn_player()
	if _help_auto > 0.0:
		_help_auto -= real_dt
		if _help_auto <= 0.0:
			show_help = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		if event.is_action_pressed("respawn"):
			respawn_player()
		return
	var code: Key = event.physical_keycode
	if code == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if code == KEY_BACKSPACE:
		_set_paused(false)
		build_world()
		hud.message("Playground resetado")
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("respawn"):
		respawn_player()
		return
	for s: Dictionary in SPAWNS:
		if code == s["key"]:
			spawn_at_cursor(s)
			return
	match code:
		KEY_X:
			clear_enemies()
			hud.message("Inimigos removidos")
		KEY_C:
			clear_items()
			hud.message("Armas removidas")
		KEY_I:
			Game.ai_enabled = not Game.ai_enabled
			hud.message("IA dos inimigos: " + ("LIGADA" if Game.ai_enabled else "DESLIGADA (viram sacos de pancada)"))
		KEY_G:
			Game.god_mode = not Game.god_mode
			hud.message("Modo deus: " + ("LIGADO" if Game.god_mode else "DESLIGADO"))
		KEY_H:
			show_help = not show_help
			_help_auto = 0.0
		KEY_TAB:
			show_spawn = not show_spawn


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	hud.paused = on
	if on:
		Engine.time_scale = 1.0
