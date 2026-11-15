extends Node
## TESTE AUTOMÁTICO — roda sem abrir janela:
##   godot --headless --path . res://tests/smoke_test.tscn
## Valida os mapas e simula as mecânicas principais (golpe, bala, rolamento,
## rebater bala, câmera lenta, escalar parede, abrir porta e terminar a fase).
## Sai com código 0 se tudo passar, 1 se algo falhar.

const LEVELS := preload("res://scripts/levels.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

var failures := 0
var main: Node


func _ready() -> void:
	await _run()
	print("")
	print("RESULTADO: %s" % ("TUDO OK" if failures == 0 else "%d FALHA(S)" % failures))
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


func enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return e.is_alive())


func _run() -> void:
	print("== mapas")
	_validate_maps()

	main = MAIN_SCENE.instantiate()
	add_child(main)
	await physics(3)

	print("== todas as fases carregam e todos nascem no chão")
	for i in LEVELS.LIST.size():
		main.start_level(i)
		Game.god_mode = true   # ninguém morre enquanto checamos
		await physics(40)
		check(main.player.is_on_floor(), "fase %d: jogador no chão" % (i + 1))
		var grounded := 0
		var all := get_tree().get_nodes_in_group("enemies")
		for e in all:
			if e.is_on_floor():
				grounded += 1
		check(grounded == all.size(), "fase %d: %d/%d inimigos no chão" % [i + 1, grounded, all.size()])
		Game.god_mode = false

	print("== golpe mata inimigo")
	main.start_level(0)
	await physics(10)
	var target: Node2D = enemies()[0]
	_park(target)
	var p: CharacterBody2D = main.player
	p.global_position = target.global_position + Vector2(-40, 0)
	await physics(3)
	p.input_lock = 0.0
	p.use_aim_override = true
	p.aim_override = target.global_position + Vector2(0, -24)
	p.start_attack()
	await physics(12)
	check(not target.is_alive(), "brutamontes morre com 1 golpe")
	check(main.enemies_left == main.enemies_total - 1, "contador de alvos atualiza")

	print("== corpo morto na vertical cai até o chão")
	main.start_level(0)
	await physics(5)
	var victim: Node2D = enemies()[0]
	var floor_y := victim.global_position.y
	victim.die(Vector2.UP)
	await physics(120)
	check(absf(victim.global_position.y - floor_y) < 4.0 and victim.is_on_floor(), "corpo volta ao chão (dy=%.1f)" % (victim.global_position.y - floor_y))

	print("== bala mata o jogador (1 acerto)")
	main.start_level(0)
	await physics(10)
	p = main.player
	_fire_at(p, Vector2(250, 0))
	await physics(40)
	check(not p.is_alive(), "jogador morre com 1 bala")
	check(main.flow == main.Flow.DEAD, "tela de morte aparece")
	main.restart_level()
	await physics(5)
	check(main.player.is_alive() and main.flow == main.Flow.PLAYING, "reinício instantâneo funciona")

	print("== rolamento é invencível")
	main.start_level(0)
	await physics(10)
	p = main.player
	p.input_lock = 0.0
	_fire_at(p, Vector2(160, 0))
	p._start_roll(1)
	await physics(30)
	check(p.is_alive(), "bala atravessa jogador rolando")

	print("== rebater bala mata o atirador")
	main.start_level(1)
	await physics(10)
	p = main.player
	var gunner: Node2D = null
	for e in enemies():
		if e.kind == 0:
			gunner = e
			break
	_park(gunner)
	gunner.patrols = false
	p.global_position = gunner.global_position + Vector2(-300, 0)
	await physics(3)
	var b := _fire_from(gunner.global_position + Vector2(-20, -30), Vector2.LEFT)
	var deflected := false
	for i in 90:
		await get_tree().physics_frame
		if is_instance_valid(b) and b.global_position.distance_to(p.center()) < 70.0:
			p.input_lock = 0.0
			p.use_aim_override = true
			p.aim_override = gunner.global_position + Vector2(0, -26)
			p.start_attack()
			deflected = b.deflected
			break
	check(deflected, "golpe rebate a bala")
	await physics(40)
	check(not gunner.is_alive(), "bala rebatida mata o atirador")
	check(p.is_alive(), "jogador sobrevive")

	print("== atirador mira (laser) e atira sozinho")
	main.start_level(1)
	await physics(10)
	p = main.player
	gunner = null
	for e in enemies():
		if e.kind == 0:
			gunner = e
			break
	p.global_position = gunner.global_position + Vector2(-260 * gunner.facing * -1, 0)
	var saw_aim := false
	for i in 150:
		await get_tree().physics_frame
		if gunner.state == gunner.State.AIM:
			saw_aim = true
		if not p.is_alive():
			break
	check(saw_aim, "atirador entra em modo de mira")
	check(not p.is_alive(), "atirador acerta jogador parado")

	print("== câmera lenta")
	main.start_level(0)
	await physics(10)
	Input.action_press("slowmo")
	await get_tree().create_timer(0.4, true, false, true).timeout
	check(Game.slowmo_active and Engine.time_scale < 0.5, "SHIFT deixa o tempo lento (time_scale=%.2f)" % Engine.time_scale)
	check(Game.battery < 1.0, "bateria FOCO gasta")
	Input.action_release("slowmo")
	await get_tree().create_timer(0.4, true, false, true).timeout
	check(not Game.slowmo_active and Engine.time_scale > 0.95, "tempo volta ao normal")

	print("== escalar o poço (pulo na parede) — fase 3")
	main.start_level(2)
	await physics(5)
	Game.god_mode = true
	p = main.player
	p.global_position = Vector2(2.5 * 32, 44 * 32)   # fundo do poço A
	await physics(10)
	var top := await _climb_bot(p, 27 * 32 - 8, 8.0)
	check(top <= 27 * 32 - 8, "consegue subir o poço A (chegou a y=%d, meta %d)" % [int(top), 27 * 32 - 8])
	Game.god_mode = false

	print("== escalar o poço B — fase 3")
	main.start_level(2)
	await physics(5)
	Game.god_mode = true
	p = main.player
	p.global_position = Vector2(29.5 * 32, 24 * 32)   # degrau na entrada do poço B
	await physics(10)
	top = await _climb_bot(p, 8 * 32 - 8, 8.0)
	check(top <= 8 * 32 - 8, "consegue subir o poço B (chegou a y=%d, meta %d)" % [int(top), 8 * 32 - 8])

	print("== descer da plataforma fina (S parado)")
	main.start_level(0)
	await physics(5)
	Game.god_mode = true
	p = main.player
	p.global_position = Vector2(39.5 * 32, 14 * 32)
	await physics(15)
	var on_plat: bool = p.is_on_floor() and p._on_oneway
	p.input_lock = 0.0
	Input.action_press("down")
	await physics(2)
	Input.action_release("down")
	await physics(20)
	check(on_plat and p.global_position.y > 14 * 32 + 20, "atravessa a plataforma para baixo")
	Game.god_mode = false

	print("== pulo alcança degrau de 3 blocos")
	main.start_level(0)
	await physics(10)
	p = main.player
	p.input_lock = 0.0
	var y0 := p.global_position.y
	Input.action_press("jump")
	var min_y := y0
	for i in 40:
		await get_tree().physics_frame
		min_y = minf(min_y, p.global_position.y)
	Input.action_release("jump")
	check(y0 - min_y >= 3 * 32 + 4, "altura do pulo = %d px (precisa > 100)" % int(y0 - min_y))

	print("== matar todos abre a porta e a fase termina")
	for i in LEVELS.LIST.size():
		main.start_level(i)
		await physics(5)
		for e in enemies():
			e.die(Vector2.UP)
		await physics(5)
		check(not main.door.locked, "fase %d: porta abre sem inimigos" % (i + 1))
		main.player.global_position = main.door.global_position
		await physics(5)
		check(main.flow == main.Flow.COMPLETE, "fase %d: chegar na porta conclui" % (i + 1))
	main.next_level()
	await physics(2)
	check(main.flow == main.Flow.FINISHED, "após a última fase aparece o fim")


