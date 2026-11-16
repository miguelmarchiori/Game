extends Node2D
## Constrói o cenário a partir do mapa em texto (playground.gd):
## colisões (blocos vizinhos viram retângulos maiores, para ninguém "enganchar"
## nas emendas), rampas, plataformas finas, plataformas de salto e o desenho do fundo.

const TILE := 32
const JumpPad := preload("res://scripts/jump_pad.gd")

# paleta: galpão industrial (concreto, aço e laranja)
const C_BG_TOP := Color("#1a1e23")
const C_BG_BOTTOM := Color("#2b3037")
const C_WALL := Color("#3b4047")
const C_WALL_INNER := Color("#343940")
const C_EDGE := Color("#9aa2ab")
const C_EDGE_SIDE := Color("#2a2e33")
const C_PLATFORM := Color("#ffb21e")
const C_STEEL := Color("#2c3138")
const C_LIGHT := Color("#ffd9a0")
const C_HINT := Color(0.93, 0.9, 0.84, 0.72)

var grid: PackedStringArray = PackedStringArray()
var width := 0
var height := 0
var player_spawn := Vector2.ZERO
var enemy_spawns: Array[Dictionary] = []
var item_spawns: Array[Dictionary] = []

var _solid_rects: Array[Rect2] = []
var _platform_rects: Array[Rect2] = []
var _slopes: Array[PackedVector2Array] = []
var _signs: Array = []


func build(data: Dictionary, item_chars: Dictionary) -> void:
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
	item_spawns.clear()
	var solids := StaticBody2D.new()
	solids.name = "Solids"
	solids.collision_layer = Game.L_WORLD
	solids.collision_mask = 0
	add_child(solids)
	for y in height:
		for x in width:
			var c := grid[y][x]
			var foot := Vector2((x + 0.5) * TILE, (y + 1) * TILE)
			match c:
				"P":
					player_spawn = foot
				"g", "G", "s", "S", "b", "B", "d":
					enemy_spawns.append({"kind": c.to_lower(), "pos": foot, "facing": 1 if c == c.to_upper() else -1})
				"J":
					var pad := JumpPad.new()
					pad.position = foot
					add_child(pad)
				"/", "\\":
					_add_slope(solids, x, y, c == "/")
				_:
					if item_chars.has(c):
						item_spawns.append({"kind": item_chars[c], "pos": foot + Vector2(0, -8)})
	_build_solids(solids)
	_build_platforms()
	_build_hints(data.get("hints", []))
	_signs = data.get("signs", [])
	queue_redraw()


func pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func cell(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width or y >= height:
		return "#"
	return grid[y][x]


func _is_solid(x: int, y: int) -> bool:
	return cell(x, y) == "#"


# ------------------------------------------------------------- colisão ---

func _add_slope(body: StaticBody2D, x: int, y: int, rising_right: bool) -> void:
	var o := Vector2(x * TILE, y * TILE)
	var pts: PackedVector2Array
	if rising_right:
		pts = PackedVector2Array([o + Vector2(0, TILE), o + Vector2(TILE, TILE), o + Vector2(TILE, 0)])
	else:
		pts = PackedVector2Array([o, o + Vector2(0, TILE), o + Vector2(TILE, TILE)])
	_slopes.append(pts)
	var shape := CollisionShape2D.new()
	var poly := ConvexPolygonShape2D.new()
	poly.points = pts
	shape.shape = poly
	body.add_child(shape)


func _build_solids(body: StaticBody2D) -> void:
	var used := PackedByteArray()
	used.resize(width * height)
	_solid_rects.clear()
	for y in height:
		for x in width:
			if not _is_solid(x, y) or used[y * width + x] == 1:
				continue
			var w := 1
			while x + w < width and _is_solid(x + w, y) and used[y * width + x + w] == 0:
				w += 1
			var h := 1
			while y + h < height:
				var ok := true
				for i in w:
					if not _is_solid(x + i, y + h) or used[(y + h) * width + x + i] == 1:
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
	settings.font_size = 14
	settings.font_color = C_HINT
	settings.outline_size = 4
	settings.outline_color = Color(0.05, 0.05, 0.06, 0.9)
	for h in hints:
		var label := Label.new()
		label.text = String(h[2])
		label.label_settings = settings
		label.position = Vector2(int(h[0]) * TILE, int(h[1]) * TILE)
		add_child(label)


# ------------------------------------------------------------- desenho ---

func _draw() -> void:
	var px := pixel_size()
	draw_rect(Rect2(-2000, -2000, px.x + 4000, px.y + 4000), C_WALL)
	var bg := PackedVector2Array([Vector2.ZERO, Vector2(px.x, 0), px, Vector2(0, px.y)])
	draw_polygon(bg, PackedColorArray([C_BG_TOP, C_BG_TOP, C_BG_BOTTOM, C_BG_BOTTOM]))
	_draw_backdrop(px)

	for r in _solid_rects:
		draw_rect(r, C_WALL)
		if r.size.x >= 64.0 and r.size.y >= 64.0:
			draw_rect(r.grow(-5), C_WALL_INNER)
	for pts in _slopes:
		draw_colored_polygon(pts, C_WALL)
	# bordas iluminadas onde a parede encosta em espaço livre
	for y in height:
		for x in width:
			if not _is_solid(x, y):
				continue
			var tl := Vector2(x * TILE, y * TILE)
			if not _is_solid(x, y - 1) and cell(x, y - 1) not in ["/", "\\"]:
				draw_line(tl, tl + Vector2(TILE, 0), C_EDGE, 3.0)
			if not _is_solid(x - 1, y):
				draw_line(tl, tl + Vector2(0, TILE), C_EDGE_SIDE, 2.0)
			if not _is_solid(x + 1, y):
				draw_line(tl + Vector2(TILE, 0), tl + Vector2(TILE, TILE), C_EDGE_SIDE, 2.0)
	for pts in _slopes:
		var a := pts[0] if pts[2].y < pts[0].y else pts[0]
		var b := pts[2] if pts[2].y < pts[0].y else pts[2]
		draw_line(a, b, C_EDGE, 3.0)
	# plataformas finas: grade metálica com faixa de alerta
	for r in _platform_rects:
		draw_rect(Rect2(r.position + Vector2(0, 3), Vector2(r.size.x, 6)), C_STEEL)
		var sx := r.position.x
		var i := 0
		while sx < r.end.x:
			draw_rect(Rect2(sx, r.position.y, minf(8.0, r.end.x - sx), 3), C_PLATFORM if i % 2 == 0 else Color("#1e2226"))
			sx += 8.0
			i += 1
		var lx := r.position.x + 10.0
		while lx < r.end.x:
			draw_line(Vector2(lx, r.position.y + 9), Vector2(lx, r.position.y + 18), Color(C_STEEL, 0.8), 2.0)
			lx += 32.0


func _draw_backdrop(px: Vector2) -> void:
	# janelões com luz quente
	var wx := 120.0
	while wx < px.x - 200.0:
		var win := Rect2(wx, 70, 150, 220)
		draw_rect(win, Color(C_LIGHT, 0.05))
		draw_rect(win, Color(C_STEEL, 0.9), false, 3.0)
		draw_line(Vector2(win.get_center().x, win.position.y), Vector2(win.get_center().x, win.end.y), Color(C_STEEL, 0.9), 3.0)
		draw_line(Vector2(win.position.x, win.get_center().y), Vector2(win.end.x, win.get_center().y), Color(C_STEEL, 0.9), 3.0)
		# feixe de luz descendo na diagonal
		draw_colored_polygon(PackedVector2Array([win.position + Vector2(0, win.size.y), win.end,
			win.end + Vector2(260, 520), win.position + Vector2(260, win.size.y + 520)]), Color(C_LIGHT, 0.025))
		wx += 520.0
	# treliças de aço no teto
	var y0 := 40.0
	draw_line(Vector2(0, y0), Vector2(px.x, y0), Color(C_STEEL, 0.9), 6.0)
	draw_line(Vector2(0, y0 + 28), Vector2(px.x, y0 + 28), Color(C_STEEL, 0.9), 4.0)
	var tx := 0.0
	while tx < px.x:
		draw_line(Vector2(tx, y0), Vector2(tx + 28, y0 + 28), Color(C_STEEL, 0.8), 3.0)
		draw_line(Vector2(tx + 28, y0 + 28), Vector2(tx + 56, y0), Color(C_STEEL, 0.8), 3.0)
		tx += 56.0
	# pilares e painéis de concreto
	var cx := 64.0
	while cx < px.x:
		draw_rect(Rect2(cx, y0 + 28, 22, px.y), Color(0, 0, 0, 0.14))
		cx += 384.0
	var hy := px.y - 7 * TILE
	draw_line(Vector2(0, hy), Vector2(px.x, hy), Color(1, 1, 1, 0.03), 2.0)
	# letreiros pintados na parede
	var font := ThemeDB.fallback_font
	for s in _signs:
		var pos := Vector2(int(s[0]) * TILE, int(s[1]) * TILE)
		draw_string(font, pos, String(s[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1.0, 0.7, 0.3, 0.07))
