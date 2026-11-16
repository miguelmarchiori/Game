extends Node
## TESTE AUTOMÁTICO — roda sem abrir janela:
##   godot --headless --path . res://tests/smoke_test.tscn
## Valida o mapa e simula as mecânicas (apertando as teclas de verdade quando dá).
## Sai com código 0 se tudo passar, 1 se algo falhar.

const MAP := preload("res://scripts/playground.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const T := 32.0
const FLOOR_Y := 28 * 32.0

var failures := 0
var main: Node
var p: CharacterBody2D


func _ready() -> void:
	await _run()
	print("")
	print("RESULTADO: %s" % ("TUDO OK" if failures == 0 else "%d FALHA(S)" % failures))
	release_all()
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok     ", msg)
	else:
		failures += 1
		print("  FALHA  ", msg)


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await physics(int(s * 60.0))


func tap(action: String, frames := 2) -> void:
	Input.action_press(action)
	await physics(frames)
	Input.action_release(action)
	await physics(1)


func release_all() -> void:
	for a in ["move_left", "move_right", "jump", "down", "dash", "attack", "throw", "interact", "kick", "slowmo"]:
		Input.action_release(a)


## Reseta o playground (sem inimigos, IA desligada) com o jogador em `pos` (pés).
func fresh(pos := Vector2.INF, ai := false) -> void:
	release_all()
	main.build_world()
	main.clear_enemies()
	Game.ai_enabled = ai
	Game.god_mode = false
	p = main.player
	await physics(3)
	if pos.is_finite():
		p.global_position = pos
		p.reset_physics_interpolation()
	p.input_lock = 0.0
	await physics(8)
	p.input_lock = 0.0


func aim_at(target: Vector2) -> void:
	p.use_aim_override = true
	p.aim_override = target


func enemy_bullet(from: Vector2, to: Vector2) -> Node:
	var b := BULLET_SCENE.instantiate()
	b.setup(from, (to - from).normalized(), 700.0, 2.0, null, "enemy", 18)
	main.world.add_child(b)
	return b


func _run() -> void:
	print("== mapa")
	_validate_map()

	main = MAIN_SCENE.instantiate()
	add_child(main)
	await physics(40)
	p = main.player

	print("== playground carrega")
	check(p.is_on_floor(), "jogador nasce no chão")
	var all := get_tree().get_nodes_in_group("enemies")
	var grounded := all.filter(func(e: Node) -> bool: return e.is_on_floor()).size()
	check(grounded == all.size() and all.size() == 5, "%d/%d inimigos no chão" % [grounded, all.size()])
	check(get_tree().get_nodes_in_group("items").size() == 7, "7 armas no chão")
	check(p.weapon == "", "começa de mãos livres")

	print("== combo no boneco (cliques de verdade)")
	await fresh(Vector2(34.5 * T - 40.0, FLOOR_Y))
	var dummy: Node2D = main.spawn_enemy("d", Vector2(34.5 * T, FLOOR_Y))
	await physics(10)
	aim_at(dummy.global_position + Vector2(0, -30))
	for i in 3:
		await tap("attack")
		await seconds(0.28)
	check(main.combo >= 3, "soco, soco, chute acertam (combo x%d)" % main.combo)
	check(dummy.is_alive(), "boneco não morre")

	print("== matar atirador só no braço")
	await fresh(Vector2(46.5 * T, FLOOR_Y))
	var g: Node2D = main.spawn_enemy("g", p.global_position + Vector2(50, 0), -1)
	await physics(10)
	var items_before := get_tree().get_nodes_in_group("items").size()
	var taps := 0
	while g.is_alive() and taps < 14:
		aim_at(g.global_position + Vector2(0, -26))
		if absf(g.global_position.x - p.global_position.x) > 70.0:
			p.global_position.x = g.global_position.x - 45.0
		await tap("attack")
		await seconds(0.26)
		taps += 1
	check(not g.is_alive(), "atirador derrotado em %d golpes" % taps)
	await physics(20)
	check(get_tree().get_nodes_in_group("items").size() == items_before + 1, "inimigo larga a arma ao morrer")

	print("== gancho lança para o alto")
	await fresh(Vector2(46.5 * T, FLOOR_Y))
	g = main.spawn_enemy("g", p.global_position + Vector2(36, 0), -1)
	await physics(10)
	aim_at(p.global_position + Vector2(10, -300))
	await tap("attack")
	var max_rise := 0.0
	for i in 30:
		await get_tree().physics_frame
		max_rise = maxf(max_rise, FLOOR_Y - g.global_position.y)
	check(max_rise > 60.0, "inimigo sobe %d px" % int(max_rise))

	print("== pegar pistola e atirar")
	await fresh(Vector2(38.5 * T, FLOOR_Y))
	await physics(5)
	check(p.near_item != null, "arma ao alcance é detectada")
	await tap("interact")
	check(p.weapon == "pistola" and p.ammo == 12, "E pega a pistola (%s, %d balas)" % [p.weapon, p.ammo])
	g = main.spawn_enemy("g", p.global_position + Vector2(220, 0), -1)
	await physics(10)
	for i in 2:
		aim_at(g.global_position + Vector2(0, -26))
		await tap("attack")
		await seconds(0.3)
	check(not g.is_alive(), "2 tiros derrubam o atirador")
	check(p.ammo == 10, "munição desconta (%d)" % p.ammo)

	print("== arremessar faca")
	await fresh(Vector2(46.5 * T, FLOOR_Y))
	p.weapon = "faca"
	g = main.spawn_enemy("g", p.global_position + Vector2(180, 0), -1)
	await physics(10)
	aim_at(g.global_position + Vector2(0, -26))
	await tap("throw")
	await seconds(0.5)
	check(p.weapon == "", "arma sai da mão")
	check(not g.is_alive(), "faca arremessada mata o atirador")

	print("== taco rebate bala")
	await fresh(Vector2(46.5 * T, FLOOR_Y))
	p.weapon = "taco"
	var b := enemy_bullet(p.center() + Vector2(300, 0), p.center())
	var swung := false
	var turned := false
	for i in 60:
		await get_tree().physics_frame
		if not swung and is_instance_valid(b) and b.global_position.distance_to(p.center()) < 95.0:
			aim_at(p.center() + Vector2(300, 0))
			p._start_attack(true)
			swung = true
		if is_instance_valid(b) and b.team == "player":
			turned = true
	check(turned, "bala vira do jogador")
	check(p.health >= 99.0, "jogador não tomou o tiro (vida %d)" % int(p.health))

	print("== dano, morte e renascimento")
	await fresh(Vector2(46.5 * T, FLOOR_Y))
	enemy_bullet(p.center() + Vector2(200, 0), p.center())
	await seconds(0.5)
	check(is_equal_approx(p.health, 82.0) and p.is_alive(), "bala tira 18 de vida (vida %d)" % int(p.health))
	p.health = 10.0
	p._regen_wait = 5.0
	enemy_bullet(p.center() + Vector2(200, 0), p.center())
	await seconds(0.5)
	check(not p.is_alive(), "jogador cai com vida zerada")
	await seconds(1.8)
	check(p.is_alive() and p.health == 100.0, "renasce sozinho")
	check(p.global_position.distance_to(main.level.player_spawn) < 40.0, "renasce no ponto inicial")

	print("== dash")
	await fresh(Vector2(46.5 * T, FLOOR_Y))
	var x0 := p.global_position.x
	Input.action_press("move_right")
	await tap("dash")
	var inv: bool = p._invuln > 0.0
	await seconds(0.15)
	Input.action_release("move_right")
	check(p.global_position.x - x0 > 150.0, "dash anda %d px" % int(p.global_position.x - x0))
	check(inv, "dash dá invencibilidade")

	print("== deslizar por baixo do túnel")
	await fresh(Vector2(25.5 * T, FLOOR_Y))
	Input.action_press("move_left")
	await seconds(0.12)
	Input.action_press("down")
	var saw_slide := false
	for i in 240:
		await get_tree().physics_frame
		if p.state == p.State.SLIDE:
			saw_slide = true
		if p.global_position.x < 15.5 * T:
			break
	release_all()
	check(saw_slide, "S correndo = deslize")
	check(p.global_position.x < 15.5 * T, "atravessa o túnel (x=%d)" % int(p.global_position.x))
	await fresh(Vector2(25.0 * T, FLOOR_Y))
	Input.action_press("move_left")
	await seconds(1.5)
	release_all()
	check(p.global_position.x > 22.5 * T, "em pé não passa no túnel")

	print("== vault em caixote baixo")
	await fresh(Vector2(30.0 * T, FLOOR_Y))
	Input.action_press("move_left")
	var saw_vault := false
	for i in 90:
		await get_tree().physics_frame
		if p.state == p.State.MANTLE:
			saw_vault = true
	release_all()
	check(saw_vault and p.global_position.x < 25.5 * T, "pula o caixote sozinho correndo (x=%d)" % int(p.global_position.x))

	print("== agarrar a borda")
	await fresh(Vector2(7.5 * T, FLOOR_Y))
	Input.action_press("move_right")
	await tap("jump", 2)   # pulinho curto: não alcança sozinho
	var saw_mantle := false
	for i in 60:
		await get_tree().physics_frame
		if p.state == p.State.MANTLE:
			saw_mantle = true
		elif saw_mantle:
			break
	release_all()
	await physics(5)
	check(saw_mantle, "agarra e sobe a borda")
	check(absf(p.global_position.y - 25 * T) < 4.0 and p.is_on_floor(), "termina em cima do degrau (y=%d)" % int(p.global_position.y))

	print("== escalar a torre (pulo na parede)")
	await fresh(Vector2(2.5 * T, FLOOR_Y))
	var top := await _climb_bot(14 * T + 10.0, 8.0)
	check(top <= 14 * T + 10.0, "chega na passarela (y=%d, meta %d)" % [int(top), int(14 * T + 10.0)])

	print("== plataforma de salto")
	await fresh(Vector2(80.5 * T, FLOOR_Y))
	p.global_position = Vector2(83.5 * T, FLOOR_Y - 2.0)
	p.reset_physics_interpolation()
	var min_y := FLOOR_Y
	for i in 70:
		await get_tree().physics_frame
		min_y = minf(min_y, p.global_position.y)
	check(min_y < 13 * T, "lança até a plataforma alta (y mín=%d)" % int(min_y))

	print("== deslize na rampa ganha velocidade")
	await fresh(Vector2(73.5 * T, 24 * T))
	Input.action_press("move_right")
	await seconds(0.3)
	Input.action_press("down")
	var start_v := 0.0
	var max_v := 0.0
	for i in 50:
		await get_tree().physics_frame
		if p.state == p.State.SLIDE:
			if start_v == 0.0:
				start_v = absf(p.velocity.x)
			max_v = maxf(max_v, absf(p.velocity.x))
	release_all()
	check(max_v > start_v + 40.0, "acelera na descida (%d -> %d px/s)" % [int(start_v), int(max_v)])

	print("== câmera lenta (Q)")
	await fresh()
	Input.action_press("slowmo")
	await get_tree().create_timer(0.4, true, false, true).timeout
	check(Game.slowmo_active and Engine.time_scale < 0.5, "tempo lento (time_scale=%.2f)" % Engine.time_scale)
	Input.action_release("slowmo")
	await get_tree().create_timer(0.4, true, false, true).timeout
	check(Engine.time_scale > 0.95, "volta ao normal")

	print("== spawn na mira / IA / limpar")
	await fresh(Vector2(46.5 * T, FLOOR_Y))
	var n0: int = main.alive_enemies().size()
	var e1: Node = main.spawn_at_cursor(main.SPAWNS[0], Vector2(52.0 * T, FLOOR_Y + 40.0))   # mira dentro do chão
	var it1: Node = main.spawn_at_cursor(main.SPAWNS[9], Vector2(44.0 * T, 20 * T))
	await seconds(0.8)
	check(e1 != null and main.alive_enemies().size() == n0 + 1, "tecla 1 cria atirador")
	check(e1 != null and e1.is_on_floor() and e1.global_position.y <= FLOOR_Y + 1.0, "não nasce preso no chão")
	check(it1 != null and it1.kind == "espada", "tecla 0 cria espada")
	Game.ai_enabled = false
	e1.global_position = p.global_position + Vector2(220, 0)
	await seconds(1.5)
	check(p.health == 100.0, "IA desligada: não atira")
	Game.ai_enabled = true
	await seconds(2.0)
	check(p.health < 100.0, "IA ligada: atira (vida %d)" % int(p.health))
	main.clear_enemies()
	main.clear_items()
	await physics(2)
	check(get_tree().get_nodes_in_group("enemies").is_empty() and get_tree().get_nodes_in_group("items").is_empty(), "X e C limpam tudo")


## Bot: segura na direção da parede e pula alternando os lados.
func _climb_bot(goal_y: float, secs: float) -> float:
	var dir := -1
	var best := p.global_position.y
	var t := 0.0
	var hold := 0.0
	Input.action_press("move_left")
	while t < secs and best > goal_y:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		best = minf(best, p.global_position.y)
		hold -= 1.0 / 60.0
		if hold <= 0.0 and Input.is_action_pressed("jump"):
			Input.action_release("jump")
		var wall: int = p._detect_wall()
		if (p.is_on_floor() or wall != 0) and hold <= -0.05:
			Input.action_press("jump")
			hold = 0.2
			if wall != 0:
				Input.action_release("move_left" if dir < 0 else "move_right")
				dir = -wall
				Input.action_press("move_left" if dir < 0 else "move_right")
	release_all()
	return best


func _validate_map() -> void:
	var valid := "#-/\\JP.gGsSbBd1234567"
	var data: Dictionary = MAP.DATA
	var rows: Array = data["map"]
	var w := String(rows[0]).length()
	var ok_width := true
	var spawns := 0
	var bad := ""
	var floating := []
	for y in rows.size():
		var row := String(rows[y])
		if row.length() != w:
			ok_width = false
		for x in row.length():
			var c := row[x]
			if not valid.contains(c):
				bad += c
			if c == "P":
				spawns += 1
			if "PgGsSbBd1234567".contains(c):
				var below := String(rows[y + 1])[x] if y + 1 < rows.size() else "#"
				if not "#-/\\J".contains(below):
					floating.append("%s(%d,%d)" % [c, x, y])
	var border := true
	for x in w:
		if String(rows[0])[x] != "#" or String(rows[rows.size() - 1])[x] != "#":
			border = false
	for y in rows.size():
		var r := String(rows[y])
		if r[0] != "#" or r[r.length() - 1] != "#":
			border = false
	check(ok_width, "linhas com a mesma largura (%d)" % w)
	check(bad == "", "só caracteres válidos %s" % bad)
	check(spawns == 1, "1 ponto de nascimento")
	check(floating.is_empty(), "ninguém flutuando %s" % str(floating))
	check(border, "borda fechada")
