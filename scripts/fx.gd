extends RefCounted
## Efeitos visuais feitos só com código (sem sprites):
##   Fx.blood()   — gotas que voam e GRUDAM em paredes/chão
##   Fx.sparks()  — faíscas (tiros, balas na parede)
##   Fx.dust()    — poeira (pulo, aterrissagem, deslize)
##   Fx.impact()  — "estrela" de impacto do soco/chute
##   Fx.number()  — número de dano subindo
##   Fx.slash()   — arco do golpe com arma branca
##   Fx.ghost()   — rastro do jogador (dash)
##   Fx.ring()    — anel expandindo
##   Fx.shards()  — cacos de vidro (garrafa) / serragem (boneco)
## Uso:  const Fx := preload("res://scripts/fx.gd")  e depois  Fx.blood(parent, pos, dir)

const Rig := preload("res://scripts/rig.gd")
const C_BLOOD := Color("#d22b2b")
const C_BLOOD_DRY := Color("#8c1c1c")
const MAX_BLOOD_NODES := 80


static func blood(parent: Node, pos: Vector2, dir: Vector2, amount := 20) -> void:
	var tree := parent.get_tree()
	var all := tree.get_nodes_in_group("blood")
	if all.size() > MAX_BLOOD_NODES:
		all[0].queue_free()
	var b := BloodBurst.new()
	b.add_to_group("blood")
	parent.add_child(b)
	b.start(pos, dir, amount)


static func sparks(parent: Node, pos: Vector2, dir: Vector2, color := Color("#ffd27a"), amount := 10, speed := 420.0) -> void:
	var s := Particles.new()
	parent.add_child(s)
	s.start(pos, dir, color, amount, speed, 0.6, 0.22, Particles.LINES, 0.0)


static func dust(parent: Node, pos: Vector2, amount := 6, dir := Vector2.UP, spread := 1.4) -> void:
	var s := Particles.new()
	parent.add_child(s)
	s.start(pos, dir, Color(0.78, 0.76, 0.72, 0.45), amount, 100.0, spread, 0.32, Particles.PUFFS, 0.0)


static func shards(parent: Node, pos: Vector2, dir: Vector2, color: Color, amount := 14) -> void:
	var s := Particles.new()
	parent.add_child(s)
	s.start(pos, dir, color, amount, 380.0, 1.2, 0.6, Particles.CHIPS, 1400.0)


static func impact(parent: Node, pos: Vector2, big := false) -> void:
	var i := Impact.new()
	i.position = pos
	i.big = big
	parent.add_child(i)


static func number(parent: Node, pos: Vector2, value: int, color := Color.WHITE) -> void:
	var n := Number.new()
	n.position = pos + Vector2(randf_range(-8, 8), 0)
	n.text = str(value)
	n.color = color
	parent.add_child(n)


static func slash(parent: Node, local_pos: Vector2, dir: Vector2, radius := 60.0, color := Color(1, 1, 1)) -> void:
	var a := SlashArc.new()
	a.position = local_pos
	a.rotation = dir.angle()
	a.radius = radius
	a.color = color
	parent.add_child(a)


static func ghost(parent: Node, pos: Vector2, pose: Dictionary, facing: int, color := Color("#ffb066")) -> void:
	var g := Ghost.new()
	g.position = pos
	g.pose = pose.duplicate()
	g.facing = facing
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
			var v := d.rotated(randf_range(-0.7, 0.7)) * randf_range(120.0, 560.0)
			v.y -= randf_range(0.0, 180.0)
			vel.append(v)
			size.append(randf_range(1.5, 4.0))
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
			var q := PhysicsRayQueryParameters2D.create(pos[i], target, 1 | 16)
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
			if state[i] == 0:
				draw_line(pos[i], pos[i] - vel[i] * 0.012, C_BLOOD, s * 0.8)
			else:
				draw_rect(Rect2(pos[i] - Vector2(s, s * 0.5), Vector2(s * 2.0, s)), C_BLOOD_DRY)


