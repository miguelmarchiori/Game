extends Node2D
## Fluxo do jogo: título -> fase -> (morte = reinício instantâneo) -> fase concluída -> próxima.
## Monta cada fase a partir de levels.gd.

const LEVELS := preload("res://scripts/levels.gd")
const LevelScript := preload("res://scripts/level.gd")
const DoorScript := preload("res://scripts/exit_door.gd")
const CameraScript := preload("res://scripts/game_camera.gd")
const HudScript := preload("res://scripts/hud.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

enum Flow { TITLE, PLAYING, DEAD, COMPLETE, FINISHED }
const KINDS := {"g": 0, "s": 1, "b": 2}   # = Enemy.Kind (GUNNER, SHOTGUN, BRUTE)

var flow: Flow = Flow.TITLE
var level_index := 0
var level_time := 0.0
var run_time := 0.0
var enemies_left := 0
var enemies_total := 0

var world: Node2D
var level: Node2D
var player: CharacterBody2D
var door: Area2D
var camera: Camera2D
var hud: CanvasLayer
var _flow_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	show_title()


func level_name() -> String:
	return String(LEVELS.LIST[level_index]["name"])


func level_count() -> int:
	return LEVELS.LIST.size()


# ------------------------------------------------------------- fluxo ---

func show_title() -> void:
	_clear_world()
	flow = Flow.TITLE
	_flow_t = 0.0
	Game.gameplay_active = false
	Game.reset_for_level()
	run_time = 0.0
	Game.deaths = 0
	hud.set_mode("title")


func start_level(i: int) -> void:
	_clear_world()
	Game.reset_for_level()
	level_index = i
	level_time = 0.0
	flow = Flow.PLAYING
	_flow_t = 0.0

	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	var data: Dictionary = LEVELS.LIST[i]
	level = LevelScript.new()
	level.name = "Level"
	world.add_child(level)
	level.build(data, i)

	door = DoorScript.new()
	door.position = level.exit_pos
	world.add_child(door)
	door.reached.connect(_on_exit_reached)

	enemies_total = 0
	for s: Dictionary in level.enemy_spawns:
		var e := ENEMY_SCENE.instantiate()
		e.kind = KINDS[s["kind"]]
		e.facing = s["facing"]
		e.position = s["pos"]
		world.add_child(e)
		e.killed.connect(_on_enemy_killed)
		enemies_total += 1
	enemies_left = enemies_total

	player = PLAYER_SCENE.instantiate()
	player.position = level.player_spawn
	world.add_child(player)
	player.died.connect(_on_player_died)

	camera = CameraScript.new()
	world.add_child(camera)
	camera.make_current()
	camera.setup(player, Rect2(Vector2.ZERO, level.pixel_size()))

	Game.gameplay_active = true
	hud.set_mode("play")
	hud.intro(level_name())
	if enemies_total == 0:
		door.unlock()


func restart_level() -> void:
	start_level(level_index)


func next_level() -> void:
	if level_index + 1 < level_count():
		start_level(level_index + 1)
	else:
		_clear_world()
		flow = Flow.FINISHED
		_flow_t = 0.0
		Game.gameplay_active = false
		hud.set_mode("finished", {"total": run_time})


func _clear_world() -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = null
	player = null
	door = null
	camera = null


# ------------------------------------------------------------- eventos ---

func _on_enemy_killed(enemy: Node) -> void:
	enemies_left = maxi(0, enemies_left - 1)
	hud.flash(Color.WHITE, 0.12)
	# aliados por perto ouvem e ficam alertas
	for other in get_tree().get_nodes_in_group("enemies"):
		if other != enemy and other.is_alive() and other.global_position.distance_to(enemy.global_position) < 300.0:
			if is_instance_valid(player):
				other.alert(player.center())
	if enemies_left == 0 and is_instance_valid(door):
		door.unlock()
		hud.message("SAÍDA LIBERADA")


func _on_player_died() -> void:
	if flow != Flow.PLAYING:
		return
	flow = Flow.DEAD
	_flow_t = 0.0
	Game.deaths += 1
	Game.gameplay_active = false
	hud.flash(Color("#ff4060"), 0.45)
	hud.set_mode("dead")


func _on_exit_reached() -> void:
	if flow != Flow.PLAYING:
		return
	flow = Flow.COMPLETE
	_flow_t = 0.0
	Game.gameplay_active = false
	player.frozen = true
	run_time += level_time
	var prev: float = Game.best_times.get(level_index, INF)
	var record := level_time < prev
	if record:
		Game.best_times[level_index] = level_time
	Sfx.play("clear")
	hud.set_mode("complete", {"time": level_time, "best": minf(prev, level_time), "record": record})


# ------------------------------------------------------------- entrada ---

func _process(delta: float) -> void:
	_flow_t += delta / maxf(Engine.time_scale, 0.01)
	if flow == Flow.PLAYING and not get_tree().paused:
		level_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
				return
			KEY_Q:
				if get_tree().paused:
					_set_paused(false)
					show_title()
					return
	if event.is_action_pressed("pause") and flow in [Flow.PLAYING, Flow.DEAD]:
		_set_paused(not get_tree().paused)
		return
	if get_tree().paused:
		if event.is_action_pressed("restart"):
			_set_paused(false)
			restart_level()
		return

	var confirm: bool = event.is_action_pressed("attack") or event.is_action_pressed("jump") \
		or (event is InputEventKey and event.pressed and event.keycode == KEY_ENTER)
	match flow:
		Flow.TITLE:
			if confirm and _flow_t > 0.3:
				Sfx.play("ui")
				start_level(0)
		Flow.PLAYING:
			if event.is_action_pressed("restart"):
				restart_level()
			elif OS.is_debug_build():
				_debug_keys(event)
		Flow.DEAD:
			if (confirm or event.is_action_pressed("restart")) and _flow_t > 0.3:
				restart_level()
		Flow.COMPLETE:
			if confirm and _flow_t > 0.4:
				next_level()
		Flow.FINISHED:
			if confirm and _flow_t > 0.6:
				show_title()


## Atalhos de teste (só funcionam rodando pelo editor / build de debug).
func _debug_keys(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F1:
			Game.god_mode = not Game.god_mode
		KEY_F2:
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.is_alive():
					e.die(Vector2.UP)
		KEY_F3:
			next_level()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	hud.paused = on
	if on:
		Engine.time_scale = 1.0
