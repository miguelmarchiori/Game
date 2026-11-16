extends Node
## Gera capturas de tela de várias situações (precisa de janela/GPU):
##   godot --path . res://tests/screenshots.tscn -- <pasta_de_saida>

const MAIN_SCENE := preload("res://scenes/main.tscn")
const T := 32.0
const FLOOR_Y := 28 * 32.0

var out_dir := "user://screenshots"
var main: Node
var p: CharacterBody2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _shots()
	get_tree().quit()


func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	print("salvo ", file)


func place(pos: Vector2) -> void:
	p = main.player
	p.global_position = pos
	p.reset_physics_interpolation()
	main.camera.snap_to_target()
	p.input_lock = 0.0


func aim(at: Vector2) -> void:
	p.use_aim_override = true
	p.aim_override = at
	Input.warp_mouse(get_viewport().get_canvas_transform() * at)


func _shots() -> void:
	await wait(0.8)
	await shot("01_inicio_ajuda.png")
	main.show_help = false
	Game.god_mode = true
	Game.ai_enabled = false

	# combo no boneco
	place(Vector2(33.0 * T, FLOOR_Y))
	await wait(0.4)
	var dummy: Node2D = get_tree().get_nodes_in_group("enemies").filter(func(e): return e.kind == 3)[0]
	aim(dummy.global_position + Vector2(0, -30))
	p._start_attack(true)
	await wait(0.25)
	p._start_attack(true)
	await wait(0.25)
	p._start_attack(true)
	await frames(9)
	await shot("02_chute_boneco.png")

	# brutamontes + gancho
	await wait(0.5)
	var bru: Node2D = main.spawn_enemy("b", p.global_position + Vector2(44, 0), -1)
	await wait(0.3)
	aim(p.global_position + Vector2(10, -300))
	p._start_attack(true)
	await frames(10)
	await shot("03_gancho.png")

	# voadora no ar
	await wait(0.6)
	var g: Node2D = main.spawn_enemy("g", p.global_position + Vector2(160, 0), -1)
	await wait(0.3)
	p.velocity.y = -600.0
	await frames(14)
	aim(g.center())
	p._start_attack(false)
	await frames(8)
	await shot("04_voadora.png")

	# escopeta
	await wait(0.8)
	main.clear_enemies()
	place(Vector2(46.5 * T, FLOOR_Y))
	p.weapon = "escopeta"
	p.ammo = 6
	var g2: Node2D = main.spawn_enemy("s", p.global_position + Vector2(200, 0), -1)
	main.spawn_enemy("g", p.global_position + Vector2(260, 0), -1)
	await wait(0.4)
	aim(g2.center())
	Input.action_press("attack")
	await frames(3)
	Input.action_release("attack")
	await frames(3)
	await shot("05_escopeta.png")

	# taco
	await wait(0.6)
	p.weapon = "taco"
	var b2: Node2D = main.spawn_enemy("g", p.global_position + Vector2(50, 0), -1)
	await wait(0.3)
	aim(b2.center())
	p._start_attack(true)
	await frames(9)
	await shot("06_taco.png")

	# deslize no túnel
	await wait(0.5)
	main.clear_enemies()
	p.weapon = ""
	place(Vector2(26.0 * T, FLOOR_Y))
	await wait(0.2)
	Input.action_press("move_left")
	await frames(8)
	Input.action_press("down")
	await frames(16)
	await shot("07_deslize_tunel.png")
	Input.action_release("down")
	Input.action_release("move_left")

	# dash
	await wait(0.8)
	place(Vector2(40.0 * T, FLOOR_Y))
	await wait(0.3)
	Input.action_press("move_right")
	Input.action_press("dash")
	await frames(2)
	Input.action_release("dash")
	await frames(7)
	await shot("08_dash.png")
	Input.action_release("move_right")

	# IA ligada: inimigos mirando
	await wait(0.6)
	Game.ai_enabled = true
	place(Vector2(62.0 * T, FLOOR_Y))
	main.spawn_enemy("g", Vector2(72.5 * T, 24 * T), -1)
	main.spawn_enemy("s", Vector2(70.5 * T, 24 * T), -1)
	await wait(1.1)
	await shot("09_rampas_laser.png")

	# câmera lenta
	Input.action_press("slowmo")
	await wait(0.5)
	await shot("10_camera_lenta.png")
	Input.action_release("slowmo")

	# torre de parkour
	await wait(0.4)
	Game.ai_enabled = false
	place(Vector2(3.0 * T, 20 * T))
	p.velocity = Vector2(-200, -300)
	await frames(12)
	await shot("11_torre_parkour.png")