class Particles extends Node2D:
	const LINES := 0
	const PUFFS := 1
	const CHIPS := 2
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var color := Color.WHITE
	var life := 0.25
	var age := 0.0
	var mode := 0
	var gravity := 0.0

	func start(origin: Vector2, dir: Vector2, c: Color, amount: int, speed: float, spread: float, duration: float, draw_mode: int, grav: float) -> void:
		z_index = 4
		color = c
		life = duration
		mode = draw_mode
		gravity = grav
		for i in amount:
			pos.append(origin)
			vel.append(dir.normalized().rotated(randf_range(-spread, spread)) * randf_range(speed * 0.35, speed))

	func _process(delta: float) -> void:
		age += delta
		if age >= life:
			queue_free()
			return
		for i in pos.size():
			var v := vel[i]
			v.y += gravity * delta
			if mode != CHIPS:
				v *= 0.9
			vel[i] = v
			pos[i] += v * delta
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - age / life
		var c := Color(color, color.a * k)
		for i in pos.size():
			match mode:
				LINES:
					draw_line(pos[i], pos[i] - vel[i] * 0.03, c, 2.0)
				PUFFS:
					draw_circle(pos[i], 3.0 + (1.0 - k) * 7.0, c)
				CHIPS:
					draw_rect(Rect2(pos[i], Vector2(3, 2)), c)


class Impact extends Node2D:
	const DURATION := 0.12
	var t := 0.0
	var big := false

	func _ready() -> void:
		z_index = 7
		rotation = randf() * TAU

	func _process(delta: float) -> void:
		t += delta
		if t >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / DURATION
		var r := (22.0 if big else 14.0) * (0.6 + k * 0.8)
		var pts := PackedVector2Array()
		for i in 12:
			var rr := r if i % 2 == 0 else r * 0.38
			pts.append(Vector2.from_angle(TAU * i / 12.0) * rr)
		draw_colored_polygon(pts, Color(1, 0.95, 0.8, 1.0 - k))
		draw_arc(Vector2.ZERO, r * 1.2, 0, TAU, 20, Color(1, 0.6, 0.25, 0.8 * (1.0 - k)), 2.0)


class Number extends Node2D:
	const DURATION := 0.7
	var t := 0.0
	var text := ""
	var color := Color.WHITE

	func _ready() -> void:
		z_index = 8

	func _process(delta: float) -> void:
		t += delta
		position.y -= 60.0 * delta * (1.0 - t / DURATION)
		if t >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := clampf((DURATION - t) / 0.25, 0.0, 1.0)
		var s := 1.0 + maxf(0.0, 0.12 - t) * 4.0
		var font := ThemeDB.fallback_font
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
		draw_string_outline(font, Vector2(-20, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 40, 16, 5, Color(0, 0, 0, a))
		draw_string(font, Vector2(-20, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(color, a))


class SlashArc extends Node2D:
	const DURATION := 0.14
	const SPAN := 2.3
	var t := 0.0
	var radius := 60.0
	var color := Color.WHITE

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
		var sweep := lerpf(-0.6, 0.3, sqrt(k))
		var pts := PackedVector2Array()
		var n := 14
		for i in n + 1:
			pts.append(Vector2.from_angle(sweep - SPAN * 0.5 + SPAN * i / n) * radius)
		for i in range(n, -1, -1):
			var w := maxf(sin(PI * float(i) / n) * radius * 0.35, 2.0)
			pts.append(Vector2.from_angle(sweep - SPAN * 0.5 + SPAN * i / n) * (radius - w))
		draw_colored_polygon(pts, Color(color, 0.85 * (1.0 - k)))


class Ghost extends Node2D:
	const DURATION := 0.2
	var t := 0.0
	var pose := {}
	var facing := 1
	var color := Color.WHITE

	func _ready() -> void:
		z_index = 2

	func _process(delta: float) -> void:
		t += delta
		if t >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1))
		Rig.draw_silhouette(self, pose, Color(color, 0.5 * (1.0 - t / DURATION)))


class Ring extends Node2D:
	const DURATION := 0.4
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