## Bot simples: segura na direção da parede e pula alternando os lados.
func _climb_bot(p: CharacterBody2D, goal_y: float, seconds: float) -> float:
	var dir := -1
	var best := p.global_position.y
	var t := 0.0
	var jump_hold := 0.0
	Input.action_press("move_left")
	while t < seconds and best > goal_y:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		best = minf(best, p.global_position.y)
		jump_hold -= get_physics_process_delta_time()
		if jump_hold <= 0.0 and Input.is_action_pressed("jump"):
			Input.action_release("jump")
		var wall: int = p._detect_wall()
		if (p.is_on_floor() or wall != 0) and jump_hold <= -0.05:
			Input.action_press("jump")
			jump_hold = 0.2
			if wall != 0:
				Input.action_release("move_left" if dir < 0 else "move_right")
				dir = -wall
				Input.action_press("move_left" if dir < 0 else "move_right")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("jump")
	return best


func _park(e: Node2D) -> void:
	e.patrols = false
	e.velocity = Vector2.ZERO


func _fire_at(p: Node2D, offset: Vector2) -> Node:
	var from: Vector2 = p.center() + offset
	return _fire_from(from, (p.center() - from).normalized())


func _fire_from(from: Vector2, dir: Vector2) -> Node:
	var b := BULLET_SCENE.instantiate()
	b.setup(from, dir, 700.0, 2.0, null)
	main.world.add_child(b)
	return b


func _validate_maps() -> void:
	var valid := "#-.PDgGsSbB"
	for i in LEVELS.LIST.size():
		var data: Dictionary = LEVELS.LIST[i]
		var rows: Array = data["map"]
		var w := String(rows[0]).length()
		var ok_width := true
		var counts := {"P": 0, "D": 0, "enemy": 0}
		var bad_chars := ""
		var floating := []
		for y in rows.size():
			var row := String(rows[y])
			if row.length() != w:
				ok_width = false
			for x in row.length():
				var c := row[x]
				if not valid.contains(c):
					bad_chars += c
				if c == "P" or c == "D":
					counts[c] += 1
				if "gGsSbB".contains(c):
					counts["enemy"] += 1
				if "PDgGsSbB".contains(c):
					var below := String(rows[y + 1])[x] if y + 1 < rows.size() else "#"
					if below != "#" and below != "-":
						floating.append("%s(%d,%d)" % [c, x, y])
		var border := true
		for x in w:
			if String(rows[0])[x] != "#" or String(rows[rows.size() - 1])[x] != "#":
				border = false
		for y in rows.size():
			var row2 := String(rows[y])
			if row2[0] != "#" or row2[row2.length() - 1] != "#":
				border = false
		var name := String(data["name"])
		check(ok_width, "%s: todas as linhas com a mesma largura" % name)
		check(bad_chars == "", "%s: caracteres válidos %s" % [name, bad_chars])
		check(counts["P"] == 1 and counts["D"] == 1, "%s: 1 jogador e 1 porta" % name)
		check(counts["enemy"] > 0, "%s: %d inimigos" % [name, counts["enemy"]])
		check(floating.is_empty(), "%s: ninguém flutuando %s" % [name, str(floating)])
		check(border, "%s: borda fechada" % name)
