extends Node
## Gera capturas de tela de várias situações do jogo (precisa de janela/GPU):
##   godot --path . res://tests/screenshots.tscn -- <pasta_de_saida>
## Útil para documentação e para revisar o visual sem jogar.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

var out_dir := "user://screenshots"
var main: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _shots()
	get_tree().quit()


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(file))
	print("salvo ", file)


func mouse_at_world(p: Vector2) -> void:
	var screen := get_viewport().get_canvas_transform() * p
	main.world.get_viewport().warp_mouse(screen)
	Input.warp_mouse(screen)


func _shots() -> void:
	await wait(0.6)
	await shot("01_titulo.png")

	main.start_level(0)
	await wait(0.4)
	Game.god_mode = true
	await shot("02_fase1_inicio.png")
	var p: CharacterBody2D = main.player
	var e: Node2D = main.get_tree().get_nodes_in_group("enemies")[0]
	p.global_position = e.global_position + Vector2(-60, 0)
	e.patrols = false
	await wait(0.3)
	p.input_lock = 0.0
	p.use_aim_override = true
	p.aim_override = e.global_position + Vector2(0, -24)
	p.start_attack()
	await wait(0.03)
	await shot("03_golpe.png")
	await wait(0.8)
	await shot("04_sangue.png")

	main.start_level(1)
	await wait(0.3)
	p = main.player
	var g: Node2D = null
	for en in main.get_tree().get_nodes_in_group("enemies"):
		if en.kind == 0:
			g = en
			break
	g.patrols = false
	p.global_position = g.global_position + Vector2(-330, 0)
	for i in 120:
		await get_tree().physics_frame
		if g.state == g.State.AIM and g._t > 0.42:
			break
	await shot("05_laser_mira.png")
	await wait(0.2)
	Input.action_press("slowmo")
	await wait(0.5)
	await shot("06_camera_lenta.png")
	Input.action_release("slowmo")
	await wait(0.5)

	main.start_level(2)
	Game.god_mode = true
	await wait(0.2)
	main.player.global_position = Vector2(20 * 32, 26 * 32)
	await wait(0.7)
	await shot("07_fase3_meio.png")

	main.start_level(4)
	await wait(0.6)
	await shot("08_fase5.png")
	Game.god_mode = false
	var b := BULLET_SCENE.instantiate()
	b.setup(main.player.center() + Vector2(220, 0), Vector2.LEFT, 700.0, 2.0, null)
	main.world.add_child(b)
	await wait(1.0)
	await shot("09_morte.png")

	main.start_level(0)
	await wait(0.2)
	for en in main.get_tree().get_nodes_in_group("enemies"):
		en.die(Vector2.UP)
	await wait(0.3)
	await shot("10_saida_liberada.png")
	main.player.global_position = main.door.global_position
	await wait(0.8)
	await shot("11_fase_concluida.png")
