extends Node2D
## Constrói uma fase a partir do mapa ASCII de levels.gd:
## cria as colisões (blocos vizinhos são fundidos em retângulos maiores,
## o que evita o personagem "enganchar" nas emendas), desenha o cenário
## e guarda as posições de nascimento.

const TILE := 32
const C_BG_TOP := Color("#120e24")
const C_BG_BOTTOM := Color("#261a3d")
const C_WALL := Color("#1c1730")
const C_WALL_INNER := Color("#231d3b")
const C_EDGE := Color("#7b5cff")
const C_EDGE_SIDE := Color("#4a3a9a")
const C_PLATFORM := Color("#a594ff")
const C_HINT := Color(0.85, 0.82, 1.0, 0.75)

var grid: PackedStringArray = PackedStringArray()
var width := 0
var height := 0
var player_spawn := Vector2.ZERO
var exit_pos := Vector2.ZERO
var enemy_spawns: Array[Dictionary] = []

var _solid_rects: Array[Rect2] = []
var _platform_rects: Array[Rect2] = []
var _windows: Array[Rect2] = []
var _window_colors: Array[Color] = []
var _pillars: Array[float] = []


func build(data: Dictionary, seed_value: int) -> void:
	z_index = -10
	var rows: Array = data["map"]
	height = rows.size()
	width = 0
	for r in rows:
		width = maxi(width, String(r).length())
	grid.clear()
	for r in rows:
		grid.append(String(r).rpad(width, "."))

	enemy_spawns.clear()
	for y in height:
		for x in width:
			var c := grid[y][x]
			var foot := Vector2((x + 0.5) * TILE, (y + 1) * TILE)
			match c:
				"P":
					player_spawn = foot
				"D":
					exit_pos = foot
				"g", "G", "s", "S", "b", "B":
					enemy_spawns.append({
						"kind": c.to_lower(),
						"pos": foot,
						"facing": 1 if c == c.to_upper() else -1,
					})
	_build_solids()
	_build_platforms()
	_build_hints(data.get("hints", []))
	_build_decor(seed_value)
	queue_redraw()


func pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func cell(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width or y >= height:
		return "#"
	return grid[y][x]


# ------------------------------------------------------------- colisão ---

func _build_solids() -> void:
	var body := StaticBody2D.new()
	body.name = "Solids"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	add_child(body)
	var used := PackedByteArray()
	used.resize(width * height)
	_solid_rects.clear()
	for y in height:
		for x in width:
			if cell(x, y) != "#" or used[y * width + x] == 1:
				continue
			var w := 1
			while x + w < width and cell(x + w, y) == "#" and used[y * width + x + w] == 0:
				w += 1
			var h := 1
			while y + h < height:
				var ok := true
				for i in w:
					if cell(x + i, y + h) != "#" or used[(y + h) * width + x + i] == 1:
						ok = false
						break
				if not ok:
					break
				h += 1
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					used[yy * width + xx] = 1
			var rect := Rect2(x * TILE, y * TILE, w * TILE, h * TILE)
			_solid_rects.append(rect)
			var shape := CollisionShape2D.new()
			var rs := RectangleShape2D.new()
			rs.size = rect.size
			shape.shape = rs
			shape.position = rect.get_center()
			body.add_child(shape)


func _build_platforms() -> void:
	var body := StaticBody2D.new()
	body.name = "Platforms"
	body.collision_layer = Game.L_PLATFORM
	body.collision_mask = 0
	body.add_to_group("oneway")
	add_child(body)
	_platform_rects.clear()
	for y in height:
		var x := 0
		while x < width:
			if cell(x, y) != "-":
				x += 1
				continue
			var start := x
			while x < width and cell(x, y) == "-":
				x += 1
			var rect := Rect2(start * TILE, y * TILE, (x - start) * TILE, 10)
			_platform_rects.append(rect)
			var shape := CollisionShape2D.new()
			var rs := RectangleShape2D.new()
			rs.size = rect.size
			shape.shape = rs
			shape.position = rect.get_center()
			shape.one_way_collision = true
			shape.one_way_collision_margin = 8.0
			body.add_child(shape)


func _build_hints(hints: Array) -> void:
	var settings := LabelSettings.new()
	settings.font_size = 15
	settings.font_color = C_HINT
	settings.outline_size = 4
	settings.outline_color = Color(0.05, 0.03, 0.1, 0.9)
	for h in hints:
		var label := Label.new()
		label.text = String(h[2])
		label.label_settings = settings
		label.position = Vector2(int(h[0]) * TILE, int(h[1]) * TILE)
		add_child(label)


# ------------------------------------------------------------- cenário ---

func _build_decor(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + seed_value
	_windows.clear()
	_window_colors.clear()
	_pillars.clear()
	var palette := [Color("#ff3d7f"), Color("#5ae4ff"), Color("#ffd25a"), Color("#7b5cff")]
	var px := pixel_size()
	var x := rng.randf_range(40.0, 160.0)
	while x < px.x:
		_pillars.append(x)
		x += rng.randf_range(220.0, 420.0)
	for i in int(width * height / 32.0):
		var cx := rng.randi_range(1, width - 2)
		var cy := rng.randi_range(1, height - 2)
		if cell(cx, cy) != ".":
			continue
		var w := rng.randf_range(8.0, 26.0)
		var h := rng.randf_range(6.0, 16.0)
		_windows.append(Rect2(cx * TILE + rng.randf_range(0, 10), cy * TILE + rng.randf_range(0, 10), w, h))
		var c: Color = palette[rng.randi() % palette.size()]
		_window_colors.append(Color(c, rng.randf_range(0.04, 0.11)))


func _draw() -> void:
	var px := pixel_size()
	# fora do mapa (caso a tela seja maior que a fase)
	draw_rect(Rect2(-2000, -2000, px.x + 4000, px.y + 4000), C_WALL)
	# fundo em degradê
	var bg := PackedVector2Array([Vector2.ZERO, Vector2(px.x, 0), px, Vector2(0, px.y)])
	draw_polygon(bg, PackedColorArray([C_BG_TOP, C_BG_TOP, C_BG_BOTTOM, C_BG_BOTTOM]))
	# colunas e "janelas" distantes
	for x in _pillars:
		draw_rect(Rect2(x, 0, 18, px.y), Color(0.0, 0.0, 0.0, 0.18))
	for i in _windows.size():
		draw_rect(_windows[i], _window_colors[i])
	# grade sutil
	var gx := 0.0
	while gx < px.x:
		draw_line(Vector2(gx, 0), Vector2(gx, px.y), Color(1, 1, 1, 0.025), 1.0)
		gx += TILE * 4
	# paredes
	for r in _solid_rects:
		draw_rect(r, C_WALL)
		draw_rect(r.grow(-6), C_WALL_INNER)
	# bordas iluminadas (só onde a parede encosta em espaço livre)
	for y in height:
		for x in width:
			if cell(x, y) != "#":
				continue
			var tl := Vector2(x * TILE, y * TILE)
			if cell(x, y - 1) != "#":
				draw_line(tl, tl + Vector2(TILE, 0), C_EDGE, 3.0)
			if cell(x - 1, y) != "#":
				draw_line(tl, tl + Vector2(0, TILE), C_EDGE_SIDE, 2.0)
			if cell(x + 1, y) != "#":
				draw_line(tl + Vector2(TILE, 0), tl + Vector2(TILE, TILE), C_EDGE_SIDE, 2.0)
			if cell(x, y + 1) != "#":
				draw_line(tl + Vector2(0, TILE), tl + Vector2(TILE, TILE), C_EDGE_SIDE, 2.0)
	# plataformas finas
	for r in _platform_rects:
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), C_PLATFORM)
		draw_rect(Rect2(r.position + Vector2(0, 4), Vector2(r.size.x, 4)), Color(C_PLATFORM, 0.25))
		var sx := r.position.x + 8.0
		while sx < r.end.x:
			draw_line(Vector2(sx, r.position.y + 4), Vector2(sx, r.position.y + 12), Color(C_PLATFORM, 0.4), 2.0)
			sx += 24.0
