extends RigidBody2D
## ARMA SOLTA no chão. Tem física de verdade: cai, quica, gira.
## [E] pega · [botão direito] arremessa. Arremessada, machuca o inimigo que acertar.

const Weapons := preload("res://scripts/weapons.gd")
const Fx := preload("res://scripts/fx.gd")

var kind := "pistola"
var ammo := -1               ## -1 = munição cheia
var thrown := false
var pickup_delay := 0.0
var _thrower: Node
var _hit_ids := {}


func _ready() -> void:
	add_to_group("items")
	z_index = 1
	collision_layer = Game.L_ITEM
	collision_mask = Game.L_WORLD | Game.L_PLATFORM
	var d: Dictionary = Weapons.DATA[kind]
	if ammo < 0:
		ammo = int(d.get("municao", 0))
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(maxf(float(d["len"]), 16.0), 8.0)
	shape.shape = rs
	add_child(shape)
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.25
	physics_material_override = mat
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	angular_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func throw(dir: Vector2, speed: float, by: Node) -> void:
	thrown = true
	_thrower = by
	_hit_ids.clear()
	pickup_delay = 0.4
	sleeping = false
	linear_velocity = dir * speed
	if kind == "faca" or kind == "espada":
		rotation = dir.angle()      # vai de ponta
		angular_velocity = 0.0
		gravity_scale = 0.3
	else:
		angular_velocity = 20.0 * (1.0 if dir.x >= 0.0 else -1.0)


## Chamado pela plataforma de salto.
func launch(v: Vector2) -> void:
	sleeping = false
	linear_velocity = Vector2(linear_velocity.x, v.y * 0.75)
	angular_velocity = randf_range(-8.0, 8.0)


func _physics_process(delta: float) -> void:
	pickup_delay = maxf(0.0, pickup_delay - delta)
	queue_redraw()
	if not thrown:
		return
	if linear_velocity.length() < 260.0:
		_end_throw()
		return
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = Game.L_ENEMY
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 8):
		var e: Object = hit["collider"]
		if e == null or _hit_ids.has(e.get_instance_id()) or not e.has_method("take_hit"):
			continue
		_hit_ids[e.get_instance_id()] = true
		var dmg := int(Weapons.DATA[kind].get("arremesso", 20))
		var dir := linear_velocity.normalized()
		e.take_hit({"dmg": dmg, "kb": dir * 380.0 + Vector2(0, -160), "stun": 0.7, "down": dmg >= 40, "from": _thrower})
		Fx.impact(get_parent(), global_position, dmg >= 40)
		Sfx.play("kick", -3.0)
		Game.hitstop(0.05)
		Game.shake(5.0)
		if is_instance_valid(_thrower) and _thrower.has_method("register_hit"):
			_thrower.register_hit(dmg)
		if kind == "garrafa":
			_shatter()
			return
		linear_velocity = -linear_velocity * 0.2 + Vector2(0, -160)
		angular_velocity = randf_range(-15.0, 15.0)
		_end_throw()
		return


func _end_throw() -> void:
	thrown = false
	gravity_scale = 1.0


func _on_body_entered(_b: Node) -> void:
	if thrown and kind == "garrafa":
		_shatter()


func _shatter() -> void:
	Fx.shards(get_parent(), global_position, Vector2.UP, Weapons.C_GLASS, 16)
	Sfx.play("glass", -2.0)
	queue_free()


func _draw() -> void:
	var d: Dictionary = Weapons.DATA[kind]
	var half := float(d["len"]) * 0.5
	Weapons.draw(self, kind, Vector2(-half + 4.0, 0), 0.0)
	# destaque quando o jogador está perto o bastante para pegar
	var p := get_tree().get_first_node_in_group("player")
	if p and p.get("near_item") == self:
		var t := Time.get_ticks_msec() / 1000.0
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		var a := 0.6 + 0.4 * sin(t * 8.0)
		draw_arc(Vector2.ZERO, half + 8.0, 0, TAU, 28, Color(1.0, 0.6, 0.2, a), 2.0)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-30, -half - 14), "E", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, 5, Color.BLACK)
		draw_string(font, Vector2(-30, -half - 14), "E", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color("#ffb066"))
