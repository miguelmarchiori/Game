extends RefCounted
## Efeitos visuais feitos só com código (sem sprites):
##   Fx.blood()  — gotas que voam e GRUDAM em paredes/chão (ficam até reiniciar a fase)
##   Fx.sparks() — faíscas (tiro, bala rebatida)
##   Fx.dust()   — poeira (pulo, aterrissagem)
##   Fx.slash()  — arco do golpe da lâmina
##   Fx.ghost()  — "fantasma" do jogador durante o rolamento
##   Fx.ring()   — anel expandindo (porta abrindo, etc.)
## Uso:  const Fx := preload("res://scripts/fx.gd")  e depois  Fx.blood(parent, pos, dir)

const C_BLOOD := Color("#e0244f")
const C_BLOOD_DRY := Color("#9c1838")


static func blood(parent: Node, pos: Vector2, dir: Vector2, amount := 30) -> void:
	var b := BloodBurst.new()
	parent.add_child(b)
	b.start(pos, dir, amount)


static func sparks(parent: Node, pos: Vector2, dir: Vector2, color := Color("#ffe08a"), amount := 10, speed := 420.0) -> void:
	var s := Particles.new()
	parent.add_child(s)
	s.start(pos, dir, color, amount, speed, 0.6, 0.22, true)


static func dust(parent: Node, pos: Vector2, amount := 6) -> void:
	var s := Particles.new()
	parent.add_child(s)
	s.start(pos, Vector2.UP, Color(0.75, 0.72, 0.85, 0.5), amount, 90.0, 1.4, 0.3, false)


static func slash(parent: Node, local_pos: Vector2, dir: Vector2) -> void:
	var a := SlashArc.new()
	a.position = local_pos
	a.rotation = dir.angle()
	parent.add_child(a)


static func ghost(parent: Node, pos: Vector2, rolling: bool, color := Color("#ff3d7f")) -> void:
	var g := Ghost.new()
	g.position = pos
	g.rolling = rolling
	g.color = color
	parent.add_child(g)


static func ring(parent: Node, pos: Vector2, color: Color, radius := 60.0) -> void:
	var r := Ring.new()
	r.position = pos
	r.color = color
	r.max_radius = radius
	parent.add_child(r)


# ------------------------------------------------------------------ classes ---

class BloodBurst extends Node2D:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var size := PackedFloat32Array()
	var state := PackedByteArray()   # 0 = voando, 1 = grudada, 2 = sumiu
	var age := 0.0

	func start(origin: Vector2, dir: Vector2, amount: int) -> void:
		z_index = 2
		var d := dir.normalized() if dir.length_squared() > 0.0 else Vector2.UP
		for i in amount:
			pos.append(origin + Vector2(randf_range(-4, 4), randf_range(-6, 6)))
			var v := d.rotated(randf_range(-0.7, 0.7)) * randf_range(120.0, 620.0)
			v.y -= randf_range(0.0, 180.0)
			vel.append(v)
			size.append(randf_range(2.0, 5.0))
			state.append(0)

	func _physics_process(delta: float) -> void:
		age += delta
		var space := get_world_2d().direct_space_state
		var moving := false
		for i in pos.size():
			if state[i] != 0:
				continue
			var v := vel[i]
			v.y += 1500.0 * delta
			vel[i] = v
			var target := pos[i] + v * delta
			var q := PhysicsRayQueryParameters2D.create(pos[i], target, 1 | 16)  # mundo + plataformas
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				pos[i] = target
				moving = true
			else:
				pos[i] = hit["position"]
				state[i] = 1
			if age > 2.5 and state[i] == 0:
				state[i] = 2
		queue_redraw()
		if not moving:
			set_physics_process(false)

	func _draw() -> void:
		for i in pos.size():
			if state[i] == 2:
				continue
			var s := size[i]
			var c := C_BLOOD if state[i] == 0 else C_BLOOD_DRY
			if state[i] == 0:
				# gota voando = risco na direção do movimento
				draw_line(pos[i], pos[i] - vel[i] * 0.012, c, s * 0.8)
			else:
				draw_rect(Rect2(pos[i] - Vector2(s, s * 0.5), Vector2(s * 2.0, s)), c)


class Particles extends Node2D:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var color := Color.WHITE
	var life := 0.25
	var age := 0.0
	var lines := true

	func start(origin: Vector2, dir: Vector2, c: Color, amount: int, speed: float, spread: float, duration: float, as_lines: bool) -> void:
		z_index = 4
		color = c
		life = duration
		lines = as_lines
		for i in amount:
			pos.append(origin)
			vel.append(dir.normalized().rotated(randf_range(-spread, spread)) * randf_range(speed * 0.35, speed))

	func _process(delta: float) -> void:
		age += delta
		if age >= life:
			queue_free()
			return
		for i in pos.size():
			pos[i] += vel[i] * delta
			vel[i] *= 0.9
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - age / life
		var c := Color(color, color.a * k)
		for i in pos.size():
			if lines:
				draw_line(pos[i], pos[i] - vel[i] * 0.03, c, 2.0)
			else:
				draw_circle(pos[i], 3.0 + (1.0 - k) * 6.0, c)


class SlashArc extends Node2D:
	const DURATION := 0.15
	const RADIUS := 66.0
	const SPAN := 2.4
	var t := 0.0

	func _ready() -> void:
		z_index = 6

	func _process(delta: float) -> void:
		t += delta
		if t >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / DURATION
		var sweep := lerpf(-0.5, 0.25, sqrt(k))   # o arco "varre" um pouco
		_crescent(RADIUS + 6.0, 0.5, sweep, Color(1.0, 0.24, 0.5, 0.55 * (1.0 - k)))
		_crescent(RADIUS, 0.42, sweep, Color(1.0, 1.0, 1.0, 0.95 * (1.0 - k)))

	func _crescent(r: float, thick: float, rot: float, c: Color) -> void:
		var pts := PackedVector2Array()
		var n := 16
		for i in n + 1:
			var a := rot - SPAN * 0.5 + SPAN * i / n
			pts.append(Vector2.from_angle(a) * r)
		for i in range(n, -1, -1):
			var a := rot - SPAN * 0.5 + SPAN * i / n
			var w := maxf(sin(PI * float(i) / n) * r * thick, 2.0)
			pts.append(Vector2.from_angle(a) * (r - w))
		draw_colored_polygon(pts, c)


class Ghost extends Node2D:
	const DURATION := 0.22
	var t := 0.0
	var rolling := false
	var color := Color.MAGENTA

	func _ready() -> void:
		z_index = -1

	func _process(delta: float) -> void:
		t += delta
		if t >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var c := Color(color, 0.45 * (1.0 - t / DURATION))
		if rolling:
			draw_circle(Vector2(0, -14), 13.0, c)
		else:
			draw_rect(Rect2(-7, -38, 14, 38), c)
			draw_circle(Vector2(1, -45), 7.0, c)


class Ring extends Node2D:
	const DURATION := 0.45
	var t := 0.0
	var color := Color.WHITE
	var max_radius := 60.0

	func _ready() -> void:
		z_index = 5

	func _process(delta: float) -> void:
		t += delta
		if t >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / DURATION
		draw_arc(Vector2.ZERO, max_radius * sqrt(k), 0.0, TAU, 40, Color(color, 1.0 - k), 3.0)
